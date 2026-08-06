# Concurrency Guidelines for cutter2

**Version**: 1.1
**Last Updated**: August 6, 2026
**Swift Version**: 6.0

---

## Overview

This document establishes the official concurrency patterns for cutter2. All new code must follow these patterns. Existing code not conforming should be migrated during maintenance.

---

## Core Principles

1. **Actor Isolation First**: Use `@MainActor` for UI, dedicated `actor` for mutable background state
2. **Structured Concurrency**: Prefer `async/await` and `Task` over completion handlers
3. **Sendable Compliance**: All types crossing isolation boundaries must be `Sendable`
4. **Explicit Synchronization**: Use `ActorUtilities` and `AsyncBridge` — never raw `DispatchQueue` for new code
5. **Fail Fast**: Use `guard let` / `throws` instead of force-unwrap on async boundaries

---

## Pattern Reference

### 1. `@MainActor` Classes (UI Layer)

**Use for:** All AppKit/UIKit interaction, document lifecycle, view controllers, windows.

```swift
@MainActor
final class Document: NSDocument {
    var movieMutator: MovieMutator?
    var player: AVPlayer?
    // All methods implicitly @MainActor
}
```

**Rules:**
- All `@IBOutlet`, `@IBAction`, storyboard-connected code must be `@MainActor`
- Never call blocking sync APIs on main actor
- Use `Task { @MainActor in ... }` only when hopping FROM a non-isolated context

### 2. Dedicated `actor` (Background Mutable State)

**Use for:** Long-running operations with mutable state (export, transcode, custom write).

```swift
actor MovieWriter: SampleBufferChannelDelegate {
    private(set) var writeProgress: Float = 0.0
    private(set) var writeError: Error?

    func exportMovie(...) async throws { ... }
}

// progressStream() is on MovieMutatorBase, which is @MainActor-isolated, not on MovieWriter
@MainActor
class MovieMutatorBase: NSObject {
    public func progressStream() -> AsyncStream<Float> { ... }
}
```

**Rules:**
- All mutable state lives inside the actor
- Public API is `async` — callers `await` to hop in
- Use `AsyncStream` for progress reporting
- Never expose mutable state directly

### 3. `Task.detached(priority:)` (CPU-Intensive Background Work)

**Use for:** Heavy computation that must not block main actor and doesn't need actor isolation.

```swift
Task.detached(priority: .userInitiated) {
    let result = heavyComputation(input)
    await MainActor.run { updateUI(with: result) }
}
```

**Rules:**
- Always specify priority (`.userInitiated` for user-facing, `.background` for maintenance)
- Capture values explicitly — no implicit `self`
- Hop to `@MainActor` only for UI updates
- Prefer `AsyncBridge` when you need sync result from non-async context

### 4. `Task { @MainActor in ... }` (Explicit Main Actor Hop)

**Use for:** Callback handlers, notification observers, completion blocks that need main actor.

```swift
NotificationCenter.default.addObserver(forName: .foo, object: nil, queue: nil) { _ in
    Task { @MainActor in
        self.handleNotification()
    }
}
```

**Rules:**
- Only use when currently NOT on main actor
- If already on main actor, call directly (redundant hop wastes cycles)
- Keep the `@MainActor` block small — do computation outside

### 5. `ActorUtilities.performSyncOnMainActor` (Sync Main Actor Call)

**Use for:** Synchronous main-actor execution from ANY thread (background, other actors, detached tasks).

```swift
// From background thread / actor / detached task
let text = ActorUtilities.performSyncOnMainActor {
    currentDisplayText  // @MainActor property
}

try ActorUtilities.performSyncOnMainActor {
    try updateModel(with: newValue)  // @MainActor throwing method
}
```

**Rules:**
- **Preferred** over `DispatchQueue.main.sync` for new code
- Uses `MainActor.assumeIsolated` (Swift 6) — no redundant thread hop if already on main
- Two variants: throwing and non-throwing
- Blocks caller — avoid in hot paths

### 6. `Document.performAsync` (Async-to-Sync Bridge)

**Use for:** Running async work synchronously from non-async contexts (e.g., `NSDocument` overrides).

```swift
// Document+ActorIsolation.swift
nonisolated func performAsync<T: Sendable>(
    _ block: @Sendable @escaping () async throws -> T
) throws -> T {
    try AsyncBridge.perform(block)
}
```

**Rules:**
- **Must not be called from main thread** (precondition check)
- Use `allowMainThread: true` ONLY with documented deadlock risk acknowledgment
- Returns `Sendable` result — closure must be `@Sendable`

### 7. `DispatchQueue` (Legacy / Specific Interop)

**Allowed ONLY for:**
- `SampleBufferChannel` internal queue (created at `SampleBufferChannel.swift:30`, used by `requestMediaDataWhenReady`)
- `MovieWriter+CustomExport.swift:539` (`exportCustomMovie` dedicated queue, passed to `SampleBufferChannel`)
- AVFoundation `requestMediaDataWhenReady(on:using:)` API (AVFoundation interop)
- `OperationQueue.main` for `NotificationCenter` (AppKit requirement)
- `Timer.scheduledTimer` (Foundation API)

**Migration target:** Replace with `Task` / `AsyncBridge` / `ActorUtilities` where possible.

#### AVFoundation `requestMediaDataWhenReady` DispatchQueue Usage

The `requestMediaDataWhenReady(on:using:)` API in AVFoundation asynchronously notifies on the specified `DispatchQueue` when media data is ready for writing. This is an official AVFoundation API that requires a `DispatchQueue` parameter.

- **Usage locations:**
  - `SampleBufferChannel.swift:30` — each `SampleBufferChannel` creates its own queue (`SBC-<mediaType>`) in its `init`, used by `requestMediaDataWhenReady` at line 63
  - `MovieWriter+CustomExport.swift:539` — `MovieWriter` creates a separate `exportCustomMovie` queue stored as `customQueue`, passed to `SampleBufferChannel` for custom export
- **Reason:** AVFoundation API contract requires `DispatchQueue` — cannot be replaced with `Task` / `async`.
- **Safety:** `requestMediaDataWhenReady` processes sequentially on the queue, so no data races occur. Queue cleanup happens at `stopRequestingMediaData` call.
- **Note:** This API is called from the `SampleBufferChannel` (not from within an actor), with data passed back via `@Sendable` closure.

---

## Anti-Patterns (Prohibited)

| Pattern | Problem | Replacement |
|---------|---------|-------------|
| `DispatchQueue.main.sync { ... }` (new code) | No `Sendable` checking, no `MainActor.assumeIsolated` | `ActorUtilities.performSyncOnMainActor` (exception: `ActorUtilities` internally uses `DispatchQueue.main.sync` after checking `Thread.isMainThread`) |
| `Thread.isMainThread` checks (new code) | Bypasses actor isolation, unreliable | `MainActor.assertIsolated()` or `ActorUtilities.performSyncOnMainActor` (exception: `ActorUtilities` and `AsyncBridge` use `Thread.isMainThread` internally for optimization and precondition checks) |
| `Task { await MainActor.run { ... } }` (already on main) | Redundant hop, performance penalty | Direct call |
| `unowned self` in `@Sendable` closure | CRASH risk if self deallocates | `let me = self` + `ActorUtilities` |
| `preconditionFailure("Unexpected nil")` for teardown | Crashes on normal lifecycle | `return` / `throw` / `NSSound.beep(); return` |
| `!` on async boundary (`await x!`) | Silent crash on failure | `guard let x = await x else { throw ... }` |
| `Task.detached { [weak self] in ... }` without guard | Silent no-op if deallocated | Explicit `guard let self = self else { return }` |

---

## Concurrency Contract Documentation

Every public type crossing isolation boundaries MUST document:

1. **Actor Isolation**: Which actor (if any) the type is isolated to
2. **Sendable Conformance**: Whether the type is `Sendable` and why
3. **Reentrancy**: Whether methods can be called reentrantly
4. **Thread Safety**: What synchronization callers must provide

**Example:**
```swift
/// `MovieWriter` is a dedicated `actor` isolating all export state.
///
/// - Actor Isolation: All public methods run on `MovieWriter`'s actor.
/// - Sendable: The actor itself is `Sendable`; `MovieWriterParams` must be `Sendable`.
/// - Reentrancy: `exportMovie` and `cancelExport` are NOT reentrant — call `cancelExport`
///   before starting a new export on the same instance.
/// - Progress: Progress is reported via `MovieMutatorBase.progressStream()`.
actor MovieWriter { ... }
```

---

## Migration Checklist (for existing code)

When touching a file, verify:

- [ ] No raw `DispatchQueue.main.sync/async` for new logic
- [ ] No `Thread.isMainThread` checks — use `ActorUtilities` (exception: `AsyncBridge.perform` uses `Thread.isMainThread` internally for its main-thread guard precondition)
- [ ] No force-unwrap on async results
- [ ] All `@Sendable` closures have explicit captures
- [ ] Actor-isolated types document their contract (see above)
- [ ] Progress streams created BEFORE operation starts

---

## Related Documents

- [CODEBASE_REVIEW.md](CODEBASE_REVIEW.md) — System architecture overview and detailed code review
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) — Development practices

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.1 | 2026-08-06 | — | Clarified `MovieMutatorBase` `@MainActor` isolation and synchronized the documented concurrency examples with the current implementation. |
| 1.0 | 2026-06-21 | — | Initial version based on post-PR#33/34/37/39/40/41 codebase |

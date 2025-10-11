# cutter2: Document.write() 非同期ブリッジ改善計画

最終更新: 2024-01-27

## TL;DR
- 目的: AppKit 同期API `Document.write(...)` 内での長時間処理（export/write）を、Swift Concurrency と整合的かつ安全にブリッジし、UI/ドキュメントのライフサイクルと統合する。
- 現状: `performAsync`（Task.detached + DispatchSemaphore + SendableBox）で async→sync をブロッキング変換。`canAsynchronouslyWrite` が true を返し、AppKit によるバックグラウンド処理が有効。
- 問題: Task.detached によるタスク継承の切断・NSProgress 未統合・標準キャンセル機構の不在。
- 推奨案: 現在の実装を基盤として、段階的に `NSProgress` 連携とキャンセル対応を導入。`NSDocument.performActivity` への置き換えは任意の第2案として位置づけ。

---

## 対象と範囲
- 対象コード
  - `cutter2/Document.swift`
    - `override nonisolated func write(...) throws`
    - `override nonisolated func writeSafely(...) throws`
    - `private func writeAsync(...) async throws`
    - `private func export(...) async throws`
    - `private func exportCustom(...) async throws`
  - `cutter2/Document+Utilities.swift`
    - `performAsync`（throwing/non-throwing）
    - `performSyncOnMainActor`
- 非対象
  - `MovieMutator` の個別編集ロジック（必要に応じてキャンセル対応を追加）
  - UI/Storyboard の構造（Busy Sheet は現状維持で可）

## 現状の動作フロー（抜粋）
1. `writeSafely(...)` で前処理（UTI/上書き等の検証）を MainActor 同期実行（`performSyncOnMainActor` 経由）。
2. `write(...)` で `performAsync { ... await export/writeAsync }` を呼び、セマフォで完了待ち。
3. `writeAsync/export/exportCustom` は Busy Sheet を表示し、`mutator.updateProgress` で進捗を UI に反映。
4. `canAsynchronouslyWrite(...) == true` により、AppKit 側が write() をバックグラウンドキューで実行。
5. 非同期処理は `MovieWriter` actor 内で実行され、AVAssetExportSession や AVAssetWriter を使用。

## 主要な課題
### 現状の同期ブリッジに関する懸念
- `Task.detached` のため親タスクのキャンセルと優先度の継承が切れる。
  - ただし、`nonisolated` コンテキストからの呼び出しという制約上、detached の使用は設計上必要な面もある。
- セマフォ待機がタスク協調キャンセルに不親和。
- `SendableBox` が `@unchecked Sendable` を使用しており、慎重な検証が必要。

### NSProgress / 標準キャンセル機構の不在
- `NSProgress` の利用がなく、標準進捗 UI やシステム統合が弱い。
- ユーザーによるキャンセル操作が実装されていない。
  - `MovieWriter` には内部的に `writeCancelled` フラグと `cancelCustomMovie` メソッドが存在するが、外部からの呼び出しインターフェースが不完全。
  - `AVAssetExportSession` のキャンセルは可能だが、統合されていない。

### NSDocument アクティビティ管理
- 既に `canAsynchronouslyWrite` が true を返しており、AppKit が適切にバックグラウンド処理を行っている。
- `performActivity` への移行は必須ではなく、現状でも基本的に機能している。

## 改善方針（推奨案）

### 基本方針
現在の実装（`canAsynchronouslyWrite` + `performAsync`）は既に基本的に機能している。大規模なリファクタリングのリスクを避け、段階的かつ保守的なアプローチを採用する。

### Step 1: NSProgress 統合（優先度: 高）
進捗報告を `NSProgress` と統合し、標準的な進捗管理を実現する。

1. `Document` に `private var saveProgress: Progress?` を追加。
2. 書き込み/エクスポート開始時に `Progress(totalUnitCount: 100)` を作成。
3. `mutator.updateProgress` コールバック内で `progress.completedUnitCount` を更新。
4. 完了/失敗で `saveProgress = nil` によりクリーンアップ。
5. NSDocument の標準 `progress` プロパティとの統合を検討（`self.progress = saveProgress`）。

**注意点:**
- `Progress` は thread-safe だが、更新は MainActor で行うことを推奨。
- `mutator.updateProgress` は既に `performSyncOnMainActor` 経由で MainActor で実行されている。

### Step 2: キャンセル対応（優先度: 中）
ユーザーによる長時間処理のキャンセルを可能にする。

1. `MovieWriter` に public なキャンセルメソッドを追加:
   ```swift
   public func cancelExport() {
       writeCancelled = true
       exportSession?.cancelExport()
   }
   ```
2. `MovieMutator` に `cancel()` メソッドを追加し、内部の `MovieWriter` に転送。
3. Busy Sheet に Cancel ボタンを追加し、押下で `saveProgress?.cancel()` と `mutator.cancel()` を呼ぶ。
4. キャンセル検出時:
   - エラーシートは表示せず、静かにクローズ。
   - ドキュメントの Dirty フラグは維持（未保存状態）。
   - `writeCancelled` エラーを特別扱いして通常のエラー処理を回避。

### Step 3: ドキュメント化とコードコメント（優先度: 高）
現在の実装の意図を明確化する。

1. `performAsync` に以下の理由をドキュメント化:
   - `nonisolated` コンテキストから async 処理を呼び出す必要性。
   - `Task.detached` を使用する理由（既に AppKit がバックグラウンドキューで実行している）。
   - `canAsynchronouslyWrite` との関係。
2. `SendableBox` の thread-safety を説明するコメントを追加。

### 代替案: performActivity への置き換え（優先度: 低）
より標準的なアプローチを求める場合の選択肢。

- `write(...)` 内で `performActivity(withSynchronousWaiting: true)` を使用。
- 内部で `Task` を起動し、完了時に `done()` を呼ぶ。
- 既存の `writeAsync/export/exportCustom` は変更不要。

**メリット:**
- NSDocument の標準的なアクティビティ管理との統合。
- OS のドキュメント保存監視と連携。

**デメリット:**
- 大幅な書き換えが必要。
- 既存の実装が既に機能しているため、投資対効果が低い。
- Swift 6.0 の厳格な concurrency チェック下でのデバッグコスト。

**判断基準:**
- Step 1-3 を実施後、実際の問題が発生した場合に検討。

## 擬似コード（NSProgress 統合イメージ）
> 実装サンプル。実際のコード変更は本計画では行わない。

### Step 1: NSProgress 統合

```swift
// in Document.swift
private var saveProgress: Progress? = nil

private func writeAsync(to url: URL, ofType typeName: String) async throws {
    guard let mutator = self.movieMutator else { preconditionFailure("Unexpected nil mutator detected.") }
    
    // Create NSProgress
    let progress = Progress(totalUnitCount: 100)
    self.saveProgress = progress
    // Optional: Integrate with NSDocument standard progress
    // self.progress = progress
    defer {
        self.saveProgress = nil
        // self.progress = nil
    }
    
    // Show busy sheet
    showBusySheet("Writing...", "Please hold on second(s)...")
    mutator.unblockUserInteraction = { @Sendable [weak self] in
        self?.unblockUserInteraction()
    }
    defer {
        mutator.unblockUserInteraction = nil
        hideBusySheet()
    }
    mutator.updateProgress = { @Sendable [weak self] (progressValue) in
        guard let self else { preconditionFailure("Unexpected nil self detected.") }
        performSyncOnMainActor {
            updateProgress(progressValue)
            // Update NSProgress
            if let progress = self.saveProgress {
                progress.completedUnitCount = Int64(progressValue * 100)
            }
        }
    }
    defer {
        mutator.updateProgress = nil
    }
    
    // Existing write logic...
    let fileType: AVFileType = AVFileType.init(rawValue: typeName)
    if fileType == .mov {
        try await mutator.writeMovie(to: url, fileType: fileType, copySampleData: self.copyData)
    } else {
        try await mutator.exportMovie(to: url, fileType: fileType, presetName: nil)
    }
}
```

### Step 2: キャンセル対応

```swift
// in MovieWriter.swift (actor)
public func cancelExport() {
    writeCancelled = true
    exportSession?.cancelExport()
    // For custom export, delegate to existing cancelCustomMovie logic
}

// in MovieMutator.swift
public func cancel() {
    Task { @Sendable [weak self] in
        await self?.movieWriter?.cancelExport()
    }
}

// in Document+Utilities.swift - Update showBusySheet
public func showBusySheet(_ message: String?, _ info: String?) {
    Task { @MainActor in
        guard let window = self.window else { return }
        
        let alert: NSAlert = NSAlert()
        alert.messageText = message ?? "Processing...(message)"
        alert.informativeText = info ?? "Hold on seconds...(informative)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel") // Add Cancel button
        let handler: (NSApplication.ModalResponse) -> Void = {[weak self] (response) in
            if response == .alertFirstButtonReturn {
                // User clicked Cancel
                self?.saveProgress?.cancel()
                self?.movieMutator?.cancel()
            }
        }
        alert.beginSheetModal(for: window, completionHandler: handler)
        
        self.alert = alert
    }
}

// in Document.swift - Handle cancellation in write()
override nonisolated func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                    originalContentsURL absoluteOriginalContentsURL: URL?) throws {
    do {
        try performAsync { @Sendable [weak self] in
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            
            // Existing write logic...
        }
    } catch let error as NSError {
        // Check if error is due to cancellation
        if error.domain == "MovieWriterError" && error.localizedDescription.contains("cancelled") {
            // Silent return - don't show error sheet
            // Document remains dirty (unsaved)
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }
        throw error
    }
}
```

## 段階的移行計画
### Phase 1: NSProgress 統合（リスク: 低）
- **目標**: 進捗報告の標準化とシステム統合の準備
- **変更箇所**:
  - `Document.swift`: `saveProgress` プロパティ追加
  - `writeAsync/export/exportCustom`: NSProgress の作成と更新
- **検証**:
  - 進捗表示が正常に動作すること
  - 既存の Busy Sheet との共存
  - メモリリークがないこと

### Phase 2: ドキュメント化（リスク: なし）
- **目標**: 現在の実装の意図を明確化し、将来のメンテナンスを容易に
- **変更箇所**:
  - `Document+Utilities.swift`: `performAsync` と `SendableBox` にコメント追加
  - `Document.swift`: `canAsynchronouslyWrite` と `write()` の関係を説明
- **検証**:
  - コードレビューでの理解度確認

### Phase 3: キャンセル対応（リスク: 中）
- **目標**: ユーザー体験の向上（長時間処理の中断を可能に）
- **変更箇所**:
  - `MovieWriter.swift`: `cancelExport()` メソッド追加
  - `MovieMutator.swift`: `cancel()` メソッド追加
  - `Document+Utilities.swift`: Busy Sheet に Cancel ボタン追加
  - `Document.swift`: キャンセルエラーの特別処理
- **検証**:
  - キャンセル時にリソースが適切に解放されること
  - ドキュメント状態が正しく保持されること（Dirty フラグ）
  - 再度保存を試みた際に正常に動作すること

### Phase 4: performActivity 検討（オプショナル、リスク: 高）
- **前提条件**: Phase 1-3 実施後、実際の問題が発生した場合
- **目標**: NSDocument の標準パターンへの完全移行
- **変更箇所**:
  - `Document.swift`: `write()` の完全書き換え
- **検証**:
  - すべての保存シナリオの網羅的テスト
  - Sandbox 環境での動作確認
  - パフォーマンスの比較

### 各フェーズ間の判断基準
- Phase 1 → Phase 2: 自動的に移行（リスクなし）
- Phase 2 → Phase 3: ユーザーフィードバック次第（キャンセル機能の要望）
- Phase 3 → Phase 4: 実際の問題発生時のみ（推奨しない）

## 互換性と期待される挙動
- 外部公開 API/書式は不変。
- 保存/エクスポートの開始・完了・失敗のタイミングは従来どおり。
- ユーザ体験: 
  - Phase 1-2: 変更なし（内部実装の改善のみ）
  - Phase 3: Cancel ボタンの追加（オプト・イン的な機能追加）
- パフォーマンス: 既存の実装と同等を維持。NSProgress の追加オーバーヘッドは無視できるレベル。

## テスト計画
### 正常系
- mov 自己完結保存 / 参照ムービー保存
- mp4/m4v/m4a 変換（preset 使用）
- カスタムエクスポート（各種コーデック/ビットレート設定）
- Save / Save As / Save To の各操作

### 異常系
- UTI 不一致、拡張子不一致
- 空ムービー（duration = 0）
- 自己完結→参照上書きブロック
- ディスク不足、書込権限不足
- 破損したメディアファイル

### 進捗/長時間処理（Phase 1）
- 10分超のエクスポートで進捗が滑らかに更新されること
- NSProgress の completedUnitCount が適切に更新されること
- 進捗更新の頻度が適切であること（100ms 間隔）

### キャンセル処理（Phase 3）
- エクスポート中のキャンセルで安全に中止できること
- キャンセル後にエラーシートが表示されないこと
- ドキュメントが Dirty 状態を保持すること
- キャンセル後に再度保存を試みると正常に動作すること
- AVAssetExportSession/AVAssetWriter のリソースが適切に解放されること

### リグレッションテスト
- 既存の読み込み/再生/編集機能への影響がないこと
- Undo/Redo が正常に動作すること
- 複数ドキュメントの同時処理
- Sandbox 環境でのファイルアクセス（security-scoped bookmarks）

## 品質ゲート
### Phase 1（NSProgress 統合）
- Build: プロジェクトがエラーなくビルド可能（Swift 6.0 strict concurrency）
- Lint/Format: 既存スタイルガイド準拠（セクション MARK、ドキュメンテーションコメント）
- Unit Test: 進捗更新ロジックの検証
- Manual Test: 主要な保存シナリオで進捗が正しく表示されること
- Memory: Instruments での leak チェック

### Phase 2（ドキュメント化）
- Code Review: コメントの明確性と正確性
- Documentation: 技術的な判断の背景が説明されていること

### Phase 3（キャンセル対応）
- Build: エラーなくビルド可能
- API Test: 新規追加された cancel メソッドの動作確認
- Integration Test: Cancel ボタンから MovieWriter まで一貫してキャンセルが伝播すること
- Stress Test: キャンセル後の再試行を複数回繰り返しても問題ないこと
- Resource Test: キャンセル後にファイルハンドルや一時ファイルが残らないこと

### 全フェーズ共通
- Regression: 既存の読み込み/再生/GUI 操作へ副作用がないこと
- Performance: 既存実装と比較して性能劣化がないこと
- Sandbox: security-scoped bookmarks が正常に機能すること

## リスクと緩和
### Phase 1（NSProgress 統合）のリスク
- **リスク**: NSProgress の更新頻度が高すぎてパフォーマンスに影響
  - **緩和策**: 既存の更新頻度制限（100ms 間隔）を維持
- **リスク**: MainActor での進捗更新が UI をブロック
  - **緩和策**: 既に `performSyncOnMainActor` で適切に処理されている
- **リスク**: メモリリーク（Progress オブジェクトの保持）
  - **緩和策**: defer ブロックでの確実なクリーンアップ、Instruments での検証

### Phase 3（キャンセル対応）のリスク
- **リスク**: キャンセル時のリソースリーク
  - **緩和策**: 
    - `MovieWriter` の既存 `writeCancelled` フラグを活用
    - AVAssetExportSession/AVAssetWriter の適切なクリーンアップ確認
    - defer ブロックでの確実なリソース解放
- **リスク**: キャンセル後のドキュメント状態の不整合
  - **緩和策**: 
    - キャンセルを `NSUserCancelledError` として扱う
    - ドキュメントの Dirty フラグを維持
    - 部分的に書き込まれたファイルのクリーンアップ
- **リスク**: 複数回のキャンセル/再試行での不具合
  - **緩和策**: ストレステストでの検証、状態リセットの確認

### Phase 4（performActivity）のリスク
- **リスク**: 大規模リファクタリングによる予期しない副作用
  - **緩和策**: このフェーズは推奨しない。実施する場合は十分な検証期間を確保
- **リスク**: Swift 6.0 厳格な concurrency チェックでのコンパイルエラー
  - **緩和策**: 段階的な実装、小さなプロトタイプでの事前検証

### 共通リスク
- **リスク**: Sandbox 環境でのファイルアクセス問題
  - **緩和策**: security-scoped bookmarks の維持確認、既存のアクセスパターンを変更しない

## ロールバック戦略
### Phase 1（NSProgress 統合）のロールバック
- NSProgress 関連のコードを削除
- `updateProgress` の変更を元に戻す
- `saveProgress` プロパティを削除
- **所要時間**: 数時間
- **リスク**: 低（追加コードのみの削除）

### Phase 3（キャンセル対応）のロールバック
- Cancel ボタンを削除
- `cancelExport()` / `cancel()` メソッドを削除
- キャンセルエラー処理を削除
- **所要時間**: 1日
- **リスク**: 低（機能追加のみの削除）

### Phase 4（performActivity）のロールバック
- `write()` メソッド全体を以前の実装に戻す
- `performAsync` ユーティリティを復元（削除していた場合）
- **所要時間**: 数日（網羅的なテストが必要）
- **リスク**: 中（コア機能の変更）

### ロールバック判断基準
- **Phase 1**: 進捗更新でのパフォーマンス問題、メモリリーク
- **Phase 3**: キャンセル後の不安定動作、リソースリーク
- **Phase 4**: 保存失敗率の増加、予期しないクラッシュ

### バージョン管理
- 各フェーズを個別のコミットとして記録
- タグ付け: `phase1-nsprogress`, `phase2-docs`, `phase3-cancel`
- 問題発生時は該当コミットまで revert または cherry-pick で修正

## 今後の拡張
### 短期（Phase 1-3 実施後）
- NSProgress を NSWindow の標準進捗 UI と連携（ツールバー/タイトルバー表示）
- 進捗バーのビジュアル改善（Busy Sheet 内に埋め込み）
- 推定残り時間の表示（`estimatedTimeRemaining` プロパティ）

### 中期
- エクスポートプリセット別の最適化された進捗推定
- バックグラウンドエクスポート（ドキュメントを閉じても続行）
- 複数ドキュメントの並列エクスポート管理

### 長期（Phase 4 検討時）
- `NSDocument.performActivity` への完全移行（必要性が確認された場合）
- システムレベルの進捗監視との統合
- App Intents / Shortcuts 対応（自動化サポート）

### 計測とモニタリング
- 進捗テレメトリ（ログ/計測）でボトルネック解析
- エクスポート時間の統計収集
- ユーザーのキャンセル頻度分析（Phase 3 後）

## 参考: 影響箇所一覧
### Phase 1（NSProgress 統合）
- `Document.swift`
  - `saveProgress` プロパティ追加（private）
  - `writeAsync(to:ofType:)` 修正（NSProgress 作成・更新・クリーンアップ）
  - `export(to:ofType:preset:)` 修正（同上）
  - `exportCustom(to:ofType:)` 修正（同上）

### Phase 2（ドキュメント化）
- `Document+Utilities.swift`
  - `performAsync` メソッドのドキュメンテーションコメント拡充
  - `SendableBox` クラスのコメント追加
- `Document.swift`
  - `canAsynchronouslyWrite(to:ofType:for:)` のコメント追加
  - `write(to:ofType:for:originalContentsURL:)` のコメント追加

### Phase 3（キャンセル対応）
- `MovieWriter.swift`（actor）
  - `cancelExport()` メソッド追加（public）
  - 既存の `writeCancelled` フラグを活用
- `MovieMutator.swift`
  - `cancel()` メソッド追加（public）
- `Document+Utilities.swift`
  - `showBusySheet(_:_:)` 修正（Cancel ボタン追加）
- `Document.swift`
  - `write(to:ofType:for:originalContentsURL:)` 修正（キャンセルエラー処理）

### Phase 4（performActivity、オプショナル）
- `Document.swift`
  - `write(to:ofType:for:originalContentsURL:)` 全面書き換え
- `Document+Utilities.swift`
  - `performAsync` の使用状況確認、必要に応じて deprecation

### 非影響箇所（変更不要）
- `MovieMutatorBase.swift`（変更なし）
- `ViewController.swift`（変更なし）
- `WindowController.swift`（変更なし）
- UI/Storyboard（Phase 3 で Cancel ボタン追加時も、プログラムで実装）
- 個別の編集ロジック（MovieMutator の各種操作メソッド）

---

## 実装上の技術的補足

### Swift 6.0 Concurrency への対応
- プロジェクトは Swift 6.0 を使用し、厳格な concurrency チェックが有効
- `@Sendable`、`@MainActor`、actor isolation の要件を遵守
- `@unchecked Sendable` の使用は最小限に抑え、必要な場合は詳細にコメント化

### SendableBox の現状
- `Document+Utilities.swift` に既存実装あり
- `@unchecked Sendable` + `DispatchQueue` によるスレッドセーフな Result 受け渡し
- 計画書の擬似コードにある `AtomicBox` は未実装（SendableBox で代替可能）

### ActorUtilities の活用
- `ActorUtilities.swift` が既に存在
- `performSyncOnMainActor` の実装を提供
- `Thread.isMainThread` チェックと `MainActor.assumeIsolated` を使用

### MovieWriter の actor 設計
- `MovieWriter` は actor として実装済み
- `writeCancelled` フラグと `cancelCustomMovie` メソッドが既に存在
- `AVAssetExportSession` の進捗監視は polling task で実装済み
- キャンセル対応は既存のインフラを活用可能

### Sandbox と Security-Scoped Bookmarks
- 長時間処理中のブックマーク有効性を維持する必要あり
- `canAsynchronouslyWrite` + バックグラウンド実行により、AppKit が適切に管理
- 参照ムービーの Save As 時には、元ファイルへのアクセスを保持（既存実装で対応済み）

### NSProgress の Thread-Safety
- `Progress` クラスは thread-safe
- ただし、UI 更新を伴う場合は MainActor での更新を推奨
- 既存の `performSyncOnMainActor` パターンを継続使用

---

この計画は、実際のコードベース検証に基づき、最小変更で最大の効果を得る段階的アプローチを採用しています。既に機能している実装を尊重しつつ、標準的な進捗管理とユーザー体験の向上を目指します。
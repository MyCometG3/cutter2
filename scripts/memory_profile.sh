#!/bin/bash

# cutter2 Memory Profiling Script
#
# This script profiles memory usage of the cutter2 application using command-line tools.
# It captures baseline metrics, monitors memory during operations, and detects leaks.
#
# Usage: ./scripts/memory_profile.sh [test_file]
#
# Requirements:
#   - cutter2 must be built in Release configuration
#   - Test file must be a valid MOV file (default: scripts/sampleMedia/DL-1115173527.mov)
#
# Output:
#   - Memory metrics logged to stdout
#   - Detailed analysis saved to docs/memory_profile_results.txt

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/.build/Build/Products/Release/cutter2.app"
APP_BINARY="$APP_PATH/Contents/MacOS/cutter2"
TEST_FILE_ARG="$1"
if [ -n "$TEST_FILE_ARG" ]; then
    # Convert to absolute path if relative
    TEST_FILE="$(cd "$(dirname "$TEST_FILE_ARG")" 2>/dev/null && pwd)/$(basename "$TEST_FILE_ARG")" || TEST_FILE="$TEST_FILE_ARG"
else
    TEST_FILE="$PROJECT_ROOT/scripts/sampleMedia/DL-1115173527.mov"
fi
OUTPUT_FILE="$PROJECT_ROOT/docs/memory_profile_results.txt"
SAMPLE_INTERVAL=2  # seconds between samples

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  cutter2 Memory Profiling${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verify app exists
if [ ! -f "$APP_BINARY" ]; then
    echo -e "${RED}❌ Error: cutter2 not found at $APP_PATH${NC}"
    echo "   Please build the app first:"
    echo "   xcodebuild -project cutter2.xcodeproj -scheme cutter2 -configuration Release build"
    exit 1
fi

# Verify test file exists
if [ ! -f "$TEST_FILE" ]; then
    echo -e "${YELLOW}⚠️  Warning: Test file not found: $TEST_FILE${NC}"
    echo "   This script will profile the app without opening a file."
    echo ""
    TEST_FILE=""
fi

echo -e "${CYAN}Configuration:${NC}"
echo "  App: $APP_PATH"
echo "  Test File: ${TEST_FILE:-None (baseline only)}"
echo "  Output: $OUTPUT_FILE"
echo "  Sample Interval: ${SAMPLE_INTERVAL}s"
echo ""

# Verify app is accessible
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: App bundle not found at $APP_PATH${NC}"
    exit 1
fi

# Initialize output file
cat > "$OUTPUT_FILE" << EOF
cutter2 Memory Profiling Report
Date: $(date)
Test File: ${TEST_FILE:-None (baseline only)}
========================================

EOF

# Function to get memory usage for a PID
get_memory_usage() {
    local pid=$1
    local label=$2
    
    if ! ps -p $pid > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Process $pid no longer running${NC}"
        return 1
    fi
    
    # Get memory info using ps
    local mem_info=$(ps -o rss=,vsz= -p $pid 2>/dev/null)
    if [ -z "$mem_info" ]; then
        return 1
    fi
    
    local rss=$(echo $mem_info | awk '{print $1}')
    local vsz=$(echo $mem_info | awk '{print $2}')
    local rss_mb=$((rss / 1024))
    local vsz_mb=$((vsz / 1024))
    
    echo -e "${GREEN}[$label]${NC} RSS: ${rss_mb} MB, VSZ: ${vsz_mb} MB"
    echo "[$label] RSS: ${rss_mb} MB, VSZ: ${vsz_mb} MB" >> "$OUTPUT_FILE"
    
    return 0
}

# Function to check for leaks
check_leaks() {
    local pid=$1
    local label=$2
    
    echo -e "${CYAN}Checking for leaks ($label)...${NC}"
    echo "" >> "$OUTPUT_FILE"
    echo "=== Leak Check: $label ===" >> "$OUTPUT_FILE"
    
    # Run leaks command
    local leak_output=$(leaks $pid 2>&1)
    local leak_count=$(echo "$leak_output" | grep "ROOT LEAK" | wc -l | tr -d ' ')
    
    if [ "$leak_count" -gt 0 ]; then
        echo -e "${RED}❌ Found $leak_count leak(s)${NC}"
        echo "$leak_output" >> "$OUTPUT_FILE"
    else
        echo -e "${GREEN}✅ No leaks detected${NC}"
        echo "No leaks detected" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
}

# Function to get heap statistics
get_heap_stats() {
    local pid=$1
    local label=$2
    
    echo -e "${CYAN}Analyzing heap ($label)...${NC}"
    echo "" >> "$OUTPUT_FILE"
    echo "=== Heap Statistics: $label ===" >> "$OUTPUT_FILE"
    
    # Get heap summary
    heap $pid 2>&1 | head -30 >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

# Function to get VM map summary
get_vmmap_summary() {
    local pid=$1
    local label=$2
    
    echo -e "${CYAN}Getting VM map summary ($label)...${NC}"
    echo "" >> "$OUTPUT_FILE"
    echo "=== VM Map Summary: $label ===" >> "$OUTPUT_FILE"
    
    # Get VM map with MALLOC regions
    vmmap $pid 2>&1 | grep -A 20 "MALLOC\|SUMMARY" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

echo -e "${YELLOW}📱 Launching cutter2...${NC}"

# Launch app in background
if [ -n "$TEST_FILE" ]; then
    open -a "$APP_PATH" "$TEST_FILE" &
else
    open -a "$APP_PATH" &
fi

# Wait for app to launch
sleep 3

# Find the app's PID
APP_PID=$(pgrep -f "cutter2.app/Contents/MacOS/cutter2" | head -1)

if [ -z "$APP_PID" ]; then
    echo -e "${RED}❌ Error: Could not find cutter2 process${NC}"
    exit 1
fi

echo -e "${GREEN}✅ cutter2 launched (PID: $APP_PID)${NC}"
echo ""

# Session 1: Baseline measurement
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Session 1: Baseline Measurement${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Session 1: Baseline Measurement" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

sleep 2
get_memory_usage $APP_PID "Initial" || exit 1

if [ -n "$TEST_FILE" ]; then
    echo ""
    echo -e "${YELLOW}⏸️  Please interact with the app:${NC}"
    echo "   1. Wait for file to load (a few seconds)"
    echo "   2. Play the video for ~10 seconds"
    echo "   3. Stop playback"
    echo "   4. Press ENTER when ready to continue..."
    read
    
    get_memory_usage $APP_PID "After Playback" || exit 1
    get_heap_stats $APP_PID "After Playback"
fi

# Session 2: Memory after operations
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Session 2: Operations Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Session 2: Operations Test" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

if [ -n "$TEST_FILE" ]; then
    echo -e "${YELLOW}⏸️  Please perform these operations:${NC}"
    echo "   1. Scrub through timeline"
    echo "   2. Set in/out points"
    echo "   3. Cut/copy/paste a clip"
    echo "   4. Undo/redo a few times"
    echo "   5. Press ENTER when done..."
    read
    
    get_memory_usage $APP_PID "After Operations" || exit 1
    get_heap_stats $APP_PID "After Operations"
fi

# Session 3: Leak detection
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Session 3: Leak Detection${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Session 3: Leak Detection" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

check_leaks $APP_PID "During Session"

# Get VM map for detailed analysis
get_vmmap_summary $APP_PID "Final State"

# Final memory measurement
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Final Measurements${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Final Measurements" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

get_memory_usage $APP_PID "Final" || echo "Process terminated"

echo ""
echo -e "${YELLOW}⏸️  Close the app and press ENTER to check for cleanup...${NC}"
read

# Wait for app to close
sleep 2

# Check if app is still running
if ps -p $APP_PID > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  App still running, terminating...${NC}"
    kill $APP_PID 2>/dev/null || true
    sleep 2
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Profiling Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Results saved to: $OUTPUT_FILE${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Review results in $OUTPUT_FILE"
echo "  2. Identify memory hotspots"
echo "  3. Compare with expected baseline (200-800 MB for ProRes)"
echo "  4. Plan optimization strategy"
echo ""

# Display summary
echo "=== Summary ===" >> "$OUTPUT_FILE"
echo "Profiling completed at $(date)" >> "$OUTPUT_FILE"

cat "$OUTPUT_FILE"

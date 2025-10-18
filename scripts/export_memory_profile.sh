#!/bin/bash

# cutter2 Export Memory Profiling Script
#
# This script profiles memory usage during video export operations.
# It measures memory consumption during H.264/HEVC export to identify bottlenecks.
#
# Usage: ./scripts/export_memory_profile.sh [test_file] [output_file]
#
# Requirements:
#   - cutter2 must be built in Release configuration
#   - Test file must be a valid MOV file (default: scripts/sampleMedia/DL-1115173527.mov)
#
# Output:
#   - Memory metrics logged to stdout
#   - Detailed analysis saved to docs/export_memory_profile_results.txt

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
    TEST_FILE="$(cd "$(dirname "$TEST_FILE_ARG")" 2>/dev/null && pwd)/$(basename "$TEST_FILE_ARG")" || TEST_FILE="$TEST_FILE_ARG"
else
    TEST_FILE="$PROJECT_ROOT/scripts/sampleMedia/DL-1115173527.mov"
fi
OUTPUT_FILE="${2:-$PROJECT_ROOT/docs/export_memory_profile_results.txt}"
EXPORT_OUTPUT="/tmp/cutter2_export_test_$(date +%s).mp4"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  cutter2 Export Memory Profiling${NC}"
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
    echo -e "${RED}❌ Error: Test file not found: $TEST_FILE${NC}"
    exit 1
fi

# Verify app is accessible
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: App bundle not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${CYAN}Configuration:${NC}"
echo "  App: $APP_PATH"
echo "  Test File: $TEST_FILE"
echo "  Export Output: $EXPORT_OUTPUT"
echo "  Results: $OUTPUT_FILE"
echo ""

# Get file info
if command -v mediainfo >/dev/null 2>&1; then
    echo -e "${CYAN}Test File Info:${NC}"
    FILE_SIZE=$(ls -lh "$TEST_FILE" | awk '{print $5}')
    echo "  Size: $FILE_SIZE"
    DURATION=$(mediainfo --Inform="Video;%Duration%" "$TEST_FILE" 2>/dev/null | head -1)
    if [ -n "$DURATION" ]; then
        DURATION_SEC=$((DURATION / 1000))
        echo "  Duration: ${DURATION_SEC}s"
    fi
    echo ""
elif command -v ffprobe >/dev/null 2>&1; then
    echo -e "${CYAN}Test File Info:${NC}"
    FILE_SIZE=$(ls -lh "$TEST_FILE" | awk '{print $5}')
    echo "  Size: $FILE_SIZE"
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TEST_FILE" 2>/dev/null)
    if [ -n "$DURATION" ]; then
        echo "  Duration: ${DURATION}s"
    fi
    echo ""
fi

# Initialize output file
cat > "$OUTPUT_FILE" << EOF
cutter2 Export Memory Profiling Report
Date: $(date)
Test File: $TEST_FILE
Export Output: $EXPORT_OUTPUT
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

# Function to monitor memory continuously
monitor_memory_continuous() {
    local pid=$1
    local duration=$2
    local interval=2
    
    echo "" >> "$OUTPUT_FILE"
    echo "=== Continuous Memory Monitoring ===" >> "$OUTPUT_FILE"
    
    local elapsed=0
    local max_rss=0
    local sample_count=0
    
    while [ $elapsed -lt $duration ] && ps -p $pid > /dev/null 2>&1; do
        local mem_info=$(ps -o rss=,vsz= -p $pid 2>/dev/null)
        if [ -n "$mem_info" ]; then
            local rss=$(echo $mem_info | awk '{print $1}')
            local vsz=$(echo $mem_info | awk '{print $2}')
            local rss_mb=$((rss / 1024))
            local vsz_mb=$((vsz / 1024))
            
            if [ $rss_mb -gt $max_rss ]; then
                max_rss=$rss_mb
            fi
            
            echo "[${elapsed}s] RSS: ${rss_mb} MB, VSZ: ${vsz_mb} MB" >> "$OUTPUT_FILE"
            sample_count=$((sample_count + 1))
            
            # Show progress
            echo -ne "\r  Monitoring... ${elapsed}s / ${duration}s (RSS: ${rss_mb} MB, Peak: ${max_rss} MB)"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    echo "" >> "$OUTPUT_FILE"
    echo "Peak RSS during export: ${max_rss} MB (${sample_count} samples)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo -e "${CYAN}Peak RSS: ${max_rss} MB${NC}"
}

echo -e "${YELLOW}📱 Launching cutter2 with test file...${NC}"

# Launch app with test file
open -a "$APP_PATH" "$TEST_FILE" &

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

# Session 1: Initial state
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Initial State${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Initial State" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

sleep 2
get_memory_usage $APP_PID "Before Export" || exit 1

# Prepare for export
echo ""
echo -e "${YELLOW}⏸️  Please start export operation:${NC}"
echo "   1. File → Export → Export as H.264 (⌘E)"
echo "   2. Choose output location: $EXPORT_OUTPUT"
echo "   3. Click Export"
echo "   4. Press ENTER when export STARTS (don't wait for completion)..."
read

# Get export start state
get_memory_usage $APP_PID "Export Start" || exit 1

# Session 2: Monitor during export
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Monitoring During Export${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Monitoring During Export" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

# Monitor for up to 120 seconds (adjust based on file size)
MONITOR_DURATION=120
echo -e "${CYAN}Monitoring memory for up to ${MONITOR_DURATION}s (or until export completes)...${NC}"
monitor_memory_continuous $APP_PID $MONITOR_DURATION

# Session 3: After export completion
echo ""
echo -e "${YELLOW}⏸️  Press ENTER after export completes...${NC}"
read

if ps -p $APP_PID > /dev/null 2>&1; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  After Export Completion${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "After Export Completion" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
    
    sleep 2
    get_memory_usage $APP_PID "After Export" || echo "Process terminated"
else
    echo -e "${YELLOW}⚠️  Process terminated during export${NC}"
fi

# Check exported file
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Export Results${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Export Results" >> "$OUTPUT_FILE"
echo "========================================" >> "$OUTPUT_FILE"

if [ -f "$EXPORT_OUTPUT" ]; then
    EXPORT_SIZE=$(ls -lh "$EXPORT_OUTPUT" | awk '{print $5}')
    echo -e "${GREEN}✅ Export successful${NC}"
    echo "  Output: $EXPORT_OUTPUT"
    echo "  Size: $EXPORT_SIZE"
    echo "" >> "$OUTPUT_FILE"
    echo "Export successful" >> "$OUTPUT_FILE"
    echo "Output: $EXPORT_OUTPUT" >> "$OUTPUT_FILE"
    echo "Size: $EXPORT_SIZE" >> "$OUTPUT_FILE"
    
    # Cleanup
    echo ""
    echo -e "${CYAN}Cleaning up temporary export file...${NC}"
    rm -f "$EXPORT_OUTPUT"
    echo "Temporary file removed"
else
    echo -e "${RED}❌ Export file not found${NC}"
    echo "Export may have failed or been cancelled"
    echo "" >> "$OUTPUT_FILE"
    echo "Export file not found" >> "$OUTPUT_FILE"
fi

# Final cleanup
echo ""
echo -e "${YELLOW}⏸️  Close the app and press ENTER to finish...${NC}"
read

# Wait for app to close
sleep 2

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
echo -e "${YELLOW}Summary:${NC}"

# Extract and display summary
if [ -f "$OUTPUT_FILE" ]; then
    echo "  Peak memory usage:"
    grep "Peak RSS" "$OUTPUT_FILE" | tail -1
    echo ""
    echo "  Memory timeline:"
    grep "^\[" "$OUTPUT_FILE" | grep -v "Continuous\|Leak\|Heap\|VM Map" | tail -5
fi

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Review full results in $OUTPUT_FILE"
echo "  2. Compare with baseline (Day 1: 74-203 MB)"
echo "  3. Identify any memory growth patterns"
echo "  4. Check if optimization is needed"
echo ""

# Display summary
echo "=== Summary ===" >> "$OUTPUT_FILE"
echo "Profiling completed at $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "Note: For detailed export metrics, compare this with Day 1 baseline results." >> "$OUTPUT_FILE"

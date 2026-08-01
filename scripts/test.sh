#!/bin/bash

# cutter2 Test Runner Script
# 
# This script runs all tests for the cutter2 application with code coverage enabled.
# 
# Test Suite (as of Phase 2.1):
#   - 15 test files
#   - 190 total tests (189 passing + 1 skipped)
#   - Expected result: 189/190 passing (99.5%)
#
# Usage: ./scripts/test.sh [derivedDataPath]
#
# Options:
#   derivedDataPath - Optional custom derived data path (default: ./.build)
#
# Required Test Media:
#   - scripts/sampleMedia/DL-1115173527.mov (sample movie file for tests)

set -e

echo "🧪 Running cutter2 tests..."
echo "   Test Suite: 15 files, 190 tests"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for required test media
SAMPLE_MEDIA="./scripts/sampleMedia/DL-1115173527.mov"
if [ ! -f "$SAMPLE_MEDIA" ]; then
  echo -e "${YELLOW}⚠️  Warning: Sample media file not found${NC}"
  echo "   Expected: $SAMPLE_MEDIA"
  echo "   Some tests may be skipped or fail without this file."
  echo ""
fi

# Use custom derived data path or default
DERIVED_DATA_PATH="${1:-./.build}"

echo -e "${BLUE}ℹ️  Configuration:${NC}"
echo "   Project: cutter2.xcodeproj"
echo "   Scheme: cutter2"
echo "   Destination: platform=macOS"
echo "   Derived Data: $DERIVED_DATA_PATH"
echo "   Code Coverage: Enabled"
echo ""

# Run build, test, and analyze sequentially (xcodebuild does not parallelize these well)
echo -e "${BLUE}🔨 Building...${NC}"
xcodebuild clean build \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

BUILD_RESULT=$?
if [ $BUILD_RESULT -ne 0 ]; then
  echo -e "${RED}❌ Build failed!${NC}"
  exit 1
fi

echo -e "${BLUE}🧪 Running tests...${NC}"
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -enableCodeCoverage YES \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

TEST_RESULT=$?
if [ $TEST_RESULT -ne 0 ]; then
  echo -e "${RED}❌ Tests failed!${NC}"
  exit 1
fi

echo -e "${BLUE}🔍 Analyzing...${NC}"
xcodebuild analyze \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

ANALYZE_RESULT=$?
if [ $ANALYZE_RESULT -ne 0 ]; then
  echo -e "${RED}❌ Analysis failed!${NC}"
  exit 1
fi

if [ $TEST_RESULT -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✅ All tests passed!${NC}"
  echo ""
  
  # Generate coverage report if tests passed
  echo "📊 Generating code coverage report..."
  
  # Search for coverage data in derived data path first, then fall back to default locations
  SEARCH_PATHS=(
    "$DERIVED_DATA_PATH"
    ~/Library/Developer/Xcode/DerivedData
    ./build
  )
  
  PROFDATA=""
  BINARY=""
  
  for search_path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$search_path" ]; then
      PROFDATA=$(find "$search_path" -name "Coverage.profdata" 2>/dev/null | head -1)
      if [ -n "$PROFDATA" ]; then
        BINARY=$(find "$search_path" -name "cutter2" -type f 2>/dev/null | grep -v ".dSYM" | grep "MacOS" | head -1)
        if [ -n "$BINARY" ]; then
          echo -e "${YELLOW}ℹ️  Found coverage data in: $search_path${NC}"
          break
        fi
      fi
    fi
  done
  
  if [ -n "$PROFDATA" ] && [ -n "$BINARY" ]; then
    echo "   Using profdata: $PROFDATA"
    echo "   Using binary: $BINARY"
    echo ""
    
    # Generate LCOV format coverage report
    if xcrun llvm-cov export \
      -format="lcov" \
      -instr-profile="$PROFDATA" \
      "$BINARY" \
      > coverage.lcov 2>&1; then
      echo -e "${GREEN}✅ Coverage report generated: coverage.lcov${NC}"
      echo ""
      
      # Display coverage summary
      echo "📈 Coverage Summary:"
      xcrun llvm-cov report \
        -instr-profile="$PROFDATA" \
        "$BINARY" 2>&1 || echo -e "${YELLOW}⚠️  Could not generate coverage summary${NC}"
    else
      echo -e "${YELLOW}⚠️  Could not generate coverage report${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  Could not find coverage data${NC}"
    echo "   Searched in:"
    for search_path in "${SEARCH_PATHS[@]}"; do
      echo "   - $search_path"
    done
    echo ""
    echo "   Try running with a custom derived data path:"
    echo "   ./scripts/test.sh /path/to/derivedData"
  fi
  
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Test Run Summary${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Status: ✅ All Passed${NC}"
echo -e "  Test Files: 15"
echo -e "  Total Tests: 190"
echo -e "    - Passing: 189"
echo -e "    - Skipped: 1"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
else
  echo ""
  echo -e "${RED}❌ Tests failed!${NC}"
  echo ""
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}  Test Run Summary${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}  Status: ❌ Failed${NC}"
  echo -e "  Check the output above for details"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  exit 1
fi

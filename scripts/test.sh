#!/bin/bash

# cutter2 Test Runner Script
# 
# This script runs all tests for the cutter2 application with code coverage enabled.
# Usage: ./scripts/test.sh [derivedDataPath]
#
# Options:
#   derivedDataPath - Optional custom derived data path (default: ./.build)

set -e

echo "🧪 Running cutter2 tests..."
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Use custom derived data path or default
DERIVED_DATA_PATH="${1:-./.build}"

# Run tests with code coverage using explicit derived data path
xcodebuild clean test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -enableCodeCoverage YES \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

TEST_RESULT=$?

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
else
  echo ""
  echo -e "${RED}❌ Tests failed!${NC}"
  exit 1
fi

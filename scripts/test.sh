#!/bin/bash

# cutter2 Test Runner Script
# 
# This script runs all tests for the cutter2 application with code coverage enabled.
# Usage: ./scripts/test.sh

set -e

echo "🧪 Running cutter2 tests..."
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Run tests with code coverage
xcodebuild clean test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
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
  
  PROFDATA=$(find ~/Library/Developer/Xcode/DerivedData -name "Coverage.profdata" 2>/dev/null | head -1)
  BINARY=$(find ~/Library/Developer/Xcode/DerivedData -name "cutter2" -type f 2>/dev/null | grep -v ".dSYM" | head -1)
  
  if [ -n "$PROFDATA" ] && [ -n "$BINARY" ]; then
    xcrun llvm-cov export \
      -format="lcov" \
      -instr-profile="$PROFDATA" \
      "$BINARY" \
      > coverage.lcov
    
    echo "✅ Coverage report generated: coverage.lcov"
    
    # Display coverage summary
    xcrun llvm-cov report \
      -instr-profile="$PROFDATA" \
      "$BINARY"
  else
    echo "⚠️  Could not find coverage data"
  fi
else
  echo ""
  echo -e "${RED}❌ Tests failed!${NC}"
  exit 1
fi

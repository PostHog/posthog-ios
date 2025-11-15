#!/bin/bash

# PostHog iOS SDK Documentation Generator
# This script generates JSON documentation from Swift source code for the PostHog documentation website

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Generating PostHog iOS SDK Documentation${NC}"

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create output directories
mkdir -p "$PROJECT_ROOT/references"
mkdir -p "$PROJECT_ROOT/symbolgraph"

# Clean build cache and docs directory to avoid conflicts
rm -rf "$PROJECT_ROOT/.build" 2>/dev/null || true
rm -rf "$PROJECT_ROOT/docs" 2>/dev/null || true

echo -e "${YELLOW}📦 Generating documentation using Swift DocC Plugin...${NC}"

# Generate documentation using Swift Package Manager and DocC Plugin
# Note: iOS-only properties may not appear if generated on macOS
swift package generate-documentation \
    --target PostHog \
    --emit-digest \
    --include-extended-types

# Find the generated documentation archive in the default build location
DOCC_ARCHIVE=$(find "$PROJECT_ROOT/.build" -name "*.doccarchive" -type d | head -1)

if [ -z "$DOCC_ARCHIVE" ]; then
    echo -e "${RED}❌ Could not find generated DocC archive${NC}"
    echo -e "${YELLOW}Searching for generated files...${NC}"
    find "$PROJECT_ROOT/.build" -type f -name "*.json" | head -10
    find "$PROJECT_ROOT/.build" -name "*.doccarchive" -type d
    exit 1
fi

echo -e "${YELLOW}📄 Found DocC archive at: $DOCC_ARCHIVE${NC}"

# Copy the archive to docs directory
mkdir -p "$PROJECT_ROOT/docs"
cp -r "$DOCC_ARCHIVE" "$PROJECT_ROOT/docs/"

# Update DOCC_ARCHIVE path to point to the copied version
DOCC_ARCHIVE="$PROJECT_ROOT/docs/$(basename "$DOCC_ARCHIVE")"

echo -e "${YELLOW}📄 Copied DocC archive to: $DOCC_ARCHIVE${NC}"

# Use the DocC archive directory directly instead of copying individual files
DOCC_DATA_DIR="$DOCC_ARCHIVE/data/documentation"

if [ ! -d "$DOCC_DATA_DIR" ]; then
    echo -e "${RED}❌ Could not find documentation data directory in DocC archive${NC}"
    echo -e "${YELLOW}Archive contents:${NC}"
    find "$DOCC_ARCHIVE" -type f | head -10
    exit 1
fi

echo -e "${YELLOW}📄 Found documentation data directory at: $DOCC_DATA_DIR${NC}"

# Create a symlink to the DocC data directory for easier access
ln -sf "$DOCC_DATA_DIR" "$PROJECT_ROOT/symbolgraph/docc-data"

echo -e "${YELLOW}🔄 Transforming symbol graph to PostHog documentation format...${NC}"

# Get version from PostHogVersion.swift
VERSION=$(grep 'postHogVersion = ' "$PROJECT_ROOT/PostHog/PostHogVersion.swift" | sed 's/.*"\(.*\)".*/\1/')

# Run the DocC Python transformer with the data directory and version
python3 "$SCRIPT_DIR/transform-docc.py" \
    "$DOCC_DATA_DIR" \
    "$PROJECT_ROOT/references/posthog-ios-references-latest.json" \
    "$VERSION"

# Create versioned copy
cp "$PROJECT_ROOT/references/posthog-ios-references-latest.json" \
   "$PROJECT_ROOT/references/posthog-ios-references-$VERSION.json"

echo -e "${GREEN}✅ Documentation generated successfully!${NC}"
echo -e "📄 Files created:"
echo -e "   - references/posthog-ios-references-latest.json"
echo -e "   - references/posthog-ios-references-$VERSION.json"

# Validate JSON
if python3 -m json.tool "$PROJECT_ROOT/references/posthog-ios-references-latest.json" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ JSON validation passed${NC}"
else
    echo -e "${RED}❌ JSON validation failed${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Done! Ready for integration with posthog.com${NC}"

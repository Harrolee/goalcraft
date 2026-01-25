#!/bin/bash
#
# GoalCraft Frontend Build Script
#
# This script builds the Flutter web application for production deployment.
# The output is placed in build/web directory, ready for deployment to
# Cloudflare Pages or any static hosting service.
#
# Usage:
#   ./build_web.sh
#
# Prerequisites:
#   - Flutter SDK installed and in PATH
#   - Run 'flutter pub get' before first build
#
# Environment Variables:
#   API_BASE_URL - Backend API URL (optional, defaults to production URL)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}GoalCraft Frontend Build Script${NC}"
echo "=================================="

# Navigate to frontend directory
cd "$SCRIPT_DIR"

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
    echo "Please install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
fi

# Display Flutter version
echo -e "${YELLOW}Flutter version:${NC}"
flutter --version

# Clean previous builds
echo -e "\n${YELLOW}Cleaning previous builds...${NC}"
flutter clean

# Get dependencies
echo -e "\n${YELLOW}Getting dependencies...${NC}"
flutter pub get

# Build for web
echo -e "\n${YELLOW}Building for web (release mode)...${NC}"

# Set API_BASE_URL if provided
if [ -n "${API_BASE_URL:-}" ]; then
    echo "Using API_BASE_URL: $API_BASE_URL"
    flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
else
    echo "Using default API_BASE_URL from configuration"
    flutter build web --release
fi

# Verify build output
if [ -d "build/web" ]; then
    echo -e "\n${GREEN}Build successful!${NC}"
    echo "Output directory: $SCRIPT_DIR/build/web"
    echo ""
    echo "Build contents:"
    ls -la build/web/
    echo ""
    echo "Total size:"
    du -sh build/web/
else
    echo -e "\n${RED}Build failed: build/web directory not found${NC}"
    exit 1
fi

echo -e "\n${GREEN}Build complete!${NC}"
echo "To deploy to Cloudflare Pages:"
echo "  npx wrangler pages deploy build/web --project-name=goalcraft"

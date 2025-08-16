#!/usr/bin/env bash
set -euo pipefail

# Bump marketing version (CFBundleShortVersionString) and build number (CFBundleVersion)
# Usage: scripts/bump_version.sh 1.1 2

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <marketing_version> <build_number>" >&2
  exit 1
fi

MARKETING_VERSION="$1"
BUILD_NUMBER="$2"

PROJECT_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
PBXPROJ="$PROJECT_ROOT/translate assist.xcodeproj/project.pbxproj"

echo "Setting MARKETING_VERSION=$MARKETING_VERSION and CURRENT_PROJECT_VERSION=$BUILD_NUMBER"

gsed -i.bak -E "s/(MARKETING_VERSION = )[0-9]+(\.[0-9]+){0,2};/\1$MARKETING_VERSION;/" "$PBXPROJ" || sed -i.bak -E "s/(MARKETING_VERSION = )[0-9]+(\.[0-9]+){0,2};/\1$MARKETING_VERSION;/" "$PBXPROJ"
gsed -i.bak -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$BUILD_NUMBER;/" "$PBXPROJ" || sed -i.bak -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$BUILD_NUMBER;/" "$PBXPROJ"

rm -f "$PBXPROJ.bak"
echo "Done."



#!/bin/bash
set -euo pipefail

# ==============================================================================
# Caudit Release Script (local steps only)
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.0.5
#
# This script bumps the version, commits, tags, and pushes.
# GitHub Actions handles the rest: build, DMG, Sparkle sign, release.
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/Caudit.xcodeproj/project.pbxproj"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    error "Usage: $0 <version>  (e.g. 0.0.5)"
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Version must be in format X.Y.Z (e.g. 0.0.5)"
fi

TODAY=$(date +%Y%m%d)
EXISTING=$(grep -c "CURRENT_PROJECT_VERSION = ${TODAY}" "$PROJECT_FILE" 2>/dev/null || true)
if [[ "$EXISTING" -gt 0 ]]; then
    CURRENT=$(grep -m1 "CURRENT_PROJECT_VERSION = ${TODAY}" "$PROJECT_FILE" | tr -dc '0-9')
    SUFFIX=${CURRENT: -2}
    NEXT_SUFFIX=$(printf "%02d" $((10#$SUFFIX + 1)))
    BUILD_NUMBER="${TODAY}${NEXT_SUFFIX}"
else
    BUILD_NUMBER="${TODAY}00"
fi

TAG="v$VERSION"

info "Preparing release: $VERSION (build $BUILD_NUMBER, tag $TAG)"

cd "$PROJECT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
    error "Working directory has uncommitted changes. Commit or stash first."
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    error "Tag $TAG already exists."
fi

info "Bumping version to $VERSION (build $BUILD_NUMBER)..."

sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"

info "Version bumped in project file."

info "Committing version bump..."
git add "$PROJECT_FILE"
git commit -m "release: v$VERSION"

git tag -a "$TAG" -m "Caudit v$VERSION"

info "Pushing to remote..."
git push origin main
git push origin "$TAG"

info "============================================"
info "Tag $TAG pushed!"
info "GitHub Actions will now build, sign, and publish the release."
info "Monitor at: https://github.com/Bengerthelorf/Caudit/actions"
info "============================================"

#!/usr/bin/env bash
set -euo pipefail

# Packages the mod into a Factorio-mod-portal-ready zip
# (dist/<name>_<version>.zip), named and versioned from changelog.txt's
# own topmost "Version:" entry — the single source of truth for "what
# version is this a release of" in this repo.
#
# Built from `git archive HEAD`, not the working tree, so uncommitted
# changes (spikes, in-progress edits) never end up in a shipped zip.
# Only committed files matter; run this after committing whatever should
# ship.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Read from HEAD, not the working tree — that's what git archive below
# actually packages, so the version used to name the zip must come from
# the same place, or an uncommitted version bump could silently name the
# zip for a version it doesn't actually contain.
MOD_NAME=$(git show HEAD:info.json | python3 -c "import json, sys; print(json.load(sys.stdin)['name'])")
INFO_VERSION=$(git show HEAD:info.json | python3 -c "import json, sys; print(json.load(sys.stdin)['version'])")
CHANGELOG_VERSION=$(git show HEAD:changelog.txt | grep -m1 -oP '(?<=^Version: )\S+')

if [[ -z "$CHANGELOG_VERSION" ]]; then
  echo "error: could not find a 'Version: X.Y.Z' line in changelog.txt" >&2
  exit 1
fi

if [[ "$CHANGELOG_VERSION" != "$INFO_VERSION" ]]; then
  echo "error: changelog.txt's latest version ($CHANGELOG_VERSION) does not match info.json's version ($INFO_VERSION) — keep them in sync before packaging." >&2
  exit 1
fi

VERSION="$CHANGELOG_VERSION"
OUT_DIR="dist"
OUT_FILE="$OUT_DIR/${MOD_NAME}_${VERSION}.zip"

mkdir -p "$OUT_DIR"
rm -f "$OUT_FILE"

# Excludes: images/ (README preview screenshots, not used by the mod
# itself), docs/ (contributor-facing design docs), tools/ (this script
# and other dev tooling), .gitattributes/.gitignore (repo housekeeping,
# meaningless once unpacked outside git) — same set this repo's own
# release zips have excluded since the first 0.1.0 build.
git archive --format=zip --prefix="${MOD_NAME}_${VERSION}/" -o "$OUT_FILE" HEAD -- \
  . \
  ':(exclude)images' \
  ':(exclude)docs' \
  ':(exclude)tools' \
  ':(exclude).gitattributes' \
  ':(exclude).gitignore'

echo "Built $OUT_FILE"

#!/usr/bin/env bash
# Writes a release version into the project file that holds it.
# Called by semantic-release (@semantic-release/exec, prepare step) with the
# computed version, but does not depend on it: it can be run by hand.
# Usage: scripts/set-version.sh X.Y.Z
# Exit codes: 0 = version written, 2 = error.
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 2
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH"
}

[[ $# -eq 1 ]] || die "usage: $0 X.Y.Z"
version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "invalid version '$version' (expected X.Y.Z)"

# Always work from the repository root, wherever the script is called from
cd "$(dirname "$0")/.."

if [[ -f package.json && -f angular.json ]]; then
  project_type="npm"
elif [[ -f gradlew ]]; then
  project_type="gradle"
else
  die "unknown project type (expected package.json + angular.json, or gradlew)"
fi
echo "Detected project type: $project_type"

case "$project_type" in
  npm)
    require npm
    require node
    # Updates package.json and package-lock.json; --no-git-tag-version because
    # semantic-release does the commit and the tag
    npm version "$version" --no-git-tag-version >/dev/null \
      || die "npm version failed"
    current=$(node -p "require('./package.json').version")
    ;;
  gradle)
    # -i.bak: the only in-place syntax accepted by both macOS and GNU sed
    sed -i.bak -E "s/^version = '[^']*'$/version = '$version'/" build.gradle \
      || die "sed failed on build.gradle"
    rm -f build.gradle.bak
    current=$(sed -nE "s/^version = '([^']*)'$/\1/p" build.gradle)
    ;;
esac

# If the version line changed format, the update silently does nothing:
# fail rather than release with a stale version in the project file
[[ "$current" == "$version" ]] \
  || die "version not updated (project file says '${current:-nothing}')"
echo "Version set to $version"

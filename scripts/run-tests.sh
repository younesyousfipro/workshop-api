#!/usr/bin/env bash
# Unified test runner: detects the project type, runs its unit tests and
# collects the JUnit XML reports into test-results/ for GitLab CI.
# Exit codes: 0 = tests passed, tool exit code = tests failed, 2 = runner error.
set -euo pipefail

RESULTS_DIR="test-results"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH"
}

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

rm -rf "$RESULTS_DIR"
status=0

case "$project_type" in
  npm)
    require node
    require npm
    if [[ ! -d node_modules ]]; then
      echo "node_modules missing, installing dependencies with npm ci"
      npm ci || die "dependency installation failed (npm ci)"
    fi
    # Output folder set by karma-junit-reporter in karma.conf.js
    report_src="reports"
    rm -rf "$report_src"
    npm test || status=$?
    ;;
  gradle)
    require java
    report_src="build/test-results/test"
    ./gradlew clean test || status=$?
    ;;
esac

# Collect reports even when tests failed: GitLab needs them to show the failures
mkdir -p "$RESULTS_DIR"
cp "$report_src"/*.xml "$RESULTS_DIR"/ 2>/dev/null \
  || die "no JUnit report found in $report_src/ (tests exit code: $status)"

if [[ "$status" -ne 0 ]]; then
  echo "Tests FAILED (exit code $status), reports in $RESULTS_DIR/"
else
  echo "Tests passed, reports in $RESULTS_DIR/"
fi
exit "$status"

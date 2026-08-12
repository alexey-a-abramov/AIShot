#!/usr/bin/env bash
#
# Regenerates AIShot.xcodeproj, stamping the build number from git first.
#
# Use this instead of a bare `xcodegen generate` so CFBundleVersion tracks the
# commit count. `xcodegen generate` alone still works — you just keep whatever
# build number was last written to Config/Version.xcconfig.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

count="$(git rev-list --count HEAD 2>/dev/null || true)"
if [ -n "${count:-}" ]; then
  # Rewrite only the value line, preserving the explanatory header.
  /usr/bin/sed -i '' -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${count}/" \
    Config/Version.xcconfig
  echo "==> build number: ${count}"
else
  echo "warning: no git history; keeping the existing build number" >&2
fi

xcodegen generate

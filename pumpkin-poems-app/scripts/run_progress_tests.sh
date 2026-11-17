#!/bin/sh
# Exercises the app's real SwiftData writes in an isolated in-memory store.
set -eu
APP="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$APP/pumpkin-poems-app"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/pumpkin-progress-tests.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$OUT/module-cache"
xcrun --sdk macosx swiftc -module-cache-path "$OUT/module-cache" -o "$OUT/progress-tests" \
  "$SRC/Content/PoemContent.swift" \
  "$SRC/Content/TextNormalizer.swift" \
  "$SRC/Content/PoemLibrary.swift" \
  "$SRC/App/AppSettings.swift" \
  "$SRC/Progress/ReviewScheduler.swift" \
  "$SRC/Progress/ProgressModels.swift" \
  "$SRC/Progress/LearningSnapshot.swift" \
  "$SRC/Progress/ProgressStore.swift" \
  "$SRC/Features/Quiz/QuizScoring.swift" \
  "$APP/scripts/ProgressStoreRegressionTests.swift"
"$OUT/progress-tests" "$SRC/Resources/PoemContent.json"

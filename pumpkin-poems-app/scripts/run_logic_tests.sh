#!/bin/sh
# Compiles the app's pure-logic sources with LogicTests.swift and runs them on macOS.
set -eu
# Prefer the complete Xcode toolchain when xcode-select still points at CLT.
# Keep compiler caches in a writable temporary directory for sandboxed runs.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
APP="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$APP/pumpkin-poems-app"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/pumpkin-logic-tests.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
mkdir -p "$OUT/module-cache"
cp "$APP/scripts/LogicTests.swift" "$OUT/main.swift"
xcrun swiftc -module-cache-path "$OUT/module-cache" -o "$OUT/logic-tests" \
  "$SRC/Content/PoemContent.swift" \
  "$SRC/Content/TextNormalizer.swift" \
  "$SRC/Content/PoemLibrary.swift" \
  "$SRC/Content/GameCorpus.swift" \
  "$SRC/Features/Games/GameLibraryModels.swift" \
  "$SRC/App/AppSettings.swift" \
  "$SRC/Progress/ReviewScheduler.swift" \
  "$SRC/Features/Quiz/QuizScoring.swift" \
  "$SRC/Features/FeiHuaLing/FeiHuaLingEngine.swift" \
  "$SRC/Features/FeiHuaLing/FeiHuaRelayEngine.swift" \
  "$SRC/Features/FeiHuaLing/FlyingFlowerEngine.swift" \
  "$SRC/Features/FeiHuaLing/FlyingGlyphField.swift" \
  "$SRC/Features/VerseGrid/VerseGridEngine.swift" \
  "$SRC/Features/PoemWordle/PoemWordleEngine.swift" \
  "$SRC/Features/Workshop/PoetWorkshopContent.swift" \
  "$APP/scripts/LearningRegressionTests.swift" \
  "$APP/scripts/GameWorkshopRegressionTests.swift" \
  "$APP/scripts/LanguageRegressionTests.swift" \
  "$APP/scripts/FeiHuaRedesignTests.swift" \
  "$APP/scripts/VerseGridTests.swift" \
  "$APP/scripts/PoemWordleTests.swift" \
  "$APP/scripts/GameLibraryTests.swift" \
  "$OUT/main.swift"
"$OUT/logic-tests" "$SRC/Resources/PoemContent.json" "$SRC/Resources/GameContent.json"

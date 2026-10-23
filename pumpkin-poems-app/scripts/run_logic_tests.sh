#!/bin/sh
# Compiles the app's pure-logic sources with LogicTests.swift and runs them on macOS.
set -e
APP="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$APP/pumpkin-poems-app"
OUT="${TMPDIR:-/tmp}/pumpkin-logic-tests"
mkdir -p "$OUT"
cp "$APP/scripts/LogicTests.swift" "$OUT/main.swift"
xcrun swiftc -o "$OUT/logic-tests" \
  "$SRC/Content/PoemContent.swift" \
  "$SRC/Content/TextNormalizer.swift" \
  "$SRC/Progress/ReviewScheduler.swift" \
  "$SRC/Features/FeiHuaLing/FeiHuaLingEngine.swift" \
  "$SRC/Features/Workshop/PoetWorkshopContent.swift" \
  "$OUT/main.swift"
"$OUT/logic-tests" "$SRC/Resources/PoemContent.json"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/stm-spoken-formatter-tests"

swiftc -parse-as-library \
  "$ROOT/Sources/SpokenDictationFormatter.swift" \
  "$ROOT/Sources/PunctuationLearning.swift" \
  "$ROOT/Sources/ConfigStore.swift" \
  "$ROOT/Sources/Logger.swift" \
  "$ROOT/Tests/LinuxSupport.swift" \
  "$ROOT/Tests/SpokenDictationFormatterTests.swift" \
  -o "$OUT"

"$OUT"

LEARNING_OUT="${TMPDIR:-/tmp}/stm-punctuation-learning-tests"
swiftc -parse-as-library \
  "$ROOT/Sources/PunctuationLearning.swift" \
  "$ROOT/Sources/ConfigStore.swift" \
  "$ROOT/Sources/Logger.swift" \
  "$ROOT/Tests/LinuxSupport.swift" \
  "$ROOT/Tests/PunctuationLearningTests.swift" \
  -o "$LEARNING_OUT"

"$LEARNING_OUT"

swiftc -typecheck -parse-as-library \
  -import-objc-header "$ROOT/Sources/SpeechBridge.h" \
  "$ROOT/Sources/LocalPunctuationService.swift" \
  "$ROOT/Sources/SpokenDictationFormatter.swift" \
  "$ROOT/Sources/PunctuationLearning.swift" \
  "$ROOT/Sources/ConfigStore.swift" \
  "$ROOT/Sources/Logger.swift" \
  "$ROOT/Tests/LinuxSupport.swift"
# macOS-only sources cannot be typechecked on Linux, but `-parse` still catches syntax and
# delimiter regressions in files touched by the punctuation pipeline.
for source in \
  "$ROOT/Sources/DictationController.swift" \
  "$ROOT/Sources/AppDelegate.swift" \
  "$ROOT/Sources/SettingsWindowController.swift"; do
  swiftc -parse "$source" >/dev/null
done


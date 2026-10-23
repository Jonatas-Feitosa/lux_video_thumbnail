#!/bin/bash
# Run on macOS with an already booted iOS simulator. Does not publish.
set -eu
if [ "$(uname -s)" != "Darwin" ]; then
  echo "iOS validation requires macOS and Xcode." >&2
  exit 1
fi
if [ "$#" -ne 1 ]; then
  echo "Usage: bash tool/check_ios.sh <booted-iOS-simulator-UDID>" >&2
  exit 1
fi
task_simulator="$1"
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
cd example
flutter pub get
flutter build ios --simulator --debug
flutter test integration_test/ios_thumbnail_test.dart -d "$task_simulator"
# Restore the normal app entry point before running the separate XCTest suite.
flutter build ios --simulator --debug --target=lib/main.dart
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination "platform=iOS Simulator,id=$task_simulator" \
  -only-testing:RunnerTests test CODE_SIGNING_ALLOWED=NO

#!/usr/bin/env bash
# Typecheck the SwiftUI layer without Xcode.
#
# Command Line Tools ships the macOS SDK, which includes SwiftUI, StoreKit,
# CoreMotion and HealthKit — so most of the app compiles here even though the
# iOS SDK is absent. It will not catch iOS-only API misuse (that code sits behind
# `#if os(iOS)`), but it catches everything else, which is the overwhelming
# majority of the mistakes worth finding early.
#
# CoasterHunterCore is built as a real module first, so `import
# CoasterHunterCore` resolves exactly as it will in Xcode.

set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --show-sdk-path)
TARGET=arm64-apple-macos13.0
BUILD=".build/typecheck"
mkdir -p "$BUILD"

CORE_SOURCES=$(find Packages/CoasterHunterCore/Sources -name '*.swift')
# shellcheck disable=SC2086
swiftc -emit-module -swift-version 5 \
  -module-name CoasterHunterCore \
  -sdk "$SDK" -target "$TARGET" \
  -emit-module-path "$BUILD/CoasterHunterCore.swiftmodule" \
  $CORE_SOURCES

APP_SOURCES=$(find App Watch -name '*.swift' 2>/dev/null || find App -name '*.swift')
# shellcheck disable=SC2086
swiftc -typecheck -swift-version 5 \
  -sdk "$SDK" -target "$TARGET" \
  -I "$BUILD" \
  $APP_SOURCES

CORE_COUNT=$(echo "$CORE_SOURCES" | wc -l | tr -d ' ')
APP_COUNT=$(echo "$APP_SOURCES" | wc -l | tr -d ' ')
echo "typecheck clean — ${CORE_COUNT} core + ${APP_COUNT} app files"

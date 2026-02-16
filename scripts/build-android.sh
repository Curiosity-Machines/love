#!/usr/bin/env bash
set -euo pipefail

# Build Love2D as liblove.so for Android arm64-v8a
#
# Prerequisites:
#   - Android NDK installed at ~/Library/Android/sdk/ndk/29.0.13113456/
#   - Megasource cloned at ../../megasource (relative to this repo root, at rig level)
#   - CMake 3.19+
#
# Usage: ./scripts/build-android.sh [clean]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOVE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RIG_DIR="$(cd "$LOVE_DIR/../.." && pwd)"
MEGASOURCE_DIR="${RIG_DIR}/megasource"
OBOE_DIR="${RIG_DIR}/oboe"
BUILD_DIR="${LOVE_DIR}/build-android"

# Android NDK configuration
NDK_VERSION="29.0.13113456"
NDK_DIR="${ANDROID_NDK_HOME:-${HOME}/Library/Android/sdk/ndk/${NDK_VERSION}}"
TOOLCHAIN_FILE="${NDK_DIR}/build/cmake/android.toolchain.cmake"
ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-34"

# Validate prerequisites
if [ ! -d "$MEGASOURCE_DIR" ]; then
    echo "ERROR: megasource not found at $MEGASOURCE_DIR"
    echo "Clone it: git clone https://github.com/love2d/megasource.git $MEGASOURCE_DIR"
    exit 1
fi

if [ ! -f "$TOOLCHAIN_FILE" ]; then
    echo "ERROR: Android NDK toolchain not found at $TOOLCHAIN_FILE"
    echo "Install NDK ${NDK_VERSION} via Android Studio SDK Manager"
    exit 1
fi

if [ ! -d "$OBOE_DIR" ]; then
    echo "ERROR: Oboe not found at $OBOE_DIR"
    echo "Clone it: git clone https://github.com/google/oboe.git $OBOE_DIR"
    exit 1
fi

# Clean build if requested
if [ "${1:-}" = "clean" ]; then
    echo "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

echo "=== Configuring Love2D Android Build ==="
echo "  Love2D:     $LOVE_DIR"
echo "  Megasource: $MEGASOURCE_DIR"
echo "  NDK:        $NDK_DIR"
echo "  ABI:        $ANDROID_ABI"
echo "  Platform:   $ANDROID_PLATFORM"
echo "  Oboe:       $OBOE_DIR"
echo "  Build dir:  $BUILD_DIR"

cmake -S "$MEGASOURCE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DMEGA_LOVE="$LOVE_DIR" \
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DOBOE_SOURCE="$OBOE_DIR"

echo "=== Building ==="
cmake --build "$BUILD_DIR" --parallel "$(sysctl -n hw.ncpu)" --target love

echo "=== Build Complete ==="

# Find and report the output
LIBLOVE_SO=$(find "$BUILD_DIR" -name "liblove.so" -o -name "love.so" | head -1)
if [ -n "$LIBLOVE_SO" ]; then
    echo "Output: $LIBLOVE_SO"
    echo "Size: $(du -h "$LIBLOVE_SO" | cut -f1)"
else
    echo "WARNING: liblove.so not found in build output"
    echo "Checking for shared libraries..."
    find "$BUILD_DIR" -name "*.so" | head -20
fi

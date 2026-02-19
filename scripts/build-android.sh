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

# OS detection
OS="$(uname -s)"
ARCH="$(uname -m)"

# Android NDK configuration
NDK_VERSION="29.0.13113456"
if [ "$OS" = "Darwin" ]; then
    NDK_DEFAULT="${HOME}/Library/Android/sdk/ndk/${NDK_VERSION}"
else
    NDK_DEFAULT="${HOME}/Android/Sdk/ndk/${NDK_VERSION}"
fi
NDK_DIR="${ANDROID_NDK_HOME:-$NDK_DEFAULT}"
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
if [ "$OS" = "Darwin" ]; then
    NPROC="$(sysctl -n hw.ncpu)"
else
    NPROC="$(nproc)"
fi
cmake --build "$BUILD_DIR" --parallel "$NPROC" --target love

echo "=== Build Complete ==="

# Assemble dist: all .so files babbage needs, in jniLibs layout.
# babbage can point jniLibs.srcDirs at dist/android/ or symlink.
DIST_DIR="${LOVE_DIR}/dist/android/jniLibs/${ANDROID_ABI}"
rm -rf "${LOVE_DIR}/dist/android"
mkdir -p "$DIST_DIR"

# libliblove.so is the full engine (JNI symbols, all modules).
# Rename to liblove.so so System.loadLibrary("love") finds it.
cp "$BUILD_DIR/love/libliblove.so" "$DIST_DIR/liblove.so"

# Companion shared libraries (NEEDED by liblove.so)
cp "$BUILD_DIR/love/RelWithDebInfo/libSDL3.so" "$DIST_DIR/"
cp "$BUILD_DIR/love/RelWithDebInfo/libopenal.so" "$DIST_DIR/"
cp "$MEGASOURCE_DIR/libs/LuaJIT/android/${ANDROID_ABI}/libluajit.so" "$DIST_DIR/"

# libc++_shared.so: required since we build with -DANDROID_STL=c++_shared.
# Gradle only auto-bundles this when externalNativeBuild is used; since babbage
# consumes pre-built .so via jniLibs, we must include it explicitly.
if [ "$OS" = "Darwin" ]; then
    NDK_HOST_TAG="darwin-x86_64"
else
    NDK_HOST_TAG="linux-x86_64"
fi
LIBCXX="${NDK_DIR}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
cp "$LIBCXX" "$DIST_DIR/"

echo "=== Dist ==="
echo "  Output: $DIST_DIR"
ls -lh "$DIST_DIR"
echo ""
echo "Babbage integration: add to app/build.gradle.kts:"
echo "  sourceSets { main { jniLibs.srcDirs += \"<path-to-lovelace>/dist/android/jniLibs\" } }"

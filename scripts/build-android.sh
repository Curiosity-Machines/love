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
MEGASOURCE_DIR="${MEGASOURCE_DIR:-${RIG_DIR}/megasource}"
OBOE_DIR="${OBOE_DIR:-${RIG_DIR}/oboe}"
BUILD_DIR="${LOVE_DIR}/build-android"

# Resolve git commit/branch from ref files directly.
# orbital's rsync excludes .git/objects/ but keeps .git/HEAD and .git/refs/,
# so git rev-parse fails but we can follow the ref chain manually.
GIT_COMMIT="unknown"
GIT_BRANCH="unknown"
if [ -f "$LOVE_DIR/.git/HEAD" ]; then
    _HEAD="$(cat "$LOVE_DIR/.git/HEAD")"
    case "$_HEAD" in
        ref:*)
            _REF="${_HEAD#ref: }"
            GIT_BRANCH="$(basename "$_REF")"
            if [ -f "$LOVE_DIR/.git/$_REF" ]; then
                GIT_COMMIT="$(cat "$LOVE_DIR/.git/$_REF")"
            elif [ -f "$LOVE_DIR/.git/packed-refs" ]; then
                GIT_COMMIT="$(grep " $_REF\$" "$LOVE_DIR/.git/packed-refs" | cut -d' ' -f1)"
            fi
            ;;
        *)  GIT_COMMIT="$_HEAD"; GIT_BRANCH="HEAD" ;;
    esac
fi
GIT_COMMIT="${GIT_COMMIT:-unknown}"

# OS detection
OS="$(uname -s)"
ARCH="$(uname -m)"

# Android NDK configuration
NDK_VERSION="29.0.13113456"
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
    NDK_DIR="$ANDROID_NDK_HOME"
elif [ -n "${ANDROID_HOME:-}" ]; then
    NDK_DIR="${ANDROID_HOME}/ndk/${NDK_VERSION}"
elif [ "$OS" = "Darwin" ]; then
    NDK_DIR="${HOME}/Library/Android/sdk/ndk/${NDK_VERSION}"
else
    NDK_DIR="${HOME}/Android/Sdk/ndk/${NDK_VERSION}"
fi
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
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
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

# Generate build manifest for cross-repo traceability.
# babbage logs which love2d commit it consumed.
MANIFEST="${LOVE_DIR}/dist/android/jniLibs/manifest.json"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build file entries array
FILE_ENTRIES=""
for so in "$DIST_DIR"/*.so; do
    NAME="$(basename "$so")"
    SIZE="$(wc -c < "$so" | tr -d ' ')"
    SHA256="$(shasum -a 256 "$so" 2>/dev/null || sha256sum "$so" 2>/dev/null)"
    SHA256="$(echo "$SHA256" | awk '{print $1}')"
    [ -n "$FILE_ENTRIES" ] && FILE_ENTRIES="${FILE_ENTRIES},"
    FILE_ENTRIES="${FILE_ENTRIES}
    {\"name\":\"${NAME}\",\"sha256\":\"${SHA256}\",\"size\":${SIZE}}"
done

cat > "$MANIFEST" <<EOF
{
  "project": "love2d",
  "commit": "${GIT_COMMIT}",
  "branch": "${GIT_BRANCH}",
  "timestamp": "${BUILD_TS}",
  "abi": "${ANDROID_ABI}",
  "ndk_version": "${NDK_VERSION}",
  "files": [${FILE_ENTRIES}
  ]
}
EOF

echo ""
echo "=== Manifest ==="
cat "$MANIFEST"

# Publish to orbital shared volume for cross-repo consumption.
SHARED_DIR="/home/claude/orbital/jniLibs/love-android"
if [ -d "/home/claude/orbital" ]; then
    echo ""
    echo "=== Publishing to shared volume ==="
    rm -rf "$SHARED_DIR"
    mkdir -p "$SHARED_DIR"
    cp -r "$DIST_DIR" "$SHARED_DIR/"
    cp "$MANIFEST" "$SHARED_DIR/"
    chmod -R g+w "$SHARED_DIR"
    echo "  Published to: $SHARED_DIR"
    ls -lhR "$SHARED_DIR"
else
    echo ""
    echo "=== Shared volume not available, skipping publish ==="
fi

echo ""
echo "Babbage integration: add to app/build.gradle.kts:"
echo "  sourceSets { main { jniLibs.srcDirs += \"<path-to-lovelace>/dist/android/jniLibs\" } }"

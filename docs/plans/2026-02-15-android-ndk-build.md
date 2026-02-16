# Love2D Android NDK Build (liblove.so) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build Love2D as `liblove.so` for arm64-v8a using megasource + CMake + Android NDK.

**Architecture:** Clone megasource alongside Love2D source. Use megasource as the top-level CMake project (it sets `MEGA TRUE` and provides all dependency targets). Cross-compile with the Android NDK toolchain file targeting arm64-v8a, SDK 34. Write a build script for reproducibility.

**Tech Stack:** CMake 4.2, Android NDK r29, megasource (SDL3, LuaJIT, Freetype, etc.)

---

### Task 1: Clone Megasource

**Files:**
- Create: `megasource/` at rig level (`/Users/michaelfinkler/gt/love/megasource/`)

Megasource is the top-level CMake project that builds all Love2D dependencies and then includes Love2D itself as a subdirectory. It must be cloned at the rig level (not inside the lovelace workspace, since it's a separate repo).

**Step 1: Clone megasource from GitHub**

```bash
cd /Users/michaelfinkler/gt/love
git clone https://github.com/love2d/megasource.git
```

**Step 2: Verify structure**

```bash
ls megasource/libs/
```

Expected: Directories for SDL3, freetype, harfbuzz, openal-soft, LuaJIT, libogg, libvorbis, libtheora, zlib, libmodplug, lua-5.1.5

**Step 3: Verify LuaJIT Android prebuilts exist**

```bash
ls megasource/libs/LuaJIT/android/arm64-v8a/
```

Expected: `libluajit.so` and LuaJIT headers

**Step 4: Check megasource CMakeLists.txt has MEGA_LOVE override**

```bash
grep -n "MEGA_LOVE" megasource/CMakeLists.txt
```

Expected: Lines showing `if(NOT MEGA_LOVE)` and `set(MEGA_LOVE ...)` — confirming we can point it at our Love2D source.

---

### Task 2: Create Android Build Script

**Files:**
- Create: `scripts/build-android.sh` (in lovelace workspace)

This script encapsulates the full CMake configure + build invocation so the build is reproducible (acceptance criterion #3).

**Step 1: Write the build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build Love2D as liblove.so for Android arm64-v8a
#
# Prerequisites:
#   - Android NDK installed at ~/Library/Android/sdk/ndk/29.0.13113456/
#   - Megasource cloned at ../megasource (relative to this repo)
#   - CMake 3.19+
#
# Usage: ./scripts/build-android.sh [clean]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOVE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RIG_DIR="$(cd "$LOVE_DIR/.." && pwd)"
MEGASOURCE_DIR="${RIG_DIR}/megasource"
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
echo "  Build dir:  $BUILD_DIR"

cmake -S "$MEGASOURCE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DMEGA_LOVE="$LOVE_DIR" \
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON

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
```

**Step 2: Make it executable**

```bash
chmod +x scripts/build-android.sh
```

**Step 3: Commit the script**

```bash
git add scripts/build-android.sh
git commit -m "add Android NDK build script for liblove.so (arm64-v8a)"
```

---

### Task 3: Run the Build

**Step 1: Execute the build script**

```bash
cd /Users/michaelfinkler/gt/love/crew/lovelace
./scripts/build-android.sh clean
```

This will take a while — megasource builds SDL3, OpenAL, Freetype, Harfbuzz, and all other dependencies from source (except LuaJIT which uses prebuilt .so).

**Step 2: If CMake configure fails**

Common issues and fixes:

- **FATAL_ERROR about megasource**: The `MEGA` flag should be set automatically by megasource's top-level CMakeLists.txt. If not, check that `-DMEGA_LOVE` is pointing correctly.

- **Missing Android platform APIs**: Ensure `-DANDROID_PLATFORM=android-34` is set. Some APIs (Oboe, OpenSL) require a minimum platform level.

- **LuaJIT prebuilt not found**: Check that `megasource/libs/LuaJIT/android/arm64-v8a/libluajit.so` exists. If megasource doesn't ship prebuilts for the current version, we may need to build LuaJIT separately or use Lua 5.1 instead (`-DLOVE_JIT=OFF`).

- **SDL3 Android issues**: SDL3 has Android-specific source files. The NDK toolchain should handle this, but if there are issues with SDL's Java sources, we only need the native side.

**Step 3: If build (compile) fails**

Iterate on fixing compilation errors. Common issues:

- Missing includes → check NDK sysroot
- ABI-specific code → ensure arm64-v8a is consistent
- C++ standard issues → Love2D requires C++17, ensure NDK supports it

---

### Task 4: Verify the Output

**Step 1: Check liblove.so exists and is valid**

```bash
file build-android/love/liblove.so
```

Expected: `ELF 64-bit LSB shared object, ARM aarch64`

**Step 2: Verify JNI symbol exports**

```bash
# Use NDK's nm tool for cross-compiled binaries
~/Library/Android/sdk/ndk/29.0.13113456/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm -D build-android/love/liblove.so | grep Java_
```

Expected: JNI symbols like `Java_org_libsdl_app_SDLActivity_*` and any Love2D-specific JNI exports.

**Step 3: Check for missing symbols**

```bash
~/Library/Android/sdk/ndk/29.0.13113456/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm -D build-android/love/liblove.so | grep " U " | head -20
```

Review undefined symbols — they should all be system/NDK symbols that will be resolved at runtime (libc, libdl, liblog, libandroid, libGLESv2, etc.).

**Step 4: Check all dependency .so files built**

```bash
find build-android -name "*.so" | sort
```

Expected: liblove.so, libSDL3.so, libluajit.so, and possibly libOpenAL.so

**Step 5: Commit successful build verification**

```bash
git add -A
git commit -m "verify Android NDK build produces valid liblove.so for arm64-v8a"
```

---

### Task 5: Add build-android to .gitignore

**Files:**
- Modify: `.gitignore`

**Step 1: Add build output directory to gitignore**

Append to `.gitignore`:
```
# Android NDK build output
build-android/
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "gitignore Android build output directory"
```

---

## Troubleshooting Notes

### NDK Path Discovery

The build script checks `ANDROID_NDK_HOME` env var first, then falls back to `~/Library/Android/sdk/ndk/<version>`. Multiple NDK versions are installed:
- 18.1, 21.4, 25.1, 25.2, 26.1, 27.0 (x2), 27.1, **29.0** (latest)

We use r29 (29.0.13113456) for best compatibility with SDK 34 and modern CMake.

### Cross-Compilation from macOS

Building Android native code on macOS (darwin) is fully supported by the NDK. The toolchain file at `ndk/<version>/build/cmake/android.toolchain.cmake` handles all cross-compilation details including:
- Setting the correct compiler (clang for aarch64-linux-android)
- Configuring the sysroot
- Setting Android-specific CMake variables

### Megasource as Top-Level Project

**Critical**: Megasource must be the CMake source directory (`-S`), not Love2D. The build hierarchy is:

```
megasource/CMakeLists.txt  ← Top-level (sets MEGA=TRUE)
├── builds zlib, SDL3, freetype, etc.
└── add_subdirectory(${MEGA_LOVE})  ← Love2D included as child
    ├── sees MEGA=TRUE, uses MEGA_* targets
    └── builds liblove + love shared libs
```

If you try to use Love2D as the top-level project on Android, it will hit the FATAL_ERROR at line 168-172 because `MEGA` won't be set.

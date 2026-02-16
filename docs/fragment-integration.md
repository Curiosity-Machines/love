# Love2D Android Fragment Integration

## Overview

This document describes how Love2D can be embedded as a game runtime inside an
Android Fragment, rather than owning the entire Activity. The host application
(babbage) creates a SurfaceView within a Fragment and drives Love2D's lifecycle
through JNI calls.

## Approach

### SDL3 Surface Delegation

SDL3 does not natively support rendering to an externally-provided surface. It
creates its own `SurfaceView` via `SDLActivity.java` and registers JNI methods
against `org.libsdl.app.SDLActivity`.

The solution is for the host app to include a modified copy of `SDLActivity.java`
where `getNativeSurface()` returns the Fragment's surface instead of SDL's own.
Love2D itself does not need to modify SDL3 -- the host app handles this at the
Java layer.

### PhysFS File Loading

Love2D's `Filesystem::setSource()` falls through to `PHYSFS_mount()`, which
accepts absolute filesystem paths to `.love` files. The fragment integration
passes the `.love` file path as `argv[1]` in the simulated command line, so
Love2D's `boot.lua` picks it up through the standard argument parsing and
source-setting flow. No changes to the filesystem module are required.

### Threading Model

Love2D runs on a dedicated thread spawned by `nativeInit()`, not on the Android
UI thread. The host Fragment calls:

1. `nativeInit(lovePath)` -- spawns the Love2D thread
2. `nativePause()` / `nativeResume()` -- injects SDL window events
3. `nativeQuit()` -- signals quit and waits for the thread to finish

SDL must already be initialized by the host Activity (SDLActivity handles this
as part of its normal lifecycle).

## JNI Interface

Four native methods are exposed, matching the Java class
`com.dopple.webview.ui.love.Love2dGameFragment`:

### `nativeInit(String lovePath)`

Starts the Love2D main loop on a new thread. The `lovePath` parameter is an
absolute filesystem path to a `.love` file (e.g.,
`/data/data/com.dopple.webview/files/games/mygame.love`).

The path is passed as `argv[1]` to Love2D's boot sequence, which handles it
through `Filesystem::setSource()` -> `PHYSFS_mount()`.

### `nativePause()`

Called from `Fragment.onPause()`. Injects `SDL_EVENT_WINDOW_MINIMIZED` into
the SDL event queue, which Love2D already handles to pause audio playback
and rendering.

### `nativeResume()`

Called from `Fragment.onResume()`. Injects `SDL_EVENT_WINDOW_RESTORED` into
the SDL event queue, which Love2D already handles to resume audio playback
and rendering.

### `nativeQuit()`

Called from `Fragment.onDestroyView()`. Pushes `SDL_EVENT_QUIT` to signal
Love2D to exit its main loop, then blocks until the Love2D thread finishes
via `SDL_WaitThread()`.

## Files

- `src/common/android_fragment.h` -- Header declaring the fragment lifecycle interface
- `src/common/android_fragment.cpp` -- Implementation with JNI entry points and Love2D thread management
- `scripts/build-android.sh` -- Builds liblove.so and assembles dist artifacts

## Artifact Distribution

`scripts/build-android.sh` builds Love2D and assembles a `dist/` directory:

```
dist/android/jniLibs/arm64-v8a/
  liblove.so      -- Love2D engine (renamed from libliblove.so, has JNI symbols)
  libSDL3.so      -- SDL3 runtime
  libopenal.so    -- OpenAL audio
  libluajit.so    -- LuaJIT (prebuilt from megasource)
```

The host app (babbage) adds this as a jniLibs source directory in `build.gradle.kts`:

```kotlin
sourceSets {
    getByName("main") {
        jniLibs.srcDir(rootProject.file("$loveDir/dist/android/jniLibs"))
    }
}
```

No CMake is needed on the host side. `System.loadLibrary("love")` loads
`liblove.so` which contains all JNI entry points. The companion `.so` files
(SDL3, OpenAL, LuaJIT) are bundled into the APK automatically by Gradle.
`libc++_shared.so` is provided by the NDK via Gradle's STL packaging.

## Important Notes

- SDL3 (megasource) is NOT modified
- The existing `android.cpp` is NOT modified
- The host app must provide a modified `SDLActivity.java` that delegates
  `getNativeSurface()` to the Fragment's surface
- Love2D's event handling for `SDL_EVENT_WINDOW_MINIMIZED` /
  `SDL_EVENT_WINDOW_RESTORED` already includes audio pause/resume on Android
  (see `src/modules/event/sdl/Event.cpp`)

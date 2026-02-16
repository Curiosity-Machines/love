/**
 * Copyright (c) 2006-2026 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

/**
 * ALTERED SOURCE NOTICE: This file is not part of the original Love2D
 * distribution. It was created by Dopple (dopple.com) to support embedding
 * Love2D inside an Android Fragment rather than a standalone SDLActivity.
 *
 * This file was generated with assistance from an LLM (Claude, Anthropic)
 * and reviewed by Dopple engineers. See the project README for contributor
 * disclosure policy.
 **/

#ifndef LOVE_ANDROID_FRAGMENT_H
#define LOVE_ANDROID_FRAGMENT_H

#include "config.h"

#ifdef LOVE_ANDROID

#include <jni.h>

namespace love
{
namespace android
{
namespace fragment
{

// Start Love2D with a .love file from a filesystem path.
// Called from Love2dGameFragment.nativeInit(lovePath).
// Spawns a new thread that runs the Love2D main loop.
// context: Application Context (global ref will be taken).
void init(JNIEnv *env, jobject context, const char *lovePath);

// Pause Love2D (Fragment.onPause).
// Injects SDL_EVENT_WINDOW_MINIMIZED to pause audio/rendering.
void pause();

// Resume Love2D (Fragment.onResume).
// Injects SDL_EVENT_WINDOW_RESTORED to resume audio/rendering.
void resume();

// Quit Love2D (Fragment.onDestroyView).
// Signals love.event.quit(), waits for the main loop thread to finish.
void quit();

// Returns true if Love2D is running in fragment mode (not SDLActivity).
bool isActive();

// Get the stored JavaVM (for AttachCurrentThread on non-JNI threads).
// Returns nullptr if not in fragment mode.
void *getJavaVM();

// Get the stored Activity context (global ref).
// Returns nullptr if not in fragment mode.
void *getActivity();

} // fragment
} // android
} // love

#endif // LOVE_ANDROID
#endif // LOVE_ANDROID_FRAGMENT_H

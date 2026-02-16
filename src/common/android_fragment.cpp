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

#include "android_fragment.h"

#ifdef LOVE_ANDROID

#include <SDL3/SDL.h>
#include <SDL3/SDL_thread.h>
#include <jni.h>
#include <string>
#include <atomic>

#include "version.h"
#include "runtime.h"
#include "Variant.h"
#include "modules/love/love.h"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

namespace love
{
namespace android
{
namespace fragment
{

static SDL_Thread *loveThread = nullptr;
static std::string lovePath;
static std::atomic<bool> quitRequested{false};
static JavaVM *javaVM = nullptr;
static jobject activityRef = nullptr; // global ref

// Forward declaration of Love2D main loop runner
static int loveThreadFunc(void *data);

// Preload helper (same as in love.cpp)
static int love_preload(lua_State *L, lua_CFunction f, const char *name)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, f);
	lua_setfield(L, -2, name);
	lua_pop(L, 2);
	return 0;
}

void init(JNIEnv *env, jobject context, const char *path)
{
	if (loveThread != nullptr)
	{
		SDL_Log("Love2D: init called but already running");
		return;
	}

	// Store JavaVM and Context for use on the LoveMain thread.
	// getArg0() needs these since SDL_GetAndroidActivity() returns NULL
	// in fragment mode (SDL doesn't own the Activity).
	env->GetJavaVM(&javaVM);
	activityRef = env->NewGlobalRef(context);

	lovePath = path;
	quitRequested = false;

	// Start Love2D on a dedicated thread.
	// SDL must already be initialized by the host Activity (SDLActivity handles this).
	loveThread = SDL_CreateThread(loveThreadFunc, "LoveMain", nullptr);
	if (loveThread == nullptr)
	{
		SDL_Log("Love2D: Failed to create thread: %s", SDL_GetError());
	}
}

void pause()
{
	// Inject SDL minimize event to pause audio and rendering.
	SDL_Event event = {};
	event.type = SDL_EVENT_WINDOW_MINIMIZED;
	event.window.windowID = 1;
	SDL_PushEvent(&event);
}

void resume()
{
	// Inject SDL restore event to resume audio and rendering.
	SDL_Event event = {};
	event.type = SDL_EVENT_WINDOW_RESTORED;
	event.window.windowID = 1;
	SDL_PushEvent(&event);
}

void quit()
{
	// Signal Love2D to quit.
	quitRequested = true;
	SDL_Event event = {};
	event.type = SDL_EVENT_QUIT;
	SDL_PushEvent(&event);

	// Wait for the Love2D thread to finish.
	if (loveThread != nullptr)
	{
		int status = 0;
		SDL_WaitThread(loveThread, &status);
		loveThread = nullptr;
	}

	// Release the Activity global ref.
	if (activityRef != nullptr && javaVM != nullptr)
	{
		JNIEnv *env = nullptr;
		javaVM->GetEnv((void **)&env, JNI_VERSION_1_6);
		if (env != nullptr)
			env->DeleteGlobalRef(activityRef);
		activityRef = nullptr;
	}

	javaVM = nullptr;
	lovePath.clear();
}

bool isActive()
{
	return loveThread != nullptr || activityRef != nullptr;
}

void *getJavaVM()
{
	return javaVM;
}

void *getActivity()
{
	return activityRef;
}

static int loveThreadFunc(void *data)
{
	(void)data;

	// Build argv: love <lovePath>
	const char *argv[] = {"love", lovePath.c_str(), nullptr};
	int argc = 2;

	lua_State *L = luaL_newstate();
	luaL_openlibs(L);

	love_preload(L, luaopen_love_jitsetup, "love.jitsetup");
	lua_getglobal(L, "require");
	lua_pushstring(L, "love.jitsetup");
	lua_call(L, 1, 0);

	love_preload(L, luaopen_love, "love");

	// Set up arg table
	lua_newtable(L);
	lua_pushstring(L, argv[0]);
	lua_rawseti(L, -2, -2);
	lua_pushstring(L, "embedded boot.lua");
	lua_rawseti(L, -2, -1);
	for (int i = 1; i < argc; i++)
	{
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i);
	}
	lua_setglobal(L, "arg");

	// require "love"
	lua_getglobal(L, "require");
	lua_pushstring(L, "love");
	lua_call(L, 1, 1);

	lua_pushboolean(L, 1);
	lua_setfield(L, -2, "_exe");

	// No restart value for fragment mode
	lua_pushnil(L);
	lua_setfield(L, -2, "restart");

	lua_pop(L, 1);

	// require "love.boot"
	lua_getglobal(L, "require");
	lua_pushstring(L, "love.boot");
	lua_call(L, 1, 1);

	// Run the boot coroutine
	lua_newthread(L);
	lua_pushvalue(L, -2);
	int stackpos = lua_gettop(L);
	int nres;
	while (love::luax_resume(L, 0, &nres) == LUA_YIELD)
	{
#if LUA_VERSION_NUM >= 504
		lua_pop(L, nres);
#else
		lua_pop(L, lua_gettop(L) - stackpos);
#endif
	}

	lua_close(L);
	return 0;
}

} // fragment
} // android
} // love

// JNI entry points for com.dopple.webview.ui.love.Love2dGameFragment
extern "C" {

JNIEXPORT void JNICALL
Java_com_dopple_webview_ui_love_Love2dGameFragment_nativeInit(
	JNIEnv *env, jobject thiz, jstring lovePath)
{
	// thiz is the Fragment. Get Context for PhysFS initialization.
	// Fragment.getContext() returns android.content.Context.
	jclass fragClass = env->GetObjectClass(thiz);
	jmethodID getCtx = env->GetMethodID(fragClass, "getContext", "()Landroid/content/Context;");
	jobject context = env->CallObjectMethod(thiz, getCtx);
	env->DeleteLocalRef(fragClass);

	// Use the application context so the ref outlives the Fragment.
	jclass ctxClass = env->GetObjectClass(context);
	jmethodID getAppCtx = env->GetMethodID(ctxClass, "getApplicationContext", "()Landroid/content/Context;");
	jobject appContext = env->CallObjectMethod(context, getAppCtx);
	env->DeleteLocalRef(ctxClass);
	env->DeleteLocalRef(context);

	const char *path = env->GetStringUTFChars(lovePath, nullptr);
	love::android::fragment::init(env, appContext, path);
	env->ReleaseStringUTFChars(lovePath, path);
	env->DeleteLocalRef(appContext);
}

JNIEXPORT void JNICALL
Java_com_dopple_webview_ui_love_Love2dGameFragment_nativePause(
	JNIEnv *env, jobject thiz)
{
	(void)env;
	(void)thiz;
	love::android::fragment::pause();
}

JNIEXPORT void JNICALL
Java_com_dopple_webview_ui_love_Love2dGameFragment_nativeResume(
	JNIEnv *env, jobject thiz)
{
	(void)env;
	(void)thiz;
	love::android::fragment::resume();
}

JNIEXPORT void JNICALL
Java_com_dopple_webview_ui_love_Love2dGameFragment_nativeQuit(
	JNIEnv *env, jobject thiz)
{
	(void)env;
	(void)thiz;
	love::android::fragment::quit();
}

} // extern "C"

#endif // LOVE_ANDROID

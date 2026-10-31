// The Android runner's bit of C (scripts/build_android_runner.sh): the app's
// own folder, from raylib's NativeActivity glue.
#include <android_native_app_glue.h>

struct android_app *GetAndroidApp(void); // (raylib, PLATFORM_ANDROID)

// The app going to the background and back: raylib stops the game loop
// itself; the sound (the mixer's callback) is stopped here
// (rayzr_android_suspend, main.odin), after raylib has its say.
void rayzr_android_suspend(int on);
static void (*raylib_on_app_cmd)(struct android_app *, int32_t);

static void on_app_cmd(struct android_app *app, int32_t cmd) {
	if (raylib_on_app_cmd) raylib_on_app_cmd(app, cmd);
	if (cmd == APP_CMD_LOST_FOCUS || cmd == APP_CMD_PAUSE) rayzr_android_suspend(1);
	if (cmd == APP_CMD_GAINED_FOCUS || cmd == APP_CMD_RESUME) rayzr_android_suspend(0);
}

// rayzr_android_install_hooks: after InitWindow (raylib sets its handler there).
void rayzr_android_install_hooks(void) {
	struct android_app *app = GetAndroidApp();
	if (!app || app->onAppCmd == on_app_cmd) return;
	raylib_on_app_cmd = app->onAppCmd;
	app->onAppCmd = on_app_cmd;
}

const char *rayzr_android_internal_path(void) {
	struct android_app *app = GetAndroidApp();
	if (app && app->activity && app->activity->internalDataPath) return app->activity->internalDataPath;
	return ".";
}

// rayzr_android_read_asset: an asset of the APK, whole (malloc'd; free it),
// or NULL. (Before InitWindow raylib's own asset reading isn't set up.)
#include <android/asset_manager.h>
#include <stdlib.h>

void *rayzr_android_read_asset(const char *name, long long *size) {
	struct android_app *app = GetAndroidApp();
	*size = 0;
	if (!app || !app->activity || !app->activity->assetManager) return NULL;
	AAsset *asset = AAssetManager_open(app->activity->assetManager, name, AASSET_MODE_BUFFER);
	if (!asset) return NULL;
	off_t n = AAsset_getLength(asset);
	void *buf = malloc(n > 0 ? (size_t)n : 1);
	if (buf && n > 0 && AAsset_read(asset, buf, (size_t)n) != n) {
		free(buf);
		buf = NULL;
	}
	AAsset_close(asset);
	if (buf) *size = n;
	return buf;
}

// Symbols the runner refers to that Android 7's system libraries don't
// have (a missing one stops the app from loading at all):
//  - raylib's GL ES path names the EXT entry point; ES 3 has it built in.
//  - Odin's threads set the cancel state / type (bionic has no thread
//    cancellation) and the scheduler inheritance (API 28+).
#include <GLES3/gl3.h>
#include <pthread.h>

void glDrawBuffersEXT(GLsizei n, const GLenum *bufs) { glDrawBuffers(n, bufs); }

int pthread_setcancelstate(int state, int *old) { if (old) *old = 0; (void)state; return 0; }
int pthread_setcanceltype(int type, int *old) { if (old) *old = 0; (void)type; return 0; }
#if __ANDROID_API__ < 28
int pthread_attr_setinheritsched(pthread_attr_t *attr, int inherit) { (void)attr; (void)inherit; return 0; }
#endif

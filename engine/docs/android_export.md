# Android export

Games export to Android phones and tablets (arm64, Android 7 and newer) as
two files:

```
android/
├── <game>.apk   install it on a phone (adb install, or open it on the phone)
└── <game>.aab   upload it to Google Play
```

Both hold the Android runner (the engine, raylib, Lua and Box2D built for
Android: `lib/arm64-v8a/libmain.so`), your game's `game.rayzr` and the UI
font. On first launch, and whenever the package changes, the runner copies
the game out of the APK into the app's own storage. Save data lives there
too, and Android removes it with the app.

## What you need

Exporting runs Android's own packaging tools, so the computer that exports
needs:

- **The Android SDK** with **build-tools 34** and the **android-34**
  platform. Android Studio installs it. With only the command-line tools:
  `sdkmanager "build-tools;34.0.0" "platforms;android-34"`. The editor
  finds it through `ANDROID_HOME` / `ANDROID_SDK_ROOT`, Android Studio's
  folder, or Homebrew's.
- **Java 17 or newer**: `JAVA_HOME`, Android Studio's bundled JDK, or
  Homebrew's `openjdk`.
- **bundletool** for the AAB: `bundletool-all-<version>.jar` from
  github.com/google/bundletool/releases in `runners/android/` next to the
  editor, or set `RAYZR_BUNDLETOOL` to its path. Without it the export
  makes only the APK and says so.

The NDK is only needed to build the runner itself
(`scripts/build_android_runner.sh`). Editor releases ship it ready-made.

## Exporting

1. **Project Settings > Export**: tick **android** among the targets, or
   add a preset with platform **android**.
2. Set **Android Package**, the app's id: `com.yourname.game`. Choose it
   once. Google Play won't accept a changed one for the same app.
3. **Version Code**: a whole number that must go up with every upload to
   Google Play. People see the project's **Version** instead.
4. **Save and Export**.

### Signing

Android only installs signed apps:

- **No keystore** (the default): the export signs with the *debug key*
  (`~/.android/debug.keystore`, made the first time). That's fine for
  trying the game on your own phone, but Google Play won't take it.
- **For Google Play**: make a release keystore once and keep it safe.
  Every update must be signed with the same key.

  ```
  keytool -genkeypair -keystore mygame.jks -alias mygame -keyalg RSA -keysize 2048 -validity 10000
  ```

  Set **Keystore** (its path; relative paths are from the project) and
  **Key Alias** in Export settings. Put the password in the
  `RAYZR_ANDROID_KEYSTORE_PASSWORD` environment variable before starting
  the editor. It's never saved in the project.

## On the phone

- **Touch**: fingers work as the mouse, gestures reach scripts, and
  [Touch Joystick](../../docs/nodes/TouchJoystickNode.md) /
  [Touch Button](../../docs/nodes/TouchButtonNode.md) nodes give action
  games on-screen controls (see [Input](../../docs/lua/Input.md)). The
  templates played with keys already have them.
- **Orientation**: landscape when the project's window is wider than tall,
  else portrait. The phone can turn it either way within that.
- **Screen shape**: phones are wider than 16:9. With **Fill** set to
  **Expand** (Project Settings > Video) the game uses the whole screen;
  otherwise it has bars at the sides.
- **Leaving and coming back** (the Home button, a call): the game pauses
  while it's in the background and carries on where it was.
- **Graphics**: OpenGL ES 3, as on the web, so shaders are written in GLSL
  330 and converted automatically.

## Testing on an emulator

With the SDK's emulator and an arm64 system image
(`sdkmanager "emulator" "system-images;android-34;google_apis;arm64-v8a"`):

```
avdmanager create avd -n test -k "system-images;android-34;google_apis;arm64-v8a"
emulator -avd test &
adb install -r android/mygame.apk
adb shell am start -n com.rayzr.mygame/android.app.NativeActivity
adb logcat -s Rayzr      # the game's log
adb shell input swipe 500 800 800 800 1500   # a finger dragging
```

From the command line, without the editor, `scripts/package_android.sh
<project> <out-dir>` makes the same APK and AAB, and
`scripts/check_android_package.sh` checks them.

## Building the runner

`scripts/build_android_runner.sh` builds `bin/runners/android/libmain.so`
with the NDK (`ANDROID_NDK_HOME`, or the newest under `$ANDROID_HOME/ndk`).
It fetches raylib 5.5, Lua 5.4.7 and Box2D 3.1.1 (the versions the web
runner uses) and builds them, Clipper2 and the engine for
`linux_arm64` / `android`. CI builds it on every push and the release
workflow ships it with the editor.

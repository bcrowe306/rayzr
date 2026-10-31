package editor

import "core:fmt"
import os "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"

// ============================================================================
// Android export (#276): an APK (install it: adb install, or open it on the
// phone) and an AAB (Google Play), arm64, Android 7+. The runner is
// runners/android/libmain.so (scripts/build_android_runner.sh), raylib's
// NativeActivity: the game goes in the package's assets (game.rayzr, the
// UI font) and the runner copies it out on start.
//
// Packaging uses the Android SDK's build tools (aapt2, zipalign, apksigner,
// the android-34 platform) and Java 17+ (jar, keytool, jarsigner) - found
// through ANDROID_HOME / ANDROID_SDK_ROOT, the usual install folders and
// JAVA_HOME. The AAB also needs bundletool (bundletool*.jar in
// runners/android/ or the SDK folder, or RAYZR_BUNDLETOOL); without it only
// the APK is made. scripts/package_android.sh does the same from a shell.
//
// Signing: the project's keystore and key alias (Export settings), its
// password from RAYZR_ANDROID_KEYSTORE_PASSWORD (never saved); with none,
// the debug key (~/.android/debug.keystore, made when missing) - fine for
// testing, not for Google Play.
// ============================================================================

ANDROID_MIN_SDK :: 24
ANDROID_TARGET_SDK :: 34

// Android_SdkDir: the Android SDK ("" = not found).
Android_SdkDir :: proc() -> string {
	for env in ([]string{"ANDROID_HOME", "ANDROID_SDK_ROOT"}) {
		if v := os.get_env(env, context.temp_allocator); v != "" && os.is_dir(v) do return v
	}
	home := os.get_env("HOME", context.temp_allocator)
	if home == "" do home = os.get_env("USERPROFILE", context.temp_allocator)
	local := os.get_env("LOCALAPPDATA", context.temp_allocator)
	cands := [?]string{
		fmt.tprintf("%s/Library/Android/sdk", home), // Android Studio, macOS
		"/opt/homebrew/share/android-commandlinetools", // Homebrew
		"/usr/local/share/android-commandlinetools",
		fmt.tprintf("%s/Android/Sdk", home), // Android Studio, Linux
		fmt.tprintf("%s\\Android\\Sdk", local), // Android Studio, Windows
	}
	for c in cands do if os.is_dir(c) do return c
	return ""
}

// android_newest: the newest entry of an SDK folder (build-tools/<version>).
@(private = "file")
android_newest :: proc(dir: string) -> string {
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil || len(infos) == 0 do return ""
	names := make([dynamic]string, context.temp_allocator)
	for fi in infos do if fi.type == .Directory do append(&names, fi.name)
	if len(names) == 0 do return ""
	slice.sort_by(names[:], proc(a, b: string) -> bool {return version_less(a, b)})
	p, _ := filepath.join({dir, names[len(names) - 1]}, context.temp_allocator)
	return p
}

@(private = "file")
version_less :: proc(a, b: string) -> bool {
	as, bs := strings.split(a, ".", context.temp_allocator), strings.split(b, ".", context.temp_allocator)
	for i in 0 ..< max(len(as), len(bs)) {
		x := strings_to_int(as[i]) if i < len(as) else 0
		y := strings_to_int(bs[i]) if i < len(bs) else 0
		if x != y do return x < y
	}
	return false
}

@(private = "file")
strings_to_int :: proc(s: string) -> int {
	n := 0
	for ch in s {
		if ch < '0' || ch > '9' do break
		n = n * 10 + int(ch - '0')
	}
	return n
}

// Android_JavaBin: a JDK 17+'s bin folder ("" = none).
Android_JavaBin :: proc() -> string {
	exe := "java.exe" when ODIN_OS == .Windows else "java"
	ok :: proc(home, exe: string) -> bool {
		if home == "" do return false
		p, _ := filepath.join({home, "bin", exe}, context.temp_allocator)
		if !os.is_file(p) do return false
		st, out, errOut, err := os.process_exec({command = {p, "-version"}}, context.temp_allocator)
		if err != nil || st.exit_code != 0 do return false
		text := string(errOut) if len(errOut) > 0 else string(out)
		i := strings.index(text, "version \"")
		if i < 0 do return false
		v := text[i + 9:]
		major := strings_to_int(v)
		if major == 1 do return false // (1.8: Java 8)
		return major >= 17
	}
	cands := make([dynamic]string, context.temp_allocator)
	append(&cands, os.get_env("JAVA_HOME", context.temp_allocator))
	when ODIN_OS == .Darwin {
		append(&cands, "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home", "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home",
			"/Applications/Android Studio.app/Contents/jbr/Contents/Home")
		if st, out, _, err := os.process_exec({command = {"/usr/libexec/java_home", "-v", "17+"}}, context.temp_allocator); err == nil && st.exit_code == 0 {
			append(&cands, strings.trim_space(string(out)))
		}
	}
	for h in cands do if ok(h, exe) {
		p, _ := filepath.join({h, "bin"}, context.temp_allocator)
		return p
	}
	return ""
}

// Android_PackageId: the app's id (com.example.game).
Android_PackageId :: proc(cfg: ^e.ProjectConfig, name: string) -> string {
	if cfg.export.androidPackage != "" do return cfg.export.androidPackage
	sb := strings.builder_make(context.temp_allocator)
	for ch in strings.to_lower(name, context.temp_allocator) do if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') do strings.write_rune(&sb, ch)
	id := strings.to_string(sb)
	if id == "" || (id[0] >= '0' && id[0] <= '9') do id = strings.concatenate({"game", id}, context.temp_allocator)
	return fmt.tprintf("com.rayzr.%s", id)
}

@(private = "file")
xml_escape :: proc(s: string) -> string {
	out, _ := strings.replace_all(s, "&", "&amp;", context.temp_allocator)
	out, _ = strings.replace_all(out, "<", "&lt;", context.temp_allocator)
	out, _ = strings.replace_all(out, ">", "&gt;", context.temp_allocator)
	out, _ = strings.replace_all(out, "\"", "&quot;", context.temp_allocator)
	return out
}

// android_manifest: NativeActivity running libmain.so, full screen, the
// project's orientation (wider than tall: landscape).
android_manifest :: proc(cfg: ^e.ProjectConfig, id, label: string) -> string {
	orient := "sensorLandscape" if cfg.windowWidth >= cfg.windowHeight else "sensorPortrait"
	code := max(cfg.export.androidVersionCode, 1)
	version := cfg.version if cfg.version != "" else "1.0"
	return fmt.tprintf(`<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="%s"
    android:versionCode="%d" android:versionName="%s">
    <uses-feature android:glEsVersion="0x00030000" android:required="true"/>
    <application android:label="%s" android:icon="@mipmap/icon" android:hasCode="false"
        android:allowBackup="true" android:appCategory="game">
        <activity android:name="android.app.NativeActivity" android:exported="true"
            android:screenOrientation="%s" android:launchMode="singleTask"
            android:configChanges="orientation|keyboardHidden|screenSize|screenLayout|keyboard|navigation|uiMode"
            android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
            <meta-data android:name="android.app.lib_name" android:value="main"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
`, id, code, xml_escape(version), xml_escape(label), orient)
}

// android_bundletool: bundletool's jar ("" = none: no AAB).
@(private = "file")
android_bundletool :: proc(runner, sdk: string) -> string {
	if v := os.get_env("RAYZR_BUNDLETOOL", context.temp_allocator); v != "" && os.is_file(v) do return v
	for dir in ([]string{filepath.dir(runner, context.temp_allocator), sdk, Resource_Path("bin", "android_tools")}) {
		infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil do continue
		for fi in infos do if strings.has_prefix(fi.name, "bundletool") && strings.has_suffix(fi.name, ".jar") {
			p, _ := filepath.join({dir, fi.name}, context.temp_allocator)
			return p
		}
	}
	return ""
}

// android_run: a tool to completion (in `dir`), with extra environment;
// false (logged) when it fails.
@(private = "file")
android_run :: proc(state: ^EditorState, cmd: []string, dir := "", env: []string = nil) -> bool {
	full: []string
	if len(env) > 0 {
		cur, _ := os.environ(context.temp_allocator)
		all := make([dynamic]string, context.temp_allocator)
		append(&all, ..cur)
		append(&all, ..env)
		full = all[:]
	}
	st, _, stderr, err := os.process_exec({command = cmd, working_dir = dir, env = full}, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Error, "Android export: %s: %v", filepath.base(cmd[0]), err)
		return false
	}
	if st.exit_code != 0 {
		Editor_Log(state, .Error, "Android export: %s failed: %s", filepath.base(cmd[0]), strings.trim_space(string(stderr)))
		return false
	}
	return true
}

export_android :: proc(state: ^EditorState, cfg: ^e.ProjectConfig, runner, rayzr, dir, name: string) -> (string, bool) {
	sdk := Android_SdkDir()
	if sdk == "" {
		Editor_Log(state, .Error, "Android export needs the Android SDK (build tools 34 and the android-34 platform): install Android Studio or the command-line tools, or set ANDROID_HOME")
		return "", false
	}
	bt := android_newest(filepath.join({sdk, "build-tools"}, context.temp_allocator) or_else "")
	platform, _ := filepath.join({sdk, "platforms", fmt.tprintf("android-%d", ANDROID_TARGET_SDK), "android.jar"}, context.temp_allocator)
	if bt == "" || !os.is_file(platform) {
		Editor_Log(state, .Error, "Android export: the SDK at %s needs \"build-tools;34.0.0\" and \"platforms;android-34\" (sdkmanager)", sdk)
		return "", false
	}
	java := Android_JavaBin()
	if java == "" {
		Editor_Log(state, .Error, "Android export needs Java 17 or newer (set JAVA_HOME): it signs and packs the app")
		return "", false
	}
	exe :: proc(dir, name: string) -> string {
		n := name
		when ODIN_OS == .Windows {
			for ext in ([]string{".exe", ".bat"}) {
				p, _ := filepath.join({dir, strings.concatenate({name, ext}, context.temp_allocator)}, context.temp_allocator)
				if os.is_file(p) do return p
			}
		}
		p, _ := filepath.join({dir, n}, context.temp_allocator)
		return p
	}
	aapt2, zipalign, apksigner := exe(bt, "aapt2"), exe(bt, "zipalign"), exe(bt, "apksigner")
	jar, keytool, jarsigner, javaExe := exe(java, "jar"), exe(java, "keytool"), exe(java, "jarsigner"), exe(java, "java")

	// The staging folder: assets (the game, the font), the icon, the runner.
	stage, _ := filepath.join({dir, ".android_build"}, context.temp_allocator)
	_ = os.remove_all(stage)
	defer os.remove_all(stage)
	sub :: proc(stage: string, parts: ..string) -> string {
		all := make([dynamic]string, context.temp_allocator)
		append(&all, stage)
		append(&all, ..parts)
		p, _ := filepath.join(all[:], context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
		return p
	}
	copy_to :: proc(state: ^EditorState, dst, src: string) -> bool {
		if err := os.copy_file(dst, src); err != nil {
			Editor_Log(state, .Error, "Android export: can't copy %s: %v", src, err)
			return false
		}
		return true
	}
	if !copy_to(state, sub(stage, "assets", "game.rayzr"), rayzr) do return "", false
	if font := runner_font(runner); font != "" do copy_to(state, sub(stage, "assets", "fonts", RUNNER_FONT), font)
	if !copy_to(state, sub(stage, "lib", "arm64-v8a", "libmain.so"), runner) do return "", false
	if cfg.icon != "" {
		icon, _ := filepath.join({state.projectPath, cfg.icon}, context.temp_allocator)
		copy_to(state, sub(stage, "res", "mipmap", "icon.png"), icon)
	}
	id := Android_PackageId(cfg, name)
	label := cfg.name if cfg.name != "" else name
	manifest := sub(stage, "AndroidManifest.xml")
	_ = os.write_entire_file(manifest, transmute([]u8)android_manifest(cfg, id, label))

	// Resources, then the APK and (proto) the AAB's module.
	resZip := sub(stage, "res.zip")
	resDir, _ := filepath.join({stage, "res"}, context.temp_allocator)
	assets, _ := filepath.join({stage, "assets"}, context.temp_allocator)
	if !android_run(state, {aapt2, "compile", "-o", resZip, "--dir", resDir}) do return "", false
	link :: proc(state: ^EditorState, aapt2, out, platform, manifest, assets, resZip: string, proto: bool) -> bool {
		cmd := make([dynamic]string, context.temp_allocator)
		append(&cmd, aapt2, "link", "-o", out, "-I", platform, "--manifest", manifest, "--min-sdk-version", fmt.tprint(ANDROID_MIN_SDK), "--target-sdk-version", fmt.tprint(ANDROID_TARGET_SDK), "-A", assets, resZip)
		if proto do append(&cmd, "--proto-format")
		return android_run(state, cmd[:])
	}
	baseApk := sub(stage, "base.apk")
	if !link(state, aapt2, baseApk, platform, manifest, assets, resZip, false) do return "", false
	if !android_run(state, {jar, "uMf", baseApk, "-C", stage, "lib"}) do return "", false
	aligned := sub(stage, "aligned.apk")
	if !android_run(state, {zipalign, "-f", "-p", "4", baseApk, aligned}) do return "", false

	// The key: the project's, else the debug one.
	ks, alias := cfg.export.androidKeystore, cfg.export.androidKeyAlias
	passEnv := "RAYZR_ANDROID_KEYSTORE_PASSWORD"
	env: []string
	if ks != "" {
		if !filepath.is_abs(ks) do ks, _ = filepath.join({state.projectPath, ks}, context.temp_allocator)
		if os.get_env(passEnv, context.temp_allocator) == "" {
			Editor_Log(state, .Error, "Android export: set %s to the keystore's password (it's never saved in the project)", passEnv)
			return "", false
		}
		if alias == "" {
			Editor_Log(state, .Error, "Android export: set the key alias of %s (Export settings)", ks)
			return "", false
		}
	} else {
		home := os.get_env("HOME", context.temp_allocator)
		if home == "" do home = os.get_env("USERPROFILE", context.temp_allocator)
		ks, _ = filepath.join({home, ".android", "debug.keystore"}, context.temp_allocator)
		alias = "androiddebugkey"
		passEnv = "RAYZR_ANDROID_DEBUG_PASSWORD"
		env = {"RAYZR_ANDROID_DEBUG_PASSWORD=android"}
		if !os.is_file(ks) {
			_ = os.make_directory_all(filepath.dir(ks, context.temp_allocator))
			gen := []string{keytool, "-genkeypair", "-keystore", ks, "-storepass", "android", "-keypass", "android", "-alias", alias,
				"-dname", "CN=Android Debug,O=Android,C=US", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000"}
			if !android_run(state, gen) do return "", false
		}
		Editor_Log(state, .Info, "Android export: signed with the debug key (for testing; set a keystore in Export settings for Google Play)")
	}
	slug := strings.to_lower(export_safe_name(name), context.temp_allocator)
	apk, _ := filepath.join({dir, fmt.tprintf("%s.apk", slug)}, context.temp_allocator)
	sign := []string{apksigner, "sign", "--ks", ks, "--ks-key-alias", alias, "--ks-pass", fmt.tprintf("env:%s", passEnv),
		"--key-pass", fmt.tprintf("env:%s", passEnv), "--out", apk, aligned}
	if !android_run(state, sign, env = env) do return "", false
	idsig := strings.concatenate({apk, ".idsig"}, context.temp_allocator)
	_ = os.remove(idsig) // (incremental-install signature: not needed)
	Editor_Log(state, .Info, "Android: %s (%s)", apk, id)

	// The AAB.
	bundletool := android_bundletool(runner, sdk)
	if bundletool == "" {
		Editor_Log(state, .Warn, "Android export: no AAB - it needs bundletool: put bundletool-all.jar (github.com/google/bundletool/releases) in %s, or set RAYZR_BUNDLETOOL", filepath.dir(runner, context.temp_allocator))
		return strings.clone(dir, context.temp_allocator), true
	}
	protoApk := sub(stage, "proto.apk")
	if !link(state, aapt2, protoApk, platform, manifest, assets, resZip, true) do return "", false
	module := sub(stage, "module", "manifest", "x")
	module = filepath.dir(filepath.dir(module, context.temp_allocator), context.temp_allocator)
	if !android_run(state, {jar, "xf", protoApk}, dir = module) do return "", false
	inManifest, _ := filepath.join({module, "AndroidManifest.xml"}, context.temp_allocator)
	toManifest, _ := filepath.join({module, "manifest", "AndroidManifest.xml"}, context.temp_allocator)
	if err := os.rename(inManifest, toManifest); err != nil {
		Editor_Log(state, .Error, "Android export: %v", err)
		return "", false
	}
	if !copy_to(state, sub(stage, "module", "lib", "arm64-v8a", "libmain.so"), runner) do return "", false
	baseZip := sub(stage, "base.zip")
	if !android_run(state, {jar, "cMf", baseZip, "-C", module, "."}) do return "", false
	aab, _ := filepath.join({dir, fmt.tprintf("%s.aab", slug)}, context.temp_allocator)
	_ = os.remove(aab)
	if !android_run(state, {javaExe, "-jar", bundletool, "build-bundle", fmt.tprintf("--modules=%s", baseZip), fmt.tprintf("--output=%s", aab)}) do return "", false
	if !android_run(state, {jarsigner, "-keystore", ks, "-storepass:env", passEnv, aab, alias}, env = env) do return "", false
	Editor_Log(state, .Info, "Android: %s (Google Play)", aab)
	return strings.clone(dir, context.temp_allocator), true
}

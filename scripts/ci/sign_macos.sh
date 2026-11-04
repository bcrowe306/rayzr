#!/usr/bin/env bash
# Signs and notarizes the macOS release with a Developer ID (#289;
# .github/workflows/build-packages.yml). Two calls, in this order:
#
#   scripts/ci/sign_macos.sh "dist/Rayzr Editor.app"     # 1. the app
#   scripts/ci/archive_editor.sh ...                     # 2. the disk image is made (with the stapled app)
#   scripts/ci/sign_macos.sh rayzr-editor-<v>-macos.dmg  # 3. the disk image
#
#   .app  every dylib and executable inside signed, inside out, then the app
#         (hardened runtime, a secure timestamp; no entitlements: nothing in
#         it JITs or loads unsigned code), verified, notarized, stapled
#   .dmg  signed (a timestamp; disk images take no hardened runtime),
#         verified, notarized, stapled, Gatekeeper-assessed
#
# Notarization waits for Apple's verdict (`notarytool submit --wait`) and
# fails on anything but Accepted, printing `notarytool log`. The certificate
# goes into a temporary keychain, deleted when the script exits (also on a
# failure). From the repository secrets (RELEASING.md, "Setting up macOS
# signing"):
#   MACOS_CERTIFICATE            the Developer ID Application certificate + key (.p12, base64)
#   MACOS_CERTIFICATE_PASSWORD   the .p12's password
#   MACOS_SIGNING_IDENTITY       "Developer ID Application: Name (TEAMID)" (or its SHA-1)
#   MACOS_NOTARY_APPLE_ID        the Apple ID notarytool signs in with
#   MACOS_NOTARY_TEAM_ID         the team id (10 characters)
#   MACOS_NOTARY_PASSWORD        an app-specific password for that Apple ID
#
# SIGN_DRY_RUN=1: prints the commands it would run (with placeholder
# secrets and identity, no keychain, nothing signed or uploaded) - to check
# the steps without a certificate.
set -euo pipefail
target="${1:?usage: sign_macos.sh <app.app | image.dmg>}"
target="${target%/}"
case "$target" in
	*.app) kind=app ;;
	*.dmg) kind=dmg ;;
	*) echo "sign_macos.sh: expected a .app or a .dmg, got $target" >&2; exit 2 ;;
esac
[ -e "$target" ] || { echo "sign_macos.sh: no $target" >&2; exit 2; }
dry="${SIGN_DRY_RUN:-}"
tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
secrets=(MACOS_CERTIFICATE MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY MACOS_NOTARY_APPLE_ID MACOS_NOTARY_TEAM_ID MACOS_NOTARY_PASSWORD)

if [ -n "$dry" ]; then
	# (Placeholders, never the real values: the commands are printed.)
	for s in "${secrets[@]}"; do export "$s=<$s>"; done
	MACOS_SIGNING_IDENTITY="Developer ID Application: Dry Run (TEAMID0000)"
fi
missing=""
for s in "${secrets[@]}"; do [ -n "${!s:-}" ] || missing="$missing $s"; done
[ -z "$missing" ] || { echo "sign_macos.sh: missing repository secret(s):$missing (RELEASING.md, \"Setting up macOS signing\")" >&2; exit 1; }

# run CMD...: runs it (dry run: prints it).
run() {
	if [ -n "$dry" ]; then printf '+'; printf ' %q' "$@"; printf '\n'; else "$@"; fi
}

# --- the temporary keychain ----------------------------------------------------
keychain="$tmp/rayzr-signing-$$.keychain-db"
cleanup() {
	rm -f "$tmp/rayzr-cert-$$.p12"
	if [ -z "$dry" ] && [ -f "$keychain" ]; then security delete-keychain "$keychain" || true; fi
	[ -n "$dry" ] && echo "+ security delete-keychain $keychain"
	return 0
}
trap cleanup EXIT
if [ -n "$dry" ]; then
	echo "+ (dry run) a temporary keychain $keychain with MACOS_CERTIFICATE imported"
else
	kpass=$(uuidgen)
	(umask 077; printf '%s' "$MACOS_CERTIFICATE" | base64 --decode > "$tmp/rayzr-cert-$$.p12")
	security create-keychain -p "$kpass" "$keychain"
	security set-keychain-settings -lut 21600 "$keychain"
	security unlock-keychain -p "$kpass" "$keychain"
	security import "$tmp/rayzr-cert-$$.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain" > /dev/null ||
		{ echo "sign_macos.sh: couldn't import MACOS_CERTIFICATE (a base64 .p12 with its private key) with MACOS_CERTIFICATE_PASSWORD" >&2; exit 1; }
	rm -f "$tmp/rayzr-cert-$$.p12"
	security set-key-partition-list -S apple-tool:,apple: -s -k "$kpass" "$keychain" > /dev/null
	# (Searched first; the login and system keychains stay on the list.)
	security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
fi

# --- preflight: a Developer ID Application identity, in that keychain ------------
# (An "Apple Development" or "Apple Distribution" certificate signs, but
# notarization rejects it: say so before uploading anything.)
if [ -z "$dry" ]; then
	identities=$(security find-identity -v -p codesigning "$keychain")
	line=$(grep -F -- "$MACOS_SIGNING_IDENTITY" <<< "$identities" | head -1 || true)
	if [ -z "$line" ]; then
		echo "sign_macos.sh: MACOS_SIGNING_IDENTITY isn't a valid code-signing identity in MACOS_CERTIFICATE. The .p12 holds:" >&2
		sed -E 's/^ *[0-9]+\) [0-9A-F]{40} /  /' <<< "$identities" >&2
		echo "MACOS_SIGNING_IDENTITY must be one of those, exactly (\"Developer ID Application: Name (TEAMID)\")." >&2
		exit 1
	fi
	case "$line" in
		*'"Developer ID Application: '*) ;;
		*) echo "sign_macos.sh: MACOS_SIGNING_IDENTITY / MACOS_CERTIFICATE is $(sed -E 's/^ *[0-9]+\) [0-9A-F]{40} //' <<< "$line"), not a \"Developer ID Application\" certificate: notarization needs one (Apple Developer > Certificates > + > Developer ID Application; export it with its key as .p12 into MACOS_CERTIFICATE)." >&2
			exit 1 ;;
	esac
	echo "Signing identity: $(sed -E 's/^ *[0-9]+\) [0-9A-F]{40} //' <<< "$line")"
else
	echo "+ security find-identity -v -p codesigning $keychain   # must list \"$MACOS_SIGNING_IDENTITY\""
fi

# --- notarize FILE: submit, wait, fail unless Accepted ---------------------------
notarize() {
	local file="$1" out="$tmp/rayzr-notary-$$.json" status id
	if [ -n "$dry" ]; then
		run xcrun notarytool submit "$file" --apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" \
			--password "$MACOS_NOTARY_PASSWORD" --wait --output-format json
		echo "+ (fails unless its status is Accepted; then: xcrun notarytool log <id> ...)"
		return
	fi
	echo "Notarizing $(basename "$file") (waits for Apple)..."
	xcrun notarytool submit "$file" --apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" \
		--password "$MACOS_NOTARY_PASSWORD" --wait --output-format json > "$out" || true
	status=$(plutil -extract status raw -o - "$out" 2> /dev/null || echo "?")
	id=$(plutil -extract id raw -o - "$out" 2> /dev/null || echo "")
	echo "notarytool: $status${id:+ (submission $id)}"
	if [ "$status" != Accepted ]; then
		echo "sign_macos.sh: notarization of $(basename "$file") wasn't accepted ($status)" >&2
		cat "$out" >&2
		[ -n "$id" ] && xcrun notarytool log "$id" --apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" \
			--password "$MACOS_NOTARY_PASSWORD" >&2 || true
		rm -f "$out"
		exit 1
	fi
	rm -f "$out"
}

if [ "$kind" = app ]; then
	sign() { run codesign --force --timestamp --options runtime --sign "$MACOS_SIGNING_IDENTITY" "$@"; }
	# Inside out: libraries and helper executables (the bundled runners,
	# lua-language-server, the Frameworks) first, the app last.
	while IFS= read -r -d '' f; do
		if file "$f" | grep -q 'Mach-O'; then sign "$f"; fi
	done < <(find "$target/Contents" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) ! -path '*/MacOS/*' -print0 | sort -z)
	sign "$target"
	run codesign --verify --deep --strict --verbose=2 "$target"
	# (notarytool takes a zip of the app; the ticket is stapled to the app itself.)
	zip="$tmp/rayzr-notarize-$$.zip"
	run ditto -c -k --keepParent "$target" "$zip"
	notarize "$zip"
	rm -f "$zip"
	run xcrun stapler staple "$target"
	run xcrun stapler validate "$target"
	echo "Signed, notarized and stapled $target"
else
	run codesign --force --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$target"
	run codesign --verify --strict --verbose=2 "$target"
	notarize "$target"
	run xcrun stapler staple "$target"
	run xcrun stapler validate "$target"
	run spctl -a -t open --context context:primary-signature -v "$target"
	echo "Signed, notarized and stapled $target"
fi

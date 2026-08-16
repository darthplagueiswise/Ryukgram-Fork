#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer Homebrew GNU Make 4.x so Theos enables parallel builds.
if [ -d /opt/homebrew/opt/make/libexec/gnubin ]; then
	PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
fi

# ============================================================
# RyukGram Build Script
# ============================================================

GREEN='\033[1m\033[32m'
YELLOW='\033[0;33m'
RED='\033[1m\033[0;31m'
RESET='\033[0m'

APP_NAME="RyukGram"
PACKAGES_DIR="packages"
TWEAK_DYLIB=".theos/obj/${APP_NAME}.dylib"
BUNDLE_NAME="${APP_NAME}.bundle"
BUNDLE_PATH="${PACKAGES_DIR}/${BUNDLE_NAME}"

TWEAK_VERSION="$(awk '/^Version:/ {print $2}' "${REPO_ROOT}/control" 2>/dev/null)"
[ -n "$TWEAK_VERSION" ] || TWEAK_VERSION=unknown
IG_VER="$(head -1 "${REPO_ROOT}/IG_VERSION" 2>/dev/null | tr -d ' \t\r\n')"
[ -n "$IG_VER" ] || IG_VER=unknown

CMAKE_OSX_ARCHITECTURES="arm64e;arm64"
CMAKE_OSX_SYSROOT="iphoneos"

log() {
	printf "%b\n" "${GREEN}$*${RESET}"
}

warn() {
	printf "%b\n" "${YELLOW}$*${RESET}"
}

die() {
	printf "%b\n" "${RED}$*${RESET}" >&2
	exit 1
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$2"
}

# Auto-detect THEOS if not set.
ensure_theos() {
	if [ -n "${THEOS:-}" ]; then
		return
	fi

	if [ -d "$HOME/theos" ]; then
		export THEOS="$HOME/theos"
	else
		die "THEOS not set and ~/theos not found.
Set THEOS or install Theos to ~/theos"
	fi
}

ensure_packages_dir() {
	mkdir -p "$PACKAGES_DIR"
}

clean_build() {
	make clean 2>/dev/null || true
	rm -rf .theos
}

# Always use FINALPACKAGE=1 for Theos builds.
make_final() {
	local args="${1:-}"

	# Keep the dynamic-probe manifest in sync with the source (probe tags + hook
	# targets). Harmless when RYG_PROBE=0 (the header just isn't included).
	if [ -f "$REPO_ROOT/scripts/gen_probe_manifest.py" ]; then
		python3 "$REPO_ROOT/scripts/gen_probe_manifest.py" 2>/dev/null || true
	fi

	# Refresh the bundled Instagram icon list for the in-app icon browser.
	if [ -f "$REPO_ROOT/scripts/gen_ig_icons.py" ]; then
		python3 "$REPO_ROOT/scripts/gen_ig_icons.py" 2>/dev/null || true
	fi

	if [ -n "$args" ]; then
		make FINALPACKAGE=1 $args
	else
		make FINALPACKAGE=1
	fi

	if [ -f "$TWEAK_DYLIB" ]; then
		strip -x -S "$TWEAK_DYLIB" 2>/dev/null || true
	fi
}

# Copy Localization resources (*.lproj) into a RyukGram.bundle.
# Arg 1: destination bundle directory, created if missing.
copy_localization_into_bundle() {
	local dest="$1"
	local src="src/Localization/Resources"

	[ -d "$src" ] || return 0

	mkdir -p "$dest"

	for lproj in "$src"/*.lproj; do
		[ -d "$lproj" ] || continue
		cp -R "$lproj" "$dest/"
	done
}

# Copy generic static assets into RyukGram.bundle.
# Used for bundled images the tweak loads via RYGLocalizationBundle().
# Arg 1: destination bundle directory, created if missing.
copy_bundle_assets() {
	local dest="$1"
	local src="src/BundleAssets"

	[ -d "$src" ] || return 0

	mkdir -p "$dest"

	find "$src" -maxdepth 1 -type f \( \
		-iname '*.png' -o \
		-iname '*.jpg' -o \
		-iname '*.jpeg' -o \
		-iname '*.pdf' -o \
		-iname '*.bin' -o \
		-iname '*.json' \
	\) -exec cp {} "$dest/" \;
}

# Post-process IPA in one extraction pass:
# - Copy custom alternate app icons from ./AppIcon/
# - Patch Info.plist CFBundleAlternateIcons
# - Embed Safari extension for sideload/trollstore
# - Strip .appex bundles for the no-plugins build
# Arg 1: path to IPA.
# Arg 2: zip compression level.
# Arg 3: mode: normal / noplugins / trollstore
postprocess_ipa_bundle() {
	local ipa="$1"
	local compression="$2"
	local mode="${3:-normal}"
	local dup_id="${4:-}"

	local tmpdir
	local app_dir
	local plist
	local pb="/usr/libexec/PlistBuddy"

	local icon_src="AppIcon"
	local appex_src="extensions/OpenInstagramSafariExtension.appex"

	local icon_names=(
		"2010"
	)

	local icon_suffixes=(
		"@2x"
		"@3x"
		"-iPad@2x"
		"-iPadPro@2x"
	)

	log "Post-processing IPA"

	tmpdir="$(mktemp -d)"

	unzip -q "$ipa" -d "$tmpdir"

	app_dir="$(find "$tmpdir/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"

	if [ -z "$app_dir" ]; then
		rm -rf "$tmpdir"
		die "Could not find .app bundle inside IPA."
	fi

	plist="$app_dir/Info.plist"

	if [ ! -f "$plist" ]; then
		rm -rf "$tmpdir"
		die "Info.plist not found inside app bundle."
	fi

	# Patch alternate icons if ./AppIcon exists.
	if [ -d "$icon_src" ]; then
		[ -x "$pb" ] || {
			rm -rf "$tmpdir"
			die "PlistBuddy not found at $pb"
		}

		log "Patching alternate app icons"

		for icon_name in "${icon_names[@]}"; do
			for suffix in "${icon_suffixes[@]}"; do
				local icon="${icon_name}${suffix}.png"

				if [ ! -f "$icon_src/$icon" ]; then
					rm -rf "$tmpdir"
					die "Missing icon file: $icon_src/$icon"
				fi

				cp -f "$icon_src/$icon" "$app_dir/"
			done
		done

		"$pb" -c "Print :CFBundleIcons" "$plist" >/dev/null 2>&1 || \
			"$pb" -c "Add :CFBundleIcons dict" "$plist"

		"$pb" -c "Print :CFBundleIcons:CFBundleAlternateIcons" "$plist" >/dev/null 2>&1 || \
			"$pb" -c "Add :CFBundleIcons:CFBundleAlternateIcons dict" "$plist"

		for icon_name in "${icon_names[@]}"; do
			"$pb" -c "Delete :CFBundleIcons:CFBundleAlternateIcons:${icon_name}" "$plist" >/dev/null 2>&1 || true
			"$pb" -c "Add :CFBundleIcons:CFBundleAlternateIcons:${icon_name} dict" "$plist"
			"$pb" -c "Add :CFBundleIcons:CFBundleAlternateIcons:${icon_name}:CFBundleIconFiles array" "$plist"

			for suffix in "${icon_suffixes[@]}"; do
				"$pb" -c "Add :CFBundleIcons:CFBundleAlternateIcons:${icon_name}:CFBundleIconFiles: string ${icon_name}${suffix}" "$plist"
			done
		done
	fi

	if [ "$mode" = "noplugins" ]; then
		local appex_count="0"

		log "Stripping app extensions (no-plugins build)"

		appex_count="$(find "$app_dir" -type d -name '*.appex' | wc -l | tr -d ' ')"
		find "$app_dir" -type d -name '*.appex' -prune -exec rm -rf {} +

		warn "  removed ${appex_count} .appex bundle(s)"
	else
		if [ -d "$appex_src" ]; then
			log "Embedding Safari extension"

			mkdir -p "$app_dir/PlugIns"
			rm -rf "$app_dir/PlugIns/OpenInstagramSafariExtension.appex"
			cp -R "$appex_src" "$app_dir/PlugIns/"

			# This extension lands after cyan, so re-prefix its nested id under
			# the dup parent by hand (iOS rejects a non-prefixed nested id).
			if [ -n "$dup_id" ]; then
				local ext_plist="$app_dir/PlugIns/OpenInstagramSafariExtension.appex/Info.plist"
				local ext_id
				ext_id="$("$pb" -c "Print :CFBundleIdentifier" "$ext_plist" 2>/dev/null || true)"
				if [ -n "$ext_id" ]; then
					"$pb" -c "Set :CFBundleIdentifier ${dup_id}${ext_id#com.burbn.instagram}" "$ext_plist" 2>/dev/null || true
					warn "  re-prefixed extension id → ${dup_id}${ext_id#com.burbn.instagram}"
				fi
			fi
		fi
	fi

	(
		cd "$tmpdir"
		zip -qr -"${compression}" ../repacked.ipa Payload
	)

	mv "$tmpdir/../repacked.ipa" "$ipa"
	rm -rf "$tmpdir"
}

# Copy FFmpegKit frameworks into a dir; siblings resolve via @loader_path/..
# Arg 2 non-empty: also rename libav*/libsw* to _ryg + repoint deps. Only
# TrollFools needs it — those frameworks share the host app's Frameworks/ where
# plain ffmpeg names collide; cyan/deb keep them isolated in RyukGram.bundle.
patch_ffmpegkit_frameworks() {
	local bundle="$1"
	local rename_ffmpeg="${2:-}"
	local libs="libavutil libavcodec libavformat libavfilter libavdevice libswresample libswscale"
	local fw lib target

	[ -d "modules/ffmpegkit/ffmpegkit.framework" ] || return 0

	log "Copying FFmpegKit frameworks"

	for fw in modules/ffmpegkit/*.framework; do
		[ -d "$fw" ] || continue
		cp -R "$fw" "$bundle/"
	done

	[ -n "$rename_ffmpeg" ] || return 0

	log "Renaming FFmpegKit libs to _ryg (TrollFools collision-safety)"

	for lib in $libs; do
		[ -d "$bundle/${lib}.framework" ] || continue
		mv "$bundle/${lib}.framework" "$bundle/${lib}_ryg.framework"
		install_name_tool -id "@rpath/${lib}_ryg.framework/${lib}" \
			"$bundle/${lib}_ryg.framework/${lib}" 2>/dev/null || true
	done

	# Repoint deps to @rpath/<lib>_ryg — TrollFools adds an rpath to Frameworks/
	# when it injects each top-level framework, so @rpath resolves there.
	for target in "$bundle/ffmpegkit.framework/ffmpegkit" \
	              "$bundle"/libav*_ryg.framework/libav* \
	              "$bundle"/libsw*_ryg.framework/libsw*; do
		[ -f "$target" ] || continue
		for lib in $libs; do
			install_name_tool -change "@loader_path/../${lib}.framework/${lib}" \
				"@rpath/${lib}_ryg.framework/${lib}" "$target" 2>/dev/null || true
			install_name_tool -change "@rpath/${lib}.framework/${lib}" \
				"@rpath/${lib}_ryg.framework/${lib}" "$target" 2>/dev/null || true
		done
	done
}

# FFmpegKit ships unsigned; TrollFools and cyan sign on inject, a deb has nothing.
# AMFI won't dlopen an unsigned Mach-O.
sign_ffmpegkit_frameworks() {
	local bundle="$1"
	local bin
	local n=0

	if ! command -v ldid >/dev/null; then
		warn "ldid not found — FFmpegKit will not load on device."
		return 0
	fi

	for bin in "$bundle"/*.framework/*; do
		[ -f "$bin" ] || continue
		file "$bin" 2>/dev/null | grep -q 'Mach-O' || continue
		ldid -S "$bin" 2>/dev/null || true
		n=$((n + 1))
	done

	[ "$n" -gt 0 ] && log "Signed $n FFmpegKit Mach-O(s)"
}

# Build RyukGram.bundle: lproj resources + static assets + optional FFmpegKit.
build_bundle() {
	local bundle="$1"

	rm -rf "$bundle"
	mkdir -p "$bundle"

	copy_localization_into_bundle "$bundle"
	copy_bundle_assets "$bundle"
	patch_ffmpegkit_frameworks "$bundle"
}

# Inject RyukGram.bundle into a .deb (lproj resources + optional FFmpegKit).
# Path: Library/Application Support/RyukGram.bundle/. Arg 1: .deb path; cwd = packages/.
inject_bundle_into_deb() {
	local base_deb="$1"
	local tmpdir
	local dylib_dir
	local prefix=""
	local bundle_dir

	tmpdir="$(mktemp -d)"

	dpkg-deb -R "$base_deb" "$tmpdir"

	dylib_dir="$(find "$tmpdir" -name "${APP_NAME}.dylib" -exec dirname {} \; | head -1)"

	if [ -z "$dylib_dir" ]; then
		rm -rf "$tmpdir"
		return 0
	fi

	[[ "$dylib_dir" == *"/var/jb/"* ]] && prefix="var/jb/"

	bundle_dir="$tmpdir/${prefix}Library/Application Support/${BUNDLE_NAME}"

	mkdir -p "$bundle_dir"

	(
		cd ..
		copy_localization_into_bundle "$bundle_dir"
		copy_bundle_assets "$bundle_dir"
		patch_ffmpegkit_frameworks "$bundle_dir"
		sign_ffmpegkit_frameworks "$bundle_dir"
	)

	# injector reads the plist as mobile; 0700 is skipped
	find "$tmpdir" -name '*.plist' -exec chmod 644 {} +
	chmod -R a+rX "$tmpdir/${prefix}Library" 2>/dev/null || true
	dpkg-deb --root-owner-group -b "$tmpdir" "$base_deb"

	rm -rf "$tmpdir"
}

# Find decrypted Instagram IPA.
# Checks packages/ first, then moves a matching IPA from cwd into packages/.
find_instagram_ipa() {
	local ipa_file=""
	local cwd_ipa=""

	ensure_packages_dir

	ipa_file="$(find "./${PACKAGES_DIR}" -maxdepth 1 -type f \( \
		-iname '*com.burbn.instagram*.ipa' -o \
		-iname 'Instagram*.ipa' -o \
		-iname '[0-9]*.ipa' \
	\) ! -iname "${APP_NAME}*.ipa" -exec basename {} \; 2>/dev/null | head -1)"

	if [ -n "$ipa_file" ]; then
		printf "%s\n" "$ipa_file"
		return 0
	fi

	cwd_ipa="$(find . -maxdepth 1 -type f \( \
		-iname '*com.burbn.instagram*.ipa' -o \
		-iname 'Instagram*.ipa' -o \
		-iname '[0-9]*.ipa' \
	\) 2>/dev/null | head -1)"

	if [ -n "$cwd_ipa" ]; then
		log "Moving $(basename "$cwd_ipa") → ${PACKAGES_DIR}/" >&2
		mv "$cwd_ipa" "$PACKAGES_DIR/"
		printf "%s\n" "$(basename "$cwd_ipa")"
		return 0
	fi

	return 1
}

# Build just the dylib for Feather/manual injection.
build_dylib() {
	local fast=""
	local rootless=""
	local out="${APP_NAME}.dylib"
	local arg

	for arg in "$@"; do
		case "$arg" in
			--fast) fast=1 ;;
			--rootless) rootless=1 ;;
		esac
	done

	# Default scheme hardcodes CydiaSubstrate at /Library/Frameworks, absent under
	# /var/jb — ellekit then skips the dylib silently.
	if [ -n "$rootless" ]; then
		export THEOS_PACKAGE_SCHEME=rootless
		out="${APP_NAME}-rootless.dylib"
	fi

	# --fast: incremental build, no clean.
	if [ -z "$fast" ]; then
		clean_build
	fi

	log "Building ${APP_NAME} dylib${rootless:+ (rootless)}"

	make_final ""

	ensure_packages_dir

	cp "$TWEAK_DYLIB" "${PACKAGES_DIR}/${out}"

	# Ship localization bundle next to the dylib so Feather/manual installs work.
	rm -rf "$BUNDLE_PATH"
	mkdir -p "$BUNDLE_PATH"

	copy_localization_into_bundle "$BUNDLE_PATH"
	copy_bundle_assets "$BUNDLE_PATH"

	log "Done!"
	echo
	echo "Dylib at:  $(pwd)/${PACKAGES_DIR}/${out}"
	echo "Bundle at: $(pwd)/${BUNDLE_PATH}"
}

# Build a sideloaded IPA. The compatibility hooks are always compiled into
# RyukGram.dylib; noplugins changes only whether app extensions are stripped.
build_sideload() {
	local mode="${1:-sideload}"
	shift || true

	# --dup [id]: spoof bundle id for a side-by-side install. id resolves:
	# CLI arg > RG_DUP_ID env > com.ryuk.ryukgram.
	# --name [name]: display name for the dup. CLI arg > RG_DUP_NAME env > RyukGram.
	local option=""
	local dup_id=""
	local dup_name=""
	local dup_enabled=0

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--dup)
				dup_enabled=1
				local nxt="${2:-}"
				if [ -n "$nxt" ] && [ "${nxt#--}" = "$nxt" ]; then
					dup_id="$nxt"
					shift
				fi
				;;
			--name)
				local nn="${2:-}"
				if [ -n "$nn" ] && [ "${nn#--}" = "$nn" ]; then
					dup_name="$nn"
					shift
				fi
				;;
			--dev|--buildonly)
				option="$1"
				;;
			"")
				;;
			*)
				warn "Unknown sideload option: $1"
				;;
		esac
		shift
	done

	if [ "$dup_enabled" = "1" ]; then
		# A duplicate bundle id needs its app extensions stripped unless all nested
		# identifiers and entitlements are re-signed for the duplicate identity.
		if [ "$mode" != "noplugins" ]; then
			die "--dup is only supported on the noplugins build.
Run: ./build.sh noplugins --dup [id]"
		fi
		dup_id="${dup_id:-${RG_DUP_ID:-com.ryuk.ryukgram}}"
		dup_name="${dup_name:-${RG_DUP_NAME:-RyukGram}}"
	fi

	local dup_args=""
	if [ -n "$dup_id" ]; then
		dup_args="-b $dup_id"

		# Concrete keychain-access-group + app-group tied to the dup's bundle id.
		# $(AppIdentifierPrefix) is left literal for the signer to substitute.
		local dup_ent="${PACKAGES_DIR}/dup-entitlements.plist"
		cat > "$dup_ent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>keychain-access-groups</key>
	<array>
		<string>\$(AppIdentifierPrefix)${dup_id}</string>
	</array>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.${dup_id}</string>
	</array>
</dict>
</plist>
EOF
		dup_args="$dup_args -x $dup_ent"
	fi

	local strip_plugins=0
	local build_label="sideloading"
	local out_ipa="${PACKAGES_DIR}/${APP_NAME}_sideload_v${TWEAK_VERSION}_IG${IG_VER}.ipa"
	local compression=9
	local makeargs=""
	local ipa_file
	local cyan_files=""

	if [ "$mode" = "noplugins" ]; then
		strip_plugins=1
		build_label="no-plugins"
		out_ipa="${PACKAGES_DIR}/${APP_NAME}_noplugins_v${TWEAK_VERSION}_IG${IG_VER}.ipa"
	fi

	# Keep dup IPAs out of the normal build's path.
	if [ -n "$dup_id" ]; then
		out_ipa="${out_ipa%.ipa}-dup.ipa"
	fi

	# Check if building with dev mode.
	if [ "$option" = "--dev" ]; then
		# The dogfood runtime browser is part of RyukGram itself. Dev builds do not
		# require or inject an additional debugger dylib.
		makeargs="DEV=1"
		compression=0
	else
		# Clear stale artifacts from older builds that used external debugger libs.
		rm -rf "${PACKAGES_DIR}/cache"
		compression=9
	fi

	# Clean build artifacts.
	clean_build
	ensure_packages_dir

	# Check for decrypted Instagram IPA.
	ipa_file="$(find_instagram_ipa)" || die "Decrypted Instagram IPA not found.
Place a *com.burbn.instagram*.ipa in ./ or ./packages/."

	# Check for cyan before packaging. --buildonly only compiles the main dylib.
	if [ "$option" != "--buildonly" ]; then
		need_cmd cyan "cyan not found. Install it with:
  pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip

Use ./build.sh sideload --buildonly to just compile without creating the IPA.
Or use ./build.sh dylib to build the dylib for Feather injection."
	fi

	log "Building ${APP_NAME} tweak for ${build_label} as IPA"

	make_final "$makeargs"

	# Copy dylib to packages.
	cp "$TWEAK_DYLIB" "${PACKAGES_DIR}/${APP_NAME}.dylib"

	# Only build libs for future use in dev build mode.
	if [ "$option" = "--buildonly" ]; then
		log "Build-only finished."
		exit 0
	fi

	# Build RyukGram.bundle with renamed frameworks for cyan injection.
	log "Building ${BUNDLE_NAME}"
	build_bundle "$BUNDLE_PATH"

	# Every generated IPA carries the one main dylib. Its compatibility layer,
	# developer browser and UI hooks therefore always share one lifecycle.
	cyan_files="$TWEAK_DYLIB"

	if [ -d "$BUNDLE_PATH" ]; then
		cyan_files="$cyan_files $BUNDLE_PATH"
	fi

	cyan_files="$(printf "%s" "$cyan_files" | xargs)"

	# Create IPA: cyan injects dylib + copies RyukGram.bundle to app root.
	log "Creating the IPA file"

	rm -f "$out_ipa"

	[ -n "$dup_id" ] && log "Duplicate build → bundle id ${dup_id}${dup_name:+, name ${dup_name}}"

	# Name goes through an array so display names with spaces survive.
	local dup_name_args=()
	[ -n "$dup_name" ] && dup_name_args=(-n "$dup_name")

	cyan -i "${PACKAGES_DIR}/${ipa_file}" \
		-o "$out_ipa" \
		-f $cyan_files \
		-c "$compression" \
		-m 15.0 \
		-du \
		$dup_args \
		${dup_name_args[@]+"${dup_name_args[@]}"}

	if [ "$strip_plugins" = "1" ]; then
		postprocess_ipa_bundle "$out_ipa" "$compression" "noplugins" "$dup_id"
	else
		postprocess_ipa_bundle "$out_ipa" "$compression" "normal" "$dup_id"
	fi

	log "Done, enjoy ${APP_NAME}!"
	echo
	echo "IPA at: $(pwd)/$out_ipa"
}

# Build rootless/rootful/roothide .deb with FFmpegKit.
build_deb() {
	local scheme="$1"
	local base_deb
	local new_name

	clean_build
	ensure_packages_dir

	log "Building ${APP_NAME} tweak for ${scheme}"

	case "$scheme" in
		rootless)
			export THEOS_PACKAGE_SCHEME=rootless
			;;
		roothide)
			# needs the roothide Theos fork
			export THEOS_PACKAGE_SCHEME=roothide
			export THEOS="${THEOS_ROOTHIDE:-$HOME/theos-roothide}"
			[ -d "$THEOS" ] || die "roothide Theos not found at ${THEOS}
Clone it with: git clone --recursive https://github.com/roothide/theos.git ${THEOS}"
			;;
		*)
			unset THEOS_PACKAGE_SCHEME
			;;
	esac

	make_final "package"

	log "Injecting ${BUNDLE_NAME} with localization + FFmpegKit into deb"

	(
		cd "$PACKAGES_DIR"

		base_deb="$(ls -t *.deb 2>/dev/null | head -n1)"

		[ -n "$base_deb" ] || die "No deb package found."

		inject_bundle_into_deb "$base_deb"

		new_name="${APP_NAME}_${TWEAK_VERSION}_IG${IG_VER}_${scheme}.deb"
		mv "$base_deb" "$new_name"
	)

	[ -d "modules/ffmpegkit/ffmpegkit.framework" ] || warn "FFmpegKit not found — deb built without FFmpegKit."

	log "Done, enjoy ${APP_NAME}!"
	echo
	echo "Deb at: $(pwd)/${PACKAGES_DIR}"
}

# TrollStore build — .tipa is a renamed .ipa.
# Skip sideload re-sign; TrollStore signs on-device.
build_trollstore() {
	local compression=9
	local ipa_file
	local out_ipa="${PACKAGES_DIR}/${APP_NAME}-trollstore.ipa"
	local out_tipa="${PACKAGES_DIR}/${APP_NAME}_trollstore_v${TWEAK_VERSION}_IG${IG_VER}.tipa"
	local cyan_files="$TWEAK_DYLIB"

	# --name [name]: set the home-screen name. CLI arg > RG_DUP_NAME env > unchanged.
	local dup_name=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--name)
				local nn="${2:-}"
				if [ -n "$nn" ] && [ "${nn#--}" = "$nn" ]; then dup_name="$nn"; shift; fi
				;;
		esac
		shift
	done
	dup_name="${dup_name:-${RG_DUP_NAME:-}}"

	clean_build
	ensure_packages_dir

	ipa_file="$(find_instagram_ipa)" || die "Decrypted Instagram IPA not found."

	need_cmd cyan "cyan not found. Install it with:
  pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip"

	log "Building ${APP_NAME} tweak for TrollStore .tipa"

	make_final ""

	cp "$TWEAK_DYLIB" "${PACKAGES_DIR}/${APP_NAME}.dylib"

	# Build RyukGram.bundle with renamed frameworks for cyan injection.
	log "Building ${BUNDLE_NAME}"
	build_bundle "$BUNDLE_PATH"

	if [ -d "$BUNDLE_PATH" ]; then
		cyan_files="$cyan_files $BUNDLE_PATH"
	fi

	cyan_files="$(printf "%s" "$cyan_files" | xargs)"

	log "Creating the TIPA file"

	rm -f "$out_ipa" "$out_tipa"

	local dup_name_args=()
	[ -n "$dup_name" ] && dup_name_args=(-n "$dup_name")

	cyan -i "${PACKAGES_DIR}/${ipa_file}" \
		-o "$out_ipa" \
		-f $cyan_files \
		-c "$compression" \
		-m 15.0 \
		-du \
		${dup_name_args[@]+"${dup_name_args[@]}"}

	postprocess_ipa_bundle "$out_ipa" "$compression" "trollstore"

	mv "$out_ipa" "$out_tipa"

	log "Done!"
	echo
	echo "TIPA at: $(pwd)/$out_tipa"
}

# Build TrollFools zip — dylib + RyukGram.bundle + FFmpegKit frameworks at zip
# root. TrollFools LC-injects each top-level dylib and copies top-level
# .framework dirs into the target app's Frameworks/. No cyan or IPA packaging.
build_trollfools() {
	local stage
	local stage_bundle
	local out_zip="${PACKAGES_DIR}/${APP_NAME}_trollfools_${TWEAK_VERSION}_IG${IG_VER}.zip"

	clean_build
	ensure_packages_dir

	log "Building ${APP_NAME} tweak for TrollFools"

	make_final ""

	stage="$(mktemp -d)"

	cp "$TWEAK_DYLIB" "$stage/${APP_NAME}.dylib"

	stage_bundle="$stage/${BUNDLE_NAME}"
	mkdir -p "$stage_bundle"
	copy_localization_into_bundle "$stage_bundle"
	copy_bundle_assets "$stage_bundle"

	if [ -d "modules/ffmpegkit/ffmpegkit.framework" ]; then
		log "Staging FFmpegKit at zip root"
		patch_ffmpegkit_frameworks "$stage" ryg
	else
		warn "FFmpegKit not found — zip built without FFmpegKit."
	fi

	# Ship unsigned — TrollFools signs each Mach-O on inject. Pre-signing makes
	# it skip them as "already signed" → AMFI rejects on some devices → crash.

	# Bundle resources must be world-readable on device.
	chmod -R a+rX "$stage"

	rm -f "$out_zip"

	(
		cd "$stage"
		zip -qr -9 "$OLDPWD/$out_zip" .
	)

	rm -rf "$stage"

	log "Done!"
	echo
	echo "TrollFools zip at: $(pwd)/$out_zip"
}

usage() {
	echo '+-----------------------+'
	echo '| RyukGram Build Script |'
	echo '+-----------------------+'
	echo
	echo "Usage: $0 <dylib/sideload/noplugins/trollstore/trollfools/rootless/rootful/roothide> [option]"
	echo
	echo 'Commands:'
	echo '  dylib                 Build the dylib only for Feather/manual injection'
	echo '  dylib --fast          Build dylib without cleaning'
	echo '  sideload              Build a patched IPA, requires cyan + decrypted IPA'
	echo '  sideload --buildonly  Compile only, do not create IPA'
	echo '  sideload --dev        Build an uncompressed dogfood IPA with the integrated runtime browser'
	echo '  sideload --name [name]  Rename the app on the home screen (also works with noplugins/trollstore)'
	echo '  noplugins             Like sideload, but strips app extensions; compatibility remains integrated'
	echo '                        works with any sideloader (SideStore / AltStore / Feather)'
	echo '  noplugins --dup [id]  No-plugins dup build for coexist install next to stock IG'
	echo '  noplugins --dup [id] --name [name]  ...and set the home-screen name (spaces ok)'
	echo '  trollstore            Build a .tipa for TrollStore, requires cyan + decrypted IPA'
	echo '  trollfools            Build a TrollFools zip (dylib + bundle + frameworks, no IPA)'
	echo '  rootless              Build a rootless .deb package with FFmpegKit'
	echo '  rootful               Build a rootful .deb package with FFmpegKit'
	echo '  roothide              Build a roothide .deb package with FFmpegKit'
	echo
	echo 'Duplicate (--dup) notes:'
	echo '  id resolves:   CLI arg > RG_DUP_ID env > com.ryuk.ryukgram'
	echo '  name resolves: --name arg > RG_DUP_NAME env > RyukGram (spaces ok)'
	echo '  cyan re-prefixes nested appex ids; output goes to *-dup.ipa'
	echo
	exit 1
}

main() {
	ensure_theos

	local command="${1:-}"
	local option="${2:-}"

	case "$command" in
		dylib)
			build_dylib "${@:2}"
			;;
		sideload)
			build_sideload "sideload" "${@:2}"
			;;
		noplugins|sidestore)
			build_sideload "noplugins" "${@:2}"
			;;
		trollstore)
			build_trollstore "${@:2}"
			;;
		trollfools)
			build_trollfools
			;;
		rootless)
			build_deb "rootless"
			;;
		rootful)
			build_deb "rootful"
			;;
		roothide)
			build_deb "roothide"
			;;
		*)
			usage
			;;
	esac
}

main "$@"

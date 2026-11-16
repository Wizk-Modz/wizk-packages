TERMUX_PKG_HOMEPAGE=https://github.com/Hope2333/opencode-termux
TERMUX_PKG_DESCRIPTION="AI coding agent built for the terminal (native bionic build)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="Hope2333(幽零小喵) <u0catmiao@proton.me>"
TERMUX_PKG_VERSION="2.0.31"
# The v2 runtime is compiled on an aarch64 bionic toolchain (android-bun 1.4.0 +
# bionic libopentui), which the x86_64 build container cannot execute. Consume
# the artifact published by that pipeline instead of rebuilding it here.
#
# 2.2.5 is deliberately skipped: its release artifact predates the Android
# tagged-pointer FFI fix and the TUI dies with "Pointer exceeds safe integer
# range" on Android 11+ (issues #43/#45/#46). 2.0.31 is the newest published
# artifact whose TUI starts on Android 11+.
TERMUX_PKG_SRCURL="https://github.com/Hope2333/opencode-termux/releases/download/Push261105/opencode_${TERMUX_PKG_VERSION}_aarch64.deb"
TERMUX_PKG_SHA256=9dd31aa2765968bc5240e86befe46348239a2f2363980d1dd0d401031adf9df2
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686, x86_64"
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_CONFLICTS="opencode-wrapper"
TERMUX_PKG_REPLACES="opencode1-wrapper-standalone"
# The payload is a Bun standalone executable; stripping or running the ELF
# cleaner would corrupt the embedded .bun module graph.
TERMUX_PKG_NO_STRIP=true
TERMUX_PKG_NO_ELF_CLEANER=true

termux_step_post_get_source() {
	local deb="$TERMUX_PKG_CACHEDIR/$(basename "$TERMUX_PKG_SRCURL")"
	termux_download "$TERMUX_PKG_SRCURL" "$deb" "$TERMUX_PKG_SHA256"
	cp "$TERMUX_PKG_BUILDER_DIR/LICENSE" "$TERMUX_PKG_SRCDIR/LICENSE"
}

termux_step_make_install() {
	local deb="$TERMUX_PKG_CACHEDIR/$(basename "$TERMUX_PKG_SRCURL")"
	local unpack_dir="$TERMUX_PKG_TMPDIR/opencode-deb"
	local payload="$unpack_dir/data/data/com.termux/files/usr"

	rm -rf "$unpack_dir"
	mkdir -p "$unpack_dir"
	dpkg-deb -x "$deb" "$unpack_dir"

	install -Dm755 "$payload/bin/opencode" "$TERMUX_PREFIX/bin/opencode"
	install -Dm644 "$payload/lib/opencode/libopencode-crhandler.so" \
		"$TERMUX_PREFIX/lib/opencode/libopencode-crhandler.so"
}

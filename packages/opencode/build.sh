TERMUX_PKG_HOMEPAGE=https://github.com/Hope2333/opencode-termux
TERMUX_PKG_DESCRIPTION="AI coding agent built for the terminal (native bionic build)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="Hope2333(幽零小喵) <u0catmiao@proton.me>"
TERMUX_PKG_VERSION="2.2.5"
# The v2 runtime is compiled on an aarch64 bionic toolchain (android-bun 1.4.0 +
# bionic libopentui), which the x86_64 build container cannot execute. Consume
# the artifact published by that pipeline instead of rebuilding it here.
TERMUX_PKG_SRCURL="https://github.com/Hope2333/opencode-termux/releases/download/Push261103/opencode_${TERMUX_PKG_VERSION}_aarch64.deb"
TERMUX_PKG_SHA256=1fa4f9c85bef93bf1d345aa15b4427d18eceaecc7b188e658051da9e2bd8b843
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

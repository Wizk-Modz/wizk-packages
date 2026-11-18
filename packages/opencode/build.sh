TERMUX_PKG_HOMEPAGE=https://opencode.ai
TERMUX_PKG_DESCRIPTION="The open source AI coding agent"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="Gouranga Das Samrat <gouranga.das.khulna@gmail.com>"
# opencode and opentui; post_get_source fails if upstream pins differ.
TERMUX_PKG_VERSION=(
	"2.3.0"
	"0.8.4"
	"0.4.11"
)
TERMUX_PKG_SRCURL=(
	"https://github.com/anomalyco/opencode/archive/refs/tags/v${TERMUX_PKG_VERSION[0]}.tar.gz"
	"https://github.com/anomalyco/opentui/archive/refs/tags/v${TERMUX_PKG_VERSION[1]}.tar.gz"
	"https://github.com/sursaone/bun-pty/archive/refs/tags/v${TERMUX_PKG_VERSION[2]}.tar.gz"
)
TERMUX_PKG_SHA256=(
	48b0ab7c4732d693c59e0ad7d73656a2965b2def78cef3c6319e444b7e6c0300
	12aa2672332980ef641f74d1c763f8cf5c5684290a00b4a7298e75d71cfb78ad
	07ff88c9ee96019dd1691e9ede485e35221c036e599545075587cb85537157b2
)
TERMUX_PKG_AUTO_UPDATE=true

TERMUX_PKG_DEPENDS="bun, libc++, ripgrep"
TERMUX_PKG_RECOMMENDS="git"
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_HAS_DEBUG=false
TERMUX_PKG_ON_DEVICE_BUILD_NOT_SUPPORTED=true

# Verifies dependency version pin in package file.
__check_pin() {
	local file="$1" pattern="$2" expected="$3" actual
	actual="$(grep -m1 -oP "$pattern" "$file")"
	[[ "$actual" == "$expected" ]] ||
		termux_error_exit "$file pins '$actual', build.sh has '$expected'"
}

# Applies unified diff to secondary source directory once.
__apply_diff() {
	local dir="$1" diff="$2"
	[[ -d "$dir" ]] || termux_error_exit "$dir not found"
	[[ -f "$dir/.termux-patched" ]] && return
	patch -p1 -d "$dir" -i "$TERMUX_PKG_BUILDER_DIR/$diff"
	touch "$dir/.termux-patched"
}

termux_step_post_get_source() {
	__check_pin package.json '^\s+"@opentui/core": "\K[0-9.]+' "${TERMUX_PKG_VERSION[1]}"
	__check_pin packages/core/package.json '"bun-pty": "\K[0-9.]+' "${TERMUX_PKG_VERSION[2]}"

	__apply_diff "$TERMUX_PKG_SRCDIR/opentui-${TERMUX_PKG_VERSION[1]}" opentui-android-build.diff
	__apply_diff "$TERMUX_PKG_SRCDIR/bun-pty-${TERMUX_PKG_VERSION[2]}" bun-pty-portable-pty-0.9.diff

	local opentui="$TERMUX_PKG_SRCDIR/opentui-${TERMUX_PKG_VERSION[1]}/packages/native/src"
	install -m0644 "$TERMUX_PKG_BUILDER_DIR/opentui-tlsdesc-shim.c" "$opentui/tlsdesc-shim.c"
	mkdir -p "$opentui/bionic-include-next"
	install -m0644 "$TERMUX_PKG_BUILDER_DIR/opentui-bionic-limits.h" "$opentui/bionic-include-next/limits.h"
}

termux_step_pre_configure() {
	case "$TERMUX_ARCH" in
		aarch64) _ARCH=arm64; _PTY_LIB=librust_pty_arm64.so ;;
		x86_64)
			_ARCH=x64
			_PTY_LIB=librust_pty.so
			# x86_64 emits ELF TLS (__tls_get_addr, API 30+) in the Zig native.
			TERMUX_PKG_UNDEF_SYMBOLS_FILES="./lib/opencode/libopentui-*.so"
			;;
		*) termux_error_exit "Unsupported architecture: $TERMUX_ARCH" ;;
	esac
	_INSTALL_DIR="$TERMUX_PREFIX/lib/opencode"
}

# Builds bionic libopentui.so with Zig compiler and NDK libc.
__build_libopentui() {
	export TERMUX_ZIG_VERSION=0.17.0
	termux_setup_zig

	local src="$TERMUX_PKG_SRCDIR/opentui-${TERMUX_PKG_VERSION[1]}/packages/native"
	local sysroot="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
	local libdir="$sysroot/usr/lib/$TERMUX_HOST_PLATFORM/$TERMUX_PKG_API_LEVEL"
	local arch_inc="$sysroot/usr/include/$TERMUX_HOST_PLATFORM"
	local sys_inc="$sysroot/usr/include"
	local libc_file="$TERMUX_PKG_TMPDIR/android-libc.txt"

	[[ -d "$libdir" ]] || termux_error_exit "No NDK libc directory at $libdir"

	cat > "$libc_file" <<-EOF
		include_dir=$arch_inc
		sys_include_dir=$sys_inc
		crt_dir=$libdir
		msvc_lib_dir=
		kernel32_lib_dir=
		gcc_dir=$libdir
		darwin_sdk_dir=
	EOF

	cd "$src"
	sh scripts/prepare-zig-deps.sh
	BIONIC_ARCH_INCLUDE="$arch_inc" BIONIC_SYS_INCLUDE="$sys_inc" BIONIC_LIB_DIR="$libdir" \
		zig build \
		-Dlibrary-target="$TERMUX_HOST_PLATFORM.$TERMUX_PKG_API_LEVEL" \
		-Doptimize=ReleaseSafe \
		--libc "$libc_file"

	_LIBOPENTUI="$(find "$src/lib" -name libopentui.so | head -n 1)"
	[[ -n "$_LIBOPENTUI" ]] || termux_error_exit "libopentui.so was not built"
	${STRIP:-llvm-strip} --strip-unneeded "$_LIBOPENTUI"
}

# Builds bionic librust_pty.so with Cargo for bun-pty.
__build_rust_natives() {
	termux_setup_rust

	local bun_pty="$TERMUX_PKG_SRCDIR/bun-pty-${TERMUX_PKG_VERSION[2]}/rust-pty"

	(
		export ANDROID_NDK_HOME="$NDK"
		cd "$bun_pty"
		cargo build --jobs "$TERMUX_PKG_MAKE_PROCESSES" --release --target "$CARGO_TARGET_NAME"
	)

	_RUST_PTY_LIB="$bun_pty/target/$CARGO_TARGET_NAME/release/librust_pty.so"
	[[ -f "$_RUST_PTY_LIB" ]] || termux_error_exit "librust_pty.so was not built"
	${STRIP:-llvm-strip} --strip-unneeded "$_RUST_PTY_LIB"
}

# Replaces bundled node_modules binaries with bionic builds.
__swap_natives() {
	local slot
	local -a tui_slots=()
	mapfile -t tui_slots < <(find node_modules/.bun -path '*/@opentui/core-*/*' \( -name 'libopentui.so' -o -name 'libopentui.dylib' -o -name 'opentui.dll' \))
	[[ "${#tui_slots[@]}" -gt 0 ]] || termux_error_exit "No opentui native slots found in node_modules"
	for slot in "${tui_slots[@]}"; do
		case "$slot" in
			*/core-linux-*) cp -f "$_LIBOPENTUI" "$slot" ;;
			*) : > "$slot" ;;
		esac
	done

	local -a pty_slots=()
	mapfile -t pty_slots < <(find node_modules/.bun -path '*/bun-pty/rust-pty/target/release/*' -type f)
	[[ "${#pty_slots[@]}" -gt 0 ]] || termux_error_exit "No bun-pty native slots found in node_modules"
	for slot in "${pty_slots[@]}"; do
		case "$slot" in
			*.so) cp -f "$_RUST_PTY_LIB" "$slot" ;;
			*.dll|*.dylib) : > "$slot" ;;
		esac
	done
}

# Patches OpenTUI loader and FFI shim for Android runtime.
__patch_opentui_runtime() {
	local chunk
	chunk="$(find node_modules/.bun -name 'chunk-bun-*.js' -exec grep -l 'function getCurrentNodeAssetTarget' {} +)"
	[[ "$(printf '%s\n' "$chunk" | wc -l)" == 1 && -n "$chunk" ]] ||
		termux_error_exit "Expected exactly one opentui loader chunk, got: $chunk"
	patch -p1 "$chunk" -i "$TERMUX_PKG_BUILDER_DIR/opentui-loader-android.diff"

	# Tagged BigInt pointers must survive the Bun FFI shim.
	python3 "$TERMUX_PKG_BUILDER_DIR/opentui-ffi-android.py" "$TERMUX_PKG_SRCDIR"
}

termux_step_make() {
	__build_libopentui
	__build_rust_natives

	cd "$TERMUX_PKG_SRCDIR"
	termux_setup_bun

	export OPENCODE_VERSION="${TERMUX_PKG_VERSION[0]}"
	export OPENCODE_CHANNEL="latest"
	export OPENCODE_INSTALL_DIR="$_INSTALL_DIR"

	bun install \
		--filter '@opencode/cli' --filter '@opencode/app' \
		--os='*' --cpu='*' --libc='*' --ignore-scripts

	__swap_natives

	__patch_opentui_runtime

	cd packages/cli
	OPENCODE_TARGET="linux-${_ARCH}-android" \
		bun run script/build.ts --skip-install
}

termux_step_make_install() {
	local out="$TERMUX_PKG_SRCDIR/packages/cli/dist/cli-linux-${_ARCH}-android/lib"
	[[ -f "$out/index.js" ]] || termux_error_exit "Bundle not found in $out"

	rm -rf "$_INSTALL_DIR"
	install -d "$_INSTALL_DIR"
	cp -a "$out/." "$_INSTALL_DIR/"
	install -m0755 "$_RUST_PTY_LIB" "$_INSTALL_DIR/$_PTY_LIB"
	: > "$_INSTALL_DIR/bunfig.toml"

	# Empty bunfig and --no-env-file keep the project's bunfig/.env out of the CLI.
	cat > "$TERMUX_PREFIX/bin/opencode" <<-SCRIPT
		#!$TERMUX_PREFIX/bin/sh
		export OPENCODE_DISABLE_AUTOUPDATE=1
		export BUN_PTY_LIB="$_INSTALL_DIR/$_PTY_LIB"
		export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
		exec "$TERMUX_PREFIX/bin/bun" --smol --no-install --no-env-file --no-warnings \\
			--config="$_INSTALL_DIR/bunfig.toml" \\
			--user-agent="opencode/latest/${TERMUX_PKG_VERSION[0]}/cli" \\
			"$_INSTALL_DIR/index.js" "\$@"
	SCRIPT
	chmod 0755 "$TERMUX_PREFIX/bin/opencode"
}

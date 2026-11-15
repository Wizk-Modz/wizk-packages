TERMUX_PKG_HOMEPAGE=https://termux.dev/
TERMUX_PKG_DESCRIPTION="Basic system tools for Termux"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="1.48.0"
TERMUX_PKG_SRCURL=https://github.com/termux/termux-tools/archive/refs/tags/v1.45.0.tar.gz
TERMUX_PKG_SHA256=1ae29b1b875d95cc626dae323b45a2ace759969862d96094b2fa6d13bffe20d2
TERMUX_PKG_ESSENTIAL=true
#TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_TAG_TYPE="newest-tag"
TERMUX_PKG_BREAKS="termux-keyring (<< 1.9)"
TERMUX_PKG_CONFLICTS="procps (<< 3.3.15-2)"
TERMUX_PKG_SUGGESTS="termux-api"

# Some of these packages are not dependencies and used only to ensure
# that core packages are installed after upgrading (we removed busybox
# from essentials).
TERMUX_PKG_DEPENDS="bzip2, coreutils, curl, dash, diffutils, findutils, gawk, grep, gzip, less, procps, psmisc, sed, tar, termux-am (>= 0.8.0), termux-am-socket (>= 1.5.0), termux-core, termux-exec, util-linux, xz-utils, dialog"

# Optional packages that are distributed as part of bootstrap archives.
TERMUX_PKG_RECOMMENDS="ed, dos2unix, inetutils, net-tools, patch, unzip"

termux_step_post_get_source() {
	# Thay motd mặc định của Termux bằng motd của WizkTerm.
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/motd.sh.in" \
		"$TERMUX_PKG_SRCDIR/motds/motd.sh.in"
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/motds-Makefile.am" \
		"$TERMUX_PKG_SRCDIR/motds/Makefile.am"

	# Trỏ mirror mặc định về repo WizkTerm, bỏ toàn bộ mirror của Termux.
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/mirrors-default" \
		"$TERMUX_PKG_SRCDIR/mirrors/default"
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/mirrors-Makefile.am" \
		"$TERMUX_PKG_SRCDIR/mirrors/Makefile.am"
	rm -rf "$TERMUX_PKG_SRCDIR/mirrors/asia" \
		"$TERMUX_PKG_SRCDIR/mirrors/china" \
		"$TERMUX_PKG_SRCDIR/mirrors/chinese_mainland" \
		"$TERMUX_PKG_SRCDIR/mirrors/europe" \
		"$TERMUX_PKG_SRCDIR/mirrors/north_america" \
		"$TERMUX_PKG_SRCDIR/mirrors/oceania" \
		"$TERMUX_PKG_SRCDIR/mirrors/russia" \
		"$TERMUX_PKG_SRCDIR/mirrors/south_america"

	# pkg tìm mirror trong các thư mục group đã bị xoá, bỏ phần đó đi để
	# tránh lỗi find, chỉ dùng mirror default.
	sed -i '/mirrors+=(.*find.*MIRROR_BASE_DIR/d' \
		"$TERMUX_PKG_SRCDIR/scripts/pkg.in"

	# Không còn mirror group để chọn, thay termux-change-repo bằng thông báo.
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/termux-change-repo.in" \
		"$TERMUX_PKG_SRCDIR/scripts/termux-change-repo.in"
}

termux_step_pre_configure() {
	# configure.ac mặc định app package là com.termux và prefix là
	# /data/data/com.termux/files/usr nếu các biến này chưa được export,
	# khiến các script (pkg, termux-setup-storage, ...) hardcode sai prefix.
	export TERMUX_APP_PACKAGE
	export TERMUX_BASE_DIR
	export TERMUX_PREFIX
	autoreconf -vfi
}

termux_step_post_make_install() {
	TERMUX_PKG_CONFFILES="$(cat "$TERMUX_PKG_BUILDDIR/conffiles")"
}

termux_step_create_debscripts() {
	cat <<- EOF > ./preinst
	$(cat "$TERMUX_PKG_BUILDDIR/preinst")
	EOF
}

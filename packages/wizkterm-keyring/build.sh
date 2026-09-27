TERMUX_PKG_HOMEPAGE=https://github.com/Wizk-Modz/wizk-packages
TERMUX_PKG_DESCRIPTION="GPG public keys for the WizkTerm repositories"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@Wizk-Modz"
TERMUX_PKG_VERSION=1.0
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_ESSENTIAL=true

termux_step_make_install() {
	local GPG_SHARE_DIR="$TERMUX_PREFIX/share/wizkterm-keyring"

	rm -rf "$GPG_SHARE_DIR"
	mkdir -p "$GPG_SHARE_DIR"

	install -Dm600 "$TERMUX_PKG_BUILDER_DIR/wizkterm.gpg" "$GPG_SHARE_DIR"

	# Tạo symlink để apt và pacman tin cậy khóa này.
	for GPG_DIR in "$TERMUX_PREFIX/etc/apt/trusted.gpg.d" "$TERMUX_PREFIX/share/pacman/keyrings"; do
		mkdir -p "$GPG_DIR"
		ln -sf "$GPG_SHARE_DIR/wizkterm.gpg" "$GPG_DIR/wizkterm.gpg"
	done
}

TERMUX_PKG_HOMEPAGE=https://salsa.debian.org/debian/reprepro
TERMUX_PKG_DESCRIPTION="Debian package repository producer"
TERMUX_PKG_LICENSE="GPL-2.0-only"
TERMUX_PKG_MAINTAINER="@Wizk-Modz"
TERMUX_PKG_VERSION=5.4.2
TERMUX_PKG_SRCURL=https://snapshot.debian.org/archive/debian/20230303T030402Z/pool/main/r/reprepro/reprepro_${TERMUX_PKG_VERSION}.orig.tar.xz
TERMUX_PKG_SHA256=8955df21b88cf0d48387c7e259ba83b743cce18eef6465f9a6f0174f2861c4fb
TERMUX_PKG_DEPENDS="gpgme, libarchive, libbz2, libc++, libdb, libgpg-error, liblzma, zlib"
# Giải nén .gz/.bz2/.lzma/.xz dùng thư viện (libbz2, liblzma). Riêng .zst
# (control.tar.zst của Debian/Ubuntu hiện đại) cần unzstd bên ngoài.
TERMUX_PKG_RECOMMENDS="zstd"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--with-libbz2
--with-liblzma
--with-libgpgme
--with-libarchive
"

# Các patch dưới đây để build được bằng Clang/bionic:
# - reprepro-index-rindex.patch: index()/rindex() là hàm chỉ có trên glibc
# - reprepro-libdb18.patch: mở rộng kiểm tra DB_VERSION_MAJOR cho libdb 18
# - reprepro-sourceextraction-nested-functions.patch: bỏ nested function
termux_step_pre_configure() {
	./autogen.sh
}

termux_step_post_make_install() {
	install -Dm644 "$TERMUX_PKG_SRCDIR/docs/reprepro.bash_completion" \
		"$TERMUX_PREFIX/share/bash-completion/completions/reprepro"
	install -Dm644 "$TERMUX_PKG_SRCDIR/docs/reprepro.zsh_completion" \
		"$TERMUX_PREFIX/share/zsh/site-functions/_reprepro"
}

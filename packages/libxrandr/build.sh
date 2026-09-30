# X11 package
TERMUX_PKG_HOMEPAGE=https://xorg.freedesktop.org/
TERMUX_PKG_DESCRIPTION="X11 RandR extension library"
TERMUX_PKG_LICENSE="HPND"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="1.5.5"
TERMUX_PKG_SRCURL=https://xorg.freedesktop.org/releases/individual/lib/libXrandr-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=72b922c2e765434e9e9f0960148070bd4504b288263e2868a4ccce1b7cf2767a
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libx11, libxext, libxrender"
# libXrender.la (trong gói libxrender) trỏ tới libX11.la, mà libX11.la lại
# trỏ tiếp tới libxcb.la và libXdmcp.la. Các file .la này chỉ nằm trong gói
# -static tương ứng, nên cần khai báo chúng để libtool tìm thấy khi link.
TERMUX_PKG_BUILD_DEPENDS="libx11-static, libxcb-static, libxdmcp-static, xorgproto, xorg-util-macros"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--enable-malloc0returnsnull"

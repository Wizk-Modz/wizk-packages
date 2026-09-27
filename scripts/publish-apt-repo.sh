#!/usr/bin/env bash
# Dựng APT repository tĩnh (dists/Release/Packages + pool) trong thư mục site
# để publish lên GitHub Pages.
#
# Usage: ./scripts/publish-apt-repo.sh <site_dir> <debs_dir>
#
# <site_dir>  : thư mục gốc của site (checkout branch gh-pages)
# <debs_dir>  : thư mục chứa các *.deb mới build và built_<repo>_packages.txt
#
# Biến môi trường:
#   GPG_KEY_FPR : fingerprint khóa GPG dùng để ký (mặc định lấy khóa bí mật đầu tiên)
#   TERMUX_ARCH : kiến trúc build (mặc định aarch64)

set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <site_dir> <debs_dir>" 1>&2
	exit 1
fi

TERMUX_SCRIPTDIR=$(realpath "$(dirname "$(realpath "$0")")/..")
SITE_DIR=$(realpath -m "$1")
DEBS_DIR=$(realpath -m "$2")
REPO_JSON="$TERMUX_SCRIPTDIR/repo.json"
TERMUX_ARCH="${TERMUX_ARCH:-aarch64}"

# Kiểm tra các công cụ cần thiết đã có trong PATH.
for cmd in dpkg-scanpackages apt-ftparchive gpg jq gzip; do
	if [ -z "$(command -v "$cmd")" ]; then
		echo "ERROR: công cụ '$cmd' không có trong PATH." 1>&2
		exit 1
	fi
done

if [[ ! -f "$REPO_JSON" ]]; then
	echo "ERROR: không tìm thấy '$REPO_JSON'." 1>&2
	exit 1
fi

if [[ ! -d "$DEBS_DIR" ]]; then
	echo "ERROR: không tìm thấy thư mục debs '$DEBS_DIR'." 1>&2
	exit 1
fi

# Lấy fingerprint khóa GPG bí mật dùng để ký repository.
GPG_KEY_FPR="${GPG_KEY_FPR:-}"
if [[ -z "$GPG_KEY_FPR" ]]; then
	GPG_KEY_FPR=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
fi
if [[ -z "$GPG_KEY_FPR" ]]; then
	echo "ERROR: không tìm thấy khóa GPG bí mật để ký repository." 1>&2
	exit 1
fi

# Kiểm tra tên package có thuộc repo <repo_path> hay không.
# Nhận cả package chính (có thư mục build.sh) lẫn package con như
# `<pkg>-static` hoặc subpackage (`<pkg>` khai báo trong
# `<parent>/<pkg>.subpackage.sh`).
package_belongs_to_repo() {
	local repo_path="$1" pkg="$2" dir base

	# Gói chính: có thư mục chứa build.sh.
	[[ -f "$TERMUX_SCRIPTDIR/$repo_path/$pkg/build.sh" ]] && return 0

	# Gói -static hoặc hậu tố khác: thử bỏ hậu tố sau dấu '-' cuối cùng.
	dir="$TERMUX_SCRIPTDIR/$repo_path/${pkg%-*}"
	[[ -f "$dir/build.sh" ]] && return 0

	# Subpackage: tìm file <pkg>.subpackage.sh trong repo.
	shopt -s nullglob
	for base in "$TERMUX_SCRIPTDIR/$repo_path"/*/"$pkg".subpackage.sh; do
		shopt -u nullglob
		return 0
	done
	shopt -u nullglob

	return 1
}

# Chép các *.deb mới của một repo vào pool/ của repo đó trong site.
# Lấy tên package từ chính file .deb (field Package) để chép được cả các
# gói phụ thuộc, không chỉ các gói chính trong built_<repo>_packages.txt.
# Chỉ nhận các package thuộc <repo_path> để không chép nhầm gói của repo khác.
# Xóa các *.deb cũ cùng tên package trước, để pool chỉ giữ một phiên bản
# cho mỗi package: get_hash_from_file.py chỉ lấy entry đầu tiên trong
# Packages nên nhiều phiên bản sẽ khiến nó chọn sai Filename.
copy_new_debs() {
	local repo_path="$1" repo_name="$2" component="$3"
	local deb pkg dest letter old count=0

	shopt -s nullglob
	for deb in "$DEBS_DIR"/*.deb; do
		pkg=$(dpkg-deb -f "$deb" Package) || {
			echo "ERROR: không đọc được tên package từ '$deb'." 1>&2
			exit 1
		}
		[[ -n "$pkg" ]] || {
			echo "ERROR: package rỗng trong '$deb'." 1>&2
			exit 1
		}

		# Bỏ qua gói không thuộc repo này.
		package_belongs_to_repo "$repo_path" "$pkg" || continue

		letter="${pkg:0:1}"
		dest="$SITE_DIR/apt/$repo_name/pool/$component/$letter/$pkg"
		mkdir -p "$dest"

		# Xóa phiên bản cũ của package này (nếu có).
		for old in "$dest/${pkg}"_*.deb; do
			rm -f "$old"
		done

		cp -f "$deb" "$dest/"
		count=$((count + 1))
	done
	shopt -u nullglob

	echo "Đã chép $count file .deb vào pool của '$repo_name'"
}

# Sinh Packages (cho mọi kiến trúc trong pool) và gzip lại cho một repo.
generate_packages() {
	local repo_dir="$1" distribution="$2" component="$3"
	local out_dir="$repo_dir/dists/$distribution/$component/binary-$TERMUX_ARCH"

	mkdir -p "$out_dir"
	# dpkg-scanpackages yêu cầu thư mục pool phải tồn tại, kể cả khi rỗng.
	mkdir -p "$repo_dir/pool/$component"

	# Không truyền --arch để Packages chứa cả gói 'all' lẫn gói theo kiến trúc,
	# giống cách aptly trộn 'all' vào từng kiến trúc.
	(
		cd "$repo_dir"
		dpkg-scanpackages --multiversion pool /dev/null > "$out_dir/Packages"
	)
	gzip -9kf "$out_dir/Packages"
	bzip2 -9kf "$out_dir/Packages"

	# Contents dùng cho `apt-file`, kiểm tra xung đột file và cho
	# command-not-found sinh bảng lệnh. apt-ftparchive căn cột bằng tab
	# giữa path và tên package, nhưng generate-db.js của command-not-found
	# chỉ split bằng một dấu cách, nên phải chuẩn hoá về một dấu cách.
	local contents_dir="$repo_dir/dists/$distribution"
	(
		cd "$repo_dir"
		apt-ftparchive contents pool | sed -E 's/[[:space:]]+/ /' \
			> "$contents_dir/Contents-$TERMUX_ARCH"
	)
	gzip -9kf "$contents_dir/Contents-$TERMUX_ARCH"
}

# Sinh file Release rồi ký GPG (InRelease và Release.gpg) cho một repo.
generate_release() {
	local repo_dir="$1" distribution="$2" component="$3" origin="$4" label="$5"
	local dist_dir="$repo_dir/dists/$distribution"
	local release_tmp="$dist_dir/Release.tmp"

	# Sinh Release ra file tạm ngoài dist_dir để tránh tự tham chiếu checksum.
	apt-ftparchive \
		-o "APT::FTPArchive::Release::Origin=$origin" \
		-o "APT::FTPArchive::Release::Label=$label" \
		-o "APT::FTPArchive::Release::Suite=$distribution" \
		-o "APT::FTPArchive::Release::Codename=$distribution" \
		-o "APT::FTPArchive::Release::Architectures=$TERMUX_ARCH" \
		-o "APT::FTPArchive::Release::Components=$component" \
		-o "APT::FTPArchive::Release::Description=$label APT repository" \
		release "$dist_dir" > "$release_tmp"
	mv -f "$release_tmp" "$dist_dir/Release"

	gpg --batch --yes --local-user "$GPG_KEY_FPR" \
		--clearsign -o "$dist_dir/InRelease" "$dist_dir/Release"
	gpg --batch --yes --local-user "$GPG_KEY_FPR" \
		--detach-sign --armor -o "$dist_dir/Release.gpg" "$dist_dir/Release"

	# Xác minh chữ ký vừa tạo, fail rõ ràng nếu sai.
	gpg --verify "$dist_dir/InRelease" > /dev/null 2>&1 || {
		echo "ERROR: InRelease không verify được cho '$distribution'." 1>&2
		exit 1
	}
	echo "Đã ký và verify '$distribution'"
}

main() {
	mkdir -p "$SITE_DIR"

	local repo_path repo_name distribution component
	for repo_path in $(jq --raw-output 'del(.pkg_format) | keys | .[]' "$REPO_JSON"); do
		repo_name=$(jq --raw-output ".\"$repo_path\".name" "$REPO_JSON")
		distribution=$(jq --raw-output ".\"$repo_path\".distribution" "$REPO_JSON")
		component=$(jq --raw-output ".\"$repo_path\".component" "$REPO_JSON")

		echo "==> Xử lý repo '$repo_name' (distribution=$distribution, component=$component)"

		copy_new_debs "$repo_path" "$repo_name" "$component"
		generate_packages "$SITE_DIR/apt/$repo_name" "$distribution" "$component"
		generate_release "$SITE_DIR/apt/$repo_name" "$distribution" "$component" \
			"WizkTerm" "$repo_name"
	done

	# Publish public key để client tin cậy.
	if [[ -f "$TERMUX_SCRIPTDIR/apt-keys/wizkterm.gpg" ]]; then
		mkdir -p "$SITE_DIR/keys"
		cp -f "$TERMUX_SCRIPTDIR/apt-keys/wizkterm.gpg" "$SITE_DIR/keys/wizkterm.gpg"
		echo "Đã publish public key tại keys/wizkterm.gpg"
	fi
}

main

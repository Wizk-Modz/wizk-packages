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

# Chép các *.deb mới của một repo vào pool/ của repo đó trong site.
# Xóa các *.deb cũ cùng tên package trước, để pool chỉ giữ một phiên bản
# cho mỗi package: get_hash_from_file.py chỉ lấy entry đầu tiên trong
# Packages nên nhiều phiên bản sẽ khiến nó chọn sai Filename.
copy_new_debs() {
	local repo_name="$1" component="$2" built_file="$DEBS_DIR/built_${repo_name}_packages.txt"
	local pkg deb dest letter old

	[[ -f "$built_file" ]] || return 0

	while IFS= read -r pkg; do
		[[ -n "$pkg" ]] || continue
		letter="${pkg:0:1}"
		dest="$SITE_DIR/apt/$repo_name/pool/$component/$letter/$pkg"
		mkdir -p "$dest"

		# Xóa phiên bản cũ của package này (nếu có).
		shopt -s nullglob
		for old in "$dest/${pkg}"_*.deb; do
			rm -f "$old"
		done
		shopt -u nullglob

		shopt -s nullglob
		for deb in "$DEBS_DIR/${pkg}"_*.deb; do
			cp -f "$deb" "$dest/"
			echo "Đã chép $(basename "$deb") vào pool của '$repo_name'"
		done
		shopt -u nullglob
	done < "$built_file"
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

	# Contents dùng cho `apt-file` và cho việc kiểm tra xung đột file.
	local contents_dir="$repo_dir/dists/$distribution"
	(
		cd "$repo_dir"
		apt-ftparchive contents pool > "$contents_dir/Contents-$TERMUX_ARCH"
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

		copy_new_debs "$repo_name" "$component"
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

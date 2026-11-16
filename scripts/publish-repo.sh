#!/usr/bin/env bash
# Dựng lại APT repository trên Cloudflare R2: mirror bucket về máy, thêm .deb mới,
# sinh metadata, ký Release rồi đồng bộ ngược lại bucket.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEB_DIR=""
WORK_DIR=""
BUCKET="${R2_BUCKET:-wizk-repos}"
ARCH="aarch64"
GPG_KEY_ID="${GPG_KEY_ID:-}"
PUBLIC_URL="${R2_PUBLIC_URL:-https://wizk-repos.chuong.qzz.io}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Cách dùng: publish-repo.sh --debs <thư mục .deb> --work <thư mục làm việc> [tuỳ chọn]

  --debs     Thư mục chứa các file .deb và các file built_<repo>_packages.txt
  --work     Thư mục nháp, sẽ được mirror từ bucket rồi đồng bộ ngược lại
  --bucket   Tên bucket R2 (mặc định $R2_BUCKET hoặc wizk-repos)
  --arch     Kiến trúc cần publish (mặc định aarch64)
  --url      URL công khai của bucket, dùng cho trang index
  --dry-run  Chỉ dựng metadata ở địa phương, không upload

Biến môi trường:
  R2_ACCESS_KEY_ID      Access key ID của R2
  R2_SECRET_ACCESS_KEY  Secret access key của R2
  R2_ENDPOINT           Endpoint S3 của R2, dạng https://<account>.r2.cloudflarestorage.com
  GPG_PASSPHRASE        Passphrase của khoá ký, dùng với --pinentry-mode loopback
  GPG_KEY_ID            Key ID dùng để ký Release
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --debs) DEB_DIR="${2:-}"; shift 2 ;;
    --work) WORK_DIR="${2:-}"; shift 2 ;;
    --bucket) BUCKET="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --url) PUBLIC_URL="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Tham số không hợp lệ: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$DEB_DIR" ] || [ -z "$WORK_DIR" ]; then
  echo "Thiếu tham số bắt buộc" >&2
  usage >&2
  exit 2
fi

if [ ! -d "$DEB_DIR" ]; then
  echo "Không tìm thấy thư mục .deb: $DEB_DIR" >&2
  exit 1
fi

for tool in dpkg-deb apt-ftparchive gpg jq gzip bzip2; do
  command -v "$tool" >/dev/null || { echo "Thiếu công cụ: $tool" >&2; exit 1; }
done

# Cấu hình rclone qua biến môi trường để không cần file cấu hình trên runner
setup_rclone_remote() {
  for var in R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ENDPOINT; do
    if [ -z "${!var:-}" ]; then
      echo "Thiếu biến môi trường $var" >&2
      exit 1
    fi
  done

  export RCLONE_CONFIG_R2_TYPE=s3
  export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
  export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
  export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
  export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
  export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
}

# Lấy distribution và component của một repo từ repo.json
read_repo_meta() {
  local repo_name="$1"
  jq --raw-output --arg n "$repo_name" \
    'del(.pkg_format) | to_entries[] | select(.value.name == $n) | "\(.value.distribution) \(.value.component)"' \
    "$REPO_ROOT/repo.json"
}

repo_names() {
  jq --raw-output 'del(.pkg_format) | .[].name' "$REPO_ROOT/repo.json"
}

# Chép một file .deb vào pool của repo đích theo layout pool/<component>/<chữ cái>/<gói>/
copy_deb_to_pool() {
  local deb="$1" repo_name="$2" component="$3"
  local pkg_name pool_dir

  pkg_name="$(dpkg-deb -f "$deb" Package)"

  # Ký tự đầu của tên gói làm thư mục phân vùng; ký tự lạ gom vào "misc"
  local bucket="${pkg_name:0:1}"
  [[ "$bucket" =~ ^[a-z0-9]$ ]] || bucket="misc"

  pool_dir="$WORK_DIR/$repo_name/pool/$component/$bucket/$pkg_name"
  mkdir -p "$pool_dir"

  # Bỏ bản cũ của cùng gói để pool không phình dần qua từng lần publish
  find "$pool_dir" -maxdepth 1 -name '*.deb' ! -name "$(basename "$deb")" -delete

  cp -f "$deb" "$pool_dir/"
  pkg_count=$((pkg_count + 1))
}

pkg_count=0

if [ "$DRY_RUN" -eq 0 ]; then
  setup_rclone_remote

  echo "==> Mirror bucket r2:$BUCKET về $WORK_DIR"
  mkdir -p "$WORK_DIR"
  # Bucket là nguồn duy nhất: kéo toàn bộ pool + metadata về trước khi sửa
  rclone sync "r2:$BUCKET" "$WORK_DIR" --checksum --fast-list --stats-one-line
else
  echo "==> Chế độ dry-run: bỏ qua mirror bucket"
  fi

echo "==> Sao chép .deb vào pool"
for repo_name in $(repo_names); do
  read -r distribution component <<<"$(read_repo_meta "$repo_name")"

  manifest="$DEB_DIR/built_${repo_name}_packages.txt"
  if [ ! -f "$manifest" ]; then
    echo "    Bỏ qua $repo_name: không có $(basename "$manifest")"
    continue
  fi

  repo_added=0
  while read -r pkg; do
    [ -n "$pkg" ] || continue

    # Mỗi gói có thể sinh ra gói chính và gói -static
    for pattern in "${pkg}_*.deb" "${pkg}-static_*.deb"; do
      for deb in "$DEB_DIR"/$pattern; do
        [ -f "$deb" ] || continue

        deb_arch="$(dpkg-deb -f "$deb" Architecture)"
        # Gói platform-independent khai báo Architecture: all nhưng vẫn thuộc
        # binary-$ARCH của repo, nên phải nhận cả hai giá trị.
        if [ "$deb_arch" != "$ARCH" ] && [ "$deb_arch" != "all" ]; then
          echo "    Bỏ qua $(basename "$deb"): kiến trúc $deb_arch khác $ARCH"
          continue
        fi

        copy_deb_to_pool "$deb" "$repo_name" "$component"
        repo_added=$((repo_added + 1))
      done
    done
  done < "$manifest"

  echo "    $repo_name: $repo_added gói"
done

if [ "$pkg_count" -eq 0 ]; then
  echo "Không có gói nào được thêm vào pool" >&2
  exit 1
fi

echo "==> Sinh metadata"
for repo_name in $(repo_names); do
  read -r distribution component <<<"$(read_repo_meta "$repo_name")"
  repo_dir="$WORK_DIR/$repo_name"

  if [ ! -d "$repo_dir/pool/$component" ]; then
    echo "    Bỏ qua $repo_name: chưa có pool"
    continue
  fi

  binary_dir="$repo_dir/dists/$distribution/$component/binary-$ARCH"
  mkdir -p "$binary_dir"

  # apt-ftparchive tính Filename theo đường dẫn truyền vào, nên phải đứng ở
  # gốc repo để ra dạng "pool/<component>/..."
  (
    cd "$repo_dir"
    apt-ftparchive packages "pool/$component" > "dists/$distribution/$component/binary-$ARCH/Packages"
    apt-ftparchive contents "pool/$component" > "dists/$distribution/Contents-$ARCH"
  )

  # Mọi .deb trong pool phải xuất hiện trong Packages; thiếu nghĩa là file hỏng,
  # khi đó metadata sẽ sai và phải dừng ngay.
  pool_deb_count="$(find "$repo_dir/pool/$component" -name '*.deb' | wc -l | tr -d ' ')"
  indexed_count="$(grep -c '^Package: ' "$binary_dir/Packages" || true)"
  if [ "$pool_deb_count" != "$indexed_count" ]; then
    echo "LỖI: $repo_name có $pool_deb_count file .deb nhưng Packages chỉ có $indexed_count mục" >&2
    echo "      Kiểm tra lại tính toàn vẹn của file .deb" >&2
    exit 1
  fi

  gzip -9 -c "$binary_dir/Packages" > "$binary_dir/Packages.gz"
  bzip2 -9 -c "$binary_dir/Packages" > "$binary_dir/Packages.bz2"
  gzip -9 -c "$repo_dir/dists/$distribution/Contents-$ARCH" > "$repo_dir/dists/$distribution/Contents-$ARCH.gz"

  dist_dir="$repo_dir/dists/$distribution"
  (
    cd "$dist_dir"
    apt-ftparchive \
      -o APT::FTPArchive::Release::Origin="WizkTerm" \
      -o APT::FTPArchive::Release::Label="$repo_name" \
      -o APT::FTPArchive::Release::Suite="$distribution" \
      -o APT::FTPArchive::Release::Codename="$distribution" \
      -o APT::FTPArchive::Release::Architectures="$ARCH" \
      -o APT::FTPArchive::Release::Components="$component" \
      -o APT::FTPArchive::Release::Description="$repo_name APT repository" \
      release . > Release.new
    mv Release.new Release
  )

  # Ký Release thành InRelease và Release.gpg
  sign_args=(--batch --yes --armor --detach-sign --output "$dist_dir/Release.gpg")
  clear_args=(--batch --yes --clearsign --output "$dist_dir/InRelease")
  if [ -n "${GPG_PASSPHRASE:-}" ]; then
    sign_args+=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE")
    clear_args+=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE")
  fi
  if [ -n "$GPG_KEY_ID" ]; then
    sign_args+=(--local-user "$GPG_KEY_ID")
    clear_args+=(--local-user "$GPG_KEY_ID")
  fi

  gpg "${sign_args[@]}" "$dist_dir/Release"
  gpg "${clear_args[@]}" "$dist_dir/Release"

  echo "    OK: $repo_name ($distribution/$component)"
done

# Khoá công khai phải nằm trong bucket để client tải về cài đặt
mkdir -p "$WORK_DIR/keys"
cp -f "$REPO_ROOT/apt-keys/wizkterm.gpg" "$WORK_DIR/keys/wizkterm.gpg"

echo "==> Dựng trang index"
bash "$SCRIPT_DIR/apt-repo-index.sh" "$WORK_DIR" "$PUBLIC_URL" "$ARCH"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "==> Dry-run: đã dựng $WORK_DIR, không upload"
  du -sh "$WORK_DIR"
  exit 0
fi

# Kiểm tra chữ ký và checksum trước khi đẩy lên bucket để bản hỏng không lên sóng
echo "==> Xác thực repository"
bash "$SCRIPT_DIR/verify-apt-repo.sh" "$WORK_DIR"

echo "==> Đồng bộ ngược lên r2:$BUCKET"
# sync xoá luôn file cũ không còn trong thư mục làm việc, nhờ vậy pool
# không giữ lại bản .deb đã bị thay thế.
rclone sync "$WORK_DIR" "r2:$BUCKET" --checksum --fast-list --stats-one-line

echo "==> Hoàn tất, đã thêm $pkg_count gói"

#!/usr/bin/env bash
# Chuyển APT repository từ GitLab Pages sang Cloudflare R2: clone repo cũ, bỏ
# tiền tố apt/ trong layout rồi đồng bộ lên bucket. Metadata giữ nguyên chữ ký.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_REPO="${SRC_REPO:-https://gitlab.com/wizkmodz/wizk-apt-repo.git}"
SRC_BRANCH="${SRC_BRANCH:-gh-pages}"
SRC_DIR="${SRC_DIR:-}"
WORK_DIR="${WORK_DIR:-r2-repo}"
BUCKET="${R2_BUCKET:-wizk-repos}"
PUBLIC_URL="${R2_PUBLIC_URL:-https://wizk-repos.chuong.qzz.io}"
ARCH="${ARCH:-aarch64}"
SKIP_UPLOAD=0

usage() {
  cat <<'USAGE'
Cách dùng: migrate-gitlab-to-r2.sh [tuỳ chọn]

  --src-dir  Dùng checkout có sẵn thay vì clone lại (dùng trong CI)
  --work     Thư mục làm việc (mặc định r2-repo)
  --bucket   Tên bucket R2 (mặc định $R2_BUCKET hoặc wizk-repos)
  --url      URL công khai của bucket
  --no-upload  Chỉ dựng thư mục đích, không đẩy lên bucket

Biến môi trường:
  R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT  Thông tin đăng nhập R2
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --src-dir) SRC_DIR="${2:-}"; shift 2 ;;
    --work) WORK_DIR="${2:-}"; shift 2 ;;
    --bucket) BUCKET="${2:-}"; shift 2 ;;
    --url) PUBLIC_URL="${2:-}"; shift 2 ;;
    --no-upload) SKIP_UPLOAD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Tham số không hợp lệ: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in git git-lfs jq; do
  command -v "$tool" >/dev/null || { echo "Thiếu công cụ: $tool" >&2; exit 1; }
done

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

if [ -n "$SRC_DIR" ]; then
  # CI đã checkout sẵn và pull LFS trước khi gọi script
  echo "==> Dùng checkout có sẵn: $SRC_DIR"
  SRC_TREE="$SRC_DIR"
else
  echo "==> Clone $SRC_REPO ($SRC_BRANCH)"
  git clone --quiet --branch "$SRC_BRANCH" --depth 1 "$SRC_REPO" "$WORK_DIR/src"

  echo "==> Lấy nội dung Git LFS"
  (
    cd "$WORK_DIR/src"
    git lfs install --local >/dev/null
    git lfs pull
  )
  SRC_TREE="$WORK_DIR/src"
fi

echo "==> Chuyển layout, bỏ tiền tố apt/"
mkdir -p "$WORK_DIR/out"
for repo_name in $(jq --raw-output 'del(.pkg_format) | .[].name' "$REPO_ROOT/repo.json"); do
  if [ ! -d "$SRC_TREE/apt/$repo_name" ]; then
    echo "    Bỏ qua $repo_name: không có trong repo cũ"
    continue
  fi
  mv "$SRC_TREE/apt/$repo_name" "$WORK_DIR/out/$repo_name"
  n="$(find "$WORK_DIR/out/$repo_name" -name '*.deb' | wc -l | tr -d ' ')"
  echo "    $repo_name: $n gói"
done

mkdir -p "$WORK_DIR/out/keys"
cp -f "$REPO_ROOT/apt-keys/wizkterm.gpg" "$WORK_DIR/out/keys/wizkterm.gpg"

echo "==> Dựng trang index"
bash "$SCRIPT_DIR/apt-repo-index.sh" "$WORK_DIR/out" "$PUBLIC_URL" "$ARCH"

echo "==> Xác thực repository"
bash "$SCRIPT_DIR/verify-apt-repo.sh" "$WORK_DIR/out"

du -sh "$WORK_DIR/out"

if [ "$SKIP_UPLOAD" -eq 1 ]; then
  echo "==> Bỏ qua upload theo yêu cầu"
  exit 0
fi

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

# sync sẽ xoá mọi object không có trong thư mục nguồn. Sau khi migration hoàn
# tất, bucket đã là nguồn dữ liệu chính nên chạy lại sẽ xoá gói publish về sau.
if [ "${ALLOW_OVERWRITE:-0}" != "1" ]; then
  existing="$(rclone ls "r2:$BUCKET" | wc -l | tr -d ' ')"
  if [ "$existing" -gt 0 ]; then
    echo "Bucket r2:$BUCKET đã có $existing object." >&2
    echo "Script này ghi đè toàn bộ bucket, chỉ dùng cho lần migration đầu tiên." >&2
    echo "Đặt ALLOW_OVERWRITE=1 nếu thực sự muốn xoá và thay bằng dữ liệu GitLab." >&2
    exit 1
  fi
fi

echo "==> Đồng bộ lên r2:$BUCKET"
rclone sync "$WORK_DIR/out" "r2:$BUCKET" --checksum --fast-list --stats-one-line --transfers 16

echo "==> Kiểm tra lại từ bucket"
rclone ls "r2:$BUCKET" | wc -l

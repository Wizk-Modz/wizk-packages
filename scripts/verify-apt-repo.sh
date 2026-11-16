#!/usr/bin/env bash
# Kiểm tra tính toàn vẹn APT repository trong thư mục làm việc trước khi upload lên R2.
set -euo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "Cách dùng: verify-apt-repo.sh <thư mục làm việc chứa các repo>" >&2
  exit 2
fi

cd "$ROOT"

errors=0

fail() {
  echo "LỖI: $*" >&2
  errors=$((errors + 1))
}

echo "==> Kiểm tra chữ ký InRelease"
gnupg_home="$(mktemp -d)"
trap 'rm -rf "$gnupg_home"' EXIT
chmod 700 "$gnupg_home"
if ! GNUPGHOME="$gnupg_home" gpg --batch --quiet --import keys/wizkterm.gpg 2>/dev/null; then
  echo "LỖI: không import được keys/wizkterm.gpg" >&2
  exit 1
fi

while IFS= read -r -d '' inrelease; do
  dist_dir="$(dirname "$inrelease")"
  if ! GNUPGHOME="$gnupg_home" gpg --batch --quiet --verify "$inrelease" 2>/dev/null; then
    fail "chữ ký không hợp lệ: ${inrelease#"$ROOT"/}"
    continue
  fi
  # Nội dung đã ký phải trùng khớp file Release đi kèm
  body="$gnupg_home/inrelease-body"
  GNUPGHOME="$gnupg_home" gpg --batch --quiet --decrypt "$inrelease" 2>/dev/null > "$body"
  if ! diff -q "$dist_dir/Release" "$body" >/dev/null; then
    fail "nội dung InRelease khác Release: ${dist_dir#"$ROOT"/}"
    continue
  fi
  echo "    OK: ${inrelease#"$ROOT"/}"
done < <(find . -path ./keys -prune -o -name InRelease -print0)

# Release.gpg là chữ ký tách rời, dùng khi client không đọc InRelease
while IFS= read -r -d '' signature; do
  dist_dir="$(dirname "$signature")"
  if ! GNUPGHOME="$gnupg_home" gpg --batch --quiet --verify "$signature" "$dist_dir/Release" 2>/dev/null; then
    fail "chữ ký Release.gpg không hợp lệ: ${signature#"$ROOT"/}"
    continue
  fi
  echo "    OK: ${signature#"$ROOT"/}"
done < <(find . -path ./keys -prune -o -name Release.gpg -print0)

echo "==> Kiểm tra checksum trong các file Release"
while IFS= read -r -d '' release; do
  dist_dir="$(dirname "$release")"
  while read -r hash size path; do
    [ -n "${path:-}" ] || continue
    # Release tự liệt kê chính nó nên hash luôn lệch; apt bỏ qua entry này
    case "$path" in Release|InRelease) continue ;; esac
    target="$dist_dir/$path"
    if [ ! -f "$target" ]; then
      fail "Release thiếu file: ${release#"$ROOT"/} -> $path"
      continue
    fi
    actual_size="$(wc -c < "$target" | tr -d ' ')"
    if [ "$actual_size" != "$size" ]; then
      fail "Sai kích thước: $path (Release=$size, thực tế=$actual_size)"
    fi
    actual_hash="$(sha256sum "$target" | cut -d' ' -f1)"
    if [ "$actual_hash" != "$hash" ]; then
      fail "Sai SHA256: $path"
    fi
  done < <(awk '/^SHA256:/{f=1;next} /^[A-Za-z0-9]+:/{f=0} f && NF==3 {print $1, $2, $3}' "$release")
  echo "    OK: ${release#"$ROOT"/}"
done < <(find . -path ./keys -prune -o -name Release -not -name 'InRelease' -print0)

echo "==> Kiểm tra gói trong Packages khớp với pool"
checked=0
while IFS= read -r -d '' packages; do
  # Thư mục gốc của repo là phần trước "dists/"
  repo_root="${packages%%/dists/*}"
  pkg_count=0
  while IFS='|' read -r name version filename size sha256; do
    [ -n "${filename:-}" ] || continue
    deb="$repo_root/$filename"
    if [ ! -f "$deb" ]; then
      fail "$name: thiếu file $filename"
      continue
    fi
    actual_size="$(wc -c < "$deb" | tr -d ' ')"
    if [ "$actual_size" != "$size" ]; then
      fail "$name $version: sai kích thước ($size != $actual_size)"
      continue
    fi
    actual_hash="$(sha256sum "$deb" | cut -d' ' -f1)"
    if [ "$actual_hash" != "$sha256" ]; then
      fail "$name $version: sai SHA256"
      continue
    fi
    checked=$((checked + 1))
    pkg_count=$((pkg_count + 1))
  done < <(awk '
    function flush() {
      if (pkg != "") print pkg "|" ver "|" file "|" sz "|" sum
      pkg = ""; ver = ""; file = ""; sz = ""; sum = ""
    }
    /^Package: /   { flush(); pkg = substr($0, 10) }
    /^Version: /   { ver = substr($0, 10) }
    /^Filename: /  { file = substr($0, 11) }
    /^Size: /      { sz = substr($0, 7) }
    /^SHA256: /    { sum = substr($0, 9) }
    END { flush() }
  ' "$packages")
  if [ "$pkg_count" -eq 0 ]; then
    echo "    CẢNH BÁO: ${packages#"$ROOT"/} không có gói nào"
  else
    echo "    OK: ${packages#"$ROOT"/} ($pkg_count gói)"
  fi
done < <(find . -path ./keys -prune -o -name Packages -print0)

echo "==> Đã xác thực $checked gói"

if [ "$errors" -gt 0 ]; then
  echo "==> THẤT BẠI: $errors lỗi" >&2
  exit 1
fi

echo "==> Tất cả kiểm tra đều đạt"

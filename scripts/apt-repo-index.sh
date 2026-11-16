#!/usr/bin/env bash
# Sinh trang index.html giới thiệu các kho gói APT vào thư mục đích.
set -euo pipefail

OUT_DIR="${1:-}"
PUBLIC_URL="${2:-}"
ARCH="${3:-aarch64}"

if [ -z "$OUT_DIR" ] || [ -z "$PUBLIC_URL" ]; then
  echo "Cách dùng: apt-repo-index.sh <thư mục đích> <url công khai> [kiến trúc]" >&2
  exit 2
fi

PUBLIC_URL="${PUBLIC_URL%/}"
mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WizkTerm APT Repository</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: ui-monospace, monospace; max-width: 46rem; margin: 3rem auto; padding: 0 1rem; line-height: 1.6; }
  code, pre { background: rgba(127,127,127,.15); border-radius: 4px; }
  code { padding: .15em .35em; }
  pre { padding: .9rem; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; }
  th, td { text-align: left; padding: .35rem .6rem; border-bottom: 1px solid rgba(127,127,127,.3); }
</style>
</head>
<body>
<h1>WizkTerm APT Repository</h1>
<p>Kho gói APT cho Termux trên kiến trúc <code>$ARCH</code>.</p>

<h2>Kho gói</h2>
<table>
  <tr><th>Kho</th><th>Suite</th><th>Component</th></tr>
  <tr><td><code>wizkterm-main</code></td><td>stable</td><td>main</td></tr>
  <tr><td><code>wizkterm-root</code></td><td>root</td><td>stable</td></tr>
  <tr><td><code>wizkterm-x11</code></td><td>x11</td><td>main</td></tr>
</table>

<h2>Cài đặt</h2>
<pre>mkdir -p "\$PREFIX/etc/apt/sources.list.d" "\$PREFIX/etc/apt/trusted.gpg.d"

curl -fsSL $PUBLIC_URL/keys/wizkterm.gpg \\
  -o "\$PREFIX/etc/apt/trusted.gpg.d/wizkterm.gpg"

echo "deb [signed-by=\$PREFIX/etc/apt/trusted.gpg.d/wizkterm.gpg] $PUBLIC_URL/wizkterm-main stable main" \\
  > "\$PREFIX/etc/apt/sources.list.d/wizkterm-main.list"

pkg update</pre>

<p>Key <code>wizkterm.gpg</code> đã ở dạng binary keyring nên tải thẳng về <code>trusted.gpg.d</code>, không cần <code>gpg --dearmor</code>.</p>

<p>Đổi <code>wizkterm-main</code> thành <code>wizkterm-root</code> hoặc <code>wizkterm-x11</code> cho các kho còn lại.</p>
</body>
</html>
HTML

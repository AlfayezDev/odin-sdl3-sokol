#!/bin/sh
# Fetch a prebuilt sokol-shdc for this platform into bin/<os>-<arch>/.
# Override SOKOL_SHDC_URL for a pinned build.
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux)
    platform="linux-x86_64"
    url="${SOKOL_SHDC_URL:-https://raw.githubusercontent.com/floooh/sokol-tools-bin/master/bin/linux/sokol-shdc}"
    ;;
  Darwin)
    case "$arch" in
      arm64) platform="macos-arm64" ;;
      *)     platform="macos-x86_64" ;;
    esac
    url="${SOKOL_SHDC_URL:-https://raw.githubusercontent.com/floooh/sokol-tools-bin/master/bin/macos/sokol-shdc}"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    platform="windows-x86_64"
    url="${SOKOL_SHDC_URL:-https://raw.githubusercontent.com/floooh/sokol-tools-bin/master/bin/win32/sokol-shdc.exe}"
    ;;
  *)
    echo "unsupported platform: $os" >&2
    exit 1
    ;;
esac

dir="$root/bin/$platform"
dest="$dir/sokol-shdc"
[ "$platform" = "windows-x86_64" ] && dest="$dest.exe"

if [ -x "$dest" ] || [ -f "$dest" ]; then
  echo "sokol-shdc already available at $dest"
  exit 0
fi

mkdir -p "$dir"
echo "fetching sokol-shdc from $url"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "$dest" "$url"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$dest" "$url"
else
  echo "curl or wget is required" >&2
  exit 1
fi
chmod +x "$dest"
echo "wrote $dest"

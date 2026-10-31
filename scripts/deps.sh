#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p deps
if [[ ! -d deps/SDL3-3.2.28 ]]; then
  curl -fL https://github.com/libsdl-org/SDL/releases/download/release-3.2.28/SDL3-3.2.28.tar.gz -o deps/SDL3.tar.gz
  python3 - <<'PY'
import hashlib
assert hashlib.sha256(open('deps/SDL3.tar.gz','rb').read()).hexdigest() == '1330671214d146f8aeb1ed399fc3e081873cdb38b5189d1f8bb6ab15bbc04211', 'SDL checksum mismatch'
PY
  tar xf deps/SDL3.tar.gz -C deps
fi

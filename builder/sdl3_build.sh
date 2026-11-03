#!/bin/sh
# Compiles the vendored SDL3 sources into a static lib (desktop) or a
# shared libSDL3.so (android). All parameters come from the environment:
#   ROOT         repo root
#   OUT_DIR      output dir (obj/, SDL_build_config.h, libSDL3.a|so)
#   CC           compiler command (may include target/sysroot flags)
#   SDL_DIR      path to the SDL3 source tree (relative to ROOT)
#   SOURCES_FILE file with source GLOBS (one per line, relative to ROOT)
#   SHARED       1 = link libSDL3.so, otherwise archive libSDL3.a
#   LINK_LIBS    extra libraries for the shared link
set -e
: "${ROOT:?}" "${OUT_DIR:?}" "${CC:?}" "${SDL_DIR:?}" "${SOURCES_FILE:?}"
CONFIG_DIR="$OUT_DIR"
mkdir -p "$OUT_DIR/obj_sdl"
rm -f "$OUT_DIR"/obj_sdl/*.o

: > "$OUT_DIR/objs.txt"
while read -r pattern; do
  for f in "$ROOT"/$pattern; do
    [ -f "$f" ] || continue
    o="$OUT_DIR/obj_sdl/$(printf '%s' "${f#"$ROOT/$SDL_DIR/"}" | tr / _).o"
    echo "$o $f" >> "$OUT_DIR/objs.txt"
  done
done < "$SOURCES_FILE"

export CC CONFIG_DIR SDL_DIR
cat "$OUT_DIR/objs.txt" | xargs -P "$(nproc 2>/dev/null || sysctl -n hw.ncpu)" -L1 sh -c '
  set -e
  case "$2" in *.cpp) lang=c++ ;; *) lang=c ;; esac
  $CC -x "$lang" -c -O2 -fPIC -I"$CONFIG_DIR" -I"$SDL_DIR/include" -I"$SDL_DIR/src" "$2" -o "$1"
' _

rm -f "$OUT_DIR/libSDL3.a"
ar rcs "$OUT_DIR/libSDL3.a" "$OUT_DIR"/obj_sdl/*.o
echo "wrote $OUT_DIR/libSDL3.a"

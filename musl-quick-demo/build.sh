#!/usr/bin/env bash
# build.sh - build micro/micro_cpp/timer for glibc-dynamic and musl-static.
# required env:
#   TIZEN_CC   = Tizen cross gcc/clang        (e.g. .../arm-linux-gnueabihf-gcc or tizen clang)
#   MUSL_CC    = musl cross gcc               (e.g. .../arm-linux-musleabihf-gcc)
# optional:
#   TIZEN_CXX / MUSL_CXX  (skip C++ probe if unset)
#   FLAGS_OVERRIDE        (defaults to armv7 hard-float -O2)
set -euo pipefail
cd "$(dirname "$0")"
: "${TIZEN_CC:?set TIZEN_CC}"; : "${MUSL_CC:?set MUSL_CC}"
FLAGS="${FLAGS_OVERRIDE:--O2 -Wall -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard}"
mkdir -p out
log(){ echo "[build] $*"; }

log "glibc dynamic"
$TIZEN_CC $FLAGS -o out/micro.glibc micro.c -lpthread
log "musl static"
$MUSL_CC $FLAGS -static -o out/micro.musl micro.c -lpthread
log "timer (glibc, measurement instrument)"
$TIZEN_CC $FLAGS -o out/timer timer.c

if [[ -n "${TIZEN_CXX:-}" && -n "${MUSL_CXX:-}" ]]; then
  log "C++ probes"
  $TIZEN_CXX $FLAGS -o out/cpp.glibc micro_cpp.cpp -lpthread
  $MUSL_CXX  $FLAGS -static -static-libgcc -static-libstdc++ -o out/cpp.musl micro_cpp.cpp -lpthread
else
  log "TIZEN_CXX/MUSL_CXX unset -> skipping C++ probes (report will mark NOT_RUN)"
fi

for f in out/micro.glibc out/micro.musl out/cpp.glibc out/cpp.musl; do
  [[ -f $f ]] || continue
  cp -f "$f" "$f.stripped"
  "${STRIP_TOOL:-strip}" "$f.stripped" 2>/dev/null || {
    # try per-toolchain strip
    case "$f" in
      *musl*) "${MUSL_CC%gcc}strip" "$f.stripped" ;;
      *)      "${TIZEN_CC%gcc}strip" "$f.stripped" 2>/dev/null || "${TIZEN_CC%clang}strip" "$f.stripped" ;;
    esac
  }
done

log "sizes:"
ls -l out/ | awk '{print "[size] "$9" "$5}'
( cd out && sha256sum * ) | tee out/artifacts.sha256
log "done. record toolchain versions:"
$TIZEN_CC --version | head -1
$MUSL_CC --version | head -1

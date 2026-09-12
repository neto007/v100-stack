#!/usr/bin/env bash
# audio.cpp para sm_70. Saida: dist/audiocpp-sm70/
# Nota medida: recompilar de sm_86/89 para sm_70 rendeu apenas 1,3% de latencia
# (o cuBLAS ja fazia o trabalho pesado no caminho otimo). O ganho real e de
# tamanho -- 1,27 GB -> 83 MB -- e correcao tecnica.
source "$(dirname "$0")/../scripts/common.sh"
SRC=${SRC:-$PWD/.src/audio.cpp}
OUT=${OUT:-$PWD/dist/audiocpp-sm70}
REF=${AUDIOCPP_REF:-main}
JOBS=${JOBS:-$(nproc)}
export PATH="${CUDA_HOME}/bin:$PATH"

[ -d "$SRC" ] || git clone --depth 1 -b "$REF" "$AUDIOCPP_REPO" "$SRC"

# gcc-13: o upstream compila com ele; gcc-14 tambem funciona mas nao foi testado.
CC=$(command -v gcc-13 || command -v gcc)
CXX=$(command -v g++-13 || command -v g++)

cmake -S "$SRC" -B "$SRC/build/sm70" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_CUDA_COMPILER="${CUDA_HOME}/bin/nvcc" \
  -DCMAKE_CUDA_ARCHITECTURES=${SM_ARCH} \
  -DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets" \
  -DGGML_CUDA=ON -DGGML_CUDA_FA=ON -DGGML_CUDA_F16=ON -DGGML_CUDA_GRAPHS=ON \
  -DGGML_NATIVE=OFF \
  -DENGINE_ENABLE_CUDA=ON -DENGINE_BUILD_TESTS=OFF -DENGINE_BUILD_EXAMPLES=OFF
cmake --build "$SRC/build/sm70" --config Release -j "$JOBS"

rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$SRC/build/sm70/bin/." "$OUT/"
( cd "$SRC" && git rev-parse --short HEAD ) > "$OUT/COMMIT"
archs=$("${CUDA_HOME}/bin/cuobjdump" --list-elf "$OUT/audiocpp_cli" 2>/dev/null \
        | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' ')
[ "$(echo $archs)" = "sm_${SM_ARCH}" ] || die "arquiteturas erradas no build: '$archs'"
ok "audio.cpp pronto em $OUT (arquiteturas: $archs)"

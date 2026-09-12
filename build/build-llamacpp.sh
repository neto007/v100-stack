#!/usr/bin/env bash
# llama.cpp para sm_70. Saida: dist/llamacpp-sm70/
source "$(dirname "$0")/../scripts/common.sh"
SRC=${SRC:-$PWD/.src/llama.cpp}
OUT=${OUT:-$PWD/dist/llamacpp-sm70}
REF=${LLAMACPP_REF:-master}
JOBS=${JOBS:-$(nproc)}
export PATH="${CUDA_HOME}/bin:$PATH"

[ -d "$SRC" ] || git clone --depth 1 -b "$REF" "$LLAMACPP_REPO" "$SRC"

# GGML_CUDA_NCCL=ON e o que faz o NVLink valer: sem NCCL o -sm tensor cai para
# um all-reduce interno. Precisa de libnccl-dev no sistema.
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=${SM_ARCH} \
  -DGGML_CUDA_F16=ON \
  -DGGML_CUDA_FA=ON \
  -DGGML_CUDA_NCCL=ON \
  -DGGML_NATIVE=OFF \
  -DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets" \
  -DCMAKE_CUDA_COMPILER="${CUDA_HOME}/bin/nvcc"
cmake --build "$SRC/build" --config Release -j "$JOBS"

rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$SRC/build/bin/." "$OUT/"
( cd "$SRC" && git rev-parse --short HEAD ) > "$OUT/COMMIT"

# O binario tem que conter APENAS sm_70: qualquer outra arquitetura indica
# que o CMAKE_CUDA_ARCHITECTURES nao pegou.
archs=$("${CUDA_HOME}/bin/cuobjdump" --list-elf "$OUT"/libggml-cuda.so* 2>/dev/null \
        | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' ')
[ "$(echo $archs)" = "sm_${SM_ARCH}" ] || die "arquiteturas erradas no build: '$archs'"
ok "llama.cpp pronto em $OUT (arquiteturas: $archs)"

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

HERE="$(cd "$(dirname "$0")/.." && pwd)"
FRESH_CLONE=0
if [ ! -d "$SRC" ]; then git clone --depth 1 -b "$REF" "$AUDIOCPP_REPO" "$SRC"; FRESH_CLONE=1; fi

# Patch da aba "Podcast" (documento -> roteiro via LLM -> TTS multi-voz ->
# episodio). So aplica em clone novo: reaplicar num checkout ja patcheado
# falharia. Ver docs/podcast.md.
PATCH="$HERE/patches/audiocpp-podcast-tab.patch"
if [ "$FRESH_CLONE" = 1 ] && [ -f "$PATCH" ]; then
  log "aplicando patch da aba Podcast"
  ( cd "$SRC" && git apply "$PATCH" ) || die "patch da aba Podcast nao aplicou -- upstream pode ter mudado, ver docs/podcast.md"
fi

# Frontend (SvelteKit): o CMake abaixo le webui/native/dist/index.html como
# arquivo unico e o embute no binario. Sem Node/npm instalados, ele cai num
# placeholder de erro em vez de falhar a build -- por isso o teste explicito.
if [ -d "$SRC/webui/native" ]; then
  if ! command -v node >/dev/null; then
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    [ -s "$NVM_DIR/nvm.sh" ] || { log "instalando nvm + Node LTS"
      curl -so- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash; }
    \. "$NVM_DIR/nvm.sh"
    command -v node >/dev/null || nvm install --lts >/dev/null
  fi
  log "compilando a WebUI (npm run build)"
  ( export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    cd "$SRC/webui/native" && npm install --no-audit --no-fund && npm run build ) \
    || die "build da WebUI falhou"
  [ -s "$SRC/webui/native/dist/index.html" ] || die "dist/index.html vazio apos o build da WebUI"
  grep -q "Document to podcast" "$SRC/webui/native/dist/index.html" \
    || warn "aba Podcast nao encontrada no dist/index.html -- o patch aplicou mas o build pode ter usado cache antigo"
fi

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
archs=$(cuda_archs "$OUT/audiocpp_cli")
[ "$archs" = "sm_${SM_ARCH}" ] || die "arquiteturas erradas no build: '$archs' (esperado sm_${SM_ARCH})"
ok "audio.cpp pronto em $OUT (arquiteturas: $archs)"

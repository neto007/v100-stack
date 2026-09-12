#!/usr/bin/env bash
# Empacota os binarios compilados LOCALMENTE e sobe numa release existente.
# Use quando o CI nao estiver disponivel, ou para publicar um build seu.
#   ./build/release-local.sh v0.1.0
source "$(dirname "$0")/../scripts/common.sh"
TAG=${1:?uso: $0 <tag>}
REPO=${REPO:-neto007/v100-stack}
DIST=${DIST:-$PWD/dist}
LLAMA_BIN=${LLAMA_BIN:-$HOME/v100-stack/llama.cpp/build/bin}
AUDIO_BIN=${AUDIO_BIN:-$HOME/audio.cpp/build/linux-cuda-sm70/bin}
VENV=${VENV:-$HOME/v100-stack/.venv}
mkdir -p "$DIST"

pack(){ # $1=dir de origem  $2=nome
  [ -d "$1" ] || { warn "pulando $2: $1 nao existe"; return; }
  rm -rf "$DIST/$2"; mkdir -p "$DIST/$2"; cp -a "$1/." "$DIST/$2/"
  tar --zstd -cf "$DIST/$2.tar.zst" -C "$DIST" "$2"
  ok "$2.tar.zst ($(du -h "$DIST/$2.tar.zst" | cut -f1))"
}
pack "$LLAMA_BIN" llamacpp-sm70
pack "$AUDIO_BIN" audiocpp-sm70

# wheel do flash-attn a partir do que ja esta instalado no venv
if [ -d "$VENV" ] && "$VENV/bin/python" -c "import flash_attn_v100" 2>/dev/null; then
  SRC=${FA_SRC:-$HOME/v100-stack/flash-attention-v100}
  [ -d "$SRC" ] && ( cd "$SRC" && TORCH_CUDA_ARCH_LIST=7.0 FA_ALLOW_NO_GPU=1 \
      "$VENV/bin/python" -m pip wheel . --no-deps --no-build-isolation -w "$DIST" >/dev/null 2>&1 ) \
      && ok "wheel do flash-attn gerada" || warn "wheel do flash-attn nao gerada"
fi

( cd "$DIST" && sha256sum *.tar.zst *.whl 2>/dev/null > SHA256SUMS; cat SHA256SUMS )
log "subindo para a release ${TAG}"
gh release upload "$TAG" "$DIST"/*.tar.zst "$DIST"/SHA256SUMS --repo "$REPO" --clobber
ls "$DIST"/*.whl >/dev/null 2>&1 && gh release upload "$TAG" "$DIST"/*.whl --repo "$REPO" --clobber
ok "release ${TAG} atualizada"

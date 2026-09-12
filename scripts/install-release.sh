#!/usr/bin/env bash
# Instala os binarios JA COMPILADOS de uma release. Nao compila nada.
# Uso:  sudo ./scripts/install-release.sh [tag]   (padrao: latest)
source "$(dirname "$0")/common.sh"; need_root
REPO=${REPO:-neto007/v100-stack}
TAG=${1:-latest}
PREFIX=${PREFIX:-/opt/v100-stack}
RUN_USER=${SUDO_USER:-$(logname 2>/dev/null || echo root)}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v gh >/dev/null || die "instale o gh CLI, ou baixe os .tar.zst manualmente"
log "baixando release ${TAG} de ${REPO}"
if [ "$TAG" = latest ]; then gh release download -R "$REPO" -p '*.tar.zst' -D "$TMP" --clobber
else gh release download -R "$REPO" "$TAG" -p '*.tar.zst' -D "$TMP" --clobber; fi

mkdir -p "$PREFIX"
for f in "$TMP"/*.tar.zst; do
  log "extraindo $(basename "$f")"; tar --zstd -xf "$f" -C "$PREFIX"
done
chown -R "$RUN_USER":"$RUN_USER" "$PREFIX"

cat > /etc/profile.d/v100-stack.sh <<PROF
export PATH="${PREFIX}/llamacpp-sm70:${PREFIX}/audiocpp-sm70:\$PATH"
export LD_LIBRARY_PATH="${PREFIX}/llamacpp-sm70:\$LD_LIBRARY_PATH"
PROF
ok "binarios em ${PREFIX}; PATH configurado em /etc/profile.d/v100-stack.sh"
ls -la "$PREFIX"
echo
echo "Proximos passos:"
echo "  source /etc/profile.d/v100-stack.sh"
echo "  ${PREFIX}/llamacpp-sm70/llama-bench -m SEU_MODELO.gguf -ngl 99 -fa on -sm tensor -ts 1/1"
echo "  sudo ./scripts/setup-audio-servers.sh   # se for usar TTS/ASR nas duas placas"

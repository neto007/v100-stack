#!/usr/bin/env bash
# CUDA Toolkit 12.9.1 -- o ultimo que compila offline para sm_70.
# Instala SOMENTE o toolkit: o driver vem do 00-driver.sh (R580 > o 575 embutido).
source "$(dirname "$0")/common.sh"; need_root

WORK=${WORK:-/var/tmp/v100-stack}; mkdir -p "$WORK"
URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VER}/local_installers/${CUDA_RUN}"

if [ -x "${CUDA_HOME}/bin/nvcc" ]; then
  ok "CUDA ja em ${CUDA_HOME} ($(${CUDA_HOME}/bin/nvcc --version | grep -o 'release [0-9.]*'))"
else
  [ -f "$WORK/$CUDA_RUN" ] || { log "baixando CUDA ${CUDA_VER} (~5,9 GB)"; curl -fL -o "$WORK/$CUDA_RUN" "$URL"; }
  log "instalando toolkit em ${CUDA_HOME}"
  sh "$WORK/$CUDA_RUN" --silent --toolkit --override --no-opengl-libs --no-man-page \
     --installpath="${CUDA_HOME}" || die "instalacao do CUDA falhou"
fi
ln -sfn "${CUDA_HOME}" /usr/local/cuda

patch_cuda_glibc

cat > /etc/profile.d/v100-cuda.sh <<PROF
export CUDA_HOME=${CUDA_HOME}
export PATH="\$CUDA_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$CUDA_HOME/lib64:\$LD_LIBRARY_PATH"
PROF
ok "CUDA pronto. Abra um shell novo ou: source /etc/profile.d/v100-cuda.sh"

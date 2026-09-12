#!/usr/bin/env bash
# Instala componentes avulsos do CUDA 12.9 em vez do metapacote cuda-toolkit
# (que puxa ~6 GB de profiler, docs e samples que nao usamos).
# Uso: install-cuda.sh nvcc cudart-dev cublas-dev [cufft-dev curand-dev nvtx]
set -euo pipefail
V=12-9
curl -fsSLO https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb && rm cuda-keyring_1.1-1_all.deb
sudo apt-get update -qq
PKGS=""
for c in "$@"; do PKGS="$PKGS cuda-${c}-${V}"; done
# nomes que fogem do padrao cuda-*
PKGS=${PKGS//cuda-cublas-dev-$V/libcublas-dev-$V}
PKGS=${PKGS//cuda-cufft-dev-$V/libcufft-dev-$V}
PKGS=${PKGS//cuda-curand-dev-$V/libcurand-dev-$V}
echo "instalando:$PKGS"
sudo apt-get install -y -qq $PKGS
sudo ln -sfn /usr/local/cuda-12.9 /usr/local/cuda
/usr/local/cuda/bin/nvcc --version | tail -2
df -h / | tail -1

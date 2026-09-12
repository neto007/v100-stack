#!/usr/bin/env bash
# Versoes fixadas. Volta (sm_70) foi descontinuada: cada teto abaixo e o ultimo
# ponto em que a arquitetura ainda e suportada. Subir qualquer um quebra tudo.
set -euo pipefail

export SM_ARCH=70                       # Tesla V100 = compute capability 7.0
export DRIVER_VER=580.95.05             # R580 e o ultimo ramo com Volta (590 removeu)
export CUDA_VER=12.9.1                  # 13.0 removeu compilacao offline para Volta
export CUDA_RUN=cuda_12.9.1_575.57.08_linux.run
export CUDA_HOME=/usr/local/cuda-12.9
export TORCH_VER=2.10.0                 # 2.11 removeu sm_70 das wheels
export TORCH_INDEX=https://download.pytorch.org/whl/cu129
export PYTHON_VER=3.12                  # wheels dos forks de vLLM sao cp312
export SM_CLOCK=1530                    # teto de clock do SM na V100-SXM2

export TORCH_CUDA_ARCH_LIST="7.0"
export CMAKE_CUDA_ARCHITECTURES=$SM_ARCH

LLAMACPP_REPO=${LLAMACPP_REPO:-https://github.com/ggml-org/llama.cpp.git}
AUDIOCPP_REPO=${AUDIOCPP_REPO:-https://github.com/0xShug0/audio.cpp.git}
FLASHATTN_REPO=${FLASHATTN_REPO:-https://github.com/ai-bond/flash-attention-v100.git}
export LLAMACPP_REPO AUDIOCPP_REPO FLASHATTN_REPO

log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m [OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m [!!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m [XX]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "rode como root (sudo $0)"; }

# glibc >= 2.41 declara as funcoes C23 sinpi/cospi com __THROW; o CUDA <= 12.9
# declara as mesmas sem. Em C++ isso e erro de especificacao de excecao e
# NENHUM arquivo .cu compila -- nem um main() vazio. Idempotente e condicional.
patch_cuda_glibc() {
  local h="${CUDA_HOME}/targets/x86_64-linux/include/crt/math_functions.h"
  [ -f "$h" ] || { warn "header do CUDA nao encontrado em $h"; return 0; }
  if ! grep -qE '^extern .*(sinpi|cospi)f?\(.*\);$' "$h"; then
    ok "header do CUDA ja corrigido (ou versao nao afetada)"; return 0
  fi
  printf 'int main(){return 0;}\n' > /tmp/_glibc_probe.cu
  if "${CUDA_HOME}/bin/nvcc" -arch=sm_${SM_ARCH} -Wno-deprecated-gpu-targets \
       -o /tmp/_glibc_probe /tmp/_glibc_probe.cu 2>/dev/null; then
    ok "nvcc compila sem patch (glibc < 2.41) -- nada a fazer"
    rm -f /tmp/_glibc_probe /tmp/_glibc_probe.cu; return 0
  fi
  log "aplicando patch de compatibilidade glibc 2.41 em crt/math_functions.h"
  cp -n "$h" "${h}.orig"
  sed -i -E 's/^(extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ (double|float) +(sinpi|sinpif|cospi|cospif)\(.*\));$/\1 __THROW;/' "$h"
  "${CUDA_HOME}/bin/nvcc" -arch=sm_${SM_ARCH} -Wno-deprecated-gpu-targets \
      -o /tmp/_glibc_probe /tmp/_glibc_probe.cu \
      || die "patch aplicado mas nvcc ainda falha -- investigue $h"
  rm -f /tmp/_glibc_probe /tmp/_glibc_probe.cu
  ok "patch aplicado; original preservado em ${h}.orig"
}

# Lista as arquiteturas de UM binario. Passar varios arquivos para o cuobjdump
# faz ele imprimir o texto de ajuda -- que contem a lista de TODAS as
# arquiteturas conhecidas e vira falso positivo no grep. Resolve symlink e usa
# exatamente um arquivo.
cuda_archs() {
  local f; f=$(readlink -f "$1") || return 1
  "${CUDA_HOME}/bin/cuobjdump" --list-elf "$f" 2>/dev/null \
    | grep -oE 'sm_[0-9]+' | sort -u -V | tr '\n' ' ' | sed 's/ $//'
}

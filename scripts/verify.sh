#!/usr/bin/env bash
# Verificacao completa do stack. Compara com os valores medidos no hardware
# de referencia (2x Tesla V100-SXM2-16GB, NVLink NV6, Xeon E5-2696 v3).
source "$(dirname "$0")/common.sh"
PREFIX=${PREFIX:-/opt/v100-stack}
VENV=${VENV:-$HOME/v100-stack/.venv}
HERE="$(cd "$(dirname "$0")/.." && pwd)"

hdr(){ printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

hdr "1. GPUs"
nvidia-smi -L | grep -q V100 || die "nenhuma V100 detectada"
nvidia-smi --query-gpu=index,name,driver_version,ecc.mode.current,clocks.current.sm --format=csv

hdr "2. NVLink  (referencia: 145,2 GB/s | PCIe daria ~12)"
nvidia-smi topo -m | head -4
if [ -f "$HERE/bench/p2p.cu" ] && command -v nvcc >/dev/null; then
  nvcc -O3 -arch=sm_${SM_ARCH} -Wno-deprecated-gpu-targets -o /tmp/p2p "$HERE/bench/p2p.cu" && /tmp/p2p
fi

hdr "3. Banda HBM2  (referencia: 823,5 GB/s = 91,5% do pico)"
if [ -f "$HERE/bench/hbm.cu" ] && command -v nvcc >/dev/null; then
  nvcc -O3 -arch=sm_${SM_ARCH} -Wno-deprecated-gpu-targets -o /tmp/hbm "$HERE/bench/hbm.cu" \
    && { /tmp/hbm 0; /tmp/hbm 1; }
fi

hdr "4. PyTorch  (a armadilha do bf16)"
[ -d "$VENV" ] && "$VENV/bin/python" - <<'PY'
import torch
print("  torch:", torch.__version__, "| cuda", torch.version.cuda, "| GPUs:", torch.cuda.device_count())
print("  sm_70 na wheel:", "sm_70" in torch.cuda.get_arch_list())
print("  is_bf16_supported():", torch.cuda.is_bf16_supported(), "<- True por EMULACAO, nao confie")
try: print("  sem emulacao      :", torch.cuda.is_bf16_supported(including_emulation=False))
except TypeError: pass
import time
for dt in (torch.float16, torch.bfloat16):
    a=torch.randn(4096,4096,device='cuda',dtype=dt); b=a.clone()
    for _ in range(3): c=a@b
    torch.cuda.synchronize(); t=time.time()
    for _ in range(20): c=a@b
    torch.cuda.synchronize()
    print(f"  matmul {str(dt).split('.')[-1]:9s}: {20*2*4096**3/(time.time()-t)/1e12:6.1f} TFLOP/s")
PY

hdr "5. llama.cpp  (referencia 8B Q6_K, 1 placa: pp512 3339 t/s | tg128 94 t/s)"
B="$PREFIX/llamacpp-sm70"
[ -x "$B/llama-bench" ] && "$B/llama-bench" --help >/dev/null 2>&1 && ok "llama-bench presente" || warn "llama.cpp nao instalado"
[ -e "$B/libggml-cuda.so" ] && echo "  arquitetura: $(cuda_archs "$B/libggml-cuda.so")"

hdr "6. audio.cpp"
A="$PREFIX/audiocpp-sm70"
[ -x "$A/audiocpp_cli" ] && "$A/audiocpp_cli" --version 2>&1 | head -4 || warn "audio.cpp nao instalado"
curl -s --max-time 3 localhost:8080/health 2>/dev/null && echo " <- balanceador no ar" || true

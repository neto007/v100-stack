#!/usr/bin/env bash
# FlashAttention-2 portada para Volta. Saida: dist/wheels/*.whl
# Serve a PyTorch/transformers/vLLM -- NAO ao llama.cpp, que tem a sua propria
# FlashAttention em CUDA (com branch dedicado a Volta em fattn.cu).
source "$(dirname "$0")/../scripts/common.sh"
SRC=${SRC:-$PWD/.src/flash-attention-v100}
OUT=${OUT:-$PWD/dist/wheels}
VENV=${VENV:-$HOME/v100-stack/.venv}
export PATH="${CUDA_HOME}/bin:$HOME/.local/bin:$PATH"

[ -d "$SRC" ] || git clone --depth 1 "$FLASHATTN_REPO" "$SRC"
[ -d "$VENV" ] || die "venv ausente -- rode scripts/03-python.sh primeiro"

# O setup.py exige torch.cuda.is_available(), mas a compilacao so precisa do
# nvcc (a arquitetura esta fixa em compute_70 no proprio setup.py). Em runner
# de CI nao ha GPU, entao relaxamos o guard e restauramos depois.
cp "$SRC/setup.py" "$SRC/.setup.py.bak"
python3 - "$SRC/setup.py" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            if not torch.cuda.is_available():
                raise RuntimeError("CUDA is required but not available.")'''
new = '''            if not torch.cuda.is_available() and not os.environ.get("FA_ALLOW_NO_GPU"):
                raise RuntimeError("CUDA is required but not available.")'''
if old in s: p.write_text(s.replace(old, new)); print("guard de GPU relaxado")
PY

mkdir -p "$OUT"
( cd "$SRC" && TORCH_CUDA_ARCH_LIST=7.0 FA_ALLOW_NO_GPU=1 VIRTUAL_ENV="$VENV" \
    uv build --wheel --out-dir "$OUT" --no-build-isolation 2>/dev/null \
  || TORCH_CUDA_ARCH_LIST=7.0 FA_ALLOW_NO_GPU=1 "$VENV/bin/python" -m pip wheel . \
       --no-deps --no-build-isolation -w "$OUT" )

mv "$SRC/.setup.py.bak" "$SRC/setup.py"
ls -la "$OUT"
ok "wheel do flash-attn-v100 em $OUT"

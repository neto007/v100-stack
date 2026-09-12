#!/usr/bin/env bash
# Ambiente Python 3.12 + PyTorch 2.10 cu129 (ultimo com cubin sm_70 nativo).
# Roda como usuario comum, NAO como root.
source "$(dirname "$0")/common.sh"
VENV=${VENV:-$HOME/v100-stack/.venv}

command -v uv >/dev/null || { log "instalando uv"; curl -LsSf https://astral.sh/uv/install.sh | sh; }
export PATH="$HOME/.local/bin:$PATH"

uv python install "${PYTHON_VER}"
mkdir -p "$(dirname "$VENV")"
[ -d "$VENV" ] || uv venv --python "${PYTHON_VER}" "$VENV"

log "instalando torch ${TORCH_VER}+cu129"
VIRTUAL_ENV="$VENV" uv pip install --index-url "${TORCH_INDEX}" "torch==${TORCH_VER}+cu129"
VIRTUAL_ENV="$VENV" uv pip install numpy ninja packaging wheel setuptools psutil

# A wheel precisa ter cubin sm_70 NATIVO, nao apenas PTX: PTX de compute_80+
# nao faz JIT para baixo. Verifique antes de confiar.
"$VENV/bin/python" - <<'PY'
import torch, sys
al = torch.cuda.get_arch_list() if torch.cuda.is_available() else []
print("torch:", torch.__version__, "| cuda", torch.version.cuda)
print("arch list:", al or "(GPU indisponivel; verifique com cuobjdump)")
if al and "sm_70" not in al:
    sys.exit("ERRO: esta wheel nao traz sm_70 -- use torch 2.10 cu129")
PY
ok "venv pronto em $VENV"

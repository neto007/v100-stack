#!/usr/bin/env bash
# Ajuste de hardware. Medido neste par de V100-SXM2-16GB:
#   banda HBM2 823,5 GB/s (91,5% do pico) | NVLink P2P 145,2 GB/s | fp16 97,7 TFLOP/s
source "$(dirname "$0")/common.sh"; need_root

# Clocks travados no teto: sem isso o boost oscila e a latencia p99 vira ruido.
# Persistence mode mantem o driver residente e e pre-requisito para o lock durar.
cat > /etc/systemd/system/v100-tuning.service <<UNIT
[Unit]
Description=Tuning V100: persistence mode + lock de clocks no teto
After=nvidia-persistenced.service
Wants=nvidia-persistenced.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -lgc ${SM_CLOCK},${SM_CLOCK}
ExecStop=/usr/bin/nvidia-smi -rgc
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now v100-tuning.service
ok "clocks travados em ${SM_CLOCK} MHz e reaplicados a cada boot"

# NCCL: forca P2P pelos links NVLink. A falha silenciosa mais comum em setup
# dual e o NCCL cair para um all-reduce interno sem avisar -- voce perde os
# 145 GB/s e nada no log diz isso.
cat > /etc/profile.d/v100-nccl.sh <<'PROF'
export NCCL_P2P_LEVEL=NVL
export TORCH_CUDA_ARCH_LIST=7.0
export CMAKE_CUDA_ARCHITECTURES=70
PROF
ok "NCCL_P2P_LEVEL=NVL e arquitetura sm_70 exportados em /etc/profile.d"

# ECC: MEDIDO NESTA MAQUINA, desligar nao deu ganho nenhum -- memoria identica
# (16384/240/16145) e banda 823,2 -> 823,5 GB/s, dentro do ruido. A doc que
# promete ganho descreve a V100 PCIe. Mantenha ligado: aqui e de graca.
warn "ECC: deixe LIGADO. Medimos ganho zero ao desligar em SXM2-16GB (ver docs/playbook.md)"

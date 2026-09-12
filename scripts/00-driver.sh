#!/usr/bin/env bash
# Instala o driver NVIDIA R580 (ultimo ramo com suporte a Volta) via runfile.
# Em Debian 13 nao ha alternativa: o repo CUDA para trixie so tem a serie 590,
# que ja nao suporta Volta, e o repo do Debian 12 passou a ser rejeitado por
# assinatura SHA-1 em fev/2026.
source "$(dirname "$0")/common.sh"; need_root

RUN="NVIDIA-Linux-x86_64-${DRIVER_VER}.run"
URL="https://us.download.nvidia.com/tesla/${DRIVER_VER}/${RUN}"
WORK=${WORK:-/var/tmp/v100-stack}; mkdir -p "$WORK"

if nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | grep -q "^${DRIVER_VER}"; then
  ok "driver ${DRIVER_VER} ja instalado"; exit 0
fi

command -v dkms >/dev/null || { log "instalando dkms e headers"; apt-get update -qq
  apt-get install -y dkms "linux-headers-$(uname -r)" build-essential; }

# Pacotes do Debian e runfile brigam pelas mesmas libs: purgue antes.
# O nvidia-container-toolkit e independente da versao do driver -- preserve.
KEEP='libnvidia-container1|libnvidia-container-tools|nvidia-container-toolkit|nvidia-container-toolkit-base'
PKGS=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | sed 's/:amd64$//' \
  | grep -E '^(nvidia-|libnvidia-|libcuda1|firmware-nvidia-|glx-alternative-nvidia|xserver-xorg-video-nvidia)' \
  | grep -vE "^(${KEEP})$" | sort -u || true)
if [ -n "$PKGS" ]; then
  log "purgando $(echo "$PKGS" | wc -l) pacotes NVIDIA do Debian"
  DEBIAN_FRONTEND=noninteractive apt-get purge -y $PKGS
fi

for m in nvidia_uvm nvidia_drm nvidia_modeset nvidia; do rmmod "$m" 2>/dev/null || true; done

[ -f "$WORK/$RUN" ] || { log "baixando ${RUN} (~380 MB)"; curl -fL -o "$WORK/$RUN" "$URL"; }
chmod +x "$WORK/$RUN"
"$WORK/$RUN" --check >/dev/null || die "runfile corrompido"

# Modulo proprietario, NAO o open: o open kernel module exige Turing+.
log "instalando driver ${DRIVER_VER}"
"$WORK/$RUN" --silent --dkms --disable-nouveau --no-questions --accept-license \
  || die "instalacao falhou; veja /var/log/nvidia-installer.log"

# O runfile instala o binario do persistenced mas nao a unit systemd.
if [ ! -f /etc/systemd/system/nvidia-persistenced.service ]; then
  id nvidia-persistenced >/dev/null 2>&1 || \
    useradd -r -M -s /usr/sbin/nologin -c "NVIDIA Persistence Daemon" nvidia-persistenced
  cat > /etc/systemd/system/nvidia-persistenced.service <<'UNIT'
[Unit]
Description=NVIDIA Persistence Daemon
Before=v100-tuning.service
[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --user nvidia-persistenced
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload; systemctl enable --now nvidia-persistenced
fi

ok "driver instalado. Um REBOOT e necessario se as GPUs nao aparecerem agora."
nvidia-smi -L || warn "GPUs nao inicializaram -- reboot, e se persistir, power-cycle completo"

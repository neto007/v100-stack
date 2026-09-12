#!/usr/bin/env bash
# Sobe dois audiocpp_server (um por GPU) atras de um nginx balanceado.
# Medido: 2,04x de vazao, distribuicao 10/10.
source "$(dirname "$0")/common.sh"; need_root
ROOT=${AUDIOCPP_ROOT:-/opt/v100-stack/audiocpp-sm70}
MODELS=${MODELS_DIR:-/opt/v100-stack/models}
RUN_USER=${SUDO_USER:-$(logname 2>/dev/null || echo root)}
HERE="$(cd "$(dirname "$0")/.." && pwd)"

[ -x "$ROOT/audiocpp_server" ] || die "audiocpp_server nao encontrado em $ROOT"
command -v nginx >/dev/null || { log "instalando nginx"; apt-get install -y nginx-light; }

mkdir -p "$ROOT/deploy"
for d in 0 1; do
  sed -e "s|@AUDIOCPP_ROOT@|$ROOT|g" -e "s|@MODELS_DIR@|$MODELS|g" \
      "$HERE/deploy/server-gpu$d.json" > "$ROOT/deploy/server-gpu$d.json"
done
sed -e "s|@AUDIOCPP_ROOT@|$ROOT|g" -e "s|@USER@|$RUN_USER|g" \
    "$HERE/deploy/audiocpp@.service" > /etc/systemd/system/audiocpp@.service
cp "$HERE/deploy/nginx-audiocpp.conf" /etc/nginx/sites-available/audiocpp
ln -sfn /etc/nginx/sites-available/audiocpp /etc/nginx/sites-enabled/audiocpp
rm -f /etc/nginx/sites-enabled/default
nginx -t || die "config do nginx invalida"

systemctl daemon-reload
systemctl enable --now audiocpp@0 audiocpp@1
systemctl restart nginx
ok "servidores subindo. Verifique: curl -s localhost:8080/health"

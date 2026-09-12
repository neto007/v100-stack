#!/usr/bin/env bash
# Instala as units systemd e o comando v100ctl. NADA sobe no boot: os servicos
# ficam disponiveis para 'v100ctl llm start' / 'v100ctl audio start'.
source "$(dirname "$0")/common.sh"; need_root
PREFIX=${PREFIX:-/opt/v100-stack}
MODELS=${MODELS_DIR:-/srv/models}
RUN_USER=${SUDO_USER:-$(logname 2>/dev/null || echo root)}
HERE="$(cd "$(dirname "$0")/.." && pwd)"

[ -x "$PREFIX/llamacpp-sm70/llama-server" ] || warn "llama.cpp ausente em $PREFIX"
mkdir -p "$PREFIX/deploy"

sub(){ sed -e "s|@PREFIX@|$PREFIX|g" -e "s|@MODELS_DIR@|$MODELS|g" -e "s|@USER@|$RUN_USER|g" "$1"; }

for f in server-gpu0.json server-gpu1.json llamacpp.env audiocpp.env; do
  [ -f "$PREFIX/deploy/$f" ] && { warn "preservando $PREFIX/deploy/$f (ja existe)"; continue; }
  sub "$HERE/deploy/$f" > "$PREFIX/deploy/$f"
done
sub "$HERE/deploy/audiocpp@.service" > /etc/systemd/system/audiocpp@.service
sub "$HERE/deploy/llamacpp.service"  > /etc/systemd/system/llamacpp.service
sub "$HERE/bin/v100ctl" > /usr/local/bin/v100ctl && chmod 755 /usr/local/bin/v100ctl
chown -R "$RUN_USER":"$RUN_USER" "$PREFIX/deploy"

# audio.cpp resolve model_specs/ pelo diretorio de trabalho. Como o runtime vive
# em $PREFIX e nao na arvore de fontes, os specs precisam ser copiados para ca --
# a unit passa --model-spec-override apontando para eles.
if [ ! -d "$PREFIX/model_specs" ]; then
  for c in "$HERE/../audio.cpp/model_specs" "$HOME/audio.cpp/model_specs" "$PWD/.src/audio.cpp/model_specs"; do
    [ -d "$c" ] && { cp -a "$c" "$PREFIX/"; ok "model_specs copiado de $c"; break; }
  done
  [ -d "$PREFIX/model_specs" ] || warn "model_specs nao encontrado -- o audio.cpp vai falhar ao carregar modelos"
fi

systemctl daemon-reload
# deliberadamente SEM 'enable': o usuario sobe sob demanda
systemctl disable audiocpp@0 audiocpp@1 llamacpp 2>/dev/null || true
command -v nginx >/dev/null || apt-get install -y nginx-light
sub "$HERE/deploy/nginx-audiocpp.conf" > /etc/nginx/sites-available/audiocpp
# $connection_upgrade precisa existir no bloco http (usado pelos proxies de UI)
cp "$HERE/deploy/nginx-upgrade-map.conf" /etc/nginx/conf.d/upgrade-map.conf
ln -sfn /etc/nginx/sites-available/audiocpp /etc/nginx/sites-enabled/audiocpp
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true

ok "servicos instalados. Nada sobe no boot."
echo
echo "  v100ctl status          estado e VRAM"
echo "  v100ctl llm start --web  sobe o LLM  (API 8090, UI 8091)"
echo "  v100ctl audio start --web  sobe o TTS (API 8080 balanceada, UI 8088)"
echo "  v100ctl stop            derruba tudo"

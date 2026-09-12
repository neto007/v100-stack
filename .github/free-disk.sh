#!/usr/bin/env bash
# Runners do GitHub tem ~14 GB livres. O CUDA sozinho come 5-6 GB e o build do
# audio.cpp gera varios GB de objetos. Removendo toolchains que nao usamos
# sobram ~45 GB.
set -euo pipefail
echo "antes:"; df -h / | tail -1
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc \
            /usr/local/share/boost /usr/local/share/powershell \
            /usr/share/swift /opt/hostedtoolcache 2>/dev/null || true
sudo docker image prune -af 2>/dev/null || true
sudo apt-get clean
echo "depois:"; df -h / | tail -1

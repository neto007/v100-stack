# audio.cpp nas duas placas

Medido: **2,04× de vazão** (1,53 → 3,13 req/s), distribuição 10/10, zero erros.

```
cliente -> nginx :8080 (least_conn + zone)
             |-> audiocpp@0 :8081 -> GPU 0
             |-> audiocpp@1 :8082 -> GPU 1
```

Tensor-parallel **não** se aplica: o audiocpp só aceita `--device <n>`, uma placa
por processo. O ganho vem de duas instâncias independentes.

## Instalar

```bash
sudo MODELS_DIR=/opt/v100-stack/models ./scripts/setup-audio-servers.sh
curl -s localhost:8080/health
```

O `CUDA_VISIBLE_DEVICES=%i` na unit systemd isola cada instância numa placa —
por isso os dois JSON usam `"device": 0`.

## Usar (API compatível com OpenAI)

```bash
curl -X POST localhost:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"model":"omnivoice","input":"texto","response_format":"wav"}' -o saida.wav
```

## Operar

```bash
sudo systemctl status audiocpp@0 audiocpp@1 nginx
sudo systemctl restart audiocpp@0          # reinicia só a GPU 0
sudo tail -f /var/log/nginx/audiocpp.log   # para qual placa cada requisição foi
```

## Detalhes da config que não são óbvios

- **`zone` no upstream é obrigatório** — sem ela a distribuição fica 16/3.
- **Nada de `max_conns`** — vira 502 sob carga no nginx open-source.
- **`proxy_read_timeout 600s`** — o padrão de 60 s cortaria sínteses longas.
- **`proxy_buffering off` nos endpoints `/live`** — senão o nginx segura os
  deltas do SSE e o streaming deixa de ser streaming.

## Adicionar modelos

Edite os **dois** JSON (idênticos, só o `port` difere) e reinicie ambas as
instâncias. Cada modelo extra consome VRAM nas duas placas; use
`--max-loaded-models` e `--idle-unload-ms` se apertar.

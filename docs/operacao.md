# Layout e operação

## Onde cada coisa mora

```
/opt/v100-stack/          runtime — vem da release, você nunca edita
├── llamacpp-sm70/        binários do llama.cpp          (88 MB)
├── audiocpp-sm70/        binários do audio.cpp         (244 MB)
├── model_specs/          specs de família do audio.cpp (572 KB)
├── venv/                 Python 3.12 + torch cu129      (7,7 GB)
└── deploy/               configs geradas na instalação

/srv/models/              modelos                         (26 GB)
~/src/v100-stack/         este repo: scripts, docs, configs versionadas
~/build/                  árvores de fonte — descartáveis, só para recompilar
```

A regra: **o que os serviços usam vem de uma release, não de um build local.**
Recompilar, limpar ou reclonar a fonte nunca derruba produção. Depois de
formatar, `install-release.sh` reconstrói `/opt` inteiro sem compilar nada.

Os modelos ficam em `/srv/models` por dois motivos: são 26 GB que não têm nada
a ver com código, e assim sobrevivem a uma reinstalação do sistema se você
preservar a partição.

## Nada sobe no boot

Os serviços são instalados mas **não habilitados**. Você sobe o que for usar:

```bash
v100ctl status            # estado dos serviços e VRAM das duas placas
v100ctl llm start         # LLM em :8090   (~1m30s para carregar)
v100ctl audio start       # TTS em :8080   (balanceado nas 2 placas)
v100ctl llm stop
v100ctl stop              # derruba tudo
v100ctl llm logs          # journalctl -f do serviço
```

Para habilitar no boot, se um dia quiser: `sudo systemctl enable llamacpp`.

## Orçamento de VRAM

31,5 GiB no total (2 × 15,77). Medido com os dois serviços no ar:

| serviço | VRAM |
|---|---|
| LLM (27B Q4_K_M + draft MTP) | ~19,3 GiB de pesos + KV cache |
| áudio ocioso | **0** — `lazy_load` descarrega |
| áudio em uso | ~1,9 GiB por placa |

Os dois juntos cabem (medido: 13,9 GiB por placa com ambos ativos), mas apertam
o KV cache do LLM. Se você usa só um, suba só um.

O áudio está com `lazy_load: true` e `idle_unload_ms: 600000`: ele devolve a
VRAM depois de 10 min sem uso e recarrega sob demanda. **Custo medido: ~4,9 s na
primeira requisição de cada placa**, contra 0,45 s quente. Se a latência da
primeira chamada importar mais que a VRAM, troque para `"lazy_load": false` em
`/opt/v100-stack/deploy/server-gpu*.json`.

## Configurar o LLM

Tudo em `/opt/v100-stack/deploy/llamacpp.env` — trocar de modelo não exige mexer
na unit:

```bash
LLM_MODEL=/srv/models/.../modelo.gguf
LLM_DRAFT=/srv/models/.../draft-mtp.gguf
SPEC_N_MAX=2        # ponto ótimo medido; acima de 3 a aceitação cai
LLM_CTX=32768       # NUNCA deixe no padrão do modelo — ver abaixo
LLM_PORT=8090
```

Depois: `sudo systemctl restart llamacpp`.

## Detalhes que já morderam

**`LLM_CTX` explícito é obrigatório.** O modelo declara `context_length` de
262144 e o servidor tenta alocar o KV cache inteiro — 8 GiB de uma vez, e falha.
O `llama-bench` não sofre disso porque usa contexto curto, então o problema só
aparece em uso real.

**O audio.cpp precisa de `model_specs/`.** Ele resolve esse diretório pelo
working directory, que na árvore de fontes era a raiz do repo. Com o runtime em
`/opt`, a unit passa `--model-spec-override /opt/v100-stack/model_specs`. Sem
isso: `GGUF has no embedded model spec for family 'omnivoice'`.

**O Qwen3.8 é um modelo de reasoning.** A saída vai para `reasoning_content`
até ele terminar de pensar; com `max_tokens` baixo você recebe `content` vazio e
`finish_reason: length`. Use pelo menos 1000 tokens.

**O venv do `uv` é relocável.** Mover `/opt/v100-stack/venv` não quebra nada,
mas o interpretador vive em `~/.local/share/uv/` — não apague esse diretório.

# Problemas conhecidos

## Nenhum arquivo `.cu` compila, nem um `main()` vazio

```
error: exception specification is incompatible with that of previous function "cospi"
```

glibc 2.41 (Debian 13) declara as funções C23 `sinpi`/`cospi` com `__THROW`; o
CUDA ≤ 12.9 declara as mesmas sem. Em C++ isso é erro. O `nvcc` já aplica
`__THROW` em 189 outras declarações — faltaram quatro.

```bash
source scripts/common.sh && sudo -E bash -c 'source scripts/common.sh; patch_cuda_glibc'
```

Idempotente, preserva o original em `.orig`. **Reinstalar o CUDA traz de volta.**

## As GPUs somem após `nvidia-smi -r`

```
NVRM: GPU 0000:03:00.0: RmInitAdapter failed! (0x23:0xffff:1552)
```

Reset de GPU deixa placas SXM2 num estado que **nem recarregar os módulos nem
reinstalar o driver recuperam**. Só power-cycle. Se um reboot quente não
resolver, desligue na fonte por ~30 s.

Placas com NVLink precisam ser resetadas **juntas**: `nvidia-smi -r -i 0,1`.

Evite o problema: não há motivo para desligar o ECC nestas placas (ganho medido
= zero), e era só isso que exigia o reset.

## `SPLIT_MODE_TENSOR requires flash_attn to be enabled`

Não é bug. No llama.cpp tensor-parallel e flash attention são acoplados: use
`-fa on` junto com `-sm tensor`.

## `backend offload failed for seq_id=0; using CPU sampler`

Esperado e inofensivo. O `llama-context.cpp` recusa deliberadamente sampling no
backend quando o split mode é `TENSOR`. Vale ~2%; o tensor-parallel vale ~28%.
A troca compensa. Ignore.

## `alloc_tensor_range: failed to allocate CUDA0 buffer of size 8589934592`

O modelo declara `context_length` enorme (262144 é comum) e o servidor tenta
alocar o KV cache inteiro. Passe `-c` explícito e quantize o KV:

```bash
-c 32768 -ctk q8_0 -ctv q8_0
```

O `llama-bench` não sofre disso (usa contexto curto), então só aparece em uso real.

## Driver R580 não está no repositório do Debian 13

O repo CUDA da NVIDIA para trixie só oferece a série 590, que já não suporta
Volta; o repo do Debian 12 tem o 580 mas passou a ser rejeitado em fev/2026 por
assinatura SHA-1. Use o runfile: `sudo ./scripts/00-driver.sh`.

Se o driver atual veio de pacotes Debian (`dkms status` mostra `nvidia-current`),
o script purga os pacotes antes — senão os dois sistemas brigam pelas mesmas libs.
O `nvidia-container-toolkit` é preservado.

## Treino silenciosamente 9,6× mais lento

`torch.cuda.is_bf16_supported()` devolve `True` numa V100 por **emulação**. Use
`including_emulation=False`, e em configs de treino `fp16=True, bf16=False`.

## O nginx manda tudo para uma placa só

Falta a diretiva `zone` no bloco `upstream`. O estado de balanceamento do nginx
é **por worker**; com 36 workers cada um escolhe o primeiro backend. Com `zone`
o estado é compartilhado e a distribuição fica 10/10.

E **não** use `max_conns` para contornar: sem a diretiva `queue` (exclusiva do
NGINX Plus) ele devolve 502 quando todos os backends estão no limite.

## `{"error":{"message":"WebUI is disabled"}}`

O `audiocpp_server` sobe com `--no-ui` por padrão. Use `v100ctl audio start --web`.

## WebUI do llama-server devolve HTTP 415

```
Error: gzip is not supported by this browser
```

Não é erro de configuração. Os assets da WebUI do llama.cpp são servidos
pré-comprimidos e o servidor exige `Accept-Encoding: gzip`. Navegadores sempre
mandam esse header; `curl` não manda por padrão. Para testar pela linha de
comando:

```bash
curl -H 'Accept-Encoding: gzip' http://127.0.0.1:8091/ | gunzip | head
```

## `GGUF has no embedded model spec for family '...'`

O audio.cpp resolve `model_specs/` pelo diretório de trabalho. Com o runtime em
`/opt` (fora da árvore de fontes), a unit precisa passar
`--model-spec-override $PREFIX/model_specs`. O `setup-services.sh` copia os
specs automaticamente se encontrar a árvore do audio.cpp.

## `{"error":{"message":"unknown endpoint: /llm/v1/chat/completions"}}`

Essa mensagem vem do **audiocpp_server**, não do nginx nem do llama-server —
significa que a requisição caiu na porta errada. O proxy `/llm/` só existe no
bloco `:8088` (pinado à GPU0). Se você acessou a WebUI por `:8080` (o pool
balanceado), ela carrega normalmente — as duas placas servem a mesma UI
estática — mas qualquer chamada a `/llm/` cai no `location /` genérico do
pool, que a repassa para o audiocpp_server, e ele não conhece essa rota.

**Use sempre `:8088` para a interface.** Isso deveria ser impossível pela
config atual (`:8080` tem `location = /` fixo, nunca serve a página), mas se
alguém remover essa trava, o sintoma volta. Ver `docs/podcast.md` e o trecho
sobre pinning em `AGENTS.md`.

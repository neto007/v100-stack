# Instruções para agentes

Contexto para um agente de IA que for trabalhar neste repositório ou na máquina
que ele configura. Leia antes de sugerir qualquer coisa.

## A regra que domina tudo

**Volta (sm_70) foi descontinuada.** Quase todo conselho atual sobre otimizar
inferência CUDA assume Ampere ou mais novo e está *errado* aqui. Antes de
recomendar qualquer pacote, verifique se ele ainda suporta `sm_70`.

Nunca sugira, em nenhuma circunstância:

| item | motivo |
|---|---|
| CUDA 13.x | removeu compilação offline para Volta |
| PyTorch 2.11+ | removeu os cubins `sm_70` |
| Triton 3.3+ | dropou Volta |
| driver série 590+ | não suporta Volta |
| `flash-attn` do PyPI | exige `sm_80`; use a wheel deste repo |
| `gptq_marlin`, AWQ-Marlin | exigem tensor cores INT8, que a Volta não tem |
| `bf16=True` em treino | **ver abaixo** |
| open kernel module da NVIDIA | exige Turing+; use o proprietário |

## A armadilha mais perigosa: bf16

`torch.cuda.is_bf16_supported()` retorna **`True`** numa V100 — por emulação.
Não é hardware. Medido nesta máquina:

```
matmul 4096³ em float16  :  97,7 TFLOP/s
matmul 4096³ em bfloat16 :  10,2 TFLOP/s     <- 9,6x mais lento
```

Verifique sempre com `torch.cuda.is_bf16_supported(including_emulation=False)`,
que devolve `False` corretamente. Em configs de treino: `fp16=True, bf16=False`.

## O que quebra o build em Debian 13

glibc 2.41 declara as funções C23 `sinpi`/`cospi` com `__THROW`; o CUDA ≤ 12.9
declara as mesmas sem. Em C++ isso é erro de especificação de exceção e
**nenhum arquivo `.cu` compila** — nem um `int main(){}` vazio. O sintoma engana:
parece problema do projeto, é do ambiente.

`scripts/common.sh` traz `patch_cuda_glibc()`, que detecta e corrige de forma
idempotente. Reinstalar o CUDA traz o problema de volta.

## Erros de medição que já cometemos aqui

Se você for medir desempenho nesta máquina, evite estes três:

1. **Não coloque um monitor de `nvidia-smi` em background dentro do mesmo
   `wait`.** Você acaba cronometrando o monitor. Isso produziu um "paralelo é
   mais lento" que era puro artefato.
2. **Speculative decoding tem variância alta** (±2 t/s entre seeds), porque a
   velocidade depende de quantos tokens do draft são aceitos. Use ≥3 seeds. Uma
   execução isolada nos deu 71,8 t/s onde a média real era 67,7.
3. **`grep -oP 'Generation: \K[0-9,]+'` trunca decimais** quando o locale usa
   ponto. Fixe `LC_NUMERIC=C` e case o separador.

## Configuração ótima medida

**LLM (llama.cpp)** — cada ajuste e o que vale:

| ajuste | efeito |
|---|---:|
| cabeça MTP, `--spec-draft-n-max 2` | +42% |
| `-sm tensor` vs `-sm layer` | +28% |
| sampler do draft na GPU | +2% |
| KV `f16` vs `q8_0` | +1% (ruído) |
| `--spec-draft-p-min > 0` | **−40% — não use** |

```bash
llama-server -m modelo.gguf -md draft-mtp.gguf -ngld all \
  --spec-draft-n-max 2 --spec-draft-n-min 1 \
  -sm tensor -ts 1/1 -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -c 32768
```

Dois detalhes não óbvios: `-sm tensor` **exige** `-fa on` (o llama.cpp recusa
carregar sem), e o aviso `backend offload failed; using CPU sampler` é
**esperado** — sampling no backend é incompatível com `SPLIT_MODE_TENSOR` por
decisão do próprio llama.cpp, e vale só 2%.

**Áudio (audio.cpp)** — não tem tensor-parallel, só `--device <n>`. O ganho vem
de duas instâncias, uma por placa, atrás de um nginx. Ver `docs/audio-servers.md`.

## Sempre passe `-c` explícito

Modelos com `context_length` grande (262144 é comum) fazem o servidor tentar
alocar o KV cache inteiro — 8 GiB de uma vez, e falha. O `llama-bench` **não**
sofre disso porque usa contexto curto, então o problema só aparece em uso real.

## Antes de afirmar que algo não funciona

Rode o experimento de controle. Um erro real desta sessão: concluí que o backend
CUDA do audio.cpp estava quebrado porque não gerava arquivo — o backend CPU
também não gerava. A flag era `--out`, não `-o`.

## Layout em produção

Runtime e fonte são separados de propósito. **Nunca aponte um serviço para
dentro de uma árvore de build** — um rebuild derruba produção.

```
/opt/v100-stack/   runtime (vem da release)   /srv/models/  modelos
~/src/v100-stack/  este repo                  ~/build/      fontes descartáveis
```

Nada sobe no boot. Controle: `v100ctl status|start|stop`, `v100ctl llm start`,
`v100ctl audio start`. Detalhes em `docs/operacao.md`.

## Estrutura

```
scripts/   00→03 setup da máquina, install-release, verify
build/     os mesmos scripts que o CI usa
deploy/    units systemd, config do nginx, JSON dos servidores
bench/     hbm.cu (banda) e p2p.cu (NVLink) — CUDA puro, sem dependências
docs/      playbook (achados), benchmarks (números), troubleshooting
```

Placeholders nos arquivos de `deploy/`: `@AUDIOCPP_ROOT@`, `@MODELS_DIR@`,
`@USER@`. Os scripts de instalação os substituem — não os edite à mão.

## Valores de referência

Se a verificação divergir muito disto, há algo errado no ambiente:

| métrica | referência |
|---|---|
| banda HBM2 | 823,5 GB/s (91,5% do pico) |
| NVLink P2P | 145,2 GB/s (PCIe daria ~12) |
| fp16 matmul | 97,7 TFLOP/s |
| llama.cpp 8B Q6_K, 1 placa | pp512 3339 t/s, tg128 94 t/s |

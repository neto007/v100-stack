# Números medidos

Hardware: 2× Tesla V100-SXM2-16GB (NVLink NV6), Xeon E5-2696 v3 (36 threads),
31 GiB RAM, Debian 13, driver 580.95.05, CUDA 12.9.1, clocks travados em 1530 MHz.

## Hardware

| métrica | medido | pico teórico |
|---|---:|---:|
| banda HBM2 (TRIAD) | 823,5 GB/s | 900 GB/s (91,5%) |
| NVLink P2P unidirecional | 145,2 GB/s | ~150 GB/s |
| matmul fp16 4096³ | 97,7 TFLOP/s | 125 TFLOP/s (78%) |
| matmul bf16 4096³ | 10,2 TFLOP/s | — (emulado) |

## llama.cpp

**Baseline, Llama-3.1 8B Q6_K, uma placa:**

| teste | medido | scoreboard oficial (Q4_0) |
|---|---:|---:|
| pp512 | 3 338 ± 133 t/s | 3 043 t/s |
| tg128 | 93,9 ± 0,1 t/s | 129–135 t/s |

O tg menor é coerente: Q6_K move ~1,5× mais bytes por token que o Q4_0 da
referência, e geração é limitada por banda de memória.

**Qwen3.8 27B Q4_K_M (17,66 GiB, não cabe numa placa):**

| teste | `-sm layer` | `-sm tensor` | ganho |
|---|---:|---:|---:|
| pp512 | 912 ± 18 t/s | 1 594 ± 14 t/s | +74,8% |
| tg128 | 34,7 ± 0,0 t/s | 50,6 ± 0,4 t/s | +45,8% |

**Speculative decoding com a cabeça MTP** (média de 3 seeds; a variância é real,
±2 t/s, porque a velocidade depende da taxa de aceitação do draft):

| configuração | geração | vs. baseline |
|---|---:|---:|
| sem MTP | 47,5 t/s | — |
| `--spec-draft-n-max 2` | **67,7 t/s** | **+42,5%** |
| `n-max 3` | 69,6 t/s * | — |
| `n-max 6` | 58,2 t/s * | — |

\* execução única; empatam com n=2 dentro da variância, exceto n=6 que cai claramente.

**Quanto vale cada ajuste:**

| ajuste | efeito |
|---|---:|
| cabeça MTP (n-max 2) | +42% |
| `-sm tensor` vs `-sm layer` | +28% |
| sampler do draft na GPU | +2% (incompatível com `-sm tensor`) |
| KV `f16` vs `q8_0` | +1% (ruído) |
| `--spec-draft-p-min > 0` | **−40%** |

Total: **34,7 → 67,7 t/s = 1,95×**, só por configuração.

## FlashAttention

O llama.cpp tem a **sua própria** FlashAttention em CUDA, com branch dedicado à
Volta em `fattn.cu`. Não tem relação com a wheel Python deste repo.

Llama-3.1 8B Q6_K, uma placa, `-sm layer` (necessário para poder desligar a FA —
`-sm tensor` exige `-fa on`):

| prompt | FA on | FA off | ganho |
|---|---:|---:|---:|
| 512 | 3 255 t/s | 3 059 t/s | +6% |
| 2 048 | 3 361 t/s | 2 842 t/s | +18% |
| 8 192 | 2 949 t/s | 1 964 t/s | +50% |
| 16 384 | 2 542 t/s | 1 353 t/s | +88% |

O ganho cresce com o contexto, como se espera de um algoritmo que troca memória
por recomputação. Em contexto curto a atenção não é o gargalo.

**A wheel Python** (`flash_attn_v100`, serve PyTorch/transformers/vLLM): no teste
do projeto com B=1, H=32, M=N=8192, D=256, roda forward *e* backward em 2 708 MB,
onde o SDPA do PyTorch dá OOM na mesma forma. Com máscara causal: 52,6 ms forward,
202,8 ms backward.

## audio.cpp

**Recompilar de `sm_86/89` para `sm_70`: +1,3%** (1 101 → 1 087 ms). O ganho é
desprezível porque o cuBLAS já fazia o trabalho pesado no caminho ótimo,
independente da arquitetura compilada. O ganho real é de tamanho: **1,27 GB → 83 MB**.

**Dois servidores balanceados, um por placa: 2,04×** (1,53 → 3,13 req/s), com
distribuição 10/10 e zero erros em 20 requisições. Latência sob carga: p50 3,80 s,
p95 6,37 s.

Para referência, RTF do OmniVoice numa placa: **0,21** (4,8× mais rápido que
tempo real) contra **4,99** na CPU com 36 threads — 21,6× de diferença.

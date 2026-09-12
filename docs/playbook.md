# Playbook: o que a pesquisa dizia e o que a medição mostrou

Este documento existe porque três recomendações amplamente repetidas sobre
otimizar V100 **não se sustentaram** quando medidas. Cada uma tem uma explicação
de por que o conselho original existia — nenhuma era invenção; todas eram
verdadeiras noutro contexto.

## 1. "Desligue o ECC para ganhar VRAM e banda"

**Falso em SXM2-16GB. Ganho zero, nas duas métricas.**

| | ECC ligado | ECC desligado |
|---|---|---|
| memória | 16384 Total / 240 Reserved / 16145 Free | idêntico |
| banda HBM2 | 823,2 GB/s | 823,5 GB/s |

A diferença de banda é ruído. A documentação que promete ganho descreve a V100
**PCIe**, onde o `nvidia-smi` reporta 16 160 MiB contra 16 384 nominais — essa
reserva não existe na SXM2 de 16 GB.

**Recomendação revisada: deixe o ECC ligado.** Aqui ele é de graça, e desligá-lo
custou um `RmInitAdapter failed` que só um power-cycle completo resolveu.

## 2. "Tensor-parallel não ajuda em stream único"

**Falso. Ajuda muito.**

| teste | `-sm layer` | `-sm tensor` | ganho |
|---|---:|---:|---:|
| pp512 | 912 t/s | 1 594 t/s | +74,8% |
| tg128 | 34,7 t/s | 50,6 t/s | +45,8% |

A afirmação original vem de um guia **Windows sem NCCL nativo**, onde o
all-reduce caía para um caminho interno e o custo de sincronização comia o ganho.
Com NCCL sobre NVLink no Linux, o resultado se inverte.

**Use `-sm tensor` como padrão**, não apenas sob concorrência.

## 3. "Speculative decoding é net-negativo em V100"

**Verdadeiro para o vLLM, falso para o llama.cpp: +42,5%.**

A justificativa original — o backend rápido não mantém CUDA graphs em Volta — é
real e específica do vLLM. O llama.cpp implementa MTP de outro jeito e se
comporta ao contrário.

**Meça por engine, nunca generalize por arquitetura de GPU.**

## O que a pesquisa acertou

Nem tudo caiu. Confirmados na medição:

- **Os tetos de versão.** CUDA 12.9.1, PyTorch 2.10, Triton 3.2, driver R580.
  Todos reais e todos críticos.
- **A ausência de BF16.** E pior do que documentado: `is_bf16_supported()`
  retorna `True` por emulação, escondendo uma perda de 9,6×.
- **A falha silenciosa do NCCL.** Se o P2P não ativar, você perde 145 GB/s e
  nada no log avisa. Verificar é obrigatório.
- **A ausência de tensor cores INT8.** Marlin e derivados estão realmente fora.

## O que a pesquisa não previu

Coisas que só apareceram compilando de verdade:

- **glibc 2.41 quebra todo o CUDA 12.9.** Quatro declarações sem `__THROW` e
  nenhum `.cu` compila. Nenhuma fonte mencionava isso.
- **O llama.cpp ganhou suporte de primeira classe para Volta.** `VOLTA_MMA_AVAILABLE`
  e um branch dedicado de FlashAttention em `fattn.cu`, que ajusta a otimização
  de GQA para a arquitetura. Nenhum guia citava.
- **`-sm tensor` exige `-fa on`.** Acoplamento não documentado.
- **O contexto padrão estoura a VRAM** em modelos de 262k, e o `llama-bench`
  esconde o problema porque usa contexto curto.
- **Recompilar o audio.cpp para `sm_70` rendeu 1,3%.** O cuBLAS já fazia o
  trabalho pesado no caminho ótimo, independente da arquitetura compilada.

## A lição metodológica

Todas as três recomendações falsas eram verdadeiras em *algum* contexto — outro
modelo de placa, outro sistema operacional, outra engine. O erro não estava em
quem escreveu; estava em aplicar sem verificar se o contexto batia.

Rode `scripts/verify.sh` na sua máquina antes de confiar em qualquer número
daqui — inclusive nos meus.

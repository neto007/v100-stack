# v100-stack

Stack de inferência local para **NVIDIA Tesla V100 (Volta, sm_70)**, com binários
pré-compilados. Volta foi descontinuada em 2026 — CUDA 13 removeu o suporte,
PyTorch 2.11 tirou os cubins, Triton 3.3 dropou a arquitetura. Este repo fixa
cada peça no último ponto em que ainda funciona, e publica o resultado compilado
para você não precisar refazer isso depois de formatar a máquina.

Todos os números aqui foram **medidos**, não estimados. Hardware de referência:
2× Tesla V100-SXM2-16GB com NVLink NV6, Xeon E5-2696 v3, Debian 13.

## Instalação rápida (sem compilar nada)

```bash
git clone https://github.com/neto007/v100-stack && cd v100-stack
sudo ./scripts/00-driver.sh        # driver R580 (último ramo com Volta)
sudo ./scripts/01-cuda.sh          # CUDA 12.9.1 + patch do glibc 2.41
sudo ./scripts/02-tuning.sh        # clocks travados, NCCL sobre NVLink
./scripts/03-python.sh             # Python 3.12 + torch 2.10 cu129
sudo ./scripts/install-release.sh  # baixa os binários já compilados
sudo ./scripts/setup-services.sh   # instala as units e o comando v100ctl
./scripts/verify.sh                # confere tudo contra os valores de referência
```

Nada sobe no boot. Você controla o que usar:

```bash
v100ctl status        # serviços e VRAM das duas placas
v100ctl llm   start --web   # LLM  : API 8090 | WebUI 8091
v100ctl audio start --web   # áudio: API 8080 (balanceada) | WebUI 8088
v100ctl stop                # derruba tudo
```

Layout, orçamento de VRAM e configuração: [docs/operacao.md](docs/operacao.md).

Depois de um `sudo ./scripts/00-driver.sh` pode ser preciso reiniciar. Se as GPUs
não voltarem com um reboot quente, faça **power-cycle completo** — veja
[troubleshooting](docs/troubleshooting.md).

## O que vem na release

| artefato | o quê |
|---|---|
| `llamacpp-sm70.tar.zst` | llama.cpp compilado só para sm_70, com NCCL e cuBLAS |
| `audiocpp-sm70.tar.zst` | audio.cpp (TTS/ASR/separação) para sm_70 |
| `flash_attn_v100-*.whl` | FlashAttention-2 portada para Volta (PyTorch/vLLM) |
| `SHA256SUMS` | checksums |

> **Compatibilidade de glibc.** Os binários do CI são compilados em Ubuntu 24.04
> (glibc 2.39) de propósito: rodam em alvos com glibc igual ou mais novo. Se a
> release tiver sido publicada por `build/release-local.sh` a partir de um
> Debian 13, ela exige **glibc ≥ 2.41**. Verifique com `ldd --version`.

## Resultados medidos

**Hardware** — banda HBM2 **823,5 GB/s** (91,5% do pico), NVLink P2P **145,2 GB/s**,
fp16 **97,7 TFLOP/s** (78% do pico teórico de 125).

**LLM, Qwen3.8 27B Q4_K_M em duas placas:**

| configuração | geração |
|---|---:|
| layer-split, sem MTP | 34,7 t/s |
| tensor-parallel sobre NVLink | 50,6 t/s |
| \+ cabeça MTP (`--spec-draft-n-max 2`) | **67,7 t/s** |

**1,95× só por configuração.** Detalhes e a varredura completa em
[docs/benchmarks.md](docs/benchmarks.md).

**Áudio, dois servidores balanceados (um por placa):** **2,04×** de vazão
(1,53 → 3,13 req/s), distribuição 10/10. Veja [docs/audio-servers.md](docs/audio-servers.md).

## Três recomendações populares que não se sustentaram

Medimos e elas são falsas neste hardware. O raciocínio está em
[docs/playbook.md](docs/playbook.md).

1. **"Desligue o ECC para ganhar VRAM e banda."** Ganho **zero** em SXM2-16GB —
   memória idêntica e banda dentro do ruído. A doc que promete ganho descreve a
   V100 **PCIe**. Deixe ligado.
2. **"Tensor-parallel não ajuda em stream único."** Ajuda: **+74,8%** em prompt
   processing, **+45,8%** em geração. A afirmação original vem de um setup
   Windows sem NCCL nativo.
3. **"Speculative decoding é net-negativo em V100."** Verdade para o vLLM, falso
   para o llama.cpp: **+42,5%**. Meça por engine, não por arquitetura de GPU.

## Compilar localmente

```bash
source scripts/common.sh
bash build/build-llamacpp.sh      # ~10 min em 36 threads
bash build/build-audiocpp.sh      # ~25 min em 36 threads
bash build/build-flashattn.sh     # ~9 min
```

O CI roda exatamente esses mesmos scripts. Para empacotar e publicar o que você
compilou localmente:

```bash
./build/release-local.sh v0.1.0
```

## Tetos de versão (não suba nenhum)

| peça | teto | o que quebra acima |
|---|---|---|
| CUDA | 12.9.1 | 13.0 removeu compilação offline para Volta |
| PyTorch | 2.10 | 2.11 tirou `sm_70` das wheels |
| Triton | 3.2 | 3.3 dropou Volta |
| Driver | R580 | série 590 não tem Volta |
| Python | 3.12 | wheels dos forks de vLLM são `cp312` |

## Licença

MIT. Os projetos compilados (llama.cpp, audio.cpp, flash-attention-v100) mantêm
suas licenças originais.

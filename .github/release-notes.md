Binários para **NVIDIA Tesla V100 (sm_70)**, compilados no último conjunto de
versões que ainda suporta Volta: CUDA 12.9.1, driver R580, PyTorch 2.10 cu129.

Compilados em Ubuntu 24.04 (glibc 2.39) **de propósito**: rodam em alvos com
glibc igual ou mais novo, como Debian 13. O contrário não funcionaria.

### Instalar

```bash
sudo ./scripts/install-release.sh   # ou baixe os .tar.zst e extraia em /opt/v100-stack
```

### Conteúdo

- `llamacpp-sm70.tar.zst` — llama.cpp com NCCL (necessário para `-sm tensor` usar o NVLink)
- `audiocpp-sm70.tar.zst` — audio.cpp para TTS/ASR/separação
- `flash_attn_v100-*.whl` — FlashAttention-2 para Volta (PyTorch/transformers/vLLM; **não** é usada pelo llama.cpp)

Verifique com `sha256sum -c SHA256SUMS`.

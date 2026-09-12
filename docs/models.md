# Trocando modelos do audio.cpp (fine-tunes em safetensors → GGUF)

O `audio.cpp` só carrega OmniVoice (e a maioria das famílias) em **GGUF
próprio** — não um GGUF genérico de llama.cpp/whisper.cpp, e não safetensors
direto. Um fine-tune publicado em safetensors (o formato comum no Hub) precisa
passar pelo conversor do próprio projeto antes de virar carregável.

Caso concreto: trocar o OmniVoice base por
[`edwixx/omnivoice-brpt-v15`](https://huggingface.co/edwixx/omnivoice-brpt-v15),
um fine-tune para português do Brasil.

## 1. Confirme que é fine-tune direto, não mudança de arquitetura

```bash
curl -sL .../edwixx/omnivoice-brpt-v15/raw/main/config.json -o /tmp/cfg_ft.json
curl -sL .../k2-fsa/OmniVoice/raw/main/config.json          -o /tmp/cfg_base.json
diff /tmp/cfg_base.json /tmp/cfg_ft.json   # idêntico = mesma arquitetura, só pesos mudaram
```

Se divergir, a conversão abaixo ainda pode funcionar, mas a compatibilidade
não está garantida — investigue as diferenças antes de seguir.

## 2. Veja se o fine-tune publicou TODOS os componentes

OmniVoice tem dois componentes de tensores, declarados no
`model_specs/omnivoice.json` do audio.cpp:

| namespace | arquivo típico | o que é |
|---|---|---|
| `weights` | `model.safetensors` | gerador (o que costuma ser fine-tunado) |
| `audio_tokenizer_weights` | `audio_tokenizer/model.safetensors` | codec de áudio |

Muitos fine-tunes de voz só re-treinam o gerador e não publicam o
`audio_tokenizer/` de novo — quando faltar, pegue esse componente do
repositório base (`k2-fsa/OmniVoice`).

```bash
mkdir -p /tmp/modelo-src/audio_tokenizer
cd /tmp/modelo-src

# do fine-tune
for f in model.safetensors config.json tokenizer.json tokenizer_config.json chat_template.jinja; do
  curl -sL -o "$f" "https://huggingface.co/<fine-tune>/resolve/main/$f"
done

# do modelo base (o que o fine-tune não publicou)
for f in config.json preprocessor_config.json model.safetensors; do
  curl -sL -o "audio_tokenizer/$f" "https://huggingface.co/k2-fsa/OmniVoice/resolve/main/audio_tokenizer/$f"
done
```

## 3. Compile e rode o conversor

```bash
cmake --build build/linux-cuda-sm70 --target audiocpp_gguf -j "$(nproc)"

./build/linux-cuda-sm70/bin/audiocpp_gguf \
  --input weights=/tmp/modelo-src/model.safetensors \
  --input audio_tokenizer_weights=/tmp/modelo-src/audio_tokenizer/model.safetensors \
  --root /tmp/modelo-src \
  --output /srv/models/OmniVoice-BRPT-GGUF/omnivoice-brpt-q8_0.gguf \
  --family omnivoice \
  --model-spec /opt/v100-stack/model_specs/omnivoice.json \
  --type q8_0 \
  --overwrite

# confirma: deve mostrar os dois namespaces e "embedded_model_spec=true"
./build/linux-cuda-sm70/bin/audiocpp_gguf --inspect \
  /srv/models/OmniVoice-BRPT-GGUF/omnivoice-brpt-q8_0.gguf
```

Os namespaces (`weights`, `audio_tokenizer_weights`) vêm de
`assets.cpp:120-121` de cada família — para converter outra família, procure
`open_tensor_source("...")` no `src/models/<family>/assets.cpp` correspondente
para achar os nomes certos, e a seção `tensors` do `model_specs/<family>.json`
para os `--input namespace=`.

## 4. Troque e teste antes de assumir que é melhor

```bash
sudo cp /opt/v100-stack/deploy/server-gpu0.json{,.bak-basemodel}
sudo cp /opt/v100-stack/deploy/server-gpu1.json{,.bak-basemodel}
sudo sed -i 's|OmniVoice-GGUF|OmniVoice-BRPT-GGUF|' /opt/v100-stack/deploy/server-gpu{0,1}.json
v100ctl audio stop && v100ctl audio start --web
```

Teste os dois caminhos de síntese antes de confiar na troca — o "voice
design" sozinho não prova que a clonagem por referência (o que a aba Podcast
usa) também funciona:

```bash
CLI=/opt/v100-stack/audiocpp-sm70/audiocpp_cli
M=/srv/models/OmniVoice-BRPT-GGUF
$CLI --task tts --family omnivoice --model $M --model-spec-override /opt/v100-stack/model_specs \
  --backend cuda --device 0 --language pt --instruct "female, young adult, moderate pitch" \
  --text "teste" --out /tmp/t1.wav
$CLI --task tts --family omnivoice --model $M --model-spec-override /opt/v100-stack/model_specs \
  --backend cuda --device 0 --language pt \
  --voice-ref /tmp/t1.wav --reference-text "teste" \
  --text "segunda fala, mesma voz?" --out /tmp/t2.wav
```

**Reverter:** restaure os `.bak-basemodel` e reinicie o serviço de áudio.

## Ganho medido neste caso

Modesto, não transformador — o modelo base já era bom em português (por isso
resolveu o caso de uso original antes de cogitar a troca):

| | WER | CER |
|---|---:|---:|
| OmniVoice base | 4,56% | 4,00% |
| fine-tune BR-PT v1.5 (`checkpoint-9000`) | 4,00% | 3,79% |

Números do próprio autor do fine-tune, não verificados de forma independente.
Vale ouvir os dois lado a lado (RTF e tamanho de arquivo são praticamente
idênticos — mesma arquitetura, mesma quantização) antes de decidir manter.

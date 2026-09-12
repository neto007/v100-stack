# Aba Podcast

Documento entra, dois apresentadores discutem em áudio — estilo NotebookLM
"Deep Dive". Vive dentro da WebUI do audio.cpp (`v100ctl audio start --web`,
porta 8088), como uma aba nova ao lado de Studio/Arena/Models/Runtime.

## Arquitetura: sem serviço novo

Tudo roda no navegador, orquestrando os dois serviços que já existem:

```
browser (Podcast.svelte)
  ├─→ /llm/v1/chat/completions   (llama-server, proxy nginx em :8088)
  └─→ /v1/audio/speech           (audiocpp_server, mesma origem)
```

O `/llm/` só existe atrás da porta 8088 (pinada à GPU0) — **nunca** na 8080
(pool balanceado). Ver `docs/operacao.md` para o porquê disso ser crítico, não
cosmético.

## Pipeline

1. **Extração de texto** — `.txt`/`.md` via `FileReader`; `.pdf` via
   `pdfjs-dist`, com o worker importado como string (`?raw`) em vez de arquivo
   separado — o CMake do audio.cpp só embute `dist/index.html` como arquivo
   único, então qualquer asset que o Vite emitisse à parte ficaria fora do
   binário.
2. **Roteiro, turno a turno via tool calling** — uma chamada por fala, cada
   uma vendo o histórico real e comprometido da conversa (não o plano interno
   do modelo). Ver "Por que turno a turno" abaixo.
3. **Síntese de voz, âncora + clone** — a primeira fala de cada apresentador
   usa voice design (`options.instruct` + seed fixa); o resultado sobe via
   `uploadWav()` e vira referência (`voice_ref` + `reference_text`) para todas
   as falas seguintes daquele apresentador. Ver "A armadilha da voz" abaixo.
4. **Concatenação** — `concatenateAudioBlobsWithGaps()` (extensão de
   `audio.ts`) junta os clipes com 350 ms de silêncio entre falas.

## Por que turno a turno, não um JSON só

A primeira versão pedia o roteiro inteiro numa chamada só (`json_schema` com
um array de turnos). Funcionava, mas o diálogo degradava: até a 4ª–5ª fala, os
apresentadores paravam de reagir um ao outro e viravam **dois narradores se
revezando** — cada fala uma afirmação de fato independente, sem responder à
anterior.

Testamos tool calling ingênuo (uma chamada, `tool_choice: "required"`) e não
resolveu sozinho: o modelo despeja todas as falas de uma vez como uma lista de
`tool_calls`, no mesmo surto de raciocínio — o mesmo problema, só que
embrulhado como chamadas de função em vez de itens de um array JSON.

A correção real: o **cliente** força a incrementalidade. A cada rodada:
- Envia o histórico + uma tool `write_turn(text)` com `tool_choice: "required"`.
- Pega **só a primeira** `tool_call` da resposta, descarta qualquer outra que
  o modelo tenha oferecido no mesmo surto.
- Commita no histórico: `{role: assistant, tool_calls: [essa]}` +
  `{role: tool, tool_call_id, content: "ok"}`.
- Pede a próxima fala — agora vendo o texto **real e comprometido** da fala
  anterior, não o plano interno do modelo.

Custo: ~10× as idas-e-voltas (cada uma com seu próprio preâmbulo de
raciocínio) — um roteiro de 10 falas passa de ~15-20s para **2-3 minutos**.
Escolha deliberada do usuário, não padrão automático — veja se vale a pena
para o seu caso antes de aumentar `turnCount` muito.

O sistema prompt (enviado uma vez) carrega o guia de estilo completo; cada
rodada recebe só um lembrete curto (regra de resposta direta + regra de tags)
— combate a deriva de instrução em loop longo sem repetir o texto inteiro a
cada chamada.

## A armadilha da voz

`options.instruct` (voice design) **reamostra uma voz nova a cada chamada**
— seed fixa não ancora identidade entre requisições separadas. Confirmado por
ouvido: a primeira versão soava como narrador diferente em quase toda fala
("10 locutores" em vez de 2).

Correção: a primeira fala de cada apresentador usa voice design; o clipe
resultante sobe via `/v1/ui/upload` e vira `voice_ref` + `reference_text` para
todas as falas seguintes — identidade ancorada em áudio real, não em descrição
reamostrada.

## Tags não-verbais do OmniVoice

`tokenizer_text.cpp` reconhece por **regex exato**: `[laughter]` `[sigh]`
`[confirmation-en]` `[question-en]` `[question-ah]` `[question-oh]`
`[question-ei]` `[question-yi]` `[surprise-ah]` `[surprise-oh]` `[surprise-wa]`
`[surprise-yo]` `[dissatisfaction-hnn]`. Uma variante como `[laugh]` não é tag
— é lida como texto literal e sai como ruído.

Duas armadilhas que o LLM caiu, mesmo com instrução explícita e exemplo de
bom/mau no prompt:

1. **Tag inventada** (`[laugh]` em vez de `[laughter]`) — blindado no cliente:
   `sanitizeNonverbalTags()` remove qualquer `[...]` que não bata exatamente
   com a lista.
2. **Eco falado da tag** (`[question-ei] Ei, sério?` — a interjeição "Ei" já
   é a própria tag renderizada, repeti-la é redundante) — blindado com um
   mapa `ECHO_WORDS` por sufixo de tag, que remove a palavra de eco se
   aparecer logo após uma tag válida.

Ambas as blindagens são backstops **do lado do cliente**: o prompt pede o
comportamento certo, mas `json_schema`/tool calling só garantem a forma da
resposta, nunca o conteúdo exato — LLMs derivam desses pedidos com frequência
suficiente para exigir um filtro determinístico, não só instrução.

## Outras armadilhas medidas

- **`max_tokens` para modelo de reasoning precisa de folga generosa.** O
  roteiro raciocina antes de responder, e o comprimento do raciocínio não é
  fixo entre execuções — um teto apertado corta no meio do pensamento sem
  nunca emitir o JSON/tool_call. `Math.max(6000, turnCount*400)` no modo de
  bloco único; `3000` por rodada no modo turno a turno (cada rodada só precisa
  planejar uma fala, não o episódio inteiro).
- **`temperature: 1.05`** — um roteiro "seguro" e de baixa variância é
  exatamente o que soa robótico. Seguro de subir porque `json_schema`/tools já
  garantem a forma da resposta; temperatura só afeta escolha de palavras e
  ritmo.
- **Variar o tamanho das falas precisa de instrução explícita** — sem isso o
  modelo produz falas de tamanho uniforme, que lê como texto formal, não
  conversa.

## Limitações conhecidas

- **Sem chunking de documento longo.** Acima de `MAX_DOC_CHARS` (12.000
  caracteres) o texto é truncado, não resumido hierarquicamente.
- **Alternância A/B é sempre estrita.** O loop decide quem fala, o modelo não
  escolhe — mais previsível para a arquitetura de âncora de voz, mas não
  permite um apresentador falar duas vezes seguidas.
- **Título vem de uma chamada extra ao final** — pequeno custo de latência
  adicional, mas evita repetir o guia de estilo inteiro só para nomear o
  episódio.

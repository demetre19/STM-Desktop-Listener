# Research: Small Local Speech-to-Text Models vs Parakeet

**Date:** 2026-09-09
**Context:** STM Desktop Listener currently uses local Parakeet for dictation. User asked for small LOCAL models that are efficient and better than Parakeet, recalling one "around 600MB" claimed to beat it. Research ran through the last30days skill (two engine passes over Reddit, X, HN, GitHub, YouTube) plus targeted web searches, then a direct look at Desert Ant Labs' Voz.

**Raw evidence files:**
- `~/Documents/Last30Days/lightweight-efficient-speech-to-text-transcription-models-better-than-parakeet-raw-v3.md` (run 1: 9 Reddit, 39 X, 31 HN, 16 GitHub, 2 YouTube)
- `~/Documents/Last30Days/lightweight-speech-to-text-models-better-than-parakeet-for-transcription-raw-v4.md` (run 2: 17 Reddit, 16 X, 16 HN, 23 GitHub; includes appended `## WebSearch Supplemental Results`)

---

## TL;DR

- The "~600MB better than Parakeet" memory most likely refers to **Qwen3-ASR-0.6B** (same size class, claimed to beat Whisper/Parakeet on difficult and multilingual audio) or **Voz** (467MB, but it IS Parakeet weights, not a competitor).
- For a drop-in accuracy upgrade on Apple Silicon: **Qwen3-ASR-0.6B** (MLX port exists).
- For streaming: **NVIDIA Nemotron 3.5 ASR Streaming 0.6B** via NeMo-Speech.cpp.
- For zero-download on macOS 26+: **Apple SpeechAnalyzer/SpeechTranscriber** (mixed accuracy evidence).
- For same accuracy but much faster/cheaper on Apple silicon: **Voz** (Parakeet TDT 0.6B v3 on the Neural Engine, 467MB, Swift SDK).
- Community caveat: benchmark WER claims are actively distrusted. r/LocalLLaMA: "Don't trust the benchmarks without locally testing. In my experience none of the new models have surpassed Whisper on transcription accuracy."

---

## Candidate models

### 1. Qwen3-ASR-0.6B (and 1.7B) — prime suspect for the "~600MB" memory

- HF: https://huggingface.co/Qwen/Qwen3-ASR-0.6B and https://huggingface.co/Qwen/Qwen3-ASR-1.7B
- Tech report: https://arxiv.org/html/2601.21337v1
- Claims: 30 languages + 22 Chinese dialects, long-audio support, offline + streaming inference, 92ms time-to-first-token, 2,000s of speech in 1s at concurrency. 1.7B reports 5.76% mean WER (not directly comparable across eval sets).
- Community: r/LocalLLaMA "Qwen3 ASR seems to outperform Whisper in almost every aspect" (https://www.reddit.com/r/LocalLLaMA/comments/1rq118c/) — with the skeptic reply quoted above.
- Apple Silicon: ground-up MLX reimplementation exists (https://www.reddit.com/r/LocalLLaMA/comments/1r56ak1/); MemoAI has an open request to add Qwen3-ASR-1.7B incl. an MLX version (https://github.com/Makememo/MemoAI/issues/428).
- Real-time head-to-head vs faster-whisper arguing WER alone is insufficient: https://nanosamur.ai/blog/posts/qwen-vs-whisper/

### 2. NVIDIA Nemotron 3.5 ASR Streaming 0.6B — the streaming pick

- HF: https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- Released June 2026; cache-aware FastConformer-RNNT, ~40 locales.
- int4 config: 8.20% average streaming WER, 0.56s algorithmic latency.
- Local runtime: NeMo-Speech.cpp (https://github.com/NVIDIA/NeMo-Speech.cpp) — ~7x realtime on an 8-core Apple Silicon laptop for the quantized model. Also supports Nemotron Speech Streaming and Parakeet.

### 3. Apple SpeechAnalyzer / SpeechTranscriber (macOS 26 built-in) — zero-download option

- HN benchmark: "Apple's new SpeechAnalyzer is the most accurate on-device speech engine we tested. It beat every Whisper model we ship" (https://news.ycombinator.com/item?id=48894752).
- MacStories: 2.2x faster than Whisper on a 7GB file (https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/).
- Counter-evidence: whispernotes.app scored Apple Speech 5.41 vs Qwen3-ASR 1.7B 3.38 and Whisper Large V3 Turbo 3.62 (https://whispernotes.app/blog/apple-speech-vs-whisper); r/MacOS commenter: "I use FluidVoice for dictation with Parakeet and it is still significantly more accurate" (https://www.reddit.com/r/MacOS/comments/1uvfksb/).
- Argmax/WhisperKit comparison: https://www.argmaxinc.com/blog/apple-and-argmax

### 4. Voz (Desert Ant Labs) — Parakeet itself, ANE-optimized, 467MB

- Model page: https://desertant.com/models/voz/ — Docs: https://desertant.com/docs/voz/ — HF: https://huggingface.co/desert-ant-labs/voz — SDK: https://github.com/Desert-Ant-Labs/desert-ant-core
- **It is NVIDIA Parakeet TDT 0.6B v3, weights unchanged (CC BY 4.0)**, converted to Core ML and compressed. Not a Parakeet-beater — a Parakeet-optimizer.
- 467MB on disk; 100% Apple Neural Engine resident, no CPU/GPU fallback; peak memory flat vs recording length.
- Speed: ~290-319x realtime on long files (10 min in 2s on iPhone 17 Pro; 30 min in 5.6s on M3 Ultra); 4.7x faster than whisper.cpp large-v3-turbo.
- Accuracy: 7.40% WER avg over six Open ASR Leaderboard sets (Whisper large-v3-turbo 7.00%); better on AMI meetings (11.84% vs 13.87%), behind on GigaSpeech/SPGISpeech/Earnings-22.
- Word timestamps: starts within 83ms, ends within 95ms of a forced aligner; 80ms frame resolution.
- 25 European languages; **no language auto-detection** — uncovered languages yield confident nonsense; pair with their Ear model for language ID.
- Batch-oriented: 15s windows cut at pauses, joined on agreed words. Short clips each pay a full 15s window (50-62x realtime) — a latency floor for short dictations (~0.3s for a 3s clip).
- Integration: SwiftPM `desert-ant-core` from 3.1.0, `import Voz`, `let voz = try await Voz(); voz.transcribe(url)`; macOS 15+, Apple Silicon only. Weights download from HF on first use (one-time ~20s Core ML specialization, then 0.2s loads) or ship the folder and pass `directory`.
- CLI for quick benchmarking: `brew install desert-ant-labs/tap/desertant` then `da`.
- **License: source-available, not OSS** — free below 100k monthly active devices per platform per model; attribution required; no training competing models on outputs. Canonical terms: https://license.desertant.com/1.0
- Fit for this app: same accuracy as current Parakeet, but ANE-resident (frees CPU/GPU, lower power) and a maintained SDK. Works as a post-stop transcription engine, not a live partial-results streaming one.

### 5. Also surfaced (weaker signals)

- **Moonshine** (~245M): efficiency leader, matches models 6x its size (https://www.onresonant.com/resources/local-stt-models-2026) — nobody claims it beats Parakeet on accuracy.
- **Whisper large-v3-turbo** (809M): still the practitioner accuracy reference; one engineer chose it over Parakeet for production citing Parakeet's 16+GB VRAM serving needs (https://www.arunbaby.com/speech-tech/0073-whisper-vs-parakeet-asr-decision/).
- **Mega-ASR**: new in-the-wild foundation ASR (https://arxiv.org/html/2605.19833v1, https://github.com/xzf-thu/Mega-ASR); being evaluated in r/speechtech vs Parakeet-TDT-v3 and Whisper-Turbo-v3 (https://www.reddit.com/r/speechtech/comments/1ue4tse/) — unproven.
- **CrisperWhisper**: verbatim-style transcription (https://github.com/nyrahealth/CrisperWhisper), HN 2026-09-06.
- **MOSS-Transcribe-Diarize**: joint transcription + diarization, requested alongside Qwen3-ASR in MemoAI.
- **Canary-Qwen 2.5B**: ~5.6% WER but much larger; tops Open ASR leaderboard.
- **Gemini 3.5 Transcribe**: Google's new API model (@GeminiApp, 2026-09-08) — cloud, not local; fails the local constraint.
- **SenseVoice** (Alibaba, ~234M) and **MediaTek Breeze-ASR-25**: appeared in GitHub requests; multilingual/regional plays.

## Parakeet ecosystem is improving underneath us

- Apple merged a live-streaming Parakeet v3 mode into coreai-models: https://github.com/apple/coreai-models/pull/184
- Parakeet v2 ported to Core ML for on-phone long-form transcription (@JackdeS11, 2026-08-19): https://x.com/JackdeS11/status/2089951553637802423
- whisper.cpp ships a parakeet-cli example: https://github.com/23rd/Scrib/issues/19
- sherpa-onnx added a Parakeet TDT 0.6B engine (run-1 GitHub item)
- FluidAudio remains the Core ML Parakeet path used by apps like FluidVoice

## Market/architecture signals

- WisprFlow's $280M raise made "small local STT + cheap cloud LLM cleanup" the reference architecture. @manavvnotop's teardown: "the gatekeeper is a tiny model: before anything expensive runs, a small, fast model decides what you actually said" (https://x.com/manavvnotop/status/2089636417349833071). @hkay_okay's free-stack recipe: "Spokenly (entirely free, ultrafast Parakeet V2) + an API key for Cerebras" (https://x.com/hkay_okay/status/2089227099903017195).
- Free local dictation apps multiplying: Handy (30K stars, Tauri/Rust, 100% offline — https://x.com/Trorram/status/2094209704226410623), Meetily, Wordmate (Show HN 2026-09-03), Dictata, AutoSubs, pixcribe.
- Hume AI published "benchmaxxing" research on 11 open ASR models (run-1 GitHub item) — benchmark WER skepticism is mainstream.

## Measured same-audio benchmark on this Mac

Test audio: 18.576 seconds, 16 kHz mono WAV generated with macOS `say`, containing conversational dictation plus difficult words and formatting targets (`speech-to-text`, `bake-off`, `12%`, `2:30`, `epitome`, `hyperbole`, and `Worcestershire sauce`).

| Engine | Measured time | Observed transcript quality |
| --- | ---: | --- |
| Cloudflare Worker, Whisper Turbo | 3.16s first run; 4.33s repeat | Correct difficult words; rendered `2.30` |
| Qwen3-ASR-0.6B 8-bit via MLX | 3.17s warm inference; ~31s process/model load; 1.86GB peak memory | Correct difficult words and stronger punctuation: `pace—the` and `2:30` |
| Current Parakeet TDT 0.6B v3 int8 via sherpa-onnx | 9.35s cold | Misheard `epitome` as `epitomy` and `Worcestershire sauce` as `Worcester source`; rendered `230` |

The Qwen model was `mlx-community/Qwen3-ASR-0.6B-8bit`; its Hugging Face cache was stored on `/Volumes/TheHoneyBadger/ai-cache/huggingface` because the startup disk was 98% full. The one-time download was excluded from warm inference. For app use, load and retain the model before dictation so the ~31s Python process/model-load cost is not paid per recording.

### Punctuation compatibility

STM Desktop Listener already applies punctuation independently of the selected recognizer:

1. `SpokenDictationFormatter` converts spoken commands such as “comma,” “question mark,” “new paragraph,” quotes, parentheses, dashes, and hyphens.
2. The bundled 7.1MB `Resources/PunctuationModel` runs afterward for both local and Cloudflare engines.
3. `applyingAutomaticPunctuation` accepts the model's punctuation only when the proposed and original word sequences match, so the punctuation pass cannot silently rewrite recognized words.
4. Existing recognizer punctuation and explicit spoken punctuation/newlines are preserved.

Qwen's native punctuation therefore complements the existing add-ons rather than replacing or bypassing them.

## Recommendation for STM Desktop Listener

1. **Strict “faster and more accurate than Cloudflare” bar:** no tested model has yet won both decisively. Qwen3-ASR-0.6B produced the best transcript and punctuation, but its 3.17s warm inference is effectively tied with Cloudflare's 3.16–4.33s response time.
2. **Best candidate to integrate if a tie-to-faster local result is sufficient:** Qwen3-ASR-0.6B 8-bit via MLX. Preload and retain it; otherwise model-load cost erases the latency benefit. It preserves compatibility with STM's punctuation layer.
3. **Fastest model:** Voz should be far faster than Cloudflare, but it uses unchanged Parakeet weights and cannot exceed Parakeet's word-recognition accuracy.
4. **Do not switch to the current sherpa-onnx Parakeet path for performance/accuracy alone:** it lost this same-audio test on both cold latency and difficult-word recognition.
5. **If integration complexity or a strict speed win outweighs offline/privacy benefits:** keep Cloudflare Whisper Turbo until a retained in-app Qwen benchmark proves lower end-to-end latency across real user recordings.

## Implemented local backup

STM Desktop Listener now ships Qwen3-ASR 0.6B 8-bit as its only optional local transcription engine. Cloudflare Worker remains the default and explicitly preferred engine; upgrading a legacy `parakeet` selection migrates it to Cloudflare, and installing Qwen never selects local mode automatically.

Implementation details:

- Model: `mlx-community/Qwen3-ASR-0.6B-8bit`, pinned to revision `89e96d92ba34aca20b3e29fb10cc284097d1219f`, 1,010,771,234 bytes across nine required files. Every download uses HTTPS, exact size bounds, and pinned SHA-256 verification before atomic installation.
- Runtime: private Python 3.10.18 environment with `mlx-audio` 0.5.3 and transitive dependencies from a hash-locked manifest. The app bundles pinned arm64 `uv` 0.8.5 and verifies its SHA-256 before execution.
- Process model: one isolated JSON-lines helper validates WAV paths/headers, caps inputs at 512 MiB, loads Qwen once, stays resident while local mode is used, and is stopped at app termination.
- Installer UX: a persistent model-parent folder picker, application-scoped single-flight task, byte/phase progress bar that survives leaving Settings, disabled duplicate starts, and native success/failure notifications.
- Current workstation: the model is stored under `/Volumes/TheHoneyBadger/STM Desktop Listener Models/qwen3-asr-0.6b-8bit`; config remains mode `0600`.
- The alternative pure-C Qwen runtime was rejected after exceeding 120 seconds on the 18.576-second proof WAV on this M1.

Installed proof:

- `/Applications/STM Desktop Listener.app` built and installed successfully as arm64.
- Installed Qwen self-test returned the exact difficult-word transcript with correct `speech-to-text`, `bake-off`, `12%`, `2:30`, `epitome`, `hyperbole`, and `Worcestershire sauce`; cold load plus transcription was 23.232 seconds in the final run.
- The clean persistent helper produced the same exact transcript twice; retained inference measured about 5.7 seconds per 18.576-second clip on this M1.
- Final Cloudflare regression returned HTTP 200 in 2.63 seconds with 561 characters and no error field.
- Diagnostics reported `transcriptionEngine=worker`, `qwenRuntimeInstalled=true`, and Qwen status ready.
- The relaunched Voice AI UI showed Cloudflare preferred, Qwen installed/ready, the external model folder, and a full progress indicator.

## Next steps if picked up later

- [x] Build and retain Qwen3-ASR-0.6B inside STM Desktop Listener as an optional local backup.
- [ ] Run a larger corpus of real user dictation WAVs through Cloudflare and Qwen3-ASR; compare word errors, punctuation, and warm latency.
- [ ] Benchmark Voz only if Neural Engine speed becomes more important than Qwen's better word recognition.
- [ ] Re-run last30days in a few weeks; the local-ASR space is moving weekly.

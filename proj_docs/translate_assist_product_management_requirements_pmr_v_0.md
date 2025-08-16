# Menubar Translator — Product Management Requirements (PMR)

## 1) Product one‑liner
A macOS menubar popover that gives **context‑aware EN/ES/ZH/HI/AR → Persian** translations with **LLM sense‑picking, style control, and a personal termbank**—without leaving your app.

## 2) Problem & why now
- **Context‑switching** to web translators breaks flow.
- **Domain ambiguity** (AI/CS, Business) makes generic MT wrong or awkward in Persian.
- **macOS UX gap:** Lookup shows definitions, not domain‑aware translations.
- **LLMs are fast/cheap enough** (Groq/Perplexity) to rerank senses and polish tone in real time.

## 3) Target users & intents
Primary:
- **Engineers/Researchers reading technical docs** (Intent: Read)
- **Product/Business folks drafting or reviewing content** (Intent: Write)
Secondary:
- **Casual learners** improving Persian comprehension (Intent: Learn)

## 4) Value proposition
- **One‑keystroke, in‑context** translations (selection or manual input).
- **LLM‑assisted sense disambiguation** tuned by persona axes (Intent × Domain × Proficiency × Register × Quality).
- **Teaching support**: quick Persian gloss, synonyms, examples, pronunciation.
- **Memory**: save terms to a personal termbank with light SRS.

## 5) Differentiators
- **Persona axes** instead of rigid roles; editable presets.
- **Domain chips** (start with AI/CS & Business) that reshape outputs.
- **Quality micro‑toggles** (Literal↔Idiomatic, Formal↔Conversational) in the popover.
- **Fast**: first paint from cache ≤300ms; MT ≤800ms P95; LLM rerank ≤400ms.

## 6) MVP scope (v0.1)
**Included**
- Trigger via macOS **Services** or menubar/hotkey.
- If no selection, show **input textbox** in popover.
- **Google Translation API** for MT; **Groq/Perplexity LLM** for rerank, rewrite, explain.
- Languages: auto‑detect top‑5 sources (EN/ES/ZH/HI/AR) → **Persian only** target.
- UI: Lookup‑inspired popover (own visual style): header (term·IPA·POS·audio), primary translation card, alternatives (expand), domain chips, micro‑toggles, Save.
- **Termbank + SRS (light)**; CSV/Anki export.
- **Examples** from Tatoeba/Wiktionary (EN → MT to FA → optional LLM clean‑up, labeled).
- **TTS** via `AVSpeechSynthesizer`.
- **Caching** (SQLite/Core Data) and error/confidence states.
- **Direct download** distribution (Developer ID, notarized, Sparkle updates).

**Excluded (defer)**
- Inline **Replace** of selected text.
- **OCR** and screenshot translation.
- **Onboarding** flow (use minimal first‑run consent only).
- **Accessibility/AX** hooks (consider later for reliable selection & blocklist).
- “Do not send clipboard from these apps” **blocklist** (needs AX; defer).

## 7) Success metrics (MVP)
- **Activation rate**: ≥60% of installers complete first translation in 24h.
- **Time‑to‑meaning** (first result): P95 ≤1.1s (cache+MT+LLM).
- **Save rate**: ≥20% of sessions save ≥1 term.
- **Perceived accuracy**: ≥80% “Right meaning” thumbs‑up on first choice (from in‑popover feedback) on gold set terms.
- **7‑day retention**: ≥30%.
- **Crash‑free sessions**: ≥99%.

## 8) Non‑goals (for clarity)
- Not a general bilingual dictionary app.
- Not a web browser extension (will consider later).
- Not multi‑target; only FA target in v0.1.

## 9) Release plan
- **Alpha (internal)**: dogfood with 50–100 handpicked gold‑set items.
- **Private beta**: 30–50 users (EN↔FA heavy users). Collect thumbs‑up/down + edits.
- **Public beta**: signed DMG via website; feedback button in app.

## 10) Monetization (not enforced in MVP)
- **Free beta** to learn.
- **Pro** later: persona editor, per‑app mapping, glossary lock, multi‑engine compare, offline packs, OCR, AX blocklist.

## 11) Key risks & mitigations
- **Quality for Persian in niche domains** → Seed with AI/CS & Business only; rely on MT+LLM rerank; learn from user corrections.
- **Latency/cost from LLM** → Use small, fast models for rerank/rewrite; strict JSON mode; aggressive caching.
- **Provider quotas/outages** → Abstract providers; health checks & circuit breaker; fallback to MT‑only.
- **Licensing** (examples/defs) → Use Wiktionary/Tatoeba/OPUS (CC); cache; attribute in About.
- **UI review risk (MAS later)** → Unique visual style; avoid cloning Lookup.
- **RTL correctness** → Test mixed LTR/RTL; enforce semantic attributes.

## 12) Competitive landscape
- **Google/DeepL web/extension**: strong MT, weak domain‑aware Persian; requires tab switch.
- **Apple Translate/Lookup**: system‑native but not domain‑aware Persian; Lookup focuses on definitions.
- **Mate/PopClip**: handy utilities; weaker persona/domain controls.

## 13) Dependencies
- macOS 13+, Xcode 15+, Developer ID & notarization, Sparkle.
- Google Cloud Translation key; Groq or Perplexity key.
- Data sources: Wiktionary/Tatoeba dumps or APIs.

## 14) Roadmap (high level)
- **v0.1 MVP**: scope above.
- **v0.2**: per‑app persona mapping; glossary lock; improved examples; blocklist (requires AX).
- **v0.3**: OCR; multi‑engine compare; Safari/Chrome extension.
- **v1.0**: Mac App Store build (sandboxing/IAP), offline packs, usage analytics dashboard.

## 15) Assumptions
- Users accept cloud processing in MVP.
- Persian target is the highest leverage for initial audience.
- LLMs (Groq/Perplexity) can meet ≤400ms rerank/rewrite at typical prompt sizes.


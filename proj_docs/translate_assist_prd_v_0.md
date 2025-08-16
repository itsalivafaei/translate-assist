# Menubar Translator — Product Requirements Document (PRD) v0.1

## 0) Overview

A macOS 13+ menubar popover that delivers **EN/ES/ZH/HI/AR → FA** translations with **Google MT** plus **LLM (Google AI Studio: Gemma/Gemini) rerank/rewrite/explain**, persona‑aware outputs, a personal termbank with light SRS, examples, and TTS. Distribution is direct‑download (signed, notarized) with Sparkle. No OCR, no inline Replace, no onboarding; cloud is required in MVP.

## 1) User stories & acceptance criteria

**US‑01 Translate selection (Read)**

- As a user, when I select text and trigger the hotkey/menubar, I see a popover with the best Persian translation, IPA/POS (if found), and an audio button.
- *AC:* If selection provided via Services, show result ≤1.1s P95; if cache hit, ≤300ms. If confidence < τ, show “Low confidence” and 1–2 alternates.

**US‑02 Manual input (no selection)**

- As a user, I can open the popover and paste/type text into an input box to translate.
- *AC:* Input textbox focused by default; history of last 5 inputs; same latency budgets as US‑01.

**US‑03 Domain chips & personas**

- As a user, I can toggle domain chips (AI/CS, Business) and a persona preset (Engineer·Read, Business·Write, Casual·Learn) that change results.
- *AC:* Toggling re‑requests LLM rewrite/rerank and updates output within 400ms P95 (from cache where possible).

**US‑04 Quality controls**

- As a user, I can switch between Literal↔Idiomatic and Formal↔Conversational and see the result update.
- *AC:* Rewrite completes ≤400ms P95; ensure meaning preserved (no added facts) per validator.

**US‑05 Save to termbank + SRS**

- As a user, I can save the current term with its chosen sense, examples, and domain. I can export CSV.
- *AC:* Save ≤50ms; daily review shows ≤10 items; CSV exports valid UTF‑8 with headers.

**US‑06 Examples & explain**

- As a user, I can expand to see 1–3 example sentences (labeled if machine‑generated) and a short Persian gloss at my proficiency.
- *AC:* Examples load progressively; explain text ≤40 words for B1–C1.

**US‑07 Error & offline states**

- As a user, I see clear messages for rate limit, provider down, or offline; cached results still show.
- *AC:* Distinct banners; retry button; no crashes.

## 2) Functional requirements

- **Entry**: macOS Services primary; menubar button + global hotkey; clipboard fallback when no Services payload.
- **Language**: auto‑detect sources among EN/ES/ZH/HI/AR; target FA only.
- **Translation pipeline**: MT (Google) → LLM rerank (choose sense & domain) → LLM rewrite (register/literal bias) → Explain → Examples.
- **UI**: Header (term, IPA, POS, audio, copy); Primary card; Alternatives (expand); Domain chips; Persona preset switcher; Quality toggles; Save button.
- **Caching**: MT cache keyed by `(term, contextHash, src→fa)`; LLM cache keyed by `(term, contextHash, personaHash, mtHash)`.
- **Termbank**: Entities for Term, Sense, Example, ReviewLog; CSV/Anki export.
- **TTS**: On‑device `AVSpeechSynthesizer`.
- **Telemetry (opt‑in later; MVP minimal)**: local counters only.

## 3) Non‑functional requirements

- **Performance**: first paint ≤300ms cache; MT ≤800ms P95; LLM ≤400ms P95; UI stays responsive during streaming.
- **Reliability**: crash‑free ≥99%; safe fallback to MT‑only if LLM fails JSON.
- **Security/Privacy**: cloud required; keys stored locally; no clipboard source identification in MVP; data stays local except requests to providers.
- **Accessibility & i18n**: RTL support; VoiceOver labels; keyboard‑only navigation.
- **Compatibility**: macOS 13+; Intel & Apple Silicon.

## 4) Architecture

- **UI layer**: SwiftUI views inside an AppKit `NSPopover` driven by `NSStatusItem`.
- **View models**: `PopoverVM`, `TranslationVM`, `TermbankVM` using async/await.
- **Services**: `TranslationService`, `LLMEnhancerService`, `ExamplesService`, `PronunciationService`, `CacheService`, `CSVExportService`.
- **Providers** (adapters): `GoogleTranslationProvider`, `GemmaLLMProvider` or `GeminiLLMProvider` (Google AI Studio), `WiktionaryProvider`, `TatoebaProvider`.
- **Storage**: Core Data (Termbank); SQLite (GRDB) for caches.
- **Updates**: Sparkle.

## 5) API contracts (internal)

**TranslationProvider**

```
translate(term: String, src: String?, dst: String, context: String?) -> MTResponse
// MTResponse { candidates: [Sense], detectedSrc: String?, usage: Quota }
```

**LLMEnhancer**

```
rerank(input: RerankInput) -> RerankOutput
rewrite(input: RewriteInput) -> RewriteOutput
explain(input: ExplainInput) -> ExplainOutput
```

**RerankInput**

```
{ term, src, dst:"fa", context, persona, domainPriority:["AI/CS","Business"],
  candidates:[{text, pos?, ipa?, provenance:"google"}], glossaryHits:[...] }
```

**RerankOutput (strict JSON)**

```
{ best:{text, pos?, ipa?, rationale}, alternatives:[{text, rationale}],
  confidence:0.0-1.0, domain:"AI/CS"|"Business" }
```

**RewriteInput**

```
{ text, register:"formal"|"conversational", literalBias:0..1, constraints:"preserve meaning" }
```

**ExplainInput**

```
{ term, level:"B1"|"C1", lang:"fa", maxWords:40 }
```

## 6) Data model (Core Data)

**Term**: id, lemma, srcLang, createdAt, updatedAt

**Sense**: id, termId, textFA, pos, ipa, domainTag, register, literalBias, source("mt"|"llm"), confidence

**Example**: id, termId, textEN, textFA, provenance("tatoeba"|"wiktionary"|"mt"|"llm"), isMachineGenerated: Bool

**ReviewLog**: id, termId, dueAt, ease, interval, success: Bool

**PersonaPreset**: id, name, intent, domains[], proficiency, register, quality{ literalBias, thoroughness, contextChars, glossaryMode }

## 7) Persona schema (editable JSON)

```
{
  "id": "engineer_read",
  "intent": "read",
  "domains": ["AI/CS","Cloud"],
  "proficiency": "C1",
  "register": "neutral",
  "quality": { "literalBias": 0.7, "thoroughness": 0.4, "contextChars": 400, "glossaryMode": "prefer" }
}
```

## 8) Prompt specs (LLM)

**System (rerank)**: “You are a bilingual sense disambiguator for EN/ES/ZH/HI/AR→FA. Choose the most context‑appropriate Persian translation, then provide up to two alternatives. Output strict JSON only.”

**User payload**: `RerankInput` as JSON.

**System (rewrite)**: “Rewrite Persian text to the requested register and literal/idiomatic bias. Preserve meaning. Output only the revised text.”

**System (explain)**: “Explain the term in Persian at the user’s proficiency level in ≤N words.”

**Validation**: JSON schema check; retry once; fallback to MT on failure.

## 9) UI spec (states)

- **Header**: Term (bold), IPA (dim), POS tag, ▶︎ audio, ⧉ copy.
- **Primary card**: Large FA translation, small domain badge, confidence dot (green/amber/red).
- **Alternatives**: collapsed list; “More senses ▸”.
- **Chips**: Domain toggles; Persona dropdown (3 presets).
- **Quality toggles**: Literal↔Idiomatic; Formal↔Conversational.
- **Actions**: Save, Export (in menu), Feedback (👍/👎 with reason tags).
- **Errors**: inline banners (“Offline—showing cache”, “Provider busy—retrying”).

## 10) Edge cases

- Zero/very long selection → trim to max contextChars.
- Email/password fields (secure) → no Services payload; show input box instead.
- Mixed LTR/RTL punctuation → enforce semantic attributes; test numerals.
- Provider limit/hiccups → exponential backoff; switch to MT‑only.

## 11) Analytics (later; stub now)

- Events: app\_open, translate\_request, cache\_hit, mt\_ok, llm\_ok, llm\_json\_fail, save\_term, srs\_review, feedback\_up, feedback\_down.
- Properties: personaId, domain, length, latency\_ms, confidence.

## 12) Release criteria

- P95 latency ≤1.1s; crash‑free sessions ≥99% (7‑day).
- ≥80% “Right meaning” on gold set (internal) across AI/CS & Business.
- All UI accessible by keyboard; VoiceOver labels present.
- Signed, notarized DMG; Sparkle updates validated.

## 13) Test plan (summary)

- Unit tests: adapters (Google, LLM), parsers, cache.
- UI tests: popover flows, toggles, error banners, RTL rendering.
- Gold set: 100 items (50 AI/CS, 50 Business) with expected senses.
- Network chaos: simulate timeouts/rate limits; verify fallbacks.

## 14) Packaging & distribution

- Developer ID–signed app; notarized via Xcode.
- Sparkle feed & DSA keys; auto‑update checks weekly.
- Keys in local plist; not in repo.

## 15) Out of scope (v0.1)

- Inline Replace, OCR, Accessibility/AX integrations, App Store build, multi‑target languages, browser extensions.

## 16) Open questions

- Gemma vs Gemini default model for rerank/rewrite? (Pick based on latency/quality in your region.)
- Budget for monthly API usage during beta (set cap & in‑app warning)?
- Extend domains beyond AI/CS & Business before v0.2?


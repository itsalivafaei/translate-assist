## Translate Assist — Project Report v1

This report documents the current state of Translate Assist, a macOS menubar translator focused on EN/ES/ZH/HI/AR → FA with domain/persona‑aware results. It summarizes what is implemented, how the system is architected, and how to extend or operate it.

### 1) Product overview
- **Platform**: macOS 13+ (Intel & Apple Silicon)
- **Function**: Context‑aware translations to Persian using Google MT plus Google AI Studio LLM (Gemma/Gemini) to rerank/optionally rewrite and explain.
- **UX**: Menubar popover; show MT first, then LLM enhancement; persona presets and domain chips adjust outputs; examples and termbank.
- **Scope exclusions (MVP)**: No OCR, no inline Replace, no onboarding wizard, no audio controls (TTS hidden), no AX blocklist.

### 2) Status summary (what’s done)
- ✅ SwiftUI menubar shell with `NSStatusItem` and `NSPopover`, global hotkeys (Ctrl+T / Ctrl+Shift+T), Services integration for selected text.
- ✅ Orchestration that streams: MT → LLM decision → finalize → examples, with banners and graceful fallbacks.
- ✅ Providers and caches for Google Translate MT and Google AI Studio LLM (Gemma/Gemini), plus examples via Tatoeba.
- ✅ Rate‑limit scheduler with token‑bucket for RPM/TPM/RPD, exponential backoff, and a 60s circuit breaker.
- ✅ Storage via GRDB/SQLite (schema v1) for termbank, examples, SRS, caches, metrics; plus v2 input history.
- ✅ Structured logging (os.Logger) and `os_signpost` for timing around pipeline stages.
- ✅ Export/import flows for termbank and senses (CSV/JSONL). Light SRS list and input history UI.

### 3) Key user‑facing features
- **Menubar translator**: One‑keystroke open; paste or auto‑prefill input; see best result quickly.
- **Domain & persona controls**: Toggle `AI/CS` and `Business`; choose among presets (Engineer·Read, Business·Write, Casual·Learn). Changes re‑evaluate using cached LLM decisions when possible.
- **Alternatives & explanation**: Primary FA choice with a confidence indicator; alternatives collapsed; short explanation text.
- **Examples**: 1–3 example pairs from Tatoeba (progressive, labeled with provenance).
- **Termbank & SRS**: Save chosen output; view saved senses/examples; light review flow with due items.
- **Banners & error states**: Offline banner, rate‑limit/circuit banners, “Retry” action for LLM.
- **Exports/Imports**: CSV and JSONL exports; import CSV/JSONL from Settings.

### 4) Architecture (high‑level)
- **UI**: SwiftUI views inside an AppKit `NSPopover` managed by `NSStatusItem`. Views are thin; ViewModels and services own logic. Closing the popover cancels in‑flight work.
- **Services**: `TranslationService` orchestrates MT → LLM decision → finalize → examples; streaming updates using `AsyncStream`.
- **Providers (adapters)**: Protocol‑oriented: MT, LLM, Examples, Glossary, Metrics; cache decorators to enforce caching policy.
- **Networking**: `URLSession` client with timeouts, request IDs, structured logs; rate‑limit hints parsing.
- **Scheduling**: Token‑bucket scheduler per provider; backoff + circuit breaker for resilience.
- **Storage**: GRDB/SQLite with deterministic migrations; TTL caches for MT/LLM; metrics table; export/import utilities.

### 5) Codebase map
- `translate assist/translate_assistApp.swift` — App entry. Creates `NSStatusItem`, popover root (`MenubarPopoverView`), hotkeys, Services integration, and wires `TranslationService` via `ProvidersBootstrap`. Hosts Settings and export/import actions.
- `ViewModels/OrchestrationVM.swift` — Binds to `TranslationService` stream; manages UI state: chosen text, alternatives, explanation, confidence, examples, banners, in‑flight state.
- `Services/TranslationService.swift` — Core orchestration:
  - Yields updates: `.mt(MTResponse)`, `.decision(LLMDecision)`, `.final(TranslationOutcome)`, `.examples([Example])`, `.banner(String)`.
  - Stages: MT (cached) → LLM decision → finalize outcome → examples (non‑blocking) → finish.
  - Handles offline proactively and degrades to MT‑only; auto‑retry LLM once after cooldown for rate‑limit/timeouts; glossary conflict banner; optional escalation path (separate cache tag).
- `Providers/Contracts.swift` — DTOs and protocols:
  - DTOs: `SenseCandidate`, `MTResponse`, `GlossaryHit`, `LLMDecisionInput`, `LLMDecision`, `Example`.
  - Protocols: `TranslationProvider`, `LLMEnhancer`, `ExamplesProvider`, `GlossaryProvider`, `MetricsProvider`.
- `Providers/GoogleTranslationProvider.swift` — Google Translate v2 adapter (detects source when possible) using `RateLimitScheduler`.
- `Providers/GemmaLLMProvider.swift`, `Providers/GeminiLLMProvider.swift` — Google AI Studio adapters using `PromptFactory` and strict JSON parsing with one compact repair attempt.
- `Providers/Examples/TatoebaExamplesProvider.swift` — Fetch examples via Tatoeba API; language code mapping; returns up to 3 labeled examples.
- `Providers/Cached/CachedProviders.swift` — Cache decorators for MT and LLM using `CacheService` and deterministic keys.
- `Providers/PromptFactory.swift` — Central prompt builder for decision + repair; tests include schema decode.
- `Providers/ProvidersBootstrap.swift` — Factory for MT, LLM, Examples, Glossary, Metrics providers with `SecretsLoader` and cache decoration; configurable primary LLM (`gemma` or `gemini`).
- `Networking/NetworkClient.swift` — Request timeouts, `X-Request-ID`, structured logs, `RateLimitHints` parsing (`retry-after`, `x-ratelimit-*` headers), error mapping.
- `Scheduler/RateLimitScheduler.swift` — Token‑bucket with capacities from `Config/RateLimitConfig.swift`; exponential backoff on 429/503/timeouts; circuit breaker (persisted); priority queueing hooks.
- `Config/SecretsLoader.swift` — Loads keys and model IDs from environment or `Secrets.plist`.
- `Config/Constants.swift` — Tunables: timeouts, cache TTLs, popover sizing, maintenance intervals, etc.
- `Storage/` — GRDB/SQLite stack: schema migrations, DAOs, cache service, metrics, validation helpers, export/import.
- `Previews/` — Static previews for UI states.
- `Tests/` — Unit tests for caches, scheduler, prompts/validator, LLM fallback, gold set smoke, UI smoke.

### 6) Data model (Schema v1 + v2)
Tables (see `Storage/Migrations.swift`):
- `term(id, src, dst, lemma, created_at)`
- `sense(id, term_id, canonical, variants, domain, notes, style, source, confidence, created_at)`
- `example(id, term_id, src_text, dst_text, provenance, created_at)`
- `review_log(id, term_id, due_at, ease, interval, success, created_at)`
- `cache_mt(key primary, payload, created_at, ttl)`
- `cache_llm(key primary, payload, created_at, ttl)`
- `metrics(id, event, value, created_at)`
- v2: `input_history(id, text, created_at)`

DTOs used in orchestration (see `Providers/Contracts.swift`):
- `LLMDecisionInput { term, src, dst:"fa", context?, persona?, domainPriority:[String], candidates:[...], glossaryHits:[...] }`
- `LLMDecision { version:"1.0", decision:"mt"|"rewrite"|"reject", topIndex:Int, rewrite:String?, explanation:String, confidence:Double, warnings:[String] }`

### 7) Networking & scheduling
- `NetworkClient` attaches a UUID request ID header, applies per‑request timeouts (`Constants.requestTimeoutMs`), logs requests/responses, and parses rate‑limit headers into `RateLimitHints`.
- `RateLimitScheduler` consumes scheduling tokens for RPM and TPM and handles backpressure:
  - On insufficient tokens, requests are queued with a computed delay until refill.
  - On 429/503/timeouts, it applies exponential backoff with jitter and can open a 60s circuit breaker per provider (persisted).
  - Offline errors are surfaced without tripping backoff/circuit.

### 8) Providers & prompts
- **MT**: `GoogleTranslationProvider` calls Google Translate v2; parses candidates and detected source if available; usage quotas sourced from `ProviderRateLimits.googleTranslate`.
- **LLM**: `GemmaLLMProvider` and `GeminiLLMProvider` call Google AI Studio `generateContent`:
  - Send `PromptFactory.decisionPrompt(input: LLMDecisionInput)` with `responseMimeType: application/json`.
  - Parse first candidate text; attempt strict JSON decode; on failure, run a single compact `repairPrompt` and re‑decode; otherwise error with `AppDomainError.invalidLLMJSON`.
- **Examples**: `TatoebaExamplesProvider` fetches and maps examples (best effort, capped at 3), labeled with provenance.
- **Glossary**: `FakeGlossaryProvider` stubbed for MVP; influences decision inputs and conflict detection.
- **Metrics**: `MetricsProvider` interface; `translate_assistApp.swift` wires a metrics provider stub for event tracking.

### 9) Orchestration flow (runtime)
1. User opens popover and enters text (or selection arrives via Services).
2. `OrchestrationVM` starts a `TranslationService.translate(...)` stream.
3. Stage 1 — MT: Cached MT lookup; if miss, `GoogleTranslationProvider` call via `RateLimitScheduler`. Yield `.mt` and log `mt_ok`.
4. Stage 2 — LLM Decision: Build `LLMDecisionInput` (includes persona, domain priority, candidates, glossary hits). If offline, finalize MT‑only immediately.
   - Primary LLM call via provider adapter; if error (rate‑limit/timeouts/server), degrade to MT‑only with banner and schedule a single auto‑retry after cooldown.
   - Glossary conflict detection yields a banner; optional escalation path runs a raw enhancer and stores under an `escalated` cache tag.
   - Yield `.decision` upon success.
5. Stage 3 — Finalize: Choose `rewrite` (if provided) or MT candidate at `topIndex`; compute alternatives and explanation; yield `.final` and log `llm_ok`.
6. Stage 4 — Examples: Fetch examples asynchronously; yield `.examples` and finish.

### 10) Caching strategy
- **Keys** (`Storage/CacheService.swift`):
  - MT key: `v1|mt|src:...|dst:fa|term:...|ctx:contextHash` → SHA‑256
  - LLM key: `v1|llm|src:...|dst:fa|term:...|ctx:contextHash|persona:hash|mt:hashOfCandidates` (+ `|tag:escalated` when escalation used)
- **TTL**: Per entry TTL; enforcement on reads controlled by `Constants.cacheEnforceTtlOnReads`; periodic eviction and pruning scheduled on app start and timers.
- **Decoration**: Cached providers wrap base providers; MT writes use detected source for a stable key.

### 11) UI/UX specifics
- `MenubarPopoverView`:
  - Header with app label; banners are overlaid.
  - Multiline input; auto focus; offline banner if disconnected.
  - Persona segmented picker and domain toggles drive re‑requests.
  - Translate/Retry/Save/Clear actions; keyboard shortcuts applied.
  - Primary translation card with confidence dot and percentage; alternatives disclosure; explanation text; examples list with provenance.
  - Term detail disclosure for saved senses/examples; history (last 5); reviews due list; footer shows current hotkey.
- `SettingsView`:
  - Global hotkey selector.
  - Import Senses CSV / Termbank JSONL.
- App menubar menu provides exports for terms, senses, examples, and termbank JSONL.

### 12) Configuration & secrets
- `Config/SecretsLoader.swift` sources:
  - `GEMINI_API_KEY`, `GOOGLE_TRANSLATE_API_KEY`
  - `GEMMA3_MODEL_ID` (default `gemma-3-12b`), `GEMINI_MODEL_ID` (default `gemini-2.5-flash-lite`)
- `Config/RateLimitConfig.swift` defaults (env‑overridable): per‑provider RPM/TPM/RPD for Gemma, Gemini, and Google Translate.
- Keys are not stored in repo; loaded from `Secrets.plist` with env overrides.

### 13) Logging, metrics, and performance
- `os.Logger` at boundaries (network, scheduler, menubar, translation service).
- `os_signpost` spans: `stage.mt`, `stage.llm`, `stage.finalize`, `stage.examples`, `network.request`.
- Metrics events (local only in MVP): `mt_ok`, `llm_ok`, `llm_fallback`, `llm_auto_recover_ok`, `llm_auto_recover_fail`, `cache_hit_mt`, `cache_put_mt`, `cache_hit_llm`, `cache_put_llm`, etc.
- Latency budgets per PRD: first MT ≤800ms P95; LLM ≤400ms P95; cache first paint ≤300ms.

### 14) Testing (current coverage)
- `Tests/LLMJSONValidatorTests.swift` — Decoding valid decision JSON; repair prompt contains schema and broken payload.
- `Tests/CacheServiceTests.swift`, `Tests/CacheEvictionTests.swift` — MT/LLM cache reads/writes, TTL enforcement, pruning.
- `Tests/RateLimitSchedulerTests.swift` (+ backoff/circuit tests) — Token refill, backoff, headers handling, circuits.
- `Tests/LLMFallbackTests.swift` — Verifies fallback to MT‑only + banners under LLM errors.
- `Tests/GoldSetSmokeTests.swift` / `GoldSetSubsetTests.swift` — Basic smoke across seed terms; compares MT‑only vs MT+LLM.
- `UITests/MenubarSmokeUITests.swift` — Popover open, input focus, basic flows (hooked via `-UITestOpenPopover`).

### 15) Security & privacy
- Keys loaded locally; no secrets in repo or logs (masked when necessary).
- Data stays local except requests to MT/LLM/examples endpoints.
- No clipboard source identification in MVP; no remote telemetry.

### 16) Accessibility & RTL
- RTL layout verified in previews; mixed LTR/RTL text rendering considered.
- VoiceOver labels present for interactive elements; keyboard navigation supported.

### 17) Build & distribution
- Build with Xcode 15+; targets macOS 13+.
- Distribution: Developer ID–signed, notarized DMG (no in‑app updates in MVP).

### 18) Roadmap highlights
- v0.1 (MVP): Current scope; stabilize latency and resilience; finalize persona presets; gold set evaluation.
- v0.2: Persona editor, glossary lock and conflict UI, improved examples; consider update mechanism.
- v0.3: OCR, multi‑engine compare, browser extension exploration.

### 19) How to run (developer)
1. Create `translate assist/Secrets.plist` (or set env vars) with `GEMINI_API_KEY` and `GOOGLE_TRANSLATE_API_KEY`. Optionally set `GEMMA3_MODEL_ID` / `GEMINI_MODEL_ID` and rate‑limit envs.
2. Open the Xcode project and run on macOS 13+.
3. On first launch: DB migrations run; caches prune scheduled; reachability monitor starts; hotkeys registered.
4. Use Services (or menubar) to send selection; or paste text into the popover input.
5. Exports accessible via status menu; imports via Settings.

### 20) Known limitations & next steps
- Examples rely on Tatoeba public API (best effort); license attribution in About; may be rate‑limited.
- Glossary is a stub; real glossary provider and biasing needed for production use.
- Escalation currently uses a separate cache tag but the same Google LLM adapter by default; consider larger model option (within Google AI Studio) for difficult cases.
- Sparkle updates are not integrated in MVP; revisit after stabilization.

---

This report reflects the current code in the repository and the updated PMR/PRD decisions to standardize on Google AI Studio LLMs and Google MT. The system is modular and resilient by design, with strict JSON validation, strong caching, rate‑limit awareness, and UI that remains responsive while progressively revealing results.



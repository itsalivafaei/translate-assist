## Menubar Translator — Planning v2

Sources: `proj_docs/translate_assist_prd_v_0.md` (PRD), `proj_docs/translate_assist_product_management_requirements_pmr_v_0.md` (PMR), `proj_docs/planning_v_1.md` (v1), current code (providers, scheduler, storage, UI).

### Executive summary (delta vs v1)
- **LLM contract**: The app uses a single-step `LLMDecision` (decision | top_index | rewrite | explanation | confidence | warnings) which matches the engineering rules’ strict JSON schema and consolidates PRD’s rerank/rewrite/explain. We keep this unified step.
- **Providers**: Current adapters target Google Translate (MT) and Google AI Studio models (`Gemma 3` and `Gemini 2.5 Flash‑Lite`). We standardize on Google AI Studio for MVP and remove Groq from scope.
- **Rate limiting**: Token‑bucket scheduler for RPM/TPM/RPD is implemented; honors 429/503 with backoff and a 60s circuit breaker, leveraging parsed rate‑limit headers.
- **Pipeline**: MT → LLM decision → finalize → examples, streaming updates (`AsyncStream`) and non‑blocking UI, with MT‑only fallback on any LLM failure.
- **Storage**: GRDB schema v1 matches plan (termbank, examples, SRS, caches, metrics) plus v2 input history. TTL caches and periodic maintenance exist.
- **UI shell**: Menubar popover with input, persona presets, domain chips, banners, history, SRS hooks, exports. Audio/TTS is hidden per MVP.

### Affected modules (for v2 scope)
- `Providers/` — `GoogleTranslationProvider`, `GeminiLLMProvider`, `GemmaLLMProvider`, cache decorators, `PromptFactory`.
- `Services/` — `TranslationService` orchestration and `ExamplesService` (Tatoeba provider).
- `Scheduler/` — `RateLimitScheduler` + headers‑aware backoff/circuit.
- `Networking/` — `NetworkClient` structured logs and rate‑limit hints.
- `Storage/` — schema v1/v2, DAOs, `CacheService`, metrics, export/import.
- `ViewModels/` + `translate_assistApp.swift` — popover shell, controls, streaming, banners.

### Decisions locked
- **LLM vendor policy**: Google AI Studio only. **Primary** `Gemma 3 12B`; **fallback** `Gemini 2.5 Flash‑Lite`.
- **Escalation model**: Use `Gemini 2.5 Flash‑Lite` as the raw enhancer for low confidence (<0.65) or glossary conflicts (separate LLM cache tag `escalated`).
- **Examples provider**: Keep both Tatoeba API and LLM‑generated examples; label provenance clearly (`"tatoeba"` vs `"llm"`).
- **Persona presets**: Seed from `proj_docs/personas.json`.
- **Gold set**: Use `proj_docs/gold_set_menubar_translator_v0.csv`.
- **Distribution**: Ship notarized DMG and publish on GitHub Releases (no Sparkle in MVP).

### Target architecture (confirmed)
- **UI**: SwiftUI in `NSPopover` via `NSStatusItem`. Views thin; VMs own logic; closing popover cancels tasks.
- **Services**: `TranslationService` streams MT first, LLM decision next, then examples; MT‑only fallback on invalid JSON or rate‑limit/circuit events.
- **Providers**: Protocol‑oriented adapters; caches via decorators. Centralized `PromptFactory`; one‑shot JSON repair on invalid outputs.
- **Storage**: GRDB/SQLite single DB; deterministic migrations; TTL caches; metrics; export/import.
- **Networking**: `URLSession` with per‑request timeouts, request IDs; structured logs; rate‑limit hints.
- **Scheduling**: Token‑bucket for RPM/TPM/RPD; exponential backoff; 60s circuit breaker with persistence; proactive offline banners.

### Data contracts (v2)
- `LLMDecisionInput { term, src, dst:"fa", context?, persona?, domainPriority:[String], candidates:[{text,pos?,ipa?,provenance}], glossaryHits:[{term,domain?,canonical,note?}] }`
- `LLMDecision { version:"1.0", decision:"mt"|"rewrite"|"reject", topIndex:Int, rewrite:String?, explanation:String, confidence:Double, warnings:[String] }`
- Cache keys: MT `(term, contextHash, src→fa)`; LLM `(term, contextHash, personaHash, mtHash)`; escalations use a distinct provider tag to avoid collisions.

### Phased plan (v2)

#### Phase A — LLM policy alignment and adapters
- Keep `GemmaLLMProvider` (primary) and `GeminiLLMProvider` (fallback) — Google AI Studio only.
- `ProvidersBootstrap`: default `primary = gemma`; allow switching to `gemini` via config if regionally better.
- `RateLimitConfig`: quotas via env for both Gemma and Gemini; LLM cache keys include model id when relevant.
- Acceptance: LLM decisions ≤400ms P95; MT‑only fallback on invalid JSON; on confidence <0.65 or glossary conflict, escalate using raw `Gemini 2.5 Flash‑Lite` and store under `escalated` tag.

#### Phase B — Prompt & validator hardening
- Keep unified decision step; ensure `PromptFactory.decisionPrompt` reflects schema and persona/domain fields.
- Improve repair prompt minimalism and add strict length guards. Unit tests: valid decode, repair path, reject path.
- Acceptance: 100% of happy‑path outputs decode; invalid → repaired once; otherwise MT‑only + banner; no crashes.

#### Phase C — Scheduler & resilience polish
- Honor `retry-after` and `x-ratelimit-*` across providers; verify circuit persistence between launches; add small burst buffer.
- Add global FIFO priority for popover actions if contention observed.
- Acceptance: chaos tests for 429/503/timeouts show graceful degrade to MT‑only; auto‑recovery after cooldown; UI remains responsive.

#### Phase D — UI polish & accessibility
- Bind confidence dot and domain badge; ensure RTL rendering and VoiceOver labels across controls.
- Add copy buttons and subtle alternates disclosure animations; keep audio controls hidden for MVP.
- Acceptance: keyboard navigation complete; RTL verified; banners distinct (offline, rate‑limited, JSON invalid).

#### Phase E — Storage, personas & exports finalization
- Confirm monthly VACUUM and TTL eviction cadence; cap cache rows.
- Load persona presets from `proj_docs/personas.json` at runtime (seed defaults); persist future edits (editor deferred).
- Validate CSV/JSONL exports for UTF‑8; import flows resilient to malformed rows.
- Acceptance: save ≤50ms; export/import pass sample datasets; DB migrations idempotent; persona presets loaded.

#### Phase F — Tests & gold set
- Unit: providers (fake + real), prompt validator, caches, scheduler, persona logic, SRS math; provenance labeling for examples (tatoeba vs llm).
- UI: selection → popover → save; toggles; error banners; RTL.
- Gold set: use `proj_docs/gold_set_menubar_translator_v0.csv` (100 items). Log MT‑only vs MT+LLM wins; record P50/P95.
- Acceptance: tests green; ≥80% “Right meaning”; latency budgets met; examples show correct provenance.

#### Phase G — Packaging & release
- Scripted pipeline `scripts/package_release.sh`: Build → Sign (Developer ID) → DMG → Notarize (notarytool) → Staple.
- GitHub release: attach notarized `TranslateAssist.dmg`, include changelog and SHA‑256 checksum.
- Acceptance: DMG passes Gatekeeper; download + open on a clean macOS 13+ host; app launches and hotkey works.

### Risks & mitigations
- **Provider policy drift (Google models)**: Keep adapters swappable (Gemma/Gemini); separate cache tags by model id; environment‑based selection.
- **JSON drift**: Strict decoder + one repair; otherwise MT‑only with banner.
- **Quota spikes**: Token‑bucket + backoff + circuit breaker; proactive offline path.
- **RTL & punctuation**: Dedicated tests for mixed LTR/RTL numerals; semantic attributes in UI.

### Acceptance criteria (MVP, reaffirmed)
- First visible MT ≤800ms (P95); cache first paint ≤300ms.
- LLM enhancement visible ≤400ms after MT (P95).
- MT‑only fallback on invalid JSON or 429/503 with clear banner; auto‑recover after cooldown.
- Single DB persists termbank, examples, caches, metrics; export/import works.
- Accessibility & RTL verified; crash‑free ≥99% in testing; previews compile with mocks.

### Configuration & keys (v2)
- LLM (Google): `GEMMA3_MODEL_ID` (default `gemma-3-12b`), `GEMINI_MODEL_ID` (default `gemini-2.5-flash-lite`), `GEMINI_API_KEY`.
- MT: `GOOGLE_TRANSLATE_API_KEY`, `GOOGLE_TRANSLATE_RPM`, `GOOGLE_TRANSLATE_CPM`, `GOOGLE_TRANSLATE_CPD`.
- Shared: `REQUEST_TIMEOUT_MS`, `CACHE_MT_TTL_S`, `CACHE_LLM_TTL_S`, `CIRCUIT_BREAKER_COOLDOWN_MS`.
- Packaging (local env or CI): notarytool credentials (`--notary-profile` or Apple ID + app‑specific password), Developer ID team ID.

### Next steps (pending answers to questions)
1) Confirm default Google AI Studio model (Gemma vs Gemini) for MVP; tune quotas and scheduler constants accordingly.
2) Finalize persona preset JSON and domain defaults; seed into UI.
3) Confirm examples source (Tatoeba vs LLM) and licensing note for About.
4) Provide gold set and expected senses; wire evaluation test.

Owner: You (engineering). Please review the clarifying questions and confirm the LLM vendor policy and examples source so we can lock Phase A.



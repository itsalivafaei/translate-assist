# Translate Assist (macOS menubar app)

Phase 0 bootstrap per `proj_docs/planning_v_1.md`.

## Build
- Xcode 15+, macOS 13+
- Open `translate assist.xcodeproj` and build the `translate assist` target

## Config
- Create or edit `translate assist/Secrets.plist` with keys:
  - `GEMINI_API_KEY`
  - `GOOGLE_TRANSLATE_API_KEY`
  - `GEMMA3_MODEL_ID` (default `gemma-3-12b`)
  - `GEMINI_MODEL_ID` (default `gemini-2.5-flash-lite`)
- Optional env overrides (Product → Scheme → Run → Arguments → Environment):
  - `REQUEST_TIMEOUT_MS`, `SCHEDULER_BURST_SIZE`, `CIRCUIT_BREAKER_COOLDOWN_MS`
  - `CACHE_MT_TTL_S`, `CACHE_LLM_TTL_S`
  - `GEMMA3_RPM`, `GEMMA3_TPM`, `GEMMA3_RPD`
  - `GEMINI_RPM`, `GEMINI_TPM`, `GEMINI_RPD`
  - `GOOGLE_TRANSLATE_RPM`, `GOOGLE_TRANSLATE_CPM`, `GOOGLE_TRANSLATE_CPD`

## Status
- Menubar `NSStatusItem` with `NSPopover` hosting SwiftUI is implemented
- Config scaffolding, rate limit config, and secrets loader are in place

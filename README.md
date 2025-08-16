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

## Distribution (Developer ID, Notarized DMG)

1) Prepare certificates and notary profile
- Install a "Developer ID Application" certificate in your login keychain.
- Configure `notarytool` either with a keychain profile or Apple ID + app-specific password.

2) Build, sign, notarize
```bash
chmod +x scripts/package_release.sh
scripts/package_release.sh \
  --scheme "translate assist" \
  --config Release \
  --team-id 597KGSTZWJ \
  --bundle-id com.klewrsolutions.translate-assist \
  --notary-profile AC_NOTARY
```

The script archives, exports a signed app, creates a DMG (uses `create-dmg` if installed), submits for notarization, and staples the ticket. Output DMG is in `build/dmg/TranslateAssist.dmg`.

3) Test
- On a second Mac, double‑click the DMG and drag the app to Applications. Gatekeeper should show "verified developer" with no warnings.

## About & Attributions
- "About Translate Assist" in the status menu opens an About window with attributions for Wiktionary, Tatoeba, Google Cloud Translation, and SF Symbols.

## CI (optional)
- GitHub Actions workflow `.github/workflows/release.yml` can build and notarize on macOS runners. Configure secrets:
  - `APPLE_TEAM_ID`, `AC_USERNAME` (Apple ID), `AC_PASSWORD` (app‑specific password)

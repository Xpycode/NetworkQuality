# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## Template

### [Date] - [Decision Title]
**Context:** [What situation prompted this decision?]
**Options Considered:**
1. [Option A] - [pros/cons]
2. [Option B] - [pros/cons]

**Decision:** [What we chose]
**Rationale:** [Why we chose it]
**Consequences:** [What this means going forward]

---

## Decisions

### 2026-04-14 — Lazy network-interface loading via `.task` on SettingsView

**Context:** Cold launch on M4 Pro MacBook Pro took 3–5 seconds — unusually slow for a lightweight SwiftUI app. Traced to `NetworkQualityViewModel.init()` calling a synchronous `getAvailableInterfaces()` that wrapped async work behind `DispatchSemaphore.wait(timeout: 5)`. The spawned `Task` inherited `@MainActor` isolation, couldn't make progress while the main thread was blocked by the semaphore, and the wait always hit its 5-second timeout before returning the fallback interface list. Classic MainActor self-deadlock.

**Options Considered:**

1. **Lazy load via `.task` on the consuming view (chosen).** Drop the sync wrapper entirely, expose only `async getAvailableInterfaces()`, remove the init-time call, and attach `.task { await viewModel.loadInterfaces() }` to the SettingsView branch (the sole consumer).
   - *Pros:* Zero work at launch; structured concurrency auto-cancels if the view disappears mid-load; matches idiomatic SwiftUI patterns.
   - *Cons:* Picker populates ~50–100ms after Settings opens instead of being pre-loaded. Acceptable because the default selection is `""` ("Default") which doesn't depend on the fetched list.

2. **Keep sync API, run the subprocess directly (no Task, no semaphore).** `ifconfig -l` returns in <10ms so direct blocking of main would be imperceptible.
   - *Pros:* Preserves the sync API signature.
   - *Cons:* Still blocks MainActor during init (even if briefly); doesn't fix the underlying antipattern; interface list still loads for every launch even though Settings is rarely opened.

3. **Eager load via `Task { await ... }` in init (fire-and-forget).**
   - *Pros:* List ready before user opens Settings.
   - *Cons:* Unstructured Task leaks if the ViewModel is deallocated mid-load; still pays `ifconfig` cost on every launch; offers no meaningful benefit over `.task` since Settings is the only consumer.

**Decision:** Option 1 — lazy load via `.task` on SettingsView.

**Rationale:**
- `availableInterfaces` is read only inside `SettingsView` (verified via grep: sole consumer at `Views/SettingsView.swift:83`). Eager loading costs launch time for data that's rarely displayed.
- `.task` participates in structured concurrency — SwiftUI owns the Task lifetime and auto-cancels on view disappear. No leaks, no manual cancellation bookkeeping.
- Fix is small (3 files, ~15 lines changed) and eliminates the antipattern cleanly rather than patching around it.
- Apple's current guidance (and the Swift forums consensus) treats `DispatchSemaphore.wait` from `@MainActor` code as a well-known antipattern; the async-then-`.task` shape is the idiomatic replacement.

**Consequences:**
- Cold launch drops from 3–5s to ~197ms on M4 Pro (verified via 3 timing samples).
- `NetworkQualityViewModel.init()` no longer performs any network-adjacent work — pure Combine subscription setup.
- Users opening Settings see the picker briefly populate "Default" only, then fill in ~50–100ms later. Acceptable because the default selection doesn't depend on the list.
- Pattern captured in the cross-project cookbook at `0-DIRECTIONS/docs/cookbook/19-swift6-concurrency.md` §2 so future apps avoid the same trap.
- Pre-existing concern remains out of scope: `Process.waitUntilExit()` inside `AppleNetworkQualityRunner.getAvailableInterfaces()` blocks a cooperative-pool thread. Acceptable for `ifconfig -l` (<10ms); revisit if it surfaces in hotter paths.

### 2026-07-12 — Next release is v1.1.0; unreleased v1.0.3 retired

**Context:** The project file said 1.0.3 (bumped 2026-04-15 for the App Shell migration) and a 1.0.3 DMG existed in `APP/`, but it was built *before* the 2026-05-29 Connection Info feature suite landed on `main` — so the artifact was stale, the CHANGELOG stopped at 1.0.2, and the new features rode unbumped under a number that was never released. Three-way mismatch between public state (1.0.2), project file (1.0.3), and actual code.

**Options Considered:**

1. **Bump to 1.1.0 (chosen).** One fresh release carrying both unreleased feature sets.
   - *Pros:* Semver-honest — a new diagnostics suite plus a UI overhaul is minor-version scope, not a patch. No ambiguity with the stale DMG.
   - *Cons:* Retires a version number that was already stamped into a built (but unshipped) artifact.
2. **Keep 1.0.3.** Zero renumbering churn.
   - *Cons:* Understates scope; two different binaries would exist claiming 1.0.3.
3. **Bump to 1.0.4.** Avoids artifact ambiguity.
   - *Cons:* Patch number signals "fixes only" — misleading for a feature release.

**Decision:** v1.1.0 (build 1100), following the `1.0.3 → 1030` build-number convention.

**Consequences:**
- v1.0.3 never ships; its App Shell work is folded into the v1.1.0 CHANGELOG entry (noted there).
- The stale `APP/NetworkQuality-v1.0.3/NetworkQuality-1.0.3.dmg` must not be notarized/distributed — archive or delete it.
- Release path: rebuild → notarize → tag `v1.1.0` → fresh screenshots. Dark-mode color audit still pending pre-release.

### 2026-07-12 — Sparkle auto-updates adopted for v1.1.0

**Context:** `/check ship` found no update mechanism — the one bucket-2 gap needing a project decision. Every DMG-distributed user is otherwise stranded on whatever version they downloaded.

**Decision:** Sparkle ≥ 2.8.1 via SPM, following the house pattern (cookbook #16, CropBatch as reference): `UpdateController` in Services/, "Check for Updates..." under About in the app menu, `SUEnableAutomaticChecks` on, appcast served from `https://raw.githubusercontent.com/Xpycode/NetworkQuality/main/appcast.xml`.

**Key handling:** Per-app EdDSA key pair, generated into this Mac's Keychain under account `NetworkQuality`; private key exported to `99-AUTH/networkquality-sparkle-private.key` (Keychain doesn't sync — the file is the cross-Mac source). Public key lives in the partial `Info.plist` (custom `SU*` keys must go there, not in `INFOPLIST_KEY_*` build settings, which silently drop them).

**Consequences:**
- Release flow gains one step: `sign_update -f <99-AUTH key> <DMG>`, then fill `sparkle:edSignature` + `length` into `appcast.xml` and push (placeholders are in the file, with the process documented in a comment).
- DMGs must be uploaded as GitHub release assets (`releases/download/v.../NetworkQuality-X.X.X.dmg`) — that's where the appcast enclosure points.
- v1.1.0 is the *first* Sparkle-enabled release: existing 1.0.x users still need one manual download; auto-update kicks in from 1.1.0 onward.
- Build numbers must stay monotonic (Sparkle compares `sparkle:version` = build number, not the marketing version).

---
*Add decisions as they are made. Future-you will thank present-you.*

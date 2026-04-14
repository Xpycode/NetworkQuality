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

---
*Add decisions as they are made. Future-you will thank present-you.*

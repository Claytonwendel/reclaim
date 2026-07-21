# Reclaim — Storage Research Findings (July 2026)

Source: 105-agent deep-research sweep, claims adversarially verified (2-of-3
vote to kill). This file records what survived verification, what got refuted,
and what's still open — so the recipe library grows on evidence, not guesses.

## Architectural findings (built into the scanner)

### APFS space accounting — there is no single "free space" number
- macOS counts snapshot-occupied space as **available** yet no file-level scan
  can see it. Finder / System Settings / `df` / `du` legitimately disagree.
  *(Apple 102154; DaisyDisk guide; Eclectic Light — all verified 3-0.)*
- **Snapshot pinning:** deleting a big file frees nothing while a snapshot
  still references its blocks — the space becomes "purgeable," released only
  when the snapshot dies. **macOS does NOT reliably purge purgeable space.**
  → *Implication, now in code:* verification must never treat "space didn't
  free" as recipe failure while snapshots exist. `SnapshotProbe` surfaces this.
- **Sparse files** (Docker.raw, VM disks): apparent size ≫ real allocation.
  → *In code:* the scanner reports allocated size and flags the sparse illusion.
- **Refuted (do not assume):** that snapshots self-purge reliably (0-3); that
  purgeable can grow to 80% of disk (0-3). Do not design around auto-purge.

### DataVault / SIP hard boundary
- `UF_DATAVAULT` blocks even root **with** Full Disk Access from some system
  stores. Sealed System Volume is read-only since Big Sur. *(Verified 3-0.)*
  → *In code:* "Operation not permitted" is reported as skipped, never fought.
- **Refuted:** the specific path list (TCC.db, keychains) offered as DataVault
  examples (0-3). Build the protected-path list empirically, version-tagged.

## Verified recipe intelligence (primary vendor docs)

| Category | Key fact | Safe method |
|---|---|---|
| **Docker Desktop** | One sparse `Docker.raw`; space freed only by deleting images; the Settings shrink slider **destroys all containers/images** | `docker system prune` — never the slider |
| **Parallels** | `.pvm` never shrinks from guest-side deletion | File → Free Up Disk Space wizard; TRIM-on-shutdown |
| **Ollama** | Models in hidden `~/.ollama/models`, 4–70 GB each | `ollama rm`; relocate via `OLLAMA_MODELS` |

## Competitive / safety intelligence
- Intego Washing Machine X9 cleared ~24 GB on an M2 MBP (single anecdote).
- **Nektony App Cleaner** once flagged the **App Store** for removal and deleted
  Adobe CC files in testing (fixed ~Apr 2025). → orphan detection needs a
  system-bundle allowlist + verify the owning app is truly gone before flagging.
- **Refuted:** MacCleaner Pro's 11.4/65.4 GB yield figures (0-3).

## Confidence tiers in the catalog
- `.verified` — case study or primary vendor docs. May earn automated actions.
- `.communityKnown` — well-known path, **detection-only** until empirically
  verified on real machines during concierge cleanups.

## OPEN QUESTIONS — need a second research pass or empirical validation
These did NOT survive verification and remain unsourced:

1. **In-the-wild size distributions** per category (iOS backups, Photos caches,
   Adobe media cache, browser profiles). The GB×prevalence prioritization the
   library needs is still unquantified. → collect from concierge cleanups.
2. **"System Data" composition** — what actually inflates it on macOS 13–26 and
   the reliable diagnosis workflow. Research Q6 produced no surviving claims.
3. **Exact DataVault-protected paths** on current macOS — build empirically.
4. **Competitor category matrices** — how CleanMyMac / DaisyDisk / Pearcleaner /
   DevCleaner partition cleanup, and what users report as missed or dangerous.
   Only 2 competitor data points survived.

## Second research pass — System Data (July 2026, partial)
This pass hit the org's monthly API spend limit mid-run; synthesis was skipped.
8 claims survived verification before it stopped. Net: it mostly **confirmed**
existing coverage rather than adding new paths.

**Verified:**
- **System Data = snapshots + system/user caches + app data + disk images +
  browser plugins + logs + temp files.** Almost all already have recipes; the
  category is opaque because these live in many places, not one. *(3-0)*
- Time Machine: hourly local snapshots, kept 24h + one of last backup until
  space needed; macOS counts snapshot space as available and auto-deletes with
  age/pressure — but NOT reliably (see pass 1). *(3-0, already in SnapshotProbe)*
- `tmutil deletelocalsnapshots <name>` removes one snapshot; `tmutil
  thinlocalsnapshots / <bytes> <urgency>` thins to reclaim a target. *(2-0/2-1)*
- Real-world magnitudes (one reviewer's Mac): 43 GB Xcode simulators, 34 GB iOS
  backup surfaced as System Data — both already have recipes. *(3-0)*
- **Refuted:** "System Data is normally ~20 GB and harmless" (0-3) — there is no
  reliable normal baseline; don't anchor UX to a number.

**Still open (spend limit cut it short):** full contributor size distributions,
extreme-case root causes (200 GB+/800 GB+ System Data), the competitor category
matrix, Spotlight-corruption and Safe-Mode-purge diagnosis workflows. Re-run
when the spend limit resets (Aug 1) or is raised.

**Product takeaway:** "System Data" is not one thing to clean — it's the sum of
what Reclaim already scans (snapshots, caches, app data, disk images, backups,
logs). The right UX is to *explain* it: attribute the opaque number to the real
recipes/orphans/snapshots that compose it. That's the sweep's job, extended.

## Detection heuristics still to design (the judgment layer)
- "Personal but probably deletable": old screen recordings, forgotten video
  exports, backups of devices no longer owned, duplicate photo exports.
- Orphan detection: leftover app state whose owning app is truly absent
  (with a system-bundle allowlist to avoid the Nektony failure mode).

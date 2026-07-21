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

## Detection heuristics still to design (the judgment layer)
- "Personal but probably deletable": old screen recordings, forgotten video
  exports, backups of devices no longer owned, duplicate photo exports.
- Orphan detection: leftover app state whose owning app is truly absent
  (with a system-bundle allowlist to avoid the Nektony failure mode).

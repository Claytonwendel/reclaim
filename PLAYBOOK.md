# Reclaim — Concierge Cleanup Playbook (Phase 0)

The operator guide for running guided Mac cleanups with the `reclaim` CLI.
Goal: 10 real cleanups, median >10 GB verified recovery, **zero** important-data
incidents (decision gate #1).

## The workflow is the product

Every session follows the same sequence. Never skip a step, never reorder:

1. **Baseline scan** — capture ground truth before anything else.
2. **Classify** — walk the findings with the user, tier by tier.
3. **Intent check** — confirm what tools/projects are still active.
4. **Act** — safest supported method only, Green tier first.
5. **Verify** — rescan and measure the real free-space delta.
6. **Ledger** — record everything: sizes, actions, skips, failures.

## 1. Baseline

```sh
# Free space ground truth (writable data volume)
df -h /System/Volumes/Data

# Reclaim read-only scan — human report + JSON ledger entry
reclaim scan
reclaim scan --json > ~/reclaim-sessions/$(date +%Y%m%d)-baseline.json
```

Record: volume free bytes, total findings, recoverable-now number.

## 2. Classify & 3. Intent check

Walk the report top-down. For every finding ask the user:

- "Do you still use <app/tool>?" (unused app state may move tiers)
- "Are you actively developing with <Xcode/npm/Swift>?" (keep SPM cache if yes —
  case-study precedent)
- For Yellow: "Do you need old <conversations/sessions/devices>?"
- For Orange: **always** explain cloud-sync consequences before anything else.
  Messages attachments may propagate deletions via iCloud.

Hard rules (from the master plan, non-negotiable):

- 🔴 Red tier: never touch. Simulator runtimes go through
  `xcrun simctl runtime` only.
- 🟠 Orange tier: user selects items explicitly; operator never chooses.
- `Operation not permitted` = **skipped**, full stop. Not a challenge.
- Never delete inside `.photoslibrary` bundles.
- Never delete the live `state.vscdb` (Cursor chat history).
- Active repos and source code are off the table entirely.

## 4. Act — supported methods per finding

| Finding | Method |
|---|---|
| npm cache | `npm cache clean --force` (falls back to Trash if ownership issues) |
| Homebrew | `brew cleanup --dry-run` first, then `brew cleanup` |
| Simulator runtimes | `xcrun simctl runtime list` → `xcrun simctl runtime delete <id>` |
| Stale simulator devices | `xcrun simctl delete unavailable` |
| Everything file-based | Move to `~/.Trash` (reversible) — never `rm -rf` directly |

Before any action: quit the owning app (the scan report flags this with ⏸).
Check again after quitting — some apps respawn helpers.

## 5. Verify

```sh
df -h /System/Volumes/Data          # free-space delta
reclaim scan                        # targets should be gone or shrunk
reclaim scan --json > ~/reclaim-sessions/$(date +%Y%m%d)-after.json
```

"Command returned no output" is not verification. The rescan is.

## 6. Ledger

Append one row per session to `~/reclaim-sessions/LEDGER.md`:

| Date | Machine | Free before | Free after | Verified Δ | Actions | Skips/failures | Incidents |
|---|---|---|---|---|---|---|---|

Also record anything the recipes *missed* — every gap is a new recipe candidate.

## Session boundaries

- One session ≤ 90 minutes. Fatigue causes mistakes.
- If the user hesitates on any item, skip it. There is always more Green.
- End every session by emptying nothing: Trash stays full for 24h minimum
  unless the user explicitly empties it themselves.

# Persistent Passive Growth Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement the tasks in order with tests and one final independent review.

**Goal:** Add permanently rolled tiers and offline passive growth while preserving existing drawings and keeping mature fish inside the tank.

**Architecture:** A small shared growth module supplies the approved balance and pure time-based calculations. The shared model owns new versioned metadata, compatibility readers, atomic migration and size-aware geometry. The app initializes metadata once and displays progress; wallpaper rendering remains read-only.

**Tech Stack:** Existing Goose standard library, gfx/ui, binary serialization and Windows build tooling. No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-07-passive-growth-design.md` (user-approved balance and offline behavior).

## Global Constraints

- Baby width 48 px; adult widths 80/112/152/208/280/400 px.
- Tier odds E/D/C/B/A/S = 40/28/18/9/4/1 percent; assign once using OS-seeded standard RNG.
- Maturity 2/6/18 hours, 3/7/30 days; growth continues while closed.
- Back up both legacy formats before atomic upgrade; keep drawings, empty aquariums and existing swim behavior.
- Editor owns migration and writes; wallpaper reads metadata and never assigns tiers.
- Keep the Windows GUI subsystem and shortcut. Do not commit or discard the existing session's changes.

## Review Focus

- Corrupt or invalid growth metadata must be rejected without altering the file (Task 1).
- Failed backup/save must not expose an unpersisted tier or alter drawings (Task 1).
- Old saves, including empty reefs, must migrate without adding a starter (Tasks 1–2).
- Mature S fish must fit, remain selectable and drag correctly after resizing (Task 2).
- Multiple renderers must derive the same age without double-counting, and restart must preserve the roll (Tasks 1–3).

### Task 1: Growth calculations and persistent metadata

**Files:** Create `reef_growth.goose`; modify `reef_model.goose`, `reef_test.goose`.

**Interfaces:** Pure `tier_from_roll(roll: i64) -> i64`, `growth_progress(tier: i64, born: f64, now: f64) -> f64`, `growth_width(tier: i64, born: f64, now: f64) -> f32`; metadata `Creature.tier: i64 = -1`, `Creature.born: f64 = 0.0`; preserve explicit v1/v2 record types; new `DREEF003` header. `upgrade_growth(reef: Creature[>..]&, save_path: const u8[:], original: const u8[:], now: f64, random: rng&) -> bool` stages rolls, backs up old bytes, and publishes metadata only after a successful atomic write.

- [x] Add tests that currently fail for all 100 roll outcomes, each tier's age-zero/midpoint/mature widths, offline elapsed time, and clamped negative age.
- [x] Implement the approved table and ease-out size calculation in the new module.
- [x] Add v1/v2 fixtures, new metadata round trips, invalid tier/timestamp fixtures, empty saves, and failed migration checks.
- [x] Implement compatibility readers and atomic staged migration; successful upgrades retain fixed metadata on reopen.
- [x] Run the model checks and confirm all cases pass.

### Task 2: App integration and size-aware aquarium

**Files:** Modify `reef_model.goose`, `doodle_reef.goose`, `reef_test.goose`, `reef_ui_test.goose`.

**Interfaces:** `creature_area`, `move_creature` and `pick_creature` share size-aware geometry. Keep the existing call signatures usable; allow a deterministic time argument where needed by tests. The app rolls metadata for successful new releases and performs one-time editor migration at load. `growth_progress` and tier labels feed the existing status area.

- [x] Add tests for mature S fitting and dragging in normal, small and resized windows; preserve baby sizing and artwork proportions.
- [x] Derive current width from metadata, cap rendered bounds to available tank space, and share the inverse vertical mapping with dragging.
- [x] Initialize/persist first-run starter, loaded legacy creatures and newly released drawings. On failure retain the existing save and disable saving with a clear message.
- [x] Keep legacy wallpaper views as babies until editor migration; reload new metadata without writing or rerolling.
- [x] Show selected tier and growth percentage in the status area; keep existing failure messages and buttons usable.
- [x] Update persistence/UI fixtures to valid metadata and run the complete model/UI checks.

### Task 3: Review, packaging and documentation

**Files:** Update `README.md` and this plan's progress ledger; rebuild existing Windows artifacts.

- [x] Review the complete change independently for migration failures, tier rerolls, fitting, time calculations and wallpaper ownership; resolve material findings with regression checks.
- [x] Document approved balance, offline growth, migration backups, existing-fish behavior, selected-fish status and old-renderer compatibility.
- [x] Run `build.ps1`, `git diff --check`, and a bounded offscreen run against isolated data; verify the GUI subsystem and shortcut remain correct.
- [x] Report tested behavior and unverified Linux/attached-wallpaper runtime honestly.

## Execution decisions

Implement inline in the existing workspace, preserving all prior uncommitted session work. These tasks share serialization and geometry interfaces, so separate implementation worktrees would obscure the state the user is actively running. Do not create commits or touch real user saves during tests. Keep the execution ledger under `.test-data/growth-progress.md`, which is already ignored.

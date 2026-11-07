# Persistent passive fish growth — approved design

## Intent

Keep the current tiny 48-pixel baby fish, then let each one grow toward a lucky, tier-dependent adult size. Growth continues while the editor and wallpaper are closed, as the user confirmed. Feeding is deferred at the user's request; this iteration is passive growth only.

## Proposed balance

The user approved these balance values on 2026-11-07.

| Tier | Roll probability | Adult width | Time to adulthood |
| --- | ---: | ---: | ---: |
| E | 40% | 80 px | 2 hours |
| D | 28% | 112 px | 6 hours |
| C | 18% | 152 px | 18 hours |
| B | 9% | 208 px | 3 days |
| A | 4% | 280 px | 7 days |
| S | 1% | 400 px | 30 days |

Every fish starts at 48 pixels regardless of tier or drawing dimensions. A tier describes maximum growth potential and remains fixed. Roll from 100 equally likely outcomes using the installed standard-library RNG seeded with OS entropy; reserve exactly one outcome for S. Save the result once, rather than rolling again on restart or wallpaper reload.

## Approaches

- **Recommended: saved tier and UTC birth time.** Compute growth from elapsed real time. This supports offline growth and lets the editor and read-only wallpaper derive the same result without adding elapsed time twice. The user selected growth while closed.
- **Active-time accumulation.** Would require periodic progress writes and coordination between editor and wallpaper. It excludes offline progress and does not fit the user's selected behavior.

## Growth and presentation

Normalize elapsed age by the tier's maturity time, clamp to 0–1, and use an ease-out curve, `p * (2 - p)`, to interpolate baby width to adult width. Growth is continuous, starts visibly, and slows toward the exact maximum. Negative elapsed time is clamped to zero. This local game does not add clock-tampering protection.

Treat adult widths as reference sizes. Limit rendered size to fit inside the current aquarium with margins for bobbing and rotation. Derive the swimming vertical range from creature size so a mature S fish remains clear of controls and tank edges. Rendering caps must not overwrite tier or age: resizing the window must not erase growth. Keep selection, dragging, wrapping, pitch and fills aligned with the rendered size.

Selecting a fish shows its tier and growth progress in the existing aquarium status area. No new panels, feeding controls, growth boosts, naming system, inventory or growth animations are included.

## Persistence and migration

Introduce a new versioned save layout with tier and birth time alongside the existing creature data. Keep explicit readers for both existing save layouts. Preserve artwork, positions, facing, base speed, and empty aquariums. Existing creatures start as babies at migration and receive one permanent tier each.

Back up the original legacy bytes before upgrading, then atomically persist the assigned tiers and birth times. A failed backup or save must preserve the original and explain the failure; never repeatedly reroll creatures silently. The first-run starter also needs its metadata saved. The wallpaper remains read-only and consumes the upgraded metadata. Old wallpaper binaries must be updated alongside the editor.

Builder's migration decision after the design check: until an editor upgrades a legacy save, the wallpaper shows those creatures as 48-pixel babies and reports the need for a one-time editor launch to its diagnostic stream. It never invents tiers or writes the save.

Validate tier values, finite timestamps, creature limits and drawing data at the file boundary. Corrupt saves remain preserved and saving stays disabled as in the current application. No cloud service or new dependency is needed.

## Reach and verification

Update the shared model/serialization, application creation/load paths, size and dragging calculations, selected-fish status, persistence fixtures, relevant UI checks and README. Keep Windows and Linux behavior in shared Goose code.

Tests should cover all 100 tier-roll outcomes and the exact 1% S allocation; birth, intermediate growth and mature caps for each tier; offline progress; fixed tiers across save/reload; both legacy migrations and empty saves; corrupt metadata and failed backups/writes; mature fish fitting and dragging across window sizes; and unchanged artwork, swimming and GUI behavior.

Run model and offscreen UI checks, rebuild the Windows GUI executable and wallpaper package, and retain the console-free shortcut. Linux and attached desktop wallpaper require separate runtime verification when available.

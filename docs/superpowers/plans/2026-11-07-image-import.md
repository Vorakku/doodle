# Image Import Implementation Plan

**Goal:** Import a transparent PNG as a persistent named, growing, animated fish.
**Spec:** `docs/superpowers/specs/2026-11-07-image-import-design.md` (as-is import selected by user).
**Execution:** Inline in the existing workspace; preserve prior session changes and real user saves. No new runtime dependency.

- [x] Add bounded file IO and pure image data helpers with tests: PNG signature/chunk/dimension limits; transparent visible crop; alpha-aware area resize; checked immutable RGBA assets.
- [x] Add DREEF005 image ID/flip metadata, explicit v4 reader and backup, artwork validation and flip rollback tests. Preserve names/tier/born exactly.
- [x] Add native asynchronous SDL PNG dialog with callback-owned storage and a test-only result queue. Keep model-only tests independent of graphics/SDL.
- [x] Implement cached source textures, mip generation and offscreen mesh poses using the existing body projection; test alpha and turn rendering.
- [x] Add studio Import/preview/clear/preserve flow and reuse required naming/save/retry. Atomically save an asset before its record, cleaning only a failed new asset. Test valid, canceled, invalid and save-failure paths.
- [x] Keep image metadata on missing assets, support flip and read-only wallpaper reload, and release GPU resources before shutdown.
- [x] Independently review integration and migration risks. Update Linux portable-data seeding and README. Run model/UI tests, isolated renderer/GUI checks and build artifacts; inspect image and dialog UI. Do not modify `build/data` during tests.

**Status 2026-11-07:** Windows verified, including the native file dialog. Linux build and launcher changes are syntax-checked only; they have not been built or run on Linux.

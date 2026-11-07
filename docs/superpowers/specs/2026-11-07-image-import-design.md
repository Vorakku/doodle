# Transparent image fish

The user requested image import and explicitly selected importing images as-is rather than drawing over them.

## Flow

Add Import to the studio beside Bring to Life. Start with an empty canvas: disable import while drawing/redo history exists and explain that Clear is needed. A native SDL file dialog selects one PNG. Cancel, invalid input or an unavailable dialog preserves the current draft. A valid image appears in the checkerboard canvas; zoom/pan, Clear, Back and the existing naming prompt continue to work. Drawing tools remain inactive for image drafts. No tracing, background removal or painting on imports.

The name prompt and save retry retain the image draft. Only successful save releases the image fish and clears the draft. Imported fish receive the same permanent tier, birth time, baby size, growth and swimming behavior as drawn fish.

## Input and assets

Accept PNG files only, with visible pixels and at least some transparency. Reject opaque backgrounds and wholly invisible images with a clear message. Bound source files to 16 MiB and dimensions to 4096 per side before decoding. Decode with the existing bundled gfx PNG loader, using a bounded, validated snapshot to avoid source-file races. Trim transparent outer padding and normalize to at most 512 pixels per side, retaining aspect ratio and alpha with area resampling.

Keep the exact original PNG at `data/images/<numeric-id>.png` and normalized RGBA rendering art at `data/images/<numeric-id>.rgba` with a small checked header. This resolves the builder review's original-pixel-preservation question without asking the user to accept destructive resizing. A native bounded-file reader prevents oversized allocations. Write both assets atomically before referencing them in the reef save. On failure remove only new uncommitted assets and keep the draft. Keep assets on fish deletion because backups can still reference them. The source PNG can later be moved or deleted.

## Rendering and persistence

Use a small textured mesh rendered to a cached offscreen target, then composite it through the existing UI layer. Reuse the current body-point projection for turns, pitch and body wave. Premultiply before mip generation and unpremultiply the pose output so normal UI blending preserves soft transparent edges. Cache source and pose textures per fish; release resources before gfx shutdown and when a slot changes.

Add an image asset ID and artwork flip to Creature, introducing DREEF005 with explicit DREEF004 compatibility. Preserve all existing names, tiers, birth times, positions and strokes and back up v4 bytes before upgrade. Image fish have no stroke points; reject invalid mixed/empty artwork records. Wallpaper remains read-only and loads assets relative to its selected data directory. Missing/corrupt assets render a visible placeholder and keep metadata, rather than losing the aquarium.

Copy the images directory when the Linux launcher first seeds a portable Windows save. Existing desktop packaging already points to the shared data directory; document keeping the whole data folder and updating old renderers.

## Verification

Test PNG/header and asset bounds, alpha/crop/resampling, artwork validation, v4 migration without changing growth or names, image flip rollback, asset-save failure, real image preview/naming/save/reopen, cancel/invalid import, source-file deletion, alpha rendering and turns, missing assets, and ordinary drawing regressions. Use a test-only dialog result injection for offscreen UI tests and inspect a native file dialog where available. Rebuild the console-free Windows executable and Lively package. Report unverified Linux and desktop attachment honestly.

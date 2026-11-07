# Required fish names and smaller babies

The user's request is to require a name when Bring to Life is pressed and reduce the size of newborn fish further. Implement inline in the existing workspace, preserving all earlier changes.

- [x] Reduce the shared baby width from 48 to 24 pixels, preserving approved adult widths, odds, durations and birth timestamps. Verify all tiers start equally small.
- [x] Validate and persist a trimmed, nonblank UTF-8 name of at most 32 code points. Keep explicit v1/v2/v3 readers and back up before upgrading to v4; preserve existing tiers, birth times and artwork. Give existing unnamed fish stable placeholder names.
- [x] Bring to Life opens a focused naming prompt. Blank/invalid names cannot release. Cancel/Escape preserves the canvas; a failed save preserves both drawing and typed name for retry. Confirm commits artwork, name and growth metadata together.
- [x] Display the saved name beside tier/growth, and correct the old studio sizing hint.
- [x] Test naming validation/roundtrip, v3 migration without rerolling/resetting growth, blank blocking, cancel/retry and successful named release. Adapt visual landmarks and drag offsets to the smaller fish; run model/UI checks and inspect screenshots.
- [x] Independently review save/UI risks, rebuild Windows GUI artifacts, verify isolated startup and keep real user saves untouched until editor launch.

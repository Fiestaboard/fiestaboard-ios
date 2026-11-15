# I4 renderer reconciliation and readable viewport

Approved source: PHASE-5-IOS-PLAN.md r3 §2.2 I4 and §2.4; tvOS source pinned to `f1fc67d`.

1. Add failing viewport, whole-point geometry and DD24 tests, then preserve that RED commit.
2. Reconcile renderer by the §2.4 manifest, preserving phone public APIs. Add canonical matrix sources and exact resources; record source and adapted hashes in VENDORED.json. Keep phone editor types.
3. Build the reusable fixed-bezel viewport, retaining 13 pt flap tiles and scrolling, with per-Note paging, partial Notes and accessible Next/Previous actions. LED content uses its own raster path.
4. Run Render, Kit, Documents, EditorState and AppState tests; compile native test bundles; run all repository/token/parity/license guards and archive exclusion check. Native rendering, FPS draw budget and editor UI tests execute on hosted tier-1 devices if CoreSimulator is inaccessible locally.
5. Independent gpt-6-astra review, maximum three rounds; normal integration from I3, normal push and stacked draft PR. Never merge.

The adapter manifest records the phone-only palette/loading/step/stretch behavior. SF/system UI waivers do not waive board geometry. The viewport is a kit in I4; I6/I7 and I13 consume it when rebuilding screens. Card thumbnails retain the owner's DD-W25 exemption.

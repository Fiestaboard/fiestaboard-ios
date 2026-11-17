# iOS native parity reporter

This CLI implements the report-only Figma comparison in Phase 5 §2.1. It does
not replace the blocking snapshot golden, device size/scale, registry/AX,
structural board or token checks.

```sh
npm ci --prefix scripts/parity
npm test --prefix scripts/parity
node scripts/parity/native-parity.mjs --shots build/parity --out build/parity/report
# Only when a real saved Figma export is available:
node scripts/parity/native-parity.mjs --refs /local/saved-figma-exports --shots build/parity
```

The exact Light Connecting screen and its Still connecting sibling are vendored
under `figma/`, byte-for-byte from the design-agent exports. Run the seed report
with:

```sh
node scripts/parity/native-parity.mjs --refs scripts/parity/figma --shots build/parity --out build/parity/report
```

`ios-connecting` maps the specification column `362:20090` to its screen instance
`362:19966` (402×874 pt, scale 3). The screenshot includes Figma's bezel corner
pixels; it is never stretched, cropped further or recoloured by this reporter.
The sibling `362:20111` PNG is retained as reference evidence for the 5 s state;
it is not claimed as an implemented or captured state in I2.

Dark has **no reference**: `ios-connecting-dark` emits `status: "no-reference"`
and `wouldPass: null`. A Light PNG is never substituted. Without `--refs`, the
CLI still reports reference unavailability. A missing native capture produces
`missing-shot`; none of these results constitutes Figma MATCH.

Reference rectangles are transcribed from `figma/figma-connecting-362-20090.md`.
`seed:*` IDs are explicitly local measurement keys, not claimed Figma node IDs:
the export does not provide inner-node IDs. The root uses the real spec-column
ID. The native registry must measure each tagged view; tests must not copy these
reference coordinates into an alleged capture. Synthetic red/blue PNGs in unit
tests exercise only the comparer.

Inputs:

- `figma-refs.json`: entries with an ID, kind, Figma root ID and geometry/text
  probe IDs. Use a separate ID for each device and appearance capture.
- `<shots>/<id>.png`: the native screenshot, with `<id>.probes.json` containing
  `{ "schema": 1, "ref": "<id>", "root": "<figma id>", "scale": 3,
  "nodes": [{ "figma": "<id>", "rect": { "x": 0, "y": 0, "width": 402,
  "height": 874 } }] }`. Rectangles are root-relative points; scale must be
  measured (phone 3, iPad 2). Optional node `text` supplies text probes.
- Optional `<shots>/runtime.json`: `osVersion`, `runtimeBuild`, `deviceModel`,
  `scale` and `goldenDirectory` identify the capture runtime in the report.
- Local refs directory: `refs.json` with a `refs` array. Each ref needs `id`,
  `figmaNode`, `mode`, `slotWidth`, `slotHeight`; specify its actual export
  `scale` and `file` path, plus `nodes` for geometry/text. No network fetching.

Native screenshots are box-filtered to the reference scale only for a positive
integer scale ratio. Missing scale, unsupported ratios and partial pixel blocks
are unavailable, never silently resized or cropped. Compared screenshots, refs,
diffs, `report.json` and `report.md` are written to `--out`.

Findings exit 0, including unavailable evidence and visual differences. Bad
arguments, malformed JSON and invalid input exit 2. `--gate` is unsupported.

`VENDORED.json` records the exact tvOS source commit and original file hashes.
`native-parity.mjs` additionally pins the original FiestaUI comparator commit;
`parity.mjs` is byte-identical and its SHA-256 is checked by the suite. The iOS
adapter adds measured scale, explicit unavailable results and runtime reporting.

## Explicit reference artifacts (I2)

The static UIHosting capture contains app views, so it cannot draw the system
status bar, Dynamic Island or home indicator. The saved Figma screen also
includes black outside the 55pt device corner clip. `artifactMasks` in the
manifest lists exactly those regions, in points, with reasons from the saved
measurement document. No title, connecting content, skeleton or tab region is
masked. SF Pro vs Inter and native tab-glass noise remain plan waivers, not masks.

The original `checks.pixel`, `wouldPass`, PNG and diff are unchanged. A separate
`artifactAdjustedPixel` reports the excluded union, visible-pixel denominator,
remaining ratio and blobs; its diff has an `artifact-adjusted` suffix. It uses
the same 2.5% screen limit and large-blob rule. A low ratio can still fail the
blob rule. Neither result replaces visual review or proves system glass.

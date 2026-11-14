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

Without `--refs`, every manifest entry has `status: "missing-reference"` and
`wouldPass: null`. Missing reference entries or PNGs are also unavailable.
No screenshot is generated or substituted for a reference. The Connecting seed
(`ios-connecting`, Figma `362:20090`) implementation is intentionally deferred
until a standalone reference exists; its manifest entry still emits an
unavailable report. The 791×1400 section composite at
`/Volumes/ExtHD/fiestaboard-universal-design/shots/mobile-09a/01-launch.png`
is qualitative context only, not a pixel reference or a source for cropping a
replacement. Synthetic red/blue PNGs in unit tests exercise the comparer only.

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

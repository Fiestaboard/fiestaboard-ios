# MG4 export notes: platform-ios.json (2026-11-14)

Read-only export from Figma file `ZQ8RMELCO6qEOFZUnQu36e` using the Plugin API via the Figma MCP. The file was not modified.

## What was found
- **`Platform · Glass`** = `VariableCollectionId:7:2` (key `fb221ded…692b`), local, **2 modes: `Light` (7:0, default) and `Dark` (7:1)**, **20 COLOR variables**: `glass/*` ×10, `tint/*` ×7, `board/edge-fade{,-clear}`, `ios/switch-thumb`.
- **No aliases.** Every value in both modes is a raw RGBA, so there was nothing to resolve. `alias: null` is recorded for each token.
- There were no ambiguous modes or values.

## Touch metrics
- `Mobile / Button` (392:72582): 7 iOS variants (brand, default, secondary, outline, ghost, destructive, link), each with a fixed height of **44** and a width that hugs the label. Android variants are 48. The nested library component is `FiestaUI Button / Size=lg`, radius `radius/md` = 8.
- `Mobile / Icon Button` (395:153837): 6 iOS variants, each fixed at **44×44**. Android variants are 48×48. The nested component is `FiestaUI Icon Button / Size=icon-lg`.
- These sizes are **fixed frame sizes, not variable bindings**. They agree with `Platform · Metrics/touch/min-ios = 44` (VariableID:7:26), which is exported as `touch.ios.min-target`.

## Related data deliberately left out of the JSON (exported here for I3)
The glass recipe's blur and shadow geometry lives in **effect styles**, not in the variable collection. Their colours are bound to the Glass variables:

| Style | Drop shadow (colour `glass/shadow`) | Inner shadow 1 (`glass/specular`) | Inner shadow 2 (`glass/edge-bottom`) | Background blur |
|---|---|---|---|---|
| `Platform/Glass/Regular`: pair with `glass/fill` and stroke style `Platform/Glass/Edge` | y 8, radius 28, spread 0 | y 1.5, radius 0.5 | y −1, radius 2 | 16 |
| `Platform/Glass/Sheet`: pair with `glass/fill-thick` | y −2, radius 40 | y 1.5, radius 0.5 | y −1, radius 2 | 30 |
| `Platform/Glass/Control`: for 44 pt buttons and the Display switcher | y 4, radius 14 | y 1.5, radius 0.5 | y −1, radius 2 | 10 |

- `Platform/Glass/Edge` is a stroke style. `get_variable_defs` reports it with an empty value. The rendered tab-bar capsule (09a) shows a 1 px `glass/edge-top` stroke.
- `Platform · Metrics` (VariableCollectionId:7:11, 27 FLOATs, one mode `Value`) also holds the iOS radii (`ios/radius/sheet` 34, `ios/radius/card` 26, `glass-control` and `tab-bar` 9999), safe areas (`safe/ios-top` 62, `safe/ios-bottom` 34, iPad 24/20) and margins (`ios/margin/compact` 16, `regular` 20). Only `touch/min-ios` was exported, because MG4 scopes the Glass collection plus touch metrics. If the owner wants more, add these in a follow-up export.
- The generator (`scripts/tokens/generate-swift.mjs`) currently reads only `platform-tv.json`. I3 must add `platform-ios.json` as an input. Colours use the same `{colorSpace, components, alpha, hex}` shape as `fiestaui-tokens.json` (where `hex` ignores alpha), split into `glass.light` and `glass.dark` groups.

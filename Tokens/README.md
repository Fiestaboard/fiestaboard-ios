# iOS token bridge (I3)

`fiestaui-tokens.json` is exactly `package/dist/tokens.json` from npm
`@fiestaboard/ui@8.17.0-alpha.2` (the owner-approved version supersedes the plan's
alpha.0). `platform-ios.json` is the unchanged MG4 Figma export from
`program/exports/ios/platform-ios.json`. SHA-256 pins live in the generator and
are embedded in generated Swift. The generator retains full input component
precision; hex strings intentionally ignore alpha.

Ported from the tvOS `scripts/tokens/generate-swift.mjs` precedent. Generated
Foundation-only values live in FiestaBoardRender so board code and app UI share
one source. `BoardColor` reads the generated board group; codes 70 and 71 both
map to its reflected black (#1a1a1a).

Regenerate: `node scripts/tokens/generate-swift.mjs`.
Verify: `node --test scripts/tokens/tests/*.test.mjs` and
`node scripts/tokens/generate-swift.mjs --check` (both blocking CI guards).

Glass effect geometry is separate from the colour-variable JSON. The unchanged
[MG4 notes](MG4-NOTES.md) preserve the exported effect styles:

| Effect style | Drop shadow (glass/shadow) | Inner shadow (glass/specular) | Inner shadow (glass/edge-bottom) | Background blur |
|---|---|---|---|---|
| Platform/Glass/Regular | y 8, radius 28, spread 0 | y 1.5, radius 0.5 | y −1, radius 2 | 16 |
| Platform/Glass/Sheet | y −2, radius 40 | y 1.5, radius 0.5 | y −1, radius 2 | 30 |
| Platform/Glass/Control | y 4, radius 14 | y 1.5, radius 0.5 | y −1, radius 2 | 10 |

Regular pairs with glass/fill and Platform/Glass/Edge; Sheet with
 glass/fill-thick; Control is for 44pt controls. The rendered capsule uses a 1px
 glass/edge-top stroke. These effect styles are documentation, not additional
 variables invented in the MG4 export. Native Liquid Glass implementation is a
 later view slice.

`TokenBridgeTests` probes structural codes; `TokenSentinelTests` re-renders
 generated pigments at both tier-one scales and samples their sRGB centers.
 This is a token rendering regression check; it makes no Figma screenshot
 equivalence claim.

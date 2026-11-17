# Figma reference: 09a Connecting (362:20090) and Still connecting (362:20239)

These are Light-mode references (no explicit variable modes on the instances, so they use the collection defaults: Light). Exported 2026-11-14 from file `ZQ8RMELCO6qEOFZUnQu36e`, page `09a · Mobile · Account, More & global states` › Section · Launch and connecting › Row · Apple. The data comes from `get_design_context`, `get_variable_defs` and a read-only Plugin API pass.

## Files (all PNG at 3×)
| File | Node | Size | Notes |
|---|---|---|---|
| `figma-connecting-362-20090@3x.png` | 362:20090 spec column (430×1418) | 1290×4254 | Step label + device + 2 annotations |
| `figma-still-connecting-362-20239@3x.png` | 362:20239 spec column (430×1211), the paired 5 s state | 1290×3633 | Step label + device + 1 annotation |
| `figma-connecting-device-362-19966@3x.png` | 362:19966 device instance | 1272×2754 | Clipped by the parent column on the left; right and bottom include the 10 pt bezel and Shadow/lg |
| `figma-still-connecting-device-362-20111@3x.png` | 362:20111 device instance | 1272×2754 | As above |
| **`figma-connecting-screen-362-19966@3x.png`** | 362:19966 screen | **1206×2622 = 402×874 @3×** | Cropped from the device PNG at px (0,36). **Use this one for the I2 seed parity.** The corners show the 55 pt bezel radius as black. |
| `figma-still-connecting-screen-362-20111@3x.png` | 362:20111 screen | 1206×2622 | Same crop |

SHA-256: column 20090 `456c9022…f58f`, column 20239 `fe2d4ba6…863f`, screen 19966 `4ee86337…3e07`, screen 20111 `5944141d…d1086`.

## Device frame (Device / Apple, iPhone)
- The screen is **402×874 pt**. The bezel is a 10 pt OUTSIDE stroke in `color-board-bezel-dark` #050505, with corner radius 55 and Shadow/lg (0,10 r15 s−3 and 0,4 r6 s−4, #0000001A).
- Status bar: 0,0 at 402×62; padding l52 r30 t21; "9:41" uses iOS/Status. The Dynamic Island is at 138,11, 126×37, r18.5.
- Home indicator: 129,861, 144×5, r3, `foreground`.
- Safe areas are 62 top and 34 bottom, with a compact margin of 16.

## 362:19966 Connecting: key frames (pt, relative to the screen)
| Element | Frame (x,y,w,h) | Style |
|---|---|---|
| iOS / Nav bar | 0,62,402,105 | Has no background. The scroll-edge gradient runs from y −62 to 129 (191 tall): `glass/scroll-edge` #f1ece6 at 94% → same at 65% → `glass/scroll-edge-clear` (0%) |
| Large title row "Home" | 0,116,402,51 (pad t2 b8 h16) | iOS/Large Title: Inter Bold 34/41, +0.4, `foreground` #0f0d0a |
| Content | 0,167,402,738 | VStack gap 16, pad t8 h16 b200 |
| Connecting row | 16,175,246,20 | HStack gap 10, pl4 |
| ↳ Spinner (FiestaUI sm, taco sprite) | 20,178,14,14 | static frame |
| ↳ "Connecting to Maya's FiestaPi…" | 44,175,218,20 | iOS/Subheadline: Inter Regular 15/20, −0.23, `muted-foreground` #4a4744 |
| Skeleton · board | 16,211,370,150 | `accent` #ece6df, `radius-md` 8 |
| Skeleton | 16,377,220,18 | same |
| Skeleton | 16,411,300,18 | same |
| Skeleton | 16,445,160,44 | same |
| Skeleton ×3 | 16,505 / 577 / 649, 370×56 | same |
| iOS / Tab bar (glass capsule) | 16,776,370,64 | pad 4; radius `ios/radius/tab-bar` 9999; fill `glass/fill` #ffffff66 + background blur; 1 px stroke `glass/edge-top` #ffffffd9; Platform/Glass/Regular (shadow `glass/shadow` #0f0d0829 0,8 r28; inner `glass/specular` 0,1.5 r0.5; inner `glass/edge-bottom` 0,−1 r2; blur 16) |
| ↳ Tab items ×5 (Home selected) | 54 tall, equal width (flex) | Selected fill `tint/selected` #fcedd5, r9999. Icon 24, gap 1. Label iOS/Tab label: Inter Semi Bold 10/12, +0.1. Selected label `brand` #895700, others `foreground` |

Screen background is `background` #f1ece6.

## 362:20111 Still connecting (5 s): differences
- The Connecting row is replaced by a **Mobile / Banner (Platform=iOS, Tone=Info)** at 16,175,370,86. It has radius 18, padding 12/14, gap 12, fill `component/alert/info-bg` (= `color-mix(info 8%)` #0064b514) and a stroke of `status/info` #0064b5. The 20 pt info icon is at 15,33 within the banner. Show action = false.
  - Title "Still connecting to Maya's FiestaPi" at 63,188 (308×22) uses iOS/Headline: Inter Semi Bold 17/22, −0.43, `foreground`.
  - Detail "fiestapi.local is slow to answer. Hubs can take a minute after a restart." at 63,212 (308×36) uses iOS/Footnote: Inter Regular 13/18, −0.08, `muted-foreground`.
- The skeletons shift down by 66: board 16,277,370,150; then 443 (220×18), 477 (300×18), 511 (160×44), and 571/643/715 (370×56).
- The nav bar, large title, tab bar and status bar are the same as in 19966.

## Annotations (spec text, not product UI)
- 20090 COLD START: "Saved hub, no cached snapshot: skeletons in the shape of the board, Now showing and Up next. With a snapshot under 10 min old, show it dimmed with 'Updating…' instead. Compose stays disabled until connected."
- 20090 NATIVE: "Launch storyboard is the plain background; the large title appears at once. Tab bar is live so Pages and More open from cache."
- 20239 has one annotation (see its PNG).

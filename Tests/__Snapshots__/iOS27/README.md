I0b renderer regression seed, iOS 27.2, fixed scale 2/light appearance.
Missing baseline intentionally fails and attaches template-chip-iOS27.png.
Retrieve the actual XCTest attachment, inspect it, and commit as template-chip.png.
No Figma parity approval is implied. I2 owns full screen/geometry/probe coverage.

Recorded from `GoldenSeedTests.testTemplateChipGolden` on iPhone 17 / iOS 27.2,
Xcode 27.2 (27B52), GitHub Actions run 43558234835 at commit d6c3731.
That run failed with GOLDEN_RECORD_REQUIRED as designed, retained the attachment,
and passed the Release archive/probe guard. Baseline copied byte-for-byte from
its XCTest attachment after visual inspection (red tile and purple variable chip).

I2 framework baselines live under `ParityFoundationTests/`: Light/Dark at
Large and AX3, phone402×874 @3 (1206×2622px) and pad1180×820 @2
(2360×1640px). These are deterministic7:41 framework fixtures, not the
Connecting Figma screen or a visual parity approval.

Recorded on Xcode27.2 / iOS27.2 build24B8117 in run43625623343 at013a818.
Both device jobs failed with exactly four missing-reference assertions as
designed; other app tests and all88 renderer tests passed on each device.
Copied byte-for-byte from native-units-iphone artifact14126827189 and
native-units-ipad artifact14126649147 after inspecting all8 PNGs.
Actual iPad screen bounds were portrait820×1180; configured static renders
are landscape1180×820. The UI proof separately rotates the real screen.

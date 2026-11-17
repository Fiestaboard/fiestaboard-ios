I0b renderer regression seed, iOS 27.2, fixed scale 2/light appearance.
Missing baseline intentionally fails and attaches template-chip-iOS27.png.
Retrieve the actual XCTest attachment, inspect it, and commit as template-chip.png.
No Figma parity approval is implied. I2 owns full screen/geometry/probe coverage.

Recorded from `GoldenSeedTests.testTemplateChipGolden` on iPhone 17 / iOS 27.2,
Xcode 27.2 (27B52), GitHub Actions run 43558234835 at commit d6c3731.
That run failed with GOLDEN_RECORD_REQUIRED as designed, retained the attachment,
and passed the Release archive/probe guard. Baseline copied byte-for-byte from
its XCTest attachment after visual inspection (red tile and purple variable chip).

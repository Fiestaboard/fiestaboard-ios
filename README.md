# FiestaBoard iOS

Native SwiftUI controller for FiestaBoard on iPhone, iPhone Duo, and iPad.

The design is approved and the first contract foundation is implemented: a source-grounded parity inventory, pinned public/internal API schemas, isolated authentication checks, and separate integrity/release-readiness gates. Swift application code has not been implemented yet.

- [Design and scope](docs/superpowers/specs/2026-10-25-fiestaboard-ios-design.md)
- [Implementation plan](docs/superpowers/plans/2026-10-25-fiestaboard-ios.md)
- [Source and Apple guidance](docs/research/2026-10-25-ui-api-audit.md)
- [Astra review and incorporated corrections](docs/research/2026-10-25-astra-review.md)
- [Full web feature-parity inventory](docs/parity.md)
- [Mobile API compatibility policy](docs/contracts.md)
- [Contract foundation verification](docs/research/2026-10-25-foundation-verification.md)
- [Run the isolated checks](Tests/Integration/README.md)

First-release requirement: complete web-app feature parity, adapted to native interaction and supported window sizes/poses. Implementation uses GPT-6.1 Sol subagents; GPT-6 Astra reviews architecture, milestones, and release readiness.

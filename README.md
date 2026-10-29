# FiestaBoard iOS

Native SwiftUI controller for FiestaBoard on iPhone and iPad, with layouts driven by available window space.

A native development draft is available with Home, Library, Displays, Settings, a simulated demo, manual connection/sign-in, board previews, text/page actions, board configuration/restore controls, on-device page drafts with recovery and undo, conditional page saves on compatible servers, explicit template validation/previews, and native Collections editing with durable recovery. It uses adaptive SwiftUI navigation and system Liquid Glass. Full web-app parity remains the first-release requirement; this draft is not a release candidate. Automatic discovery, remembered sign-in and consistent current-server board-control support are the next end-to-end milestone.

Open [FiestaBoard.xcodeproj](FiestaBoard.xcodeproj), choose the **FiestaBoard** scheme and an iPhone or iPad simulator, then Run. The shared scheme starts in demo mode. See the [testing guide](docs/draft-testing.md) for live connection, device signing, resizing checks, and current limits.

```sh
scripts/build-draft.sh simulator
```

The contract foundation includes a source-grounded parity inventory, pinned public/internal API schemas, isolated authentication checks, and separate integrity/release-readiness gates.

- [Design and scope](docs/superpowers/specs/2026-10-25-fiestaboard-ios-design.md)
- [Complete end-to-end acceptance checklist](docs/native-parity-checklist.md)
- [Current parity-completion design](docs/superpowers/specs/2026-10-28-native-parity-completion-design.md)
- [Current wave/task execution plan](docs/superpowers/plans/2026-10-28-native-parity-completion.md)
- [Implementation plan](docs/superpowers/plans/2026-10-25-fiestaboard-ios.md)
- [Source and Apple guidance](docs/research/2026-10-25-ui-api-audit.md)
- [Astra review and incorporated corrections](docs/research/2026-10-25-astra-review.md)
- [Full web feature-parity inventory](docs/parity.md)
- [Mobile API compatibility policy](docs/contracts.md)
- [Contract foundation verification](docs/research/2026-10-25-foundation-verification.md)
- [Run the isolated checks](Tests/Integration/README.md)
- [Run and test the native draft](docs/draft-testing.md)
- [Native draft verification and limits](docs/research/2026-10-25-draft-verification.md)
- [Controls and local-editor verification](docs/research/2026-10-25-parity-wave-1-verification.md)
- [Page saving and preview verification](docs/research/2026-10-26-page-editing-verification.md)
- [Collections verification and remaining runtime checks](docs/research/2026-10-27-native-collections-verification.md)
- [Remaining tasks and current work](TASKS.md)

First-release requirement: complete web-app feature parity, adapted to native interaction and supported window sizes/poses. GPT-6.1 Sol agents coordinate implementation and tests, with Claude Opus CLI requested for bounded parallel tasks when available. Current CLI authentication limits are recorded in the task tracker. GPT-6 Astra independently reviews architecture, integrated milestones, and release readiness.

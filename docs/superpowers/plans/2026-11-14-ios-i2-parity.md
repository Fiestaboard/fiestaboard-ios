# I2 parity foundation implementation plan

> Execute with the executing-plans skill; independent reporter implementation and final review use isolated agents.

**Goal:** reusable iOS snapshot, geometry and glass evidence under approved Phase5 I2.
**Architecture:** port the pinned tvOS probe tools; DEBUG-only isolated fixtures avoid network and persisted state. Static snapshots use test-only SnapshotTesting1.19.7. Real glass uses XCUIScreen.
**Spec:** /Volumes/ExtHD/fiestaboard-universal-design/program/PHASE-5-IOS-PLAN.md §2.1/I2.

## Constraints
Only new universal/i2-parity branch; never modify PR1–3 branches. iOS26 floor. Internal disk build output, serial devices. Goldens per iOS major. Figma comparison report-only, never substitute a fake reference.

## Review focus
Missing reference must remain unavailable. Missing golden must fail. Release contains no probes. Screen scale is measured rather than assumed. Geometry export must be checked against accessibility frames.

## Tasks
- [ ] Add failing app tests for sorted/root-relative registry output, missing root, actual device size/scale, deterministic clock, snapshot dimensions and light/dark output; port glass negative controls. Add UI tests for real screenshot glass and registry frames.
- [ ] Pin test-only dependency in project.yml; port registry/modifier and test support. Add DEBUG parity fixture with responsive striped panel and a static Connecting seed explicitly uncalibrated until reference exists. Regenerate project.
- [ ] Reporter helper ports pinned comparer with tests and missing-reference report; integrate commit.
- [ ] Run host/tooling/contract checks, compile simulator test bundle, attempt local runtime, archive/probe guard. Record missing baseline failure and collect actual CI goldens, then rerun comparison. Review all changes, push normally, open own stacked PR and observe CI.

## Decisions
Jev selected I1 base p0.74 vs I0b: overlapping test/project changes make I1 the lower-rework base. Existing vocabulary guard/seed stay. Structural-board and token sentinel tests follow actual renderer/token work in I4/I3.

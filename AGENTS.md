# iOS build hygiene (Phase 5, K8 / K15)

Use `scripts/test.sh` for host and simulator suites and `scripts/build-draft.sh` for builds.
All DerivedData, SwiftPM build/cache and Clang cache output must stay under
`~/Library/Developer/FiestaBoard/ios` on the internal disk. Never reuse October
`derived-*` or `swiftpm-*` directories on ExtHD. Use the default CoreSimulator set.
Tier 1 is iPhone 17 and iPad Air 11-inch (M4), both iOS 27.2; deployment floor is iOS 26.
Run simulator tests serially. Do not claim K8 closed until both devices have a green
app-hosted and UI run. The Phase 5 plan lives in the universal-design program hub.

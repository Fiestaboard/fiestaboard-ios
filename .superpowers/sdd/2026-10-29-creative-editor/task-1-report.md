# Task 1 report

Implemented atomic template insert/remove/move/duplicate and alignment/wrap in PageDocument and DocumentEditingSession. Empty [] templates are editable. Metadata travels with rows, duplicate copies exact metadata, insertion defaults metadata only if already materialized, and absent/null stays unchanged until explicit formatting. Existing unsupported known alignment/wrap guards remain.

LocalPageEditorModel exposes the requested methods, uses existing frozen-state mutation guards, invalidates preview/validation, includes metadata-only dirty state, and creates sparse patches from actual changes with the original baseline revision. Complete structural templates replace the fixed-line restriction; an empty template must gain a row before server save. Unsupported recovered top-level changes and unsupported metadata clears remain blocked.

PageSavePatch accepts validated raw lineMetadataData and serializedData() splices it into an ordinary encoded envelope without number conversion. Object arrays, syntax, trailing commas, and duplicate object keys are checked. Existing name/template Encodable clients remain supported; metadata-bearing patches explicitly require serializedData(). The live adapter uses this serializer. Demo storage applies raw member slices and preserves exact metadata through subsequent name-only saves. No live API requests or credentials were used.

Source contract audited: docs/research/2026-10-29-editor-source-contracts.md confirms variable row counts and sparse line_metadata PUT under the existing revision contract.

TDD: new structural/model/patch tests first failed on absent APIs. Metadata malformed-input coverage then exposed JSONDecoder accepting trailing commas; explicit lexical rejection fixed it. One existing fixed-slot test became obsolete; its recovered fixture now includes unsupported canvases to retain the partial-save protection assertion. Early full Documents run encountered the concurrent, not-yet-implemented TemplateSyntax; final runs include it and pass.

Final verification, all full suites, 2026-10-29:
- swift test --package-path Packages/FiestaBoardDocuments --scratch-path /tmp/fb-structure-docs: 33 passed, 0 failures.
- swift test --package-path Packages/FiestaBoardEditorState --scratch-path /tmp/fb-structure-editor: 53 passed, 0 failures.
- swift test --package-path Packages/FiestaBoardKit --scratch-path /tmp/fb-structure-kit: 141 passed, 0 failures.

Coverage includes row metadata/numeric identity, atomic unsupported-shape rejection, undo/redo and recovery, nil/null preservation, formatting materialization, metadata-only and structural sparse saves, unchanged original revision, empty editing, frozen mutation guards, every new mutation's evaluation invalidation, malformed public metadata, and Demo raw storage/readback. Parent owns final app build/UI verification.

Exact touched files:
- Packages/FiestaBoardDocuments/Sources/FiestaBoardDocuments/PageDocument.swift
- Packages/FiestaBoardDocuments/Sources/FiestaBoardDocuments/DocumentEditingSession.swift
- Packages/FiestaBoardDocuments/Sources/FiestaBoardDocuments/LosslessJSON.swift
- Packages/FiestaBoardDocuments/Tests/FiestaBoardDocumentsTests/StructuralEditingTests.swift
- Packages/FiestaBoardDocuments/README.md
- Packages/FiestaBoardEditorState/Sources/FiestaBoardEditorState/LocalPageEditorModel.swift
- Packages/FiestaBoardEditorState/Tests/FiestaBoardEditorStateTests/EditorTests.swift
- Packages/FiestaBoardEditorState/Tests/FiestaBoardEditorStateTests/StructuralModelTests.swift
- Packages/FiestaBoardEditorState/README.md
- Packages/FiestaBoardKit/Sources/FiestaBoardKit/PageEditing.swift
- Packages/FiestaBoardKit/Sources/FiestaBoardKit/Service.swift
- Packages/FiestaBoardKit/Sources/FiestaBoardKit/DemoService.swift
- Packages/FiestaBoardKit/Tests/FiestaBoardKitTests/MetadataPatchTests.swift
- Packages/FiestaBoardKit/README.md
- .superpowers/sdd/2026-10-29-creative-editor/task-1-report.md

# Native rich editor source contracts

Audit date: 2026-10-29. Exact upstream source: FiestaBoard `ff2415c4a646b55510f6f633c78915cdc9c333f2`, inspected with `git show` in the sibling `fiestaboard-ios-api` repository. This supplements the binding `2026-10-28-rich-editor-requirements.md`; it does not claim delivered native parity. No live service was used.

## Split-flap authoring

`web/src/components/tiptap-template-editor/utils/serialization.ts` (`parseLineContent`, `serializeNodeContent`, `parseVariable`) and `utils/constants.ts` define the app editor contract:

- Color atoms: `{{red}}`, also accepted on input as `{red}`, serialize as double braces. Codes: red 63, orange 64, yellow 65, green 66, blue 67, violet/purple 68, white 69, black 70, filled 71. `{{filled}}` is a solid tile; `{{filled:-}}` is a different fill operation. Numeric single-brace tiles such as `{63}` belong to the backend message grammar, but this editor parser does not turn them into color atoms. Preserve their source.
- Flexible space atoms: `{{fill_space}}`; repeat form `{{fill_space_repeat:-}}` or `{{fill_space_repeat:red}}`. The web parser uses the text after the first colon as repeat content and canonicalizes blank/default-space repeat to `{{fill_space}}`. Native source preservation should avoid copying this parser's lossy colon splitting for arbitrary future patterns.
- Variable atoms: `{{weather.temperature|pad:3|upper}}`. Split path on its first dot only: `{{parks.parks.0.rides.0.ride_abbr}}` retains the complete suffix. Filters split on pipes, then their first colon; canonical filter data is `{name, arg?}`, with deprecated `{args: [...]}` read fallback. The serializer writes `arg` first. Provider-instance paths such as `{{weather:sf.temperature}}` are valid backend variables, not span heads.
- Formula atoms: `{{= 1 + 1 }}`; expression parsing trims surrounding whitespace, serialization inserts `{{= ` and ` }}`. Keep expression as source; do not evaluate it natively. `wrappedText` serialization exists as `{{text|wrap}}`, but `parseLineContent` does not independently reconstruct that node type: this is not a complete general template grammar.
- The web editor uses one paragraph and hard breaks. Serialization pads to at least the device row count, never truncates excess lines, uppercases plain text, and removes all U+200B caret anchors. Those anchors are a web editing implementation detail, not template content. A native lossless source model must not silently strip user scalars or normalize opaque tokens merely to imitate editor internals.

`src/templates/engine.py:1877` (`_process_fill_space`) is authoritative for expanded fill width: measure drawn tiles after substitution, divide remaining width among all fill markers, assign remainder to earlier markers. With no room, remove fills and truncate by tiles. Color-name repeats create repeated tile markers; text patterns repeat/cut to allocation. Example at width 8: `A{{fill_space}}B{{fill_space}}C` has five available blanks, allocated 3 then 2. Native can show a flexible-space attachment, but cannot promise its final width before server evaluation.

## LED authoring and rendered markup

`web/src/components/charset-template-editor.tsx` delegates to `@fiestaboard/ui` TemplateEditor with the resolved `CharacterSet`. It explicitly gates toolbar forms by charset capability, preserves lowercase for `mixedCase`, marks unsupported cells, and accepts independent line alignment/wrap arrays. It is a distinct path from the app's split-flap parser. Exact dependency implementation was not re-audited from the npm tarball in this bounded audit; the prior requirements file records the package pin and integrity. No package code or assets were copied.

The backend's executable semantics are available in `src/templates/engine.py` (`_normalize_extended`), `src/markup.py`, `src/markup_icons.json`, `src/fiestaui/character-set.schema.json`, `src/fiestaui/character-sets.json`, and `tests/test_template_extended_syntax.py`:

| Author source | Rendered message | Meaning |
| --- | --- | --- |
| `{{red:HOT}}` | `{red:HOT}` | Three foreground-colored cells |
| `{{black/white:OPEN}}` | `{black/white:OPEN}` | Four cells, foreground/background |
| `{{#ff8800:Hi}}` | `{#ff8800:Hi}` | Hex foreground; case retained subject to charset |
| `{{icon:sun}}` | `{icon:sun}` | One icon cell |
| `{{red:{{demo.temp}}°}}` | `{red:72°}` with fixture temp 72 | Evaluate body before applying span |
| `{{black/white:A{{red:B}}C}}` | `{black/white:A{red:B}C}` | Nested styling |

Span heads are closed grammar: named colors, codes 63–70, or six-digit hex; foreground/background pairs use `/`. `filled` and 71 are tiles only, never span colors. Unknown heads remain variable syntax. Icons resolve through the vendored registry including aliases (`storm` → `bolt`); `icon:heart` becomes the typed heart/code62, not a bitmap icon. Rendered spans balance their own braces, nest at most eight deep; deeper openers become literal text. Tiles remain individual cells even inside spans. A native parser must balance nested braces rather than apply the split-flap `[^}]+` regex to LED spans.

`src/markup.py` BoardToken uses `type: char` plus `value`, or `type: color` plus `code`, with optional `color`, `background`, `icon`. Icons retain a split-flap fallback cell and icon annotation. Rendered legacy `{red}` is one tile, not an open text-color span; `{/}` and `{/red}` are zero-width historical end tags. Do not confuse source double-brace authoring with returned single-brace messages.

Provider values are data: the backend neutralizes non-base-markup braces unless the variable manifest declares `format: markup` (`engine.py:_as_data`). Native must not reinterpret a provider string as authored markup. Extended authoring normalization is gated by server mode/target; server validation/rendering is the verdict.

## Lines, metadata, and page patches

`src/pages/models.py:98` defines extensible `LineMetadata`: `alignment` is `left|center|right` (default left), `wrap` is Boolean (default false), and unknown JSON members survive. Metadata is positional to template lines. Modern templates store pure line content and separate metadata; legacy `{center}`, `{right}`, `{wrap}` prefixes are migration/compatibility input (`src/pages/storage.py:36`, `engine.py:527`). For covered lines, metadata takes precedence; absent entries fall back to legacy extraction. Wrap can flow into following available rows, and stops at occupied non-wrapping rows; canvas text-flow regions further affect budgets. Do not flatten wrap into baked output lines.

`web/src/components/page-builder.tsx:1090` keeps metadata aligned when the rich editor inserts/deletes lines, using matching prefix/suffix regions; inserted rows default left/false. Native should move the entire line record, including opaque metadata, for explicit insert/delete/reorder operations. Web save at approximately line 1540 sends `template` and `line_metadata` together with the originally seeded revision.

`src/pages/models.py:336`, `src/pages/service.py:219`, `src/pages/storage.py:481`, and `src/pages/routes.py:235` establish `PUT /pages/{id}` as a sparse known-field patch, not a full-document replacement. Both `template: [String]` and `line_metadata: [LineMetadata]` are supported and each supplied list replaces its complete field; there is no positional merge. Omitted fields survive. Explicit null clears these nullable fields, but a template page still must pass page validation (a missing/empty template is invalid). Unknown top-level extensions survive in storage; callers cannot patch arbitrary unknown top-level fields through PageUpdate. Nested extensions must accompany any replaced metadata list or they are lost. `tests/fixtures/page-editing/rich-extensions-v1.json` is a useful unknown-field/null/large-number preservation fixture.

Line-array length is not fixed by PageUpdate: longer/shorter nonempty arrays are accepted subject to ordinary page validation. Render-time geometry handles clipping/padding, so structural line editing needs no backend schema change. Geometry retarget uses device type, note-array dimensions or panel grid dimensions; service validates the prospective page and accepts lossy template clipping at render time. Omitted canvases scale on geometry changes; explicit canvases win. This is separate from changing the number of authored template lines. `expected_revision` is checked under storage lock and every save replaces the revision. Keep the original revision through the entire draft; do not fetch a new revision merely to retry an overwrite. Update response contains `{page, incompatible_references}`.

## Safe native scope and proof boundary

Safe without a provider evaluator: lossless source/range document model; recognized tile/fill/variable/formula/icon attachments; balanced editable LED spans; charset-gated controls; explicit structural line operations with metadata carried intact; semantic undo; caret/selection/IME behavior; source/plain round trips; revision-aware patches preserving opaque JSON. Keep unknown or unsupported syntax verbatim, with guarded editing if necessary. A chip is an authoring representation, not its evaluated cells.

Use `GET /templates/variables` and `/templates/formula-functions` for catalogs, `POST /templates/validate` for syntax verdicts, and side-effect-free `POST /templates/render` for evaluated target output/warnings (`src/templates/models.py`). Supply board_id plus explicit device geometry and line_metadata; board_id does not select geometry. Render response warnings identify charset mismatches and fallbacks; batch saved-page previews can include rich `cells` and canvas `layers` (`src/pages/models.py`). Keep `/templates/render/live` and page send separate because they have live output effects. Provider fetches, formulas, filters, exact wrapping/fill widths, charset fallback, and canvas rasterization remain server-authoritative. Source-contract inspection alone does not satisfy the required independent native TextKit/IME/undo and device visual proof for both editor families.

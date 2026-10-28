"""Native collection value corpus; backend generation/replay runs in Docker only.

Local integrity: python3 -m unittest discover -s Tests/Contracts
Docker: python /native-tests/test_collections_fixture.py --generate
Docker: python /native-tests/test_collections_fixture.py --replay
See docs/research/2026-10-27-collections-contract.md for the fenced command.
"""
import json
import hashlib
from importlib.metadata import version
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path("/native") if os.environ.get("COLLECTION_CONTRACT_DOCKER") == "1" else Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "Fixtures/contracts/collections-v1.json"
SOURCE = "79edd37d2329eaa34f42081a4d48e87bc04bb455"


def capture_backend():
    """Exercise real v1 handlers/storage and pure evaluation, with no app lifespan.

    This deliberately does not prove authentication or hardware delivery. The
    container has no network, and the only substituted boundary is plugin data.
    """
    if not Path("/.dockerenv").exists() or os.environ.get("COLLECTION_CONTRACT_DOCKER") != "1":
        raise RuntimeError("Backend imports are permitted only in the fenced Docker command")
    temporary = tempfile.TemporaryDirectory(prefix="native-collections-")
    os.environ["FIESTABOARD_DATA_DIR"] = temporary.name
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    import src
    from src.collections import service as collection_module
    from src.pages.models import Page
    from src.pages.service import get_page_service
    from src.settings.service import get_settings_service
    from src.templates.engine import get_template_engine
    from src.templates.routes import router as templates_router
    from src.v1.router import router as public_router
    from src.v1 import routes_content  # noqa: F401 - registers public wrappers.
    from unittest.mock import patch

    assert src.__version__ == "10.1.7"
    app = FastAPI()
    app.include_router(public_router)
    app.include_router(templates_router)
    client = TestClient(app)
    pages = get_page_service()
    for page_id in ("page-a", "page-b"):
        pages.storage.create(Page(id=page_id, name=page_id, type="template", template=["HELLO", "", "", "", "", ""]))
    service = collection_module.get_collection_service()
    engine = get_template_engine()
    substitutions = {}

    def sanitize(value):
        if isinstance(value, list):
            return [sanitize(item) for item in value]
        if isinstance(value, dict):
            result = {}
            for key, item in value.items():
                if key == "id" and isinstance(item, str) and item.startswith("collection:"):
                    substitutions.setdefault(item, f"collection:contract-{sum(v.startswith('collection:') for v in substitutions.values()) + 1}")
                if key in ("revision", "expected_revision") and item is not None:
                    substitutions.setdefault(item, f"revision-{sum(v.startswith('revision-') for v in substitutions.values()) + 1}")
                result[key] = ("2026-10-27T00:00:00" if key in ("created_at", "updated_at") and item is not None else sanitize(item))
            return result
        if isinstance(value, str):
            for original, replacement in substitutions.items():
                value = value.replace(original, replacement)
            # Domain-model ValueError strings include a truncated repr with
            # runtime datetime microseconds; retain the diagnostic around it.
            value = re.sub(r"input_value=.*?, input_type=dict", "input_value=<runtime model>, input_type=dict", value)
        return value

    cases = []

    def request(case_id, method, path="/v1/collections", body=None, status=200, params=None):
        response = client.request(method, path, json=body, params=params)
        assert response.status_code == status, (case_id, response.status_code, response.text)
        raw = response.json()
        sanitized_response = sanitize(raw)  # Register new opaque response values first.
        recorded_request = {"method": method, "path": sanitize(path)}
        if body is not None:
            recorded_request["body"] = sanitize(body)
        if params:
            recorded_request["query"] = sanitize(params)
        cases.append({"id": case_id, "request": recorded_request,
                      "response": {"status": status, "body": sanitized_response}})
        return raw

    def payload(mode="time", **changes):
        result = {"name": "Morning ☀️", "page_ids": ["page-b", "page-a"],
                  "selection_mode": mode, "time": {"interval_seconds": 30},
                  "variable": None, "random": None}
        if mode == "variable":
            result["variable"] = {"rules": [{"expression": "1 = 1", "page_id": "page-b"},
                                            {"expression": "2 > 1", "page_id": "page-a"}],
                                  "default_page_id": "page-a", "poll_seconds": 10}
        if mode == "random":
            result["random"] = {"interval_seconds": 30}
        result.update(changes)
        return result

    # No plugins are fetched. Empty/static context remains an explicit fixture
    # boundary, while the route models, engine, expression evaluator and stores
    # are the archived implementation.
    def no_provider_context(board=None, plugin_ids=None):
        assert plugin_ids == set(), "A fixture attempted to fetch a provider"
        return {}

    with patch.object(engine._plugin_registry, "build_template_context", side_effect=no_provider_context):
        request("list_empty", "GET")
        created = {}
        for mode in ("time", "variable", "random"):
            created[mode] = request(f"create_{mode}", "POST", body=payload(mode), status=201)
        original = created["variable"]
        cid = original["id"]
        path = f"/v1/collections/{cid}"
        request("get", "GET", path)
        request("list", "GET")
        updated = request("update_clear_configs", "PUT", path,
                          {**payload(), "expected_revision": original["revision"]})
        assert updated["revision"] != original["revision"]
        random_original = created["random"]
        request("update_clear_random", "PUT", f"/v1/collections/{random_original['id']}",
                {**payload(), "expected_revision": random_original["revision"]})
        request("update_stale", "PUT", path, {**payload(), "expected_revision": original["revision"]}, 412)
        request("delete_stale", "DELETE", path, status=412, params={"expected_revision": original["revision"]})
        settings = get_settings_service()
        board_id = settings.get_board_settings().boards[0]["id"]
        substitutions[board_id] = "board-contract"
        settings.set_active_page_id(cid)
        request("delete_in_use", "DELETE", path, status=409, params={"expected_revision": updated["revision"]})
        settings.set_active_page_id(None)
        request("delete", "DELETE", path, params={"expected_revision": updated["revision"]})
        for method in ("GET", "PUT", "DELETE"):
            request(f"{('update' if method == 'PUT' else method.lower())}_missing", method, path,
                    {"name": "Missing", "expected_revision": updated["revision"]} if method == "PUT" else None, 404,
                    params={"expected_revision": updated["revision"]} if method == "DELETE" else None)
        for case_id, changes in (
            ("create_missing_page", {"page_ids": ["missing-page"]}),
            ("create_duplicate_pages", {"page_ids": ["page-a", "page-a"]}),
            ("create_nested_collection", {"page_ids": [created["time"]["id"]]}),
            ("create_default_outside_members", {"variable": {"rules": [], "default_page_id": "outside", "poll_seconds": 10}}),
            ("create_rule_outside_members", {"variable": {"rules": [{"expression": "1", "page_id": "outside"}], "default_page_id": "page-a"}}),
            ("create_invalid_expression", {"variable": {"rules": [{"expression": "(", "page_id": "page-a"}], "default_page_id": "page-a"}}),
        ):
            request(case_id, "POST", body=payload("variable" if "variable" in changes else "time", **changes), status=400)
        boundary_cases = [
            ("name_empty", payload(name=""), 422),
            ("name_100_scalars", payload(name="😀" * 100), 201),
            ("name_101_scalars", payload(name="😀" * 101), 422),
            ("name_combining_100_scalars", payload(name="e\u0301" * 50), 201),
            ("name_combining_102_scalars", payload(name="e\u0301" * 51), 422),
            ("name_whitespace", payload(name=" "), 201),
            ("create_unknown_mode", payload(selection_mode="future"), 422),
            ("create_variable_requires_config", payload(selection_mode="variable"), 400),
            ("create_random_requires_config", payload(selection_mode="random"), 400),
            ("create_empty_members", payload(page_ids=[]), 422),
        ]
        for mode in ("time", "random"):
            for suffix, interval, status in (("min", 5, 201), ("max", 86400, 201), ("below", 4, 422), ("above", 86401, 422)):
                boundary_cases.append((f"{mode}_{suffix}", payload(mode, **{mode: {"interval_seconds": interval}}), status))
        for suffix, poll, status in (("min", 2, 201), ("max", 600, 201), ("below", 1, 422), ("above", 601, 422)):
            body = payload("variable")
            body["variable"]["poll_seconds"] = poll
            boundary_cases.append((f"poll_{suffix}", body, status))
        for case_id, body, status in boundary_cases:
            request(case_id, "POST", body=body, status=status)

        # Verify error paths cannot silently mint a new authorized generation.
        current = created["time"]
        current_path = f"/v1/collections/{current['id']}"
        request("update_invalid_keeps_revision", "PUT", current_path,
                {**payload(page_ids=["page-a", "page-a"]), "expected_revision": current["revision"]}, 400)
        unchanged = request("get_after_failed_write", "GET", current_path)
        assert unchanged["revision"] == current["revision"]
        disk = json.loads(service.storage.storage_file.read_text())
        assert all("revision" not in item and "edit_protocol" not in item for item in disk["collections"])
        service.storage._load()
        reloaded = request("get_after_restart", "GET", current_path)
        assert reloaded["revision"] != current["revision"]
        request("update_before_restart_revision", "PUT", current_path,
                {"name": "Stale", "expected_revision": current["revision"]}, 412)
        # Delete/recreate the same logical id, then reject the original token.
        saved = service.storage.get(current["id"])
        service.storage.delete(saved.id, expected_revision=saved.revision)
        service.storage.create(saved)
        request("update_recreated_old_revision", "PUT", current_path,
                {"name": "Stale", "expected_revision": reloaded["revision"]}, 412)

        # The real resolver is fed an explicit context, avoiding plugin access.
        random_id = created["random"]["id"]
        service.storage.update(random_id, {"selection_mode": "random", "random": {"interval_seconds": 30}})
        from src.collections.models import Collection, VariableModeConfig, VariableRule
        variable = Collection(id="collection:evaluation", name="Evaluation", page_ids=["page-b", "page-a"],
                              selection_mode="variable", variable=VariableModeConfig(
                                  rules=[VariableRule(expression="1 = 1", page_id="page-b"),
                                         VariableRule(expression="2 > 1", page_id="page-a")], default_page_id="page-a"))
        service.storage.create(variable)
        assert service.resolve_page_id(variable.id, context={}) == "page-b"
        service.storage.update(variable.id, {"variable": {"rules": [], "default_page_id": "page-a", "poll_seconds": 2}})
        assert service.resolve_page_id(variable.id, context={}) == "page-a"
        assert service.seconds_until_next_check(variable.id) == 2
        random_choices = [service.resolve_page_id(random_id, now_unix=t, context={}) for t in (0, 30, 60)]
        assert random_choices[0] != random_choices[1] and random_choices[1] != random_choices[2]
        time_choices = [service.resolve_page_id(current["id"], now_unix=t, context={}) for t in (0, 30, 60)]
        assert time_choices == ["page-b", "page-a", "page-b"]

        # Existing native adapter inputs: exact private endpoint payloads.
        request("validate_literal", "POST", "/templates/validate", {"template": ["HELLO", ""], "board_id": "contract-unknown"})
        request("validate_invalid", "POST", "/templates/validate", {"template": "{{= (}}", "board_id": "contract-unknown"})
        request("validate_known_board", "POST", "/templates/validate", {"template": "HELLO", "board_id": board_id})
        request("render_known_board", "POST", "/templates/render", {"template": ["HELLO", ""], "board_id": board_id, "device_type": "flagship"})
        request("render_literal", "POST", "/templates/render", {"template": ["HELLO", ""], "board_id": "contract-unknown", "device_type": "flagship", "line_metadata": [], "canvases": []})
        request("render_note_array", "POST", "/templates/render", {"template": [], "board_id": "contract-unknown", "device_type": "note_array", "notes_wide": 2, "notes_tall": 2})
        request("render_panel", "POST", "/templates/render", {"template": [], "board_id": "contract-unknown", "device_type": "panel", "grid_rows": 8, "grid_cols": 16})
    source_files = ["src/__init__.py", "src/collections/models.py", "src/collections/routes.py",
                    "src/collections/service.py", "src/collections/storage.py", "src/v1/routes_content.py",
                    "src/content_references.py", "src/templates/models.py", "src/templates/routes.py",
                    "src/templates/engine.py", "src/templates/expressions.py"]
    source_evidence = {name: hashlib.sha256(Path("/app", name).read_bytes()).hexdigest() for name in source_files}
    temporary.cleanup()
    return {"schema_version": 1, "source": {"commit": SOURCE, "version": "10.1.7"},
            "edit_protocol": "collection-revision-v1",
            "source_evidence": source_evidence,
            "generator": {"python": sys.version.split()[0], "fastapi": version("fastapi"), "pydantic": version("pydantic")},
            "sanitization": "Opaque ids/revisions and timestamps replaced; runtime model repr in Pydantic error strings redacted. Ordering, user text, nulls and diagnostic messages retained.",
            "cases": cases,
            "generation_evidence": {"update_changes_revision": True, "restart_changes_revision": True,
                                    "runtime_metadata_not_persisted": True, "recreated_id_rejects_old_revision": True,
                                    "failed_write_keeps_revision": True},
            "evaluation_evidence": {"ordered_first_match": "page-b", "empty_rules_default": "page-a", "poll_seconds": 2,
                                    "time_order": time_choices, "random_two_members_alternate": True, "context": "explicit empty fixture context"},
            "adapter_evidence": {"endpoints": ["/templates/validate", "/templates/render"],
                                 "provider_fetches": 0, "hardware_sends": 0,
                                 "limits": "Static content, temporary configured board, unknown-board fallback, geometry and response shapes only; no real board/provider/layer delivery proof."}}


class CollectionsFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads(FIXTURE.read_text())
        cls.cases = {case["id"]: case for case in cls.fixture["cases"]}

    def test_corpus_preserves_order_and_explicit_config_clearing(self):
        self.assertEqual(len(self.cases), len(self.fixture["cases"]), "Case IDs must be unique")
        for mode in ("time", "variable", "random"):
            case = self.cases[f"create_{mode}"]
            self.assertEqual(case["response"]["status"], 201)
            body = case["response"]["body"]
            self.assertEqual(body["page_ids"], ["page-b", "page-a"])
            self.assertEqual(body["selection_mode"], mode)
            self.assertEqual(body["edit_protocol"], "collection-revision-v1")
            self.assertTrue(body["revision"])
        cleared = self.cases["update_clear_configs"]
        for key in ("variable", "random"):
            self.assertIn(key, cleared["request"]["body"])
            self.assertIsNone(cleared["request"]["body"][key])
            self.assertIsNone(cleared["response"]["body"][key])
        self.assertIsNone(self.cases["update_clear_random"]["response"]["body"]["random"])
        rules = self.cases["create_variable"]["response"]["body"]["variable"]["rules"]
        self.assertEqual([rule["page_id"] for rule in rules], ["page-b", "page-a"])

    def test_refused_mutations_and_missing_resource_remain_distinct(self):
        for case_id, status in {"update_stale": 412, "delete_stale": 412,
                                "delete_in_use": 409, "get_missing": 404,
                                "update_missing": 404, "delete_missing": 404,
                                "create_missing_page": 400, "create_duplicate_pages": 400,
                                "create_nested_collection": 400,
                                "create_invalid_expression": 400}.items():
            self.assertEqual(self.cases[case_id]["response"]["status"], status, case_id)
        self.assertEqual(self.cases["delete"]["response"]["status"], 200)
        self.assertEqual(self.cases["list_empty"]["response"]["body"], {"collections": [], "total": 0})

    def test_boundaries_and_restart_proof_are_recorded(self):
        self.assertEqual(self.fixture["source"], {"commit": SOURCE, "version": "10.1.7"})
        for case_id in ("name_100_scalars", "time_min", "time_max", "random_min", "random_max", "poll_min", "poll_max", "name_whitespace"):
            self.assertEqual(self.cases[case_id]["response"]["status"], 201, case_id)
        for case_id in ("name_empty", "name_101_scalars", "time_below", "time_above", "random_below", "random_above", "poll_below", "poll_above", "create_unknown_mode"):
            self.assertEqual(self.cases[case_id]["response"]["status"], 422, case_id)
        for key in ("update_changes_revision", "restart_changes_revision", "runtime_metadata_not_persisted", "recreated_id_rejects_old_revision", "failed_write_keeps_revision"):
            self.assertIs(self.fixture["generation_evidence"][key], True, key)

    def test_preview_values_fit_native_response_invariants(self):
        for case_id in ("validate_literal", "validate_invalid", "validate_known_board"):
            body = self.cases[case_id]["response"]["body"]
            self.assertEqual(body["valid"], not body["errors"])
            for error in body["errors"]:
                self.assertIsInstance(error["line"], int)
                self.assertIsInstance(error["column"], int)
                self.assertIsInstance(error["message"], str)
        self.assertFalse(self.cases["validate_invalid"]["response"]["body"]["valid"])
        for case_id, rows in (("render_literal", 6), ("render_known_board", 6),
                              ("render_note_array", 6), ("render_panel", 8)):
            body = self.cases[case_id]["response"]["body"]
            self.assertEqual(body["line_count"], rows)
            self.assertEqual(len(body["lines"]), rows)
            self.assertEqual(body["rendered"], "\n".join(body["lines"]))


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] in ("--generate", "--replay"):
        observed = capture_backend()
        if sys.argv[1] == "--generate":
            print(json.dumps(observed, indent=2, ensure_ascii=False))
        else:
            expected = json.loads(Path("/contract-fixtures/collections-v1.json").read_text())
            assert observed == expected, "Archived backend output differs from committed corpus"
            print(f"Replayed {len(observed['cases'])} collection/adapter cases; generation and evaluation assertions passed")
    else:
        unittest.main()

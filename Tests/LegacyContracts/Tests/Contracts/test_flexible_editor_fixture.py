"""Synthetic native flexible transport fixture, pinned to the reviewed core route.

This verifies request/receipt composition; it is not backend renderer evidence.
"""
import copy
import importlib.util
import json
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('native_flexible_fixture', ROOT / 'Tests/UITests/fixture_server.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class FlexibleEditorFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), fixture.Handler)
        cls.worker = Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.worker.join()

    def setUp(self):
        self.prefix = '/flexible-' + uuid.uuid4().hex

    def request(self, method, route, body=None):
        connection = HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        self.addCleanup(connection.close)
        connection.request(method, self.prefix + '/api/' + route,
                           body=json.dumps(body) if body is not None else None,
                           headers={'Content-Type': 'application/json'})
        response = connection.getresponse()
        return response.status, json.loads(response.read())

    def document(self):
        status, page = self.request('GET', 'v1/pages/flexible')
        self.assertEqual(status, 200)
        return page

    def preview_page(self):
        page = copy.deepcopy(self.document())
        for key in ('id', 'revision', 'document_protocol', 'edit_protocol'):
            page.pop(key, None)
        return page

    def test_supported_document_has_editable_text_canvas_and_opaque_siblings(self):
        page = self.document()
        self.assertEqual(page['document_protocol'], 'page-document-v2')
        self.assertEqual(page['edit_protocol'], 'page-revision-v1')
        self.assertEqual([b['id'] for b in page['blocks']], ['welcome', 'drawing', 'retained'])
        self.assertEqual(page['blocks'][0]['extension']['large'], 900719925474099312345678)
        self.assertIsNone(page['style'])
        self.assertNotIn('layout', page)
        self.assertNotIn('template', page)
        self.assertNotIn('device_type', page)

    def test_explicit_unknown_or_empty_target_is_404_and_omission_or_null_uses_default(self):
        page = self.preview_page()
        for body in ({'page': page, 'board_id': 'contract-board'}, {'page': page}, {'page': page, 'board_id': None}):
            status, result = self.request('POST', 'pages/preview/flexible', body)
            self.assertEqual(status, 200)
            self.assertTrue(result['available']); self.assertEqual(result['page_id'], 'unsaved')
            self.assertEqual(result['message'], '\n'.join(result['lines']))
            self.assertNotIn('rendered', result)
            self.assertNotIn('board_id', result, 'The real reply does not echo a verified target')
            self.assertEqual(result['layers'][0]['physical_frame_version'], 1)
            self.assertEqual(set(result['layout_issues'][0]), {'path', 'code', 'severity', 'message'})
        for board_id in ('deleted-board', ''):
            status, _ = self.request('POST', 'pages/preview/flexible', {'page': page, 'board_id': board_id})
            self.assertEqual(status, 404)

    def test_sparse_conditional_save_and_reopen_preserve_unknowns_and_exact_numbers(self):
        before = self.document()
        blocks = copy.deepcopy(before['blocks'])
        blocks[0]['text'] = 'Edited native text'
        blocks[1]['canvas']['content']['shapes'][1]['x'] = 7
        status, receipt = self.request('PUT', 'v1/pages/flexible', {
            'expected_revision': before['revision'], 'blocks': blocks, 'style': None})
        self.assertEqual(status, 200)
        self.assertEqual(set(receipt), {'page', 'incompatible_references'})
        self.assertNotEqual(receipt['page']['revision'], before['revision'])
        reopened = self.document()
        self.assertEqual(reopened, receipt['page'])
        self.assertEqual(reopened['blocks'], blocks)
        self.assertEqual(reopened['blocks'][1]['canvas']['content']['shapes'][1]['extension'], 900719925474099312345678)
        self.assertNotIn('layout', reopened)

    def test_stale_revision_does_not_apply_second_write(self):
        original = self.document()
        status, _ = self.request('PUT', 'v1/pages/flexible', {'expected_revision': original['revision'], 'name': 'Accepted'})
        self.assertEqual(status, 200)
        status, _ = self.request('PUT', 'v1/pages/flexible', {'expected_revision': original['revision'], 'name': 'Stale overwrite'})
        self.assertEqual(status, 412)
        self.assertEqual(self.document()['name'], 'Accepted')

    def test_blocks_null_ignored_but_empty_list_rejected(self):
        original = self.document()
        status, receipt = self.request('PUT', 'v1/pages/flexible', {'expected_revision': original['revision'], 'blocks': None})
        self.assertEqual(status, 200)
        self.assertEqual(receipt['page']['blocks'], original['blocks'])
        status, _ = self.request('PUT', 'v1/pages/flexible', {'expected_revision': receipt['page']['revision'], 'blocks': []})
        self.assertEqual(status, 422)
        self.assertEqual(self.document()['blocks'], original['blocks'])

    def test_grid_patch_and_restricted_preview_are_422(self):
        original = self.document()
        status, _ = self.request('PUT', 'v1/pages/flexible', {'expected_revision': original['revision'], 'template': ['X']})
        self.assertEqual(status, 422)
        page = self.preview_page(); page['targets'] = {'boards': []}
        status, _ = self.request('POST', 'pages/preview/flexible', {'page': page, 'board_id': 'contract-board'})
        self.assertEqual(status, 422)
        self.assertEqual(self.document(), original)

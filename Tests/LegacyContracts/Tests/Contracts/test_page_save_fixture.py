"""W4: the board fixture's legacy page write path (PUT /v1/pages/{id}).

Shape follows 10.3.2 `PageUpdate` / `PageUpdateResponse` (src/pages/models.py):
author fields only, a conditional `expected_revision`, and `{page,
incompatible_references}` back. Saved pages are read back by GET for the prefix.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'UITests'))
import fixture_boards  # noqa: E402


def call(store, method, route, body=None):
    return fixture_boards.handle('/board-manual-abc123', route, method, body or {}, '', store)


class PageSaveFixtureTests(unittest.TestCase):
    def test_save_round_trips_and_bumps_the_revision(self):
        store = {}
        status, page = call(store, 'GET', 'v1/pages/hello')
        self.assertEqual(status, 200)
        status, answer = call(store, 'PUT', 'v1/pages/hello', {'expected_revision': page['revision'], 'template': ['', 'SAVED', '']})
        self.assertEqual(status, 200)
        self.assertEqual(answer['incompatible_references'], [])
        self.assertEqual(answer['page']['template'], ['', 'SAVED', ''])
        self.assertNotEqual(answer['page']['revision'], page['revision'])
        self.assertNotEqual(answer['page']['updated_at'], page['updated_at'])
        _, again = call(store, 'GET', 'v1/pages/hello')
        self.assertEqual(again['template'], ['', 'SAVED', ''])
        _, listing = call(store, 'GET', 'v1/pages')
        self.assertEqual(next(p for p in listing['pages'] if p['id'] == 'hello')['template'], ['', 'SAVED', ''])
        # Untouched fields stay as stored.
        self.assertEqual(again['line_metadata'], page['line_metadata'])

    def test_stale_revision_is_a_conflict(self):
        store = {}
        status, _ = call(store, 'PUT', 'v1/pages/hello', {'expected_revision': 'old', 'template': ['X']})
        self.assertEqual(status, 412)

    def test_non_author_fields_and_bad_values_are_refused(self):
        store = {}
        _, page = call(store, 'GET', 'v1/pages/pixel')
        rev = page['revision']
        self.assertEqual(call(store, 'PUT', 'v1/pages/pixel', {'expected_revision': rev, 'id': 'x'})[0], 422)
        self.assertEqual(call(store, 'PUT', 'v1/pages/pixel', {'expected_revision': rev, 'template': []})[0], 422)
        bad = [{'id': 'sun', 'area': {'row': 0, 'col': 1, 'rows': 5, 'cols': 8}, 'content': {}}]
        self.assertEqual(call(store, 'PUT', 'v1/pages/pixel', {'expected_revision': rev, 'canvases': bad})[0], 422)
        good = [{'id': 'sun', 'area': {'row': 2, 'col': 1, 'rows': 5, 'cols': 8}, 'content': {'size': [32, 30]}}]
        status, answer = call(store, 'PUT', 'v1/pages/pixel', {'expected_revision': rev, 'canvases': good})
        self.assertEqual(status, 200)
        self.assertEqual(answer['page']['canvases'], good)

    def test_geometry_change_is_stored(self):
        store = {}
        _, page = call(store, 'GET', 'v1/pages/lobby')
        status, answer = call(store, 'PUT', 'v1/pages/lobby', {'expected_revision': page['revision'], 'device_type': 'flagship',
                                                                 'grid_rows': None, 'grid_cols': None})
        self.assertEqual(status, 200)
        self.assertEqual((answer['page']['device_type'], answer['page']['grid_rows']), ('flagship', None))

    def test_single_and_composite_pages_are_shaped_like_10_3_2(self):
        # WEB-P4: a single page needs display_type, a composite needs rows; both carry the protocols.
        store = {}
        _, single = call(store, 'GET', 'v1/pages/single')
        _, composite = call(store, 'GET', 'v1/pages/composite')
        self.assertEqual(single['display_type'], 'weather')
        self.assertEqual(len(composite['rows']), 2)
        self.assertEqual((single['edit_protocol'], composite['document_protocol']), ('page-revision-v1', 'page-document-v1'))
        status, answer = call(store, 'PUT', 'v1/pages/single', {'expected_revision': single['revision'], 'name': 'Renamed'})
        self.assertEqual((status, answer['page']['display_type']), (200, 'weather'))


if __name__ == '__main__':
    unittest.main()

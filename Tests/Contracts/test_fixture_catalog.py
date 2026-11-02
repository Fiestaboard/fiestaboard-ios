"""Editor catalogs (PLAN §4.4, iOS-F1): `/v1/variables`, `/v1/functions` and
`/plugins/{id}/manifest` under the board prefix family, cookie-gated, shaped like
10.3.2; `no-plugins` answers no variables (B32); the validate fallback knows the
catalog's functions. Mock content; not backend evidence.
"""
import importlib.util
import json
import sys
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('catalog_fixture', ROOT / 'Tests/UITests/fixture_server.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

# `src/v1/models.py` VariableCatalog at 10.3.2.
VARIABLE_CATALOG_KEYS = {'variables', 'max_lengths', 'variable_metadata', 'variable_groups', 'colors', 'symbols',
                         'filters', 'formatting', 'syntax_examples', 'plugin_system_enabled'}


class FixtureCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), fixture.Handler)
        cls.worker = Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.worker.join()

    def request(self, method, path, body=None, cookie=None):
        connection = HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        headers = {'Content-Type': 'application/json'}
        if cookie:
            headers['Cookie'] = cookie
        connection.request(method, path, None if body is None else json.dumps(body), headers)
        response = connection.getresponse()
        data = response.read()
        cookie = response.getheader('Set-Cookie')
        connection.close()
        return response.status, json.loads(data or b'{}'), cookie

    def signed_in(self, scenario='manual'):
        prefix = f'/board-{scenario}-{uuid.uuid4().hex[:8]}/api'
        status, _, cookie = self.request('POST', prefix + '/auth/login',
                                         {'username': 'fixture_admin', 'password': 'fixture-password'})
        self.assertEqual(status, 200)
        return prefix, cookie.split(';', 1)[0]

    def test_catalog_routes_are_shaped_like_the_server_and_cookie_gated(self):
        prefix, cookie = self.signed_in()
        self.assertEqual(self.request('GET', prefix + '/v1/variables')[0], 401)
        status, catalog, _ = self.request('GET', prefix + '/v1/variables', cookie=cookie)
        self.assertEqual(status, 200)
        self.assertEqual(set(catalog), VARIABLE_CATALOG_KEYS)
        self.assertEqual(sorted(catalog['variables']), ['baywheels', 'date_time', 'stocks', 'weather'])
        self.assertNotIn('home_assistant', catalog['variables'])
        # 10.3.2 lists arrays as patterns only; items come from /displays/raw/batch (W4).
        self.assertIn('stations.*.name', catalog['variables']['baywheels'])
        self.assertFalse(any(name.startswith('stations.0') for name in catalog['variables']['baywheels']))
        status, functions, _ = self.request('GET', prefix + '/v1/functions', cookie=cookie)
        self.assertEqual(status, 200)
        categories = {entry['category'] for entry in functions['functions'].values()}
        self.assertEqual(categories, {'logic', 'array', 'date', 'math', 'text', 'convert', 'color', 'experimental'})
        self.assertTrue(all(set(entry) == {'category', 'signature', 'summary'} for entry in functions['functions'].values()))
        status, manifest, _ = self.request('GET', prefix + '/plugins/baywheels/manifest', cookie=cookie)
        self.assertEqual((status, manifest['name'], manifest['icon']), (200, 'Bay Wheels', 'bike'))
        self.assertEqual(self.request('GET', prefix + '/plugins/nope/manifest', cookie=cookie)[0], 404)

    def test_no_plugins_scenario_has_no_variables_but_keeps_colors(self):
        prefix, cookie = self.signed_in('no-plugins')
        status, catalog, _ = self.request('GET', prefix + '/v1/variables', cookie=cookie)
        self.assertEqual(status, 200)
        self.assertEqual(catalog['variables'], {})
        self.assertTrue(catalog['colors'])

    def test_other_prefixes_do_not_serve_catalogs(self):
        # The sign-in corpus has no catalog: the app falls back to its built-in sample there.
        import fixture_catalog
        self.assertIsNone(fixture_catalog.handle('/signin-abc', 'v1/variables', 'GET', {}, {}, {}))
        self.assertIsNone(fixture_catalog.handle('/board-manual-1', 'v1/variables', 'POST', {}, {}, {}))

    def test_validate_knows_the_catalog_functions(self):
        prefix, cookie = self.signed_in()
        _, bogus, _ = self.request('POST', prefix + '/templates/validate', {'template': ['{{= BOGUS(1) }}']}, cookie=cookie)
        self.assertEqual(bogus['errors'][0]['message'], 'Formula #NAME?: Unknown function: BOGUS')
        _, wobble, _ = self.request('POST', prefix + '/templates/validate', {'template': ['{{= WOBBLE(2) }}']}, cookie=cookie)
        self.assertTrue(wobble['valid'], 'Functions of an unknown category validate')



class RawBatchFixtureTests(unittest.TestCase):
    def test_raw_batch_serves_array_items_like_10_3_2(self):
        fixture_catalog = sys.modules["fixture_catalog"]
        status, body = fixture_catalog.handle('/board-manual-x', 'displays/raw/batch', 'POST',
                                              {'display_types': ['baywheels', 'nope'], 'enabled_only': True}, '', {})
        self.assertEqual(status, 200)
        self.assertEqual(set(body), {'displays', 'total', 'successful'})
        self.assertEqual((body['total'], body['successful']), (2, 1))
        stations = body['displays']['baywheels']['data']['stations']
        self.assertEqual([s['name'] for s in stations], ['MARKET ST', 'FERRY BUILDING'])
        self.assertEqual(fixture_catalog.handle('/board-manual-x', 'displays/raw/batch', 'POST', {}, '', {})[0], 400)
        empty = fixture_catalog.handle('/board-no-plugins-x', 'displays/raw/batch', 'POST', {'display_types': ['baywheels']}, '', {})[1]
        self.assertEqual(empty['displays'], {})

if __name__ == '__main__':
    unittest.main()

"""Shared render table (PLAN §4.0, §4.4): every `Fixtures/shared/render-cases*.json`
entry round-trips through the fixture server, and every mirror is byte-identical
to its canonical copy in the handoff folder. Mock content; not backend evidence.
"""
import glob
import hashlib
import importlib.util
import json
import os
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / 'Fixtures' / 'shared'
HANDOFF = Path(os.environ.get('FIESTABOARD_HANDOFF_FIXTURES', '/Volumes/ExtHD/fiestaboard-mobile-handoff/fixtures'))
spec = importlib.util.spec_from_file_location('render_cases_fixture', ROOT / 'Tests/UITests/fixture_server.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class FixtureRenderCasesTests(unittest.TestCase):
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

    def cases(self):
        out = []
        for path in sorted(glob.glob(str(SHARED / 'render-cases*.json'))):
            out += [(Path(path).name, case) for case in json.loads(Path(path).read_text())['cases']]
        return out

    def test_every_table_entry_round_trips(self):
        prefix, cookie = self.signed_in()
        cases = self.cases()
        self.assertGreater(len(cases), 0)
        for name, case in cases:
            with self.subTest(file=name, case=case['id']):
                status, body, _ = self.request('POST', prefix + case['route'], case['request'], cookie)
                self.assertEqual(status, case['response'].get('status', 200))
                self.assertEqual(body, case['response']['body'])

    def test_mirrors_equal_the_handoff_copies(self):
        provenance = json.loads((SHARED / 'source-provenance.json').read_text())['files']
        for name, entry in provenance.items():
            with self.subTest(file=name):
                self.assertEqual(sha256(SHARED / name), entry['sha256'], 'mirror differs from its recorded sha256')
                canonical = HANDOFF / name
                if not canonical.exists():
                    self.skipTest(f'handoff folder not mounted: {canonical}')
                self.assertEqual(sha256(SHARED / name), sha256(canonical), f'stale mirror: copy {canonical}')

    def test_internal_routes_require_the_session_cookie(self):
        prefix = f'/board-manual-{uuid.uuid4().hex[:8]}/api'
        for route in ('/settings/board', '/v1/status', '/templates/render', '/silence-status'):
            with self.subTest(route=route):
                method = 'POST' if route == '/templates/render' else 'GET'
                status, _, _ = self.request(method, prefix + route, {'template': ['X']} if method == 'POST' else None)
                self.assertEqual(status, 401)

    def test_fallback_is_deterministic_and_substitutes_plausible_values(self):
        prefix, cookie = self.signed_in()
        body = {'template': ['hi {{red}} {{weather.temperature}}', 'X'], 'line_metadata': [{'alignment': 'center'}],
                'device_type': 'note'}
        status, first, _ = self.request('POST', prefix + '/templates/render', body, cookie)
        self.assertEqual(status, 200)
        self.assertEqual(first['line_count'], 3)
        self.assertEqual(first['lines'][0], '    HI {63} 72    ', 'a known variable renders a plausible value; a marker is one cell')
        _, rich, _ = self.request('POST', prefix + '/templates/render', {'template': [
            '{{weather.temperature|pad:3}}° {{weather.condition}}',
            '{{= IF(weather.temperature > 70, "WARM OUT", "BRING A COAT") }}',
            '{{date_time.day_of_week|truncate:3}} {{date_time.day}} {{weather.wind_speed|zeropad:3}}', '{{nope.field}}', '{{fill_space_repeat:-}}',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ'], 'device_type': 'flagship'}, cookie)
        self.assertEqual([line.rstrip() for line in rich['lines']],
                         ['72 ° SUNNY', '???', 'SAT 31 008', '???', '-' * 22, 'ABCDEFGHIJKLMNOPQRSTUV'],
                         'pad/truncate/zeropad filters, formula → ???, shared clock, unknown → ???, fill, cut at cols')
        self.assertNotIn('charset_issues', first, 'charset_issues only when board_id is sent')
        _, second, _ = self.request('POST', prefix + '/templates/render', body, cookie)
        self.assertEqual(first, second)
        _, invalid, _ = self.request('POST', prefix + '/templates/validate', {'template': ['{{= NOPE(1) }}']}, cookie)
        self.assertEqual(invalid, {'valid': False, 'errors': [{'line': 1, 'column': 1,
                                   'message': 'Formula #NAME?: Unknown function: NOPE'}]})

    def test_scenarios_serve_board_and_status_routes(self):
        for scenario in ('manual', 'schedule', 'paused', 'schedule-gap', 'collection', 'override', 'silence'):
            with self.subTest(scenario=scenario):
                prefix, cookie = self.signed_in(scenario)
                status, boards, _ = self.request('GET', prefix + '/v1/boards', cookie=cookie)
                self.assertEqual(status, 200)
                self.assertEqual(boards['total'], len(boards['boards']))
                self.assertTrue(set(boards['boards'][0]) <= {'id', 'name', 'device_type', 'rows', 'cols', 'is_primary', 'paused',
                                                             'schedule_enabled', 'auto_restore', 'output', 'device_model', 'charset'})
                for route in ('/v1/boards/kitchen', '/settings/board', '/v1/status', '/board/current-message?board_id=kitchen',
                              '/schedules/active/page?board_id=kitchen', '/settings/active-page?board_id=kitchen',
                              '/silence-status?board_id=kitchen', '/settings/display', '/version'):
                    status, _, _ = self.request('GET', prefix + route, cookie=cookie)
                    self.assertEqual(status, 200, route)
                _, version, _ = self.request('GET', prefix + '/version', cookie=cookie)
                self.assertEqual((version['running_version'], version['is_dev']), ('10.1.20', False))
                _, detail, _ = self.request('GET', prefix + '/v1/boards/kitchen', cookie=cookie)
                self.assertEqual(detail['paused'], scenario == 'paused')
                self.assertEqual(len(detail['characters']), 6)


if __name__ == '__main__':
    unittest.main()

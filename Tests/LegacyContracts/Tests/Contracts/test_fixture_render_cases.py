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

    def test_accessory_formula_fixture_and_unknown_fallback(self):
        prefix, cookie = self.signed_in()
        status, result, _ = self.request('POST', prefix + '/templates/render', {
            'template': ['TEMP {{weather.temperature}} {{red}}',
                         '{{= IF(weather.temperature > 70, "WARM", "COOL")}}',
                         '{{= UNMODELED()}}'], 'device_type': 'flagship'}, cookie)
        self.assertEqual(status, 200)
        self.assertEqual(result['lines'][1].strip(), 'WARM')
        self.assertEqual(result['lines'][2].strip(), '???')

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
        # Re-recorded (W4): 10.3.2's render keeps case (WEB-P4); a flap board reports it in charset_issues.
        self.assertEqual(first['lines'][0], '    hi {63} 72    ', 'a known variable renders a plausible value; a marker is one cell')
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
        # Re-recorded (W4): 10.3.2 reports this at column 0 (WEB-P4, b21_bogus).
        self.assertEqual(invalid, {'valid': False, 'errors': [{'line': 1, 'column': 0,
                                   'message': 'Formula #NAME?: Unknown function: NOPE'}]})

    def test_editor_request_shape_still_finds_its_case(self):
        """P1 (W2-INT): the editor adds `board_id` and `canvases: null`; the recorded case
        still answers (WARM OUT, not ???), with the board's charset fields."""
        prefix, cookie = self.signed_in()
        case = next(c for _, c in self.cases() if c['id'] == 'page_morning_full_metadata')
        body = dict(case['request'], board_id='kitchen', canvases=None)
        status, answer, _ = self.request('POST', prefix + '/templates/render', body, cookie)
        self.assertEqual(status, 200)
        self.assertEqual(answer['lines'], case['response']['body']['lines'])
        self.assertEqual(answer['lines'][1], '72 ° SUNNY            ', "the server's pad:3 is ljust")
        self.assertEqual(answer['lines'][4].rstrip(), 'WARM OUT')
        self.assertEqual(answer['charset'], 'vestaboard_v1')
        self.assertEqual(answer['charset_issues'], [])

    def test_fallback_aligns_and_wraps_like_the_server(self):
        """P1: rows pad by their alignment; a wrap row flows into the empty rows below and
        stops at the first row with content."""
        prefix, cookie = self.signed_in()
        _, out, _ = self.request('POST', prefix + '/templates/render', {
            'template': ['THE BEST WAY TO PREDICT THE FUTURE IS TO CREATE IT', '', 'FOOTER', '', 'RIGHT', 'MID'],
            'line_metadata': [{'alignment': 'center', 'wrap': True}, {'alignment': 'left', 'wrap': False},
                              {'alignment': 'left', 'wrap': False}, {'alignment': 'left', 'wrap': False},
                              {'alignment': 'right', 'wrap': False}, {'alignment': 'center', 'wrap': False}],
            'device_type': 'flagship'}, cookie)
        self.assertEqual(out['lines'], ['   THE BEST WAY TO    ', 'PREDICT THE FUTURE IS ', 'FOOTER                ',
                                        '                      ', '                 RIGHT', '         MID          '])

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



class RealServerBehaviourTests(unittest.TestCase):
    """W4: the fallback follows what WEB-P4 observed on a real 10.3.2 (reports/W4-WEB.md)."""

    def setUp(self):
        import importlib
        import sys
        sys.path.insert(0, str(ROOT / 'Tests/UITests'))
        self.render = importlib.import_module('fixture_render')

    def test_lowercase_on_a_flap_board_is_a_case_issue_not_folded(self):
        out = self.render.toy_render({'template': ['', 'ab'], 'device_type': 'flagship', 'board_id': 'kitchen'})
        self.assertEqual(out['lines'][1].rstrip(), 'ab')
        self.assertEqual([(i['row'], i['col'], i['reason'], i['fallback']['value']) for i in out['charset_issues']],
                         [(1, 0, 'case', 'A'), (1, 1, 'case', 'B')])
        self.assertEqual(self.render.toy_render({'template': ['ab'], 'board_id': 'pixoo', 'device_type': 'panel',
                                                 'grid_rows': 10, 'grid_cols': 16})['charset_issues'], [])

    def test_wrap_fills_each_row(self):
        out = self.render.toy_render({'template': ['THE BEST WAY TO PREDICT THE FUTURE IS TO CREATE IT'],
                                      'line_metadata': [{'alignment': 'center', 'wrap': True}],
                                      'device_type': 'note_array', 'notes_wide': 2, 'notes_tall': 2})
        self.assertEqual(out['lines'][:2], [' THE BEST WAY TO PREDICT THE  ', '    FUTURE IS TO CREATE IT    '])

    def test_validate_errors_are_at_column_zero_with_the_real_messages(self):
        self.assertEqual(self.render.toy_validate({'template': ['{{= BOGUS(1) }}']})['errors'],
                         [{'line': 1, 'column': 0, 'message': 'Formula #NAME?: Unknown function: BOGUS'}])
        self.assertEqual(self.render.toy_validate({'template': ['{{= UPPER(date_time.day_of_week }}']})['errors'][0]['message'],
                         "Formula #SYNTAX: Missing ')' in call to UPPER")

if __name__ == '__main__':
    unittest.main()

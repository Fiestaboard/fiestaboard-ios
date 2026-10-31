#!/usr/bin/env python3
"""Loopback-only UI scenarios. No backend imports, device writes or real accounts.

Run before xcodebuild test. Each /signin-UUID or /setup-UUID prefix owns fresh
state. Payload shapes come from the separately verified HTTP corpus; this
server proves native UI/transport composition, not backend compatibility.
"""
import base64
import copy
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

ROOT = Path(__file__).resolve().parents[2]
CORPUS = json.loads((ROOT / 'Fixtures/contracts/10.1.20/bootstrap-control.json').read_text())
CASES = {case['id']: case['response']['body'] for case in CORPUS['cases']}
STATES = {}
LOCK = Lock()

# Synthetic authoring fixtures pinned to core 864cfa6baccdf5b9f29db712442bf40fb3e79923.
# No renderer is ported; the physical frame below is deterministic test artwork.
FLEXIBLE_PAGE = {
    'id': 'flexible', 'name': 'Flexible document', 'type': 'flexible',
    'document_protocol': 'page-document-v2', 'edit_protocol': 'page-revision-v1',
    'revision': 'flex-r1', 'style': None,
    'blocks': [
        {'id': 'welcome', 'kind': 'text', 'text': 'Native flexible text',
         'extension': {'large': 900719925474099312345678, 'null': None}},
        {'id': 'drawing', 'kind': 'canvas', 'canvas': {'source': None, 'content': {
            'size': [32, 16], 'background': 'black', 'palette': {'a': 'white'},
            'pixels': ['a.'], 'shapes': [
                {'type': 'text', 'x': 1, 'y': 1, 'text': 'Canvas', 'color': 'white', 'font': '5x7'},
                {'type': 'rect', 'x': 2, 'y': 9, 'w': 10, 'h': 5, 'fill': 'red', 'extension': 900719925474099312345678},
                {'type': 'line', 'x1': 16, 'y1': 1, 'x2': 30, 'y2': 14, 'stroke': 'green', 'width': 1},
            ]}}},
        {'id': 'retained', 'kind': 'future-art', 'payload': {'large': 900719925474099312345678}},
    ],
}
GRID_FIELDS = {'device_type', 'notes_wide', 'notes_tall', 'grid_rows', 'grid_cols', 'display_type', 'rows', 'template', 'line_metadata', 'canvases'}



class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log request bodies, cookies or credentials.

    def do_GET(self):
        self.handle_request('GET')

    def do_POST(self):
        self.handle_request('POST')

    def do_PUT(self):
        self.handle_request('PUT')

    def handle_request(self, method):
        if self.path == '/ready':
            return self.reply(200, {'fixture': 'native-onboarding'})
        parts = self.path.split('/api/', 1)
        if len(parts) != 2 or not parts[0].startswith(('/signin-', '/setup-', '/mixed-', '/flexible-')):
            return self.reply(404, {})
        prefix, route = parts
        with LOCK:
            state = STATES.setdefault(prefix, {'mode': 'disabled' if prefix.startswith(('/mixed-', '/flexible-')) else ('undecided' if prefix.startswith('/setup-') else 'enabled'),
                                              'setup': prefix.startswith('/setup-'), 'sessions': set(), 'flexible_page': copy.deepcopy(FLEXIBLE_PAGE), 'flexible_revision': 1})
            session = f'fiestaboard_session=fixture-{prefix[1:]}'
            authenticated = session in self.headers.get('Cookie', '') and session in state['sessions']
            body = {}
            if method in ('POST', 'PUT'):
                try:
                    body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
                except (ValueError, json.JSONDecodeError):
                    return self.reply(400, {})
            if method == 'GET' and route == 'health':
                return self.reply(200, CASES['health'])
            if method == 'GET' and route == 'discover':
                return self.reply(200, {'product': 'FiestaBoard', 'version': '10.1.20', 'id': prefix[1:], 'name': 'UI Test Server'})
            if method == 'GET' and route == 'auth/status':
                status = copy.deepcopy(CASES['auth_authenticated' if authenticated else 'auth_enabled'])
                status.update(mode=state['mode'], first_run=state['mode'] == 'undecided',
                              enabled=state['mode'] != 'disabled', setup_required=state['setup'] and state['mode'] != 'disabled')
                status['username'] = 'fixture_admin' if authenticated else None
                return self.reply(200, status)
            if method == 'POST' and route == 'auth/preference' and state['mode'] == 'undecided':
                state['mode'] = 'enabled' if body.get('enabled') else 'disabled'
                return self.reply(200, {'status': 'ok'})
            if method == 'POST' and route in ('auth/setup', 'auth/login'):
                if body.get('username') != 'fixture_admin' or body.get('password') != 'fixture-password':
                    return self.reply(401, CASES['login_wrong'])
                if route == 'auth/setup':
                    if not state['setup']:
                        return self.reply(409, CASES['setup_duplicate'])
                    state['setup'] = False
                state['sessions'].add(session)
                cookie = session + f'; Path={prefix}/api; HttpOnly; SameSite=Lax'
                if body.get('remember_me'):
                    cookie += '; Max-Age=2592000'
                return self.reply(201 if route == 'auth/setup' else 200, {'status': 'ok', 'username': 'fixture_admin'}, cookie)
            if method == 'POST' and route == 'auth/logout':
                state['sessions'].discard(session)
                return self.reply(200, {'status': 'ok'}, session + f'; Path={prefix}/api; Max-Age=0')
            if state['mode'] != 'disabled' and not authenticated:
                return self.reply(401, CASES['protected_unauthenticated'])
            if method == 'GET' and route == 'version':
                # Use an audited nondevelopment candidate so the UI's read-only
                # assertion actually detects accidental setup-time write opt-in.
                return self.reply(200, {**CASES['version'], 'build_version': '10.1.20', 'is_dev': False})
            if method == 'GET' and route == 'v1/boards':
                return self.reply(200, CASES['boards_list'])
            if method == 'GET' and route == 'v1/boards/contract-board':
                return self.reply(200, CASES['boards_detail'])
            if method == 'GET' and route == 'v1/pages/id-2':
                return self.reply(200, CASES['page_get'])
            if method == 'GET' and route == 'v1/pages/flexible':
                return self.reply(200, state['flexible_page'])
            if method == 'PUT' and route == 'v1/pages/flexible':
                current = state['flexible_page']
                if body.get('expected_revision') != current['revision']:
                    return self.reply(412, {'detail': 'Page changed; fetch for comparison'})
                if set(body) - {'expected_revision', 'name', 'blocks', 'style', 'layout', 'targets'}:
                    return self.reply(422, {'detail': 'Unsupported page patch fields'})
                if body.get('blocks') == []:
                    return self.reply(422, {'detail': 'Flexible page requires at least one block'})
                for key, value in body.items():
                    if key != 'expected_revision' and not (key == 'blocks' and value is None):
                        current[key] = value
                state['flexible_revision'] += 1
                current['revision'] = f"flex-r{state['flexible_revision']}"
                return self.reply(200, {'page': current, 'incompatible_references': []})
            if method == 'POST' and route == 'pages/preview/flexible':
                # Exact target semantics: explicit unknown/empty -> 404; null/omitted -> primary.
                if body.get('board_id') is not None and body['board_id'] != 'contract-board':
                    return self.reply(404, {'detail': 'Board not found'})
                page = body.get('page', {})
                if page.get('type') != 'flexible' or set(page) & GRID_FIELDS or not page.get('blocks'):
                    return self.reply(422, {'detail': 'Invalid flexible author content'})
                restrictions = page.get('targets') or {}
                if restrictions.get('boards') is not None and 'contract-board' not in restrictions['boards']:
                    return self.reply(422, {'detail': 'Page does not target this board'})
                pixels = bytearray([0, 0, 0, 255] * (32 * 16))
                for y in range(2, 14):
                    for x in range(3, 29):
                        offset = (y * 32 + x) * 4
                        pixels[offset:offset + 4] = bytes([255, 128 if x < 16 else 255, 64, 255])
                text = '\n'.join(block.get('text', '') for block in page['blocks'] if block.get('kind') == 'text')
                return self.reply(200, {'available': True, 'page_id': 'unsaved', 'message': text,
                    'lines': text.split('\n'), 'display_type': 'panel', 'raw': {},
                    'layout_issues': [{'path': ['blocks', 'retained'], 'code': 'block_kind_unsupported',
                        'severity': 'warning', 'message': 'Synthetic fixture: retained unknown block is not drawn.'}],
                    'canvas_issues': [], 'layers': [{'x': 0, 'y': 0, 'width': 32, 'height': 16,
                        'physical_frame_version': 1, 'rgba': base64.b64encode(pixels).decode()}]})
            if prefix.startswith('/mixed-') and method == 'POST' and route == 'templates/render':
                pixels = bytearray([0, 0, 0, 255] * (32 * 8))
                pixels[:4] = bytes([255, 128, 64, 255])
                pixels[-4:] = bytes([64, 128, 255, 255])
                return self.reply(200, {'rendered': '', 'lines': [''], 'line_count': 1,
                    'charset': 'ascii', 'charset_issues': [], 'canvas_issues': [],
                    'layers': [{'x': 0, 'y': 0, 'width': 32, 'height': 8,
                        'physical_frame_version': 1, 'rgba': base64.b64encode(pixels).decode()}]})
            if method == 'GET' and route == 'v1/pages':
                pages = [CASES['page_get']]
                if prefix.startswith(('/mixed-', '/flexible-')):
                    pages += [
                        state['flexible_page'],
                        {'id': 'future', 'name': 'Future document', 'type': 'future',
                         'document_protocol': 'page-document-v99', 'revision': 'future-r1'},
                    ]
                return self.reply(200, {'pages': pages, 'total': len(pages)})
            return self.reply(404, {})  # Only the synthetic conditional flexible page PUT is supported.

    def reply(self, status, body, cookie=None):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        if cookie:
            self.send_header('Set-Cookie', cookie)
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18442), Handler).serve_forever()

#!/usr/bin/env python3
"""Loopback-only UI scenarios. No backend imports, device writes or real accounts.

Run before xcodebuild test. Each /signin-UUID or /setup-UUID prefix owns fresh
state. Payload shapes come from the separately verified HTTP corpus; this
server proves native UI/transport composition, not backend compatibility.
"""
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


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log request bodies, cookies or credentials.

    def do_GET(self):
        self.handle_request('GET')

    def do_POST(self):
        self.handle_request('POST')

    def handle_request(self, method):
        if self.path == '/ready':
            return self.reply(200, {'fixture': 'native-onboarding'})
        parts = self.path.split('/api/', 1)
        if len(parts) != 2 or not parts[0].startswith(('/signin-', '/setup-')):
            return self.reply(404, {})
        prefix, route = parts
        with LOCK:
            state = STATES.setdefault(prefix, {'mode': 'undecided' if prefix.startswith('/setup-') else 'enabled',
                                              'setup': prefix.startswith('/setup-'), 'sessions': set()})
            session = f'fiestaboard_session=fixture-{prefix[1:]}'
            authenticated = session in self.headers.get('Cookie', '') and session in state['sessions']
            body = {}
            if method == 'POST':
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
            if method == 'GET' and route == 'v1/pages':
                return self.reply(200, {'pages': [CASES['page_get']], 'total': 1})
            return self.reply(404, {})  # Every device/content mutation is deliberately absent.

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

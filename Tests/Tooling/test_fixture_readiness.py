"""Execute the shared Swift preflight, including deterministic transport/deadline controls."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path.home() / 'Library/Developer/FiestaBoard/ios/cx-iosnext5-readiness-controls'


class FixtureReadinessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        main = BUILD / 'main.swift'
        main.write_text('''import Foundation
func expect(_ value: Bool, _ message: String) { precondition(value, message) }
let good = Data(#"{"fixture":"native-onboarding"}"#.utf8)
if CommandLine.arguments.count > 1 {
    do { try FixtureReadiness.require(URL(string: CommandLine.arguments[1])!); print("ready") }
    catch { print("failed: \\(error)"); exit(1) }
} else {
    let url = URL(string: "http://127.0.0.1:1/ready")!
    var clock = 0.0, calls = 0
    try FixtureReadiness.require(url, now: { clock }, pause: { clock += $0 }, attempt: { request, limit in
        expect(request.httpMethod == "GET" && limit <= 3, "health GET only, three-second attempt bound")
        calls += 1
        if calls == 1 { clock += limit; throw URLError(.timedOut) }
        return (200, good)
    })
    expect(calls == 2 && clock < 9, "transient preflight recovers within total budget")
    for reply in [(503, good), (200, Data(#"{"fixture":"wrong"}"#.utf8)), (200, Data("not-json".utf8))] {
        calls = 0; clock = 0
        do {
            try FixtureReadiness.require(url, now: { clock }, pause: { clock += $0 }, attempt: { _, _ in calls += 1; return reply })
            preconditionFailure("wrong fixture must fail")
        } catch { expect(calls == 1, "protocol/identity errors must not retry") }
    }
    calls = 0; clock = 0
    do {
        try FixtureReadiness.require(url, now: { clock }, pause: { clock += $0 }, attempt: { _, limit in
            calls += 1; clock += limit; throw URLError(.timedOut)
        })
        preconditionFailure("missing fixture must fail")
    } catch { expect(calls == 3 && clock <= 9.000001, "finite three-attempt/nine-second budget") }
    for cancellation in [URLError(.cancelled), URLError(.unsupportedURL)] {
        calls = 0; clock = 0
        do {
            try FixtureReadiness.require(url, now: { clock }, pause: { clock += $0 }, attempt: { _, _ in calls += 1; throw cancellation })
            preconditionFailure("cancellation/non-transient transport must fail")
        } catch { expect(calls == 1, "do not retry cancellation/non-transient transport") }
    }
    calls = 0; clock = 0
    do {
        try FixtureReadiness.require(url, now: { clock }, pause: { clock += $0 }, attempt: { _, _ in calls += 1; clock = 10; return (200, good) })
        preconditionFailure("late success must fail")
    } catch { expect(calls == 1, "total deadline applies to successes too") }
    print("all controls passed")
}
''')
        cls.binary = BUILD / 'controls'
        result = subprocess.run(['swiftc', '-swift-version', '6', '-module-cache-path', str(BUILD / 'modules'),
                                 str(ROOT / 'Tests/UITests/FixtureReadiness.swift'), str(main), '-o', str(cls.binary)],
                                text=True, capture_output=True)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def test_retry_classification_and_total_deadline(self):
        result = subprocess.run([str(self.binary)], text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('all controls passed', result.stdout)

    def test_real_urlsession_requires_exact_ready_identity(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                data = b'{"fixture":"native-onboarding"}' if self.path == '/ready' else b'{"fixture":"wrong"}'
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for path, expected in [('/ready', 0), ('/wrong', 1)]:
                result = subprocess.run([str(self.binary), f'http://127.0.0.1:{server.server_port}{path}'],
                                        text=True, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

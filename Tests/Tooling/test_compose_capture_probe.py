"""Pure DEBUG capability lifecycle controls; synthetic metadata, never capture proof.

This intentionally compiles the absent owner file for the first RED boundary.
The host executable exercises the same pure lifecycle used by the future native
picker/stream adapter. It imports no ScreenCaptureKit and grants no permission.
"""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(os.environ.get('CX_COMPOSE_PROBE_BUILD_DIR', str(Path.home() / 'Library/Developer/FiestaBoard/ios/cx-i8-capture-probe-controls')))


class ComposeCaptureProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        main = BUILD / 'main.swift'
        main.write_text('''import Foundation
while let line = readLine() {
    let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    var lifecycle = ComposeCaptureProbeLifecycle(enabled: input["enabled"] as? Bool ?? true,
        namespace: input["namespace"] as? String, osMajor: input["osMajor"] as? Int ?? 27)
    var snapshots: [[String: Any]] = []
    func snapshot(_ requested: Bool? = nil) -> [String: Any] {
        var value: [String: Any] = ["phase": lifecycle.phase.rawValue,
            "cleanupRequested": lifecycle.cleanupRequested, "streamOwned": lifecycle.streamOwned, "report": NSNull()]
        if let report = lifecycle.report {
            value["report"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
        }
        if let requested { value["requested"] = requested }
        return value
    }
    snapshots.append(snapshot())
    for action in input["actions"] as? [[String: Any]] ?? [] {
        var requested: Bool?
        switch action["kind"] as? String {
        case "request": requested = lifecycle.requestStart(isAvailable: action["available"] as? Bool ?? true)
        case "select": requested = lifecycle.selectedCurrentApplication()
        case "owned": lifecycle.streamConstructed()
        case "started": lifecycle.streamStarted()
        case "retryCleanup": requested = lifecycle.requestCleanupRetry()
        case "frame":
            let data = try JSONSerialization.data(withJSONObject: action["metadata"]!)
            lifecycle.receivedFrame(try JSONDecoder().decode(ComposeCaptureProbeFrame.self, from: data))
        case "cancel": lifecycle.pickerCancelled()
        case "error": lifecycle.failed(domain: action["domain"] as? String ?? "SCStreamErrorDomain", code: action["code"] as? Int ?? -3823)
        case "inactive": lifecycle.sceneBecameInactive()
        case "stop": lifecycle.stopRequested()
        case "timeout": lifecycle.deadlineExpired()
        case "cleanup": lifecycle.cleanedUp()
        case "cleanupFailure": lifecycle.cleanupFailed(domain: "SCStreamErrorDomain", code: -3819)
        default: break
        }
        snapshots.append(snapshot(requested))
    }
    print(String(data: try JSONSerialization.data(withJSONObject: snapshots, options: [.sortedKeys]), encoding: .utf8)!)
}
''')
        cls.binary = BUILD / 'controls'
        command = ['swiftc', '-swift-version', '6', '-D', 'DEBUG',
                   '-module-cache-path', str(BUILD / 'modules'),
                   str(ROOT / 'App/Features/Compose/ComposeCaptureProbeLifecycle.swift'),
                   str(main), '-o', str(cls.binary)]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)

    def run_lifecycle(self, actions, **configuration):
        configuration.setdefault('namespace', '90000000-0000-4000-8000-000000000008')
        result = subprocess.run([str(self.binary)],
            input=json.dumps(dict(actions=actions, **configuration))+'\n',
            capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def frame(self, **changes):
        # All timestamps/metadata here are synthetic controls, not SDK observations.
        rect = dict(x=0, y=0, width=402, height=874)
        result = dict(outputType='screen', status=0, displayTicks=1000, receivedTicks=1100,
            timebaseNumer=1, timebaseDenom=1, width=1206, height=2622,
            pixelFormat=875704438, videoOrientation=6, contentRect=rect,
            contentScale=1, scaleFactor=3, screenRect=rect,
            filterContentRect=rect, filterPointPixelScale=3)
        result.update(changes)
        return result

    def start(self):
        return [dict(kind='request'), dict(kind='select'), dict(kind='owned'), dict(kind='started')]

    def test_no_automatic_capture_or_selection_without_explicit_request(self):
        result = self.run_lifecycle([dict(kind='select'), dict(kind='started')])
        self.assertEqual([r['phase'] for r in result], ['idle', 'idle', 'idle'])
        self.assertFalse(result[1]['requested'])
        self.assertTrue(all(r['report'] is None for r in result))

    def test_diagnostic_flag_namespace_os_and_device_availability_fail_closed(self):
        controls = [({'enabled': False}, 'disabled'), ({'namespace': None}, 'missing_namespace'),
                    ({'namespace': ''}, 'missing_namespace'), ({'namespace': 'normal-user'}, 'invalid_namespace'),
                    ({'osMajor': 26}, 'unsupported_os')]
        for configuration, reason in controls:
            with self.subTest(reason=reason, configuration=configuration):
                result = self.run_lifecycle([dict(kind='request')], **configuration)[-1]
                self.assertFalse(result['requested'])
                self.assertEqual(result['phase'], 'finished')
                self.assertEqual(result['report']['reason'], reason)
                self.assertEqual(result['report']['status'], 'failed')
        result = self.run_lifecycle([dict(kind='request', available=False)])[-1]
        self.assertFalse(result['requested'])
        self.assertEqual(result['report']['reason'], 'unavailable')

    def test_complete_screen_metadata_is_published_only_after_cleanup_without_latency(self):
        metadata = self.frame()
        result = self.run_lifecycle(self.start()+[dict(kind='frame', metadata=metadata), dict(kind='cleanup')])
        self.assertEqual([r['phase'] for r in result], ['idle', 'awaitingConsent', 'starting', 'starting', 'capturing', 'stopping', 'finished'])
        self.assertTrue(result[1]['requested'])
        self.assertTrue(result[2]['requested'])
        self.assertTrue(result[-2]['cleanupRequested'])
        self.assertIsNone(result[-2]['report'])
        report = result[-1]['report']
        self.assertEqual(report['status'], 'metadata_captured')
        self.assertEqual(report['frame'], metadata)
        self.assertTrue(report['cleanupCompleted'])
        for forbidden in ['latency', 'presentation', 'p95', 'postDebounceUpperBoundSeconds', 'firstObservedPresentation']:
            self.assertNotIn(forbidden, report)

    def test_picker_cancellation_prevents_late_selection_and_records_failure(self):
        result = self.run_lifecycle([dict(kind='request'), dict(kind='cancel'), dict(kind='select'), dict(kind='cleanup')])
        self.assertFalse(result[-2]['requested'])
        self.assertEqual(result[-1]['report']['status'], 'failed')
        self.assertEqual(result[-1]['report']['reason'], 'canceled')
        self.assertTrue(result[-1]['report']['cleanupCompleted'])

    def test_noncomplete_and_nonscreen_samples_cannot_establish_capability(self):
        actions = self.start()
        for status in [1, 2, 3, 4, 5]:
            actions.append(dict(kind='frame', metadata=self.frame(status=status)))
        actions.append(dict(kind='frame', metadata=self.frame(outputType='audio')))
        actions += [dict(kind='timeout'), dict(kind='cleanup')]
        result = self.run_lifecycle(actions)
        self.assertTrue(all(r['report'] is None for r in result[:-1]))
        self.assertEqual(result[-1]['report']['status'], 'failed')
        self.assertEqual(result[-1]['report']['reason'], 'timeout')

    def test_invalid_complete_metadata_stops_without_claiming_capture_support(self):
        for changes in [dict(displayTicks=None), dict(displayTicks=0), dict(displayTicks=1200),
                        dict(timebaseDenom=0), dict(width=0), dict(pixelFormat=0),
                        dict(videoOrientation=None), dict(contentRect=None), dict(contentScale=0),
                        dict(scaleFactor=0), dict(screenRect=None), dict(filterPointPixelScale=0)]:
            with self.subTest(changes=changes):
                result = self.run_lifecycle(self.start()+[dict(kind='frame', metadata=self.frame(**changes)), dict(kind='cleanup')])
                self.assertEqual(result[-1]['report']['status'], 'failed')
                self.assertEqual(result[-1]['report']['reason'], 'invalid_metadata')

    def test_inactive_or_stopped_probe_rejects_late_complete_frames(self):
        for action, reason in [('inactive', 'scene_inactive'), ('stop', 'stopped')]:
            with self.subTest(action=action):
                result = self.run_lifecycle(self.start()+[dict(kind=action), dict(kind='frame', metadata=self.frame()), dict(kind='cleanup')])
                self.assertEqual(result[-1]['report']['reason'], reason)
                self.assertNotIn('frame', result[-1]['report'])

    def test_stream_error_is_structured_and_not_skipped(self):
        result = self.run_lifecycle(self.start()+[dict(kind='error', domain='SCStreamErrorDomain', code=-3823), dict(kind='cleanup')])[-1]
        self.assertEqual(result['report']['status'], 'failed')
        self.assertEqual(result['report']['reason'], 'stream_error')
        self.assertEqual(result['report']['errorDomain'], 'SCStreamErrorDomain')
        self.assertEqual(result['report']['errorCode'], -3823)

    def test_cleanup_failure_cannot_publish_a_successful_capability_result(self):
        result = self.run_lifecycle(self.start()+[dict(kind='frame', metadata=self.frame()), dict(kind='cleanupFailure')])[-1]
        self.assertEqual(result['phase'], 'finished')
        self.assertEqual(result['report']['status'], 'failed')
        self.assertEqual(result['report']['reason'], 'cleanup_failed')
        self.assertFalse(result['report']['cleanupCompleted'])
        self.assertNotIn('frame', result['report'])

    def test_cleanup_retry_retains_stream_until_actual_success_and_keeps_failed_report(self):
        result = self.run_lifecycle(self.start()+[dict(kind='frame', metadata=self.frame()),
            dict(kind='cleanupFailure'), dict(kind='retryCleanup'), dict(kind='cleanup'), dict(kind='retryCleanup')])
        failed, retrying, cleaned, duplicate = result[-4:]
        self.assertTrue(failed['streamOwned'])
        self.assertFalse(failed['report']['cleanupCompleted'])
        self.assertTrue(retrying['requested'])
        self.assertTrue(retrying['streamOwned'])
        self.assertEqual(retrying['phase'], 'stopping')
        self.assertFalse(retrying['report']['cleanupCompleted'])
        self.assertFalse(cleaned['streamOwned'])
        self.assertTrue(cleaned['report']['cleanupCompleted'])
        self.assertEqual(cleaned['report']['status'], 'failed')
        self.assertFalse(duplicate['requested'])

    def test_scene_inactive_cleanup_failure_can_retry_but_cannot_adopt_late_frame(self):
        result = self.run_lifecycle(self.start()+[dict(kind='inactive'), dict(kind='cleanupFailure'),
            dict(kind='retryCleanup'), dict(kind='frame', metadata=self.frame()), dict(kind='cleanup')])[-1]
        self.assertEqual(result['report']['status'], 'failed')
        self.assertTrue(result['report']['cleanupCompleted'])
        self.assertFalse(result['streamOwned'])
        self.assertNotIn('frame', result['report'])

    def test_cleanup_retry_without_failed_owned_stream_cannot_start_capture(self):
        for actions in [[dict(kind='retryCleanup')], [dict(kind='request'), dict(kind='retryCleanup')],
                        self.start()+[dict(kind='retryCleanup')]]:
            with self.subTest(actions=actions):
                self.assertFalse(self.run_lifecycle(actions)[-1]['requested'])

    def test_started_callback_without_constructed_stream_does_not_establish_capture(self):
        result = self.run_lifecycle([dict(kind='request'), dict(kind='select'), dict(kind='started')])[-1]
        self.assertEqual(result['phase'], 'starting')
        self.assertFalse(result['streamOwned'])
        self.assertIsNone(result['report'])

    def test_late_cleanup_error_cannot_revoke_proven_stop_success(self):
        result = self.run_lifecycle(self.start()+[dict(kind='frame', metadata=self.frame()),
            dict(kind='cleanupFailure'), dict(kind='retryCleanup'), dict(kind='cleanup'), dict(kind='cleanupFailure')])
        self.assertEqual(result[-1]['report'], result[-2]['report'])
        self.assertTrue(result[-1]['report']['cleanupCompleted'])

    def test_first_complete_sample_and_terminal_report_are_immutable(self):
        actions = self.start()+[dict(kind='frame', metadata=self.frame()), dict(kind='frame', metadata=self.frame(displayTicks=1050)), dict(kind='cleanup'), dict(kind='cleanup'), dict(kind='request')]
        result = self.run_lifecycle(actions)
        self.assertEqual(result[-1]['report']['frame']['displayTicks'], 1000)
        self.assertEqual(result[-1]['report'], result[-2]['report'])
        self.assertFalse(result[-1]['requested'])


if __name__ == '__main__':
    unittest.main()

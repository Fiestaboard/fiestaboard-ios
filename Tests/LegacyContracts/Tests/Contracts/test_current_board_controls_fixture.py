"""Native-consumable assertions on the source-bound board-control corpus."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]


class CurrentBoardControlsFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'Fixtures/contracts/current/board-control.json').read_text())
        cls.cases={case['id']:case for case in cls.fixture['cases']}

    def test_receipts_do_not_conflate_policy_partial_error_and_output(self):
        expected={'message_contract-board':200,'message_contract-led':200,'message_unchanged':200,
                  'message_ui':200,'message_paused_preview':200,'message_held':202,
                  'message_failed':500,'message_timeout':500,'message_malformed':500,
                  'message_throttled':429,'message_superseded':409,'message_partial':502,
                  'message_paused':409,'message_silenced':409}
        self.assertEqual(len(self.cases),len(self.fixture['cases']))
        for cid,status in expected.items(): self.assertEqual(self.cases[cid]['response']['status'],status,cid)
        for cid in ['message_contract-board','message_contract-led']:
            self.assertTrue(self.cases[cid]['response']['body']['sent'])
            self.assertEqual(len(self.cases[cid]['boundary_calls']),1)
            self.assertFalse(self.cases[cid]['boundary_calls'][0]['force'])
        for cid in ['message_unchanged','message_ui','message_paused_preview','message_held']:
            self.assertFalse(self.cases[cid]['response']['body']['sent'])
            self.assertTrue(self.cases[cid]['response']['body']['reason'])
        for cid in ['message_ui','message_paused_preview','message_held','message_paused','message_silenced']:
            self.assertEqual(self.cases[cid]['boundary_calls'],[],cid)
        held=self.cases['message_held']['response']['body']
        self.assertTrue(held['held']);self.assertTrue(held['silenced'])
        partial=self.cases['message_partial']['response']['body']['detail']
        self.assertTrue(partial['partial'])
        self.assertEqual(partial['failed_regions'],[{'row':0,'col':15,'rows':3,'cols':15}])
        self.assertEqual(self.cases['message_throttled']['response']['headers'],{'retry-after':'7'})

    def test_restore_acknowledgement_is_never_device_observation(self):
        for cid in ['restore_ack','restore_no_output','restore_ui']:
            self.assertFalse(self.cases[cid]['response']['body']['device_observed'])
        self.assertTrue(self.cases['restore_ack']['response']['body']['sent'])
        self.assertTrue(self.cases['restore_ack']['boundary_calls'])
        self.assertFalse(self.cases['restore_no_output']['response']['body']['sent'])
        self.assertEqual(self.fixture['boundary_evidence']['hardware_sends'],0)
        self.assertEqual(self.fixture['boundary_evidence']['real_provider_fetches'],0)

    def test_conditional_default_retains_original_generation_and_explicit_clear(self):
        initial=self.cases['default_get']['response']['body']
        changed=self.cases['default_set']['response']['body']
        for cid in ['default_set','default_stale']:
            self.assertEqual(self.cases[cid]['request']['body']['expected_revision'],initial['revision'])
        self.assertNotEqual(initial['revision'],changed['revision'])
        self.assertEqual(initial['edit_protocol'],'schedule-default-revision-v1')
        self.assertEqual(self.cases['default_stale']['response']['status'],412)
        clear=self.cases['default_clear']
        self.assertIsNone(clear['request']['body']['page_id'])
        self.assertEqual(clear['request']['body']['expected_revision'],changed['revision'])
        self.assertIsNone(clear['response']['body']['default_page_id'])
        self.assertTrue(self.cases['detail_after_nonatomic']['response']['body']['paused'])
        self.assertEqual(self.cases['patch_nonatomic']['response']['status'],404)

    def test_concrete_geometry_and_rich_led_boundary(self):
        boards=self.cases['boards_list']['response']['body']['boards']
        self.assertEqual([(b['id'],b['rows'],b['cols']) for b in boards],
                         [('contract-board',6,22),('contract-led',8,16),('contract-array',3,30)])
        self.assertEqual(boards[1]['charset'],'led_5x7')
        self.assertEqual(boards[1]['device_model'],'fiestapanel_led_matrix')
        self.assertIsNone(self.cases['message_contract-board']['boundary_calls'][0]['cells'])
        self.assertIsNotNone(self.cases['message_contract-led']['boundary_calls'][0]['cells'])
        failed=self.cases['page_send_failed']['response']['body']
        self.assertFalse(failed['sent']);self.assertTrue(failed['error']);self.assertTrue(failed['page_id'])

    def test_secondary_controls_keep_primary_selection_and_defaults(self):
        pin=self.cases['page_led_select']['response']['body']
        self.assertEqual(pin['board_id'],'contract-led')
        primary=self.cases['detail_primary_after_led_select']['response']['body']
        self.assertNotEqual(primary['active_page_id'],pin['page_id'])
        for cid in ['restore_led','patch_led_pause','patch_led_resume']:
            self.assertEqual(self.cases[cid]['response']['body'].get('board_id',self.cases[cid]['response']['body'].get('id')),'contract-led')
        self.assertTrue(self.cases['restore_led']['response']['body']['sent'])
        self.assertEqual({call['board_id'] for call in self.cases['restore_led']['boundary_calls']},{'contract-led'})
        self.assertFalse(self.cases['restore_led_schedule_gap']['response']['body']['sent'])
        self.assertFalse(self.cases['detail_primary_after_led_pause']['response']['body']['paused'])
        original=self.cases['default_led_get']['response']['body']
        changed=self.cases['default_led_set']
        self.assertEqual(changed['request']['body']['board_id'],'contract-led')
        self.assertEqual(changed['request']['body']['expected_revision'],original['revision'])
        before=self.cases['default_primary_before_led_set']['response']['body']
        after=self.cases['default_primary_after_led_set']['response']['body']
        self.assertEqual(after['default_page_id'],before['default_page_id'])
        self.assertNotEqual(after['revision'],before['revision'])
        self.assertEqual(self.cases['default_primary_invalidated_by_secondary']['response']['status'],412)
        self.assertEqual(self.cases['default_led_after_set']['response']['body'],changed['response']['body'])
        self.assertIn('?board_id=contract-led',self.cases['default_led_after_set']['request']['path'])

    def test_timed_refusal_does_not_become_an_override(self):
        self.assertEqual(self.cases['message_timed_throttled']['response']['status'],429)
        timed=self.cases['message_timed_ack']['response']['body']
        self.assertTrue(timed['sent'])
        self.assertEqual(timed['expires_at'],'<timestamp>')
        for cid in ['message_timed_secondary','message_timed_raw']:
            self.assertEqual(self.cases[cid]['response']['status'],400)
            self.assertEqual(self.cases[cid]['boundary_calls'],[])

    def test_sparse_controls_preserve_omission_and_null_without_revision_claim(self):
        for cid,field,value in [('patch_pause','paused',True),('patch_resume','paused',False),
                                ('patch_schedule','schedule_enabled',True),('patch_auto_restore','auto_restore',False)]:
            case=self.cases[cid]
            self.assertEqual(case['request']['body'],{field:value})
            self.assertEqual(case['response']['body'][field],value)
            self.assertNotIn('revision',case['response']['body'])
        before=self.cases['patch_auto_restore']['response']['body']
        after=self.cases['patch_null_scalars']['response']['body']
        for field in ['paused','schedule_enabled','auto_restore']:
            self.assertEqual(before[field],after[field])
        self.assertFalse(self.cases['detail_primary_after_led_select']['response']['body']['schedule_enabled'])

    def test_request_credentials_are_cookie_metadata_only(self):
        for case in self.fixture['cases']:
            cookie=case['request']['headers']['cookie']
            self.assertEqual(set(cookie),{'name','present'})
            self.assertTrue(cookie['present'])
            self.assertNotIn('authorization',case['request']['headers'])
            self.assertNotIn('password',case['request'].get('body',{}))

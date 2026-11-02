"""Board, status and page fixtures for the `/board-<scenario>-<n>/` prefix family.

Loaded by fixture_server.py when present. Everything here is mock content with
the wire shapes verified at FiestaBoard v10.3.2 (PLAN §2.3, §4.2, §4.3). The
fixture never evaluates templates; board frames are pre-encoded character codes.

Scenarios (PLAN §4.2): manual, schedule, schedule-gap, collection,
collection-native-null, override, paused, silence. Unknown scenarios behave as
manual.
"""
import copy
import time

CHARS = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#$()\x00-\x00+&=;:\x00\'"%,.\x00\x00/?\x00'
COLORS = {'red': 63, 'orange': 64, 'yellow': 65, 'green': 66, 'blue': 67, 'violet': 68,
          'white': 69, 'black': 70, 'filled': 71}
COLLECTION_ID = 'collection:9b3a1c2e-0000-4000-8000-00000000c011'
COLLECTION_UUID = COLLECTION_ID.split(':', 1)[1]


def encode(markup, cols):
    """Markup (`{red}` tiles, `°`/`♥` = code 62) → one row of codes, cut/padded to cols."""
    row, i = [], 0
    while i < len(markup):
        ch = markup[i]
        if ch == '{' and '}' in markup[i:]:
            end = markup.index('}', i)
            name = markup[i + 1:end]
            if name in COLORS:
                row.append(COLORS[name]); i = end + 1; continue
        if ch in '°♥':
            row.append(62)
        else:
            idx = CHARS.find(ch.upper()) if ch != '\x00' else -1
            row.append(idx if idx > 0 else 0)
        i += 1
    return (row + [0] * cols)[:cols]


def frame(lines, rows, cols, align='center'):
    grid = []
    for r in range(rows):
        text = lines[r] if r < len(lines) else ''
        width = min(cols, len(encode_strip(text)))
        pad = (cols - width) // 2 if align == 'center' else 0
        grid.append(([0] * pad + encode(text, cols))[:cols])
    return grid


def encode_strip(markup):
    out, i = [], 0
    while i < len(markup):
        if markup[i] == '{' and '}' in markup[i:]:
            end = markup.index('}', i)
            if markup[i + 1:end] in COLORS:
                out.append(1); i = end + 1; continue
        out.append(1); i += 1
    return out


def text_of(grid):
    lines = []
    for row in grid:
        s = ''
        for c in row:
            s += '°' if c == 62 else (' ' if c >= 63 or c == 0 or c >= len(CHARS) else CHARS[c])
        lines.append(s.rstrip())
    return '\n'.join(lines)


HELLO = ['', '', 'HELLO {red}{orange}{yellow} WORLD 62°']

# PLAN §4.2. `summary` = /v1/boards entry (v1 fields only); `stored` = extra
# /settings/board BoardInstance fields; `lines` = what the board shows.
BOARDS = [
    {'summary': {'id': 'kitchen', 'name': 'Kitchen', 'device_type': 'flagship', 'rows': 6, 'cols': 22,
                 'is_primary': True, 'output': 'vestaboard', 'device_model': 'vestaboard_flagship', 'charset': 'vestaboard_v1'},
     'stored': {'board_color': 'black', 'code62_glyph': 'degree'}, 'lines': HELLO},
    {'summary': {'id': 'hall', 'name': 'Hall', 'device_type': 'flagship', 'rows': 6, 'cols': 22,
                 'is_primary': False, 'output': 'vestaboard', 'device_model': 'vestaboard_flagship', 'charset': 'vestaboard_v2'},
     'stored': {'board_color': 'black', 'code62_glyph': 'heart'}, 'lines': HELLO},
    {'summary': {'id': 'desk', 'name': 'Desk', 'device_type': 'note', 'rows': 3, 'cols': 15,
                 'is_primary': False, 'output': 'vestaboard', 'device_model': 'vestaboard_note', 'charset': 'vestaboard_v2'},
     'stored': {'board_color': 'white', 'code62_glyph': 'heart'},
     'lines': ['DESK NOTE', '{white}{black} LOVE ♥ {red}', 'WHITE BOARD']},
    {'summary': {'id': 'wall', 'name': 'Wall', 'device_type': 'note_array', 'rows': 6, 'cols': 30,
                 'is_primary': False, 'output': 'vestaboard', 'device_model': 'vestaboard_note_array', 'charset': 'vestaboard_v2'},
     'stored': {'board_color': 'black', 'notes_wide': 2, 'notes_tall': 2},
     'lines': ['', 'FOUR NOTES MAKE ONE WALL', '{red}{orange}{yellow}{green}{blue}{violet}', 'SEAMS EVERY 15 COLUMNS', 'AND EVERY 3 ROWS', '']},
    {'summary': {'id': 'tv', 'name': 'Living room TV', 'device_type': 'panel', 'rows': 12, 'cols': 29,
                 'is_primary': False, 'output': 'fiestapanel', 'device_model': 'vestaboard_panel', 'charset': 'vestaboard_v2'},
     'stored': {'grid_rows': 12, 'grid_cols': 29}, 'lines': ['', '', '', '', 'LIVING ROOM TV', '', '{blue}{blue}{blue} PANEL {blue}{blue}{blue}']},
    {'summary': {'id': 'pixoo', 'name': 'Pixoo', 'device_type': 'panel', 'rows': 10, 'cols': 16,
                 'is_primary': False, 'output': 'divoom_pixoo', 'device_model': 'divoom_pixoo64', 'charset': 'led_3x5'},
     'stored': {'output': 'divoom_pixoo', 'device_model': 'divoom_pixoo64'}, 'lines': ['', '', '', '', 'HI {red}!']},
    {'summary': {'id': 'pixoo57', 'name': 'Pixoo (5x7) — mock-only', 'device_type': 'panel', 'rows': 8, 'cols': 10,
                 'is_primary': False, 'output': 'divoom_pixoo', 'device_model': 'divoom_pixoo64', 'charset': 'led_5x7'},
     'stored': {'device_model_spec': {'id': 'divoom_pixoo64', 'technology': 'led_matrix',
                                      'geometry': {'kind': 'pixels', 'width': 64, 'height': 64},
                                      'color': {'kind': 'rgb', 'bitDepth': 24}, 'charset': 'led_5x7',
                                      'layoutOptions': {'font': '5x7'}}},
     'lines': ['', '', '', 'HI {red}!']},
    {'summary': {'id': 'marquee', 'name': 'Marquee — mock-only', 'device_type': 'panel', 'rows': 2, 'cols': 5,
                 'is_primary': False, 'output': 'acme_marquee', 'device_model': None, 'charset': 'led_5x7'},
     'stored': {'device_model_spec': {'id': 'acme_marquee', 'technology': 'led_matrix',
                                      'geometry': {'kind': 'pixels', 'width': 32, 'height': 16},
                                      'color': {'kind': 'monochrome', 'color': '#ff3b1f', 'bitDepth': 1},
                                      'charset': 'led_5x7', 'font': '5x7'}},
     'lines': ['HOT', '{red}{red}'], 'not_configured': True},
    {'summary': {'id': 'mystery', 'name': 'Mystery', 'device_type': 'flagship', 'rows': 4, 'cols': 20,
                 'is_primary': False, 'output': 'acme_output', 'device_model': 'acme_unknown', 'charset': None},
     'stored': {}, 'lines': ['', 'UNKNOWN MODEL', 'DRAWN AS FLAPS'], 'error': 'Output plugin acme_output failed to start'},
]

PAGE_COMMON = {'display_type': None, 'rows': None, 'line_metadata': None, 'duration_seconds': 300,
               'transition_strategy': None, 'transition_interval_ms': None, 'transition_step_size': None,
               'demo_plugin_id': None, 'notes_wide': 1, 'notes_tall': 1, 'grid_rows': None, 'grid_cols': None,
               'canvases': None, 'created_at': '2026-10-31T08:00:00Z', 'updated_at': '2026-10-31T08:00:00Z',
               'edit_protocol': 'page-revision-v1', 'document_protocol': 'page-document-v1'}

# PLAN §4.3, with `shows` = the frame the fixture pretends the server rendered.
PAGES = [
    {'id': 'hello', 'name': 'Hello World', 'type': 'template', 'device_type': 'flagship',
     'template': ['', '', 'HELLO {{red}}{{orange}}{{yellow}} WORLD 62°'],
     'line_metadata': [{'alignment': 'left', 'wrap': False}, {'alignment': 'left', 'wrap': False}, {'alignment': 'center', 'wrap': False}], 'shows': HELLO},
    {'id': 'morning', 'name': 'Good Morning', 'type': 'template', 'device_type': 'flagship',
     'template': ['GOOD MORNING', '{{weather.temperature|pad:3}}° {{weather.condition}}', '',
                  '{{red}}{{orange}}{{yellow}}{{green}}{{blue}}{{violet}}',
                  '{{= IF(weather.temperature > 70, "WARM OUT", "BRING A COAT") }}', '{{fill_space_repeat:-}}'],
     'line_metadata': [{'alignment': 'center', 'wrap': False}, {'alignment': 'left', 'wrap': False}, {'alignment': 'left', 'wrap': False}, {'alignment': 'center', 'wrap': False}],
     'shows': ['GOOD MORNING', ' 72° SUNNY', '', '{red}{orange}{yellow}{green}{blue}{violet}', 'WARM OUT', '----------------------']},
    {'id': 'note', 'name': 'Desk Note', 'type': 'template', 'device_type': 'note',
     'template': ['HELLO', '{{date_time.time}}', '{{red}} LOVE {{red}}'],
     'line_metadata': [{'alignment': 'center', 'wrap': False}, {'alignment': 'center', 'wrap': False}],
     'shows': ['HELLO', '08:15', '{red} LOVE {red}']},
    {'id': 'wide', 'name': 'Wall Quote', 'type': 'template', 'device_type': 'note_array', 'notes_wide': 2, 'notes_tall': 2,
     'template': ['THE BEST WAY TO PREDICT THE FUTURE IS TO CREATE IT'],
     'line_metadata': [{'alignment': 'center', 'wrap': True}],
     'shows': ['THE BEST WAY TO PREDICT', 'THE FUTURE IS TO CREATE IT']},
    {'id': 'lobby', 'name': 'Lobby', 'type': 'template', 'device_type': 'panel', 'grid_rows': 12, 'grid_cols': 29,
     'template': ['WELCOME TO THE LOBBY', '{{blue}}{{blue}}{{blue}}'], 'shows': ['WELCOME TO THE LOBBY', '{blue}{blue}{blue}']},
    {'id': 'pixel', 'name': 'Pixel Clock', 'type': 'template', 'device_type': 'panel', 'grid_rows': 10, 'grid_cols': 16,
     'template': ['{{date_time.time}}'],
     'canvases': [{'id': 'sun', 'area': {'row': 0, 'col': 0, 'rows': 5, 'cols': 8},
                   'content': {'size': [32, 30], 'background': None, 'palette': {'a': 'yellow'}, 'pixels': ['aa'], 'shapes': []}}],
     'shows': ['08:15']},
    {'id': 'lower', 'name': 'Mixed Case', 'type': 'template', 'device_type': 'flagship',
     'template': ['UPPER ROW', 'lower row kept', 'THIRD'], 'line_metadata': [{'alignment': 'center', 'wrap': False}],
     'shows': ['UPPER ROW', 'LOWER ROW KEPT', 'THIRD']},
    {'id': 'single', 'name': 'Weather (single)', 'type': 'single', 'device_type': 'flagship', 'template': None,
     'document_protocol': None, 'edit_protocol': None, 'shows': ['WEATHER', '72° SUNNY']},
    {'id': 'composite', 'name': 'Mix (composite)', 'type': 'composite', 'device_type': 'flagship', 'template': None,
     'document_protocol': None, 'edit_protocol': None, 'shows': ['MIX', 'TWO PLUGINS']},
]


def _template(lines):
    import re
    return [re.sub(r'\{(red|orange|yellow|green|blue|violet|white|black|filled)\}', r'{{\1}}', line) for line in lines]


# One page per non-Kitchen board, whose frame is exactly what that board shows, so
# Home never says "No page selected" over a board full of content (W2 iOS-R2).
BOARD_PAGES = {'hall': ('hall-hello', 'Hall Hello', {'device_type': 'flagship'}),
               'desk': ('desk-note', 'Desk Love Note', {'device_type': 'note'}),
               'wall': ('wall-seams', 'Four Notes', {'device_type': 'note_array', 'notes_wide': 2, 'notes_tall': 2}),
               'tv': ('tv-welcome', 'Living Room Welcome', {'device_type': 'panel', 'grid_rows': 12, 'grid_cols': 29}),
               'pixoo': ('pixoo-hi', 'Pixoo Hello', {'device_type': 'panel', 'grid_rows': 10, 'grid_cols': 16}),
               'pixoo57': ('pixoo57-hi', 'Pixoo Hello (5x7)', {'device_type': 'panel', 'grid_rows': 8, 'grid_cols': 10}),
               'marquee': ('marquee-hot', 'Marquee Hot', {'device_type': 'panel', 'grid_rows': 2, 'grid_cols': 5}),
               'mystery': ('mystery-flaps', 'Unknown Model Test', {'device_type': 'panel', 'grid_rows': 4, 'grid_cols': 20})}
for _board in BOARDS:
    _bid = _board['summary']['id']
    if _bid in BOARD_PAGES:
        _pid, _name, _geometry = BOARD_PAGES[_bid]
        _rows = _board['summary']['rows']
        _lines = (_board['lines'] + [''] * _rows)[:_rows]
        PAGES.append({'id': _pid, 'name': _name, 'type': 'template', **_geometry, 'template': _template(_lines),
                      'line_metadata': [{'alignment': 'center', 'wrap': False} for _ in _lines], 'shows': _board['lines']})

COLLECTION = {'id': COLLECTION_UUID, 'name': 'Morning rotation', 'page_ids': ['hello', 'morning'],
              'selection_mode': 'time', 'interval_seconds': 2, 'revision': 'collection-r1'}

# Kitchen's schedule (wall-clock HH:MM, weekly), served by /v1/schedules.
SCHEDULE = [('sched-morning', 'morning', '06:00', '10:00', 'all'), ('sched-hello', 'hello', '10:00', '18:00', 'all'),
            ('sched-evening', 'lower', '18:00', '23:00', 'weekends')]


def schedule_entry(entry, board_id):
    sid, page, start, end, pattern = entry
    return {'id': sid, 'revision': 'revision-' + sid, 'board_id': board_id, 'page_id': page, 'start_time': start,
            'end_time': end, 'day_pattern': pattern, 'custom_days': None, 'enabled': True, 'recurrence_type': 'weekly',
            'annual_date': None, 'annual_end_date': None, 'one_off_date': None, 'one_off_end_date': None,
            'start_type': 'fixed', 'start_sun_offset': 0, 'end_type': 'fixed', 'end_sun_offset': 0,
            'created_at': '2026-10-31T08:00:00Z', 'updated_at': None, 'resolved_start_time': start,
            'resolved_end_time': end, 'warnings': [], 'edit_protocol': 'schedule-revision-v1'}


def page_body(page):
    body = {**PAGE_COMMON, **{k: v for k, v in page.items() if k != 'shows'}}
    body['revision'] = 'revision-' + page['id']
    return body


def page_frame(page_id, rows, cols):
    page = next((p for p in PAGES if p['id'] == page_id), None)
    return frame(page['shows'] if page else ['NO PAGE'], rows, cols)


def new_state(scenario):
    boards = {}
    for b in BOARDS:
        s = b['summary']
        boards[s['id']] = {'paused': scenario == 'paused', 'schedule_enabled': scenario.startswith(('schedule', 'collection', 'override')),
                           'auto_restore': True, 'active_page_id': None,
                           'characters': frame(b['lines'], s['rows'], s['cols'])}
    for board_id, (page_id, _, _) in BOARD_PAGES.items():
        boards[board_id]['active_page_id'] = None if scenario == 'no-pages' else page_id
    kitchen = boards['kitchen']
    if scenario in ('manual', 'paused', 'silence'):
        kitchen['active_page_id'] = 'hello'
    elif scenario in ('collection', 'collection-native-null'):
        kitchen['active_page_id'] = COLLECTION_ID
    return {'scenario': scenario, 'boards': boards, 'started': time.time()}


def board_entry(b):
    return next((x for x in BOARDS if x['summary']['id'] == b), None)


def summary(entry, live):
    s = entry['summary']
    return {**s, 'paused': live['paused'], 'schedule_enabled': live['schedule_enabled'], 'auto_restore': live['auto_restore']}


def scheduled_page(state):
    sc = state['scenario']
    if sc in ('schedule', 'override'):
        return 'hello'
    if sc.startswith('collection'):
        return COLLECTION_ID
    return None


def resolved(state, active):
    if active == COLLECTION_ID:
        if state['scenario'] == 'collection-native-null':
            return None
        tick = int((time.time() - state['started']) / 2)
        return COLLECTION['page_ids'][tick % 2]
    return active


def detail(state, entry):
    s = entry['summary']; live = state['boards'][s['id']]
    sc = state['scenario']
    is_kitchen = s['id'] == 'kitchen'
    active = live['active_page_id']
    scheduled = scheduled_page(state) if is_kitchen and live['schedule_enabled'] else None
    shown = resolved(state, active or scheduled)
    if is_kitchen and shown in [p['id'] for p in PAGES]:
        live['characters'] = page_frame(shown, s['rows'], s['cols'])
    source = 'manual' if active else ('schedule' if scheduled else 'none')
    return {**summary(entry, live), 'characters': live['characters'], 'text': text_of(live['characters']),
            'expected_characters': live['characters'], 'read_at': None,
            'active_page_id': active, 'scheduled_page_id': scheduled,
            'resolved_page_id': shown if (active or scheduled) else None,
            'resolved_next_check_seconds': 2 if (active or scheduled) == COLLECTION_ID else None,
            'source': source, 'default_page_id': None,
            'override_expires_at': '2026-10-31T09:09:00Z' if (is_kitchen and sc == 'override') else None,
            'layers': [{'x': 40, 'y': 2, 'width': 2, 'height': 2,
                        'rgba': 'AP8A/wD/AP8A/wD/AP8A/w=='}] if s['id'] == 'pixoo' else None}


def stored_board(entry, live):
    s = entry['summary']
    base = {'id': s['id'], 'name': s['name'], 'device_type': s['device_type'], 'board_color': 'black',
            'code62_glyph': 'degree', 'enabled': True, 'paused': live['paused'],
            'schedule_enabled': live['schedule_enabled'], 'polling_interval_seconds': 15,
            'board_read_interval_local': 30, 'board_read_interval_cloud': 180,
            'schedule_defer_on_reenable': False, 'auto_restore': live['auto_restore'],
            'notes_wide': 1, 'notes_tall': 1, 'grid_rows': None, 'grid_cols': None,
            'output': s['output'], 'output_config': {}}
    if s.get('device_model') and s['output'] not in ('vestaboard', 'fiestapanel'):
        base['device_model'] = s['device_model']
    base.update(copy.deepcopy(entry['stored']))
    return base


def _qs(query, key):
    for part in query.split('&'):
        if part.startswith(key + '='):
            return part.split('=', 1)[1]
    return None


def handle(prefix, route, method, body, query, store):
    """Return (status, body) or None. `store` is the per-prefix state dict."""
    if not prefix.startswith('/board-'):
        return None
    scenario = prefix[len('/board-'):].rsplit('-', 1)[0]
    state = store.get('boards_state')
    if state is None:
        state = store['boards_state'] = new_state(scenario)
    sc = state['scenario']
    board_id = _qs(query, 'board_id') or 'kitchen'

    if method == 'GET' and route == 'version':
        return 200, {'package_version': '10.1.20', 'build_version': '10.1.20', 'running_version': '10.1.20',
                     'is_dev': False, 'hardware_model': None}
    if method == 'GET' and route == 'v1/boards':
        entries = [] if sc == 'no-boards' else BOARDS
        return 200, {'boards': [summary(e, state['boards'][e['summary']['id']]) for e in entries], 'total': len(entries)}
    if method == 'GET' and route.startswith('v1/boards/') and route.count('/') == 2:
        entry = board_entry(route.split('/')[2])
        return (200, detail(state, entry)) if entry else (404, {'detail': 'Board not found'})
    if method == 'PUT' and route.startswith('v1/boards/') and route.endswith('/active-page'):
        entry = board_entry(route.split('/')[2])
        if not entry:
            return 404, {'detail': 'Board not found'}
        live = state['boards'][entry['summary']['id']]
        page_id = body.get('page_id')
        live['active_page_id'] = page_id
        sent = not live['paused']
        if sent and page_id:
            live['characters'] = page_frame(page_id, entry['summary']['rows'], entry['summary']['cols'])
        return 200, {'board_id': entry['summary']['id'], 'page_id': page_id, 'sent': sent,
                     'silenced': False, 'reason': None if sent else 'paused', 'error': None, 'warnings': []}
    if method == 'GET' and route == 'settings/board':
        return 200, {'board_type': None, 'devices': [e['summary']['device_type'] for e in BOARDS],
                     'boards': [stored_board(e, state['boards'][e['summary']['id']]) for e in BOARDS]}
    if method == 'GET' and route == 'v1/status':
        boards = {}
        for e in BOARDS:
            s = e['summary']; live = state['boards'][s['id']]
            boards[s['id']] = {'configured': not e.get('error'), 'paused': live['paused'],
                               'active_page_id': live['active_page_id'], 'error': e.get('error'),
                               'output_status': {'state': 'not_configured' if e.get('not_configured') else 'connected',
                                                 'message': 'Not configured' if e.get('not_configured') else 'Settings look complete'}}
        return 200, {'running': True, 'initialized': True, 'boards': boards}
    if method == 'GET' and route == 'board/current-message':
        entry = board_entry(board_id)
        if not entry:
            return 404, {'detail': 'Board not found'}
        d = detail(state, entry)
        out = {'characters': d['characters'], 'message': d['text'], 'rows': d['rows'], 'cols': d['cols'],
               'expected_characters': d['characters'], 'cached_at': '2026-10-31T08:15:00Z', 'api_mode': 'local'}
        if board_id == 'pixoo':
            out['layers'] = d['layers']
        return 200, out
    if method == 'GET' and route in ('schedules/active/page', 'settings/active-page'):
        entry = board_entry(board_id)
        if not entry:
            return 404, {'detail': 'Board not found'}
        d = detail(state, entry)
        page_id = d['active_page_id'] or d['scheduled_page_id']
        out = {'page_id': page_id, 'resolved_page_id': d['resolved_page_id'],
               'resolved_next_check_seconds': d['resolved_next_check_seconds']}
        if route == 'settings/active-page':
            out['board_id'] = board_id
            return 200, out
        out['schedule_enabled'] = state['boards'][entry['summary']['id']]['schedule_enabled']
        override = sc == 'override' and board_id == 'kitchen'
        out['temporary_override'] = {'active': override, 'page_id': 'note' if override else None,
                                     'expires_at': '2026-10-31T09:09:00Z' if override else None,
                                     'remaining_seconds': 540 if override else None,
                                     'revert_mode': 'schedule' if override else None}
        return 200, out
    if method == 'GET' and route == 'silence-status':
        active = sc == 'silence'
        return 200, {'enabled': active, 'active': active, 'mode': 'indicator' if active else None, 'page_id': None,
                     'ends_at_utc': '2026-10-31T14:00:00Z' if active else None, 'next_change_utc': None,
                     'seconds_until_next_change': None, 'holds_blocked_sends': False, 'held': None}
    if method == 'GET' and route == 'settings/display':
        return 200, {'reduce_motion': False, 'board_animations': True, 'site_animations': True, 'board_flap_speed': 'standard'}
    if method == 'GET' and route == 'v1/pages':
        pages = [] if sc == 'no-pages' else [page_body(p) for p in PAGES]
        return 200, {'pages': pages, 'total': len(pages)}
    if method == 'GET' and route.startswith('v1/pages/'):
        page = next((p for p in PAGES if p['id'] == route.split('/')[2]), None)
        return (200, page_body(page)) if page else (404, {'detail': 'Page not found'})
    if method == 'GET' and route == 'v1/schedules':
        entries = [] if sc == 'schedule-gap' else [schedule_entry(e, board_id) for e in SCHEDULE]
        return 200, {'schedules': entries, 'total': len(entries), 'default_page_id': None,
                     'enabled': state['boards'].get(board_id, {}).get('schedule_enabled', False)}
    if method == 'GET' and route == 'v1/collections':
        return 200, {'collections': [COLLECTION], 'total': 1}
    if method == 'GET' and route == 'v1/collections/' + COLLECTION_UUID:
        return 200, COLLECTION
    return None

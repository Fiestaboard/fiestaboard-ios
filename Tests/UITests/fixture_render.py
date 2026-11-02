"""`POST /templates/render`, `POST /templates/validate` (and `/pages/preview/batch`)
for the fixture server, from one shared table plus a deterministic toy fallback.

Table: every `Fixtures/shared/render-cases*.json` mirror (PLAN §4.4). Each case is
`{"id", "route", "request": <body>, "response": {"status", "body"}}`; a request
matches when its body equals the case's body exactly (canonical JSON). The
same request key in two files is an error at start-up.

Fallback (unlisted inputs): deterministic, and shaped like the server's output so
demos never show variable names on the board. Uppercase on flap boards (keep
case on LED), per-row alignment from `line_metadata`, cut at `cols`,
`{{color}}` → `{63}`… markers, `{{fill_space}}` / `{{fill_space_repeat:X}}`
fill the rest of the row, the variables in `VALUES` (shared with the Android
fixture) are substituted and their `upper`/`lower`/`pad`/`truncate`/`zeropad` filters applied,
any other variable and every `{{= … }}` formula render `???`.
Validate fallback: valid iff braces and parentheses balance and every `NAME(`
is a known function; otherwise the server's message shapes.
"""
import glob
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / 'Fixtures' / 'shared'
COLOR_CODES = {'red': 63, 'orange': 64, 'yellow': 65, 'green': 66, 'blue': 67, 'violet': 68,
               'purple': 68, 'white': 69, 'black': 70, 'filled': 71}
DEFAULT_FUNCTIONS = {'IF', 'AND', 'OR', 'NOT', 'ROUND', 'FLOOR', 'CEIL', 'ABS', 'MIN', 'MAX', 'SUM', 'AVG',
                     'UPPER', 'LOWER', 'LEN', 'CONCAT', 'LEFT', 'RIGHT', 'TRIM', 'REPLACE', 'TEXT', 'NUMBER',
                     'NOW', 'TODAY', 'FORMAT_DATE', 'DAYS_UNTIL', 'COUNT', 'JOIN', 'FIRST', 'LAST', 'COLOR'}
LED_BOARDS = {'pixoo', 'pixoo57', 'marquee'}
BOARD_CHARSETS = {'kitchen': 'vestaboard_v1', 'hall': 'vestaboard_v2', 'desk': 'vestaboard_v2', 'wall': 'vestaboard_v2',
                  'tv': 'vestaboard_v2', 'pixoo': 'led_3x5', 'pixoo57': 'led_5x7', 'marquee': 'led_5x7',
                  'mystery': None, 'contract-board': 'vestaboard_v1'}


def canonical(body):
    return json.dumps(body, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def load_table(directory=SHARED):
    table, origin = {}, {}
    for path in sorted(glob.glob(str(directory / 'render-cases*.json'))):
        data = json.loads(Path(path).read_text())
        for case in data.get('cases', []):
            key = (case['route'], canonical(case['request']))
            if key in table:
                raise ValueError(f"duplicate render case {case['id']} in {os.path.basename(path)}; "
                                 f"already defined by {origin[key]}")
            table[key] = case['response']
            origin[key] = f"{os.path.basename(path)}:{case['id']}"
    return table


TABLE = load_table()


def functions():
    try:
        import fixture_catalog  # noqa: F401 (iOS-F1 hook)
        return set(getattr(fixture_catalog, 'FUNCTION_NAMES', DEFAULT_FUNCTIONS))
    except ImportError:
        return DEFAULT_FUNCTIONS


def dimensions(body):
    kind = body.get('device_type') or 'flagship'
    if kind == 'note':
        return 3, 15
    if kind == 'note_array':
        return 3 * int(body.get('notes_tall') or 1), 15 * int(body.get('notes_wide') or 1)
    if kind == 'panel':
        return int(body.get('grid_rows') or 12), int(body.get('grid_cols') or 29)
    return 6, 22


TOKEN = re.compile(r'\{\{(.*?)\}\}')
SYMBOL = re.compile(r'\{(\d{1,2}|red|orange|yellow|green|blue|violet|purple|white|black|filled)\}', re.IGNORECASE)
FILL = '\x00FILL'

# Plausible values, identical to AND-R2's Android fixture (coordinator's table,
# 2026-11-01) so both platforms draw the same boards. Weather and the clock also
# match /v1/variables (PLAN §4.4). Anything else renders ??? like the server's
# `_get_variable_value`.
VALUES = {
    'weather.temperature': '72', 'weather.condition': 'SUNNY', 'weather.feels_like': '70',
    'weather.high': '75', 'weather.low': '58', 'weather.humidity': '40', 'weather.wind_speed': '8',
    'date_time.time': '08:15', 'date_time.date': '2026-10-31', 'date_time.day_of_week': 'SATURDAY',
    'date_time.day': '31', 'date_time.month': 'OCTOBER', 'date_time.year': '2026',
    'stocks.AAPL.price': '227.50', 'stocks.AAPL.change': '+1.2%',
    'baywheels.stations.0.name': 'MARKET ST', 'baywheels.stations.0.bikes': '7',
}
UNKNOWN = '???'


def lookup(path):
    """`source.field[.n]` → plausible value, or None. `stations[0]` ≡ `stations.0`."""
    key = re.sub(r'\[(\d+)\]', r'.\1', path.strip())
    return VALUES.get(key)


def apply_filters(value, filters):
    """`upper`, `lower`, `pad:N` (`ljust(N)[:N]`), `truncate:N` and `zeropad:N`
    (sign kept), as the server's filters; any other filter leaves the value as is."""
    for single in filters:
        name, _, arg = single.strip().partition(':')
        name = name.lower()
        if name == 'upper':
            value = value.upper()
        elif name == 'lower':
            value = value.lower()
        else:
            try:
                width = int(arg)
            except ValueError:
                continue
            if name == 'pad':
                value = value.ljust(width)[:width]
            elif name == 'truncate':
                value = value[:width]
            elif name == 'zeropad' and width > 0:
                value = ('-' + value[1:].rjust(width - 1, '0')) if value.startswith('-') else value.rjust(width, '0')
    return value


def expand(inner):
    """The text one `{{…}}` token renders as (markers like `{63}` kept)."""
    stripped = inner.strip()
    name = stripped.lower()
    if name in COLOR_CODES:
        return '{%d}' % COLOR_CODES[name]
    if name.isdigit() and 63 <= int(name) <= 71:
        return '{%s}' % name
    if stripped.startswith('='):
        return UNKNOWN  # the fixture never evaluates formulas
    path, *filters = stripped.split('|')
    value = lookup(path)
    if value is None:
        return UNKNOWN
    return apply_filters(value, filters)


def cells_of(text, keep_case):
    """Text with `{NN}`/`{color}` markers → list of cells (a marker is one cell)."""
    cells, pos = [], 0
    for match in SYMBOL.finditer(text):
        chunk = text[pos:match.start()]
        cells += list(chunk if keep_case else chunk.upper())
        token = match.group(1).lower()
        code = COLOR_CODES.get(token) or (int(token) if token.isdigit() and 63 <= int(token) <= 71 else None)
        if code is None:
            cells += list(match.group(0) if keep_case else match.group(0).upper())
        else:
            cells.append('{%d}' % code)
        pos = match.end()
    chunk = text[pos:]
    return cells + list(chunk if keep_case else chunk.upper())


def render_row(source, keep_case, cols=None):
    """Template row → list of cells (strings; markers like '{63}' are one cell)."""
    cells, pos, fills = [], 0, []
    for match in TOKEN.finditer(source):
        cells += cells_of(source[pos:match.start()], keep_case)
        inner = match.group(1).strip()
        name = inner.lower()
        if name == 'fill_space':
            fills.append((len(cells), ' ')); cells.append(FILL)
        elif name.startswith('fill_space_repeat:'):
            fills.append((len(cells), inner.split(':', 1)[1] or ' ')); cells.append(FILL)
        else:
            cells += cells_of(expand(inner), keep_case)
        pos = match.end()
    cells += cells_of(source[pos:], keep_case)
    if not fills:
        return cells
    room = max(0, (cols or 0) - (len(cells) - len(fills)))
    share, extra = divmod(room, len(fills))
    out = []
    for index, cell in enumerate(cells):
        if cell != FILL:
            out.append(cell); continue
        n = next(i for i, (at, _) in enumerate(fills) if at == index)
        pattern = fills[n][1] if keep_case else fills[n][1].upper()
        count = share + (1 if n < extra else 0)
        out += [pattern[i % len(pattern)] for i in range(count)]
    return out


def toy_render(body):
    rows, cols = dimensions(body)
    keep_case = body.get('board_id') in LED_BOARDS
    template = list(body.get('template') or [])
    metadata = body.get('line_metadata') or []
    lines = []
    for index in range(rows):
        source = template[index] if index < len(template) else ''
        meta = metadata[index] if index < len(metadata) and isinstance(metadata[index], dict) else {}
        cells = render_row(source, keep_case, cols)[:cols]
        pad = cols - len(cells)
        align = meta.get('alignment') or 'left'
        left = pad // 2 if align == 'center' else (pad if align == 'right' else 0)
        lines.append(''.join([' '] * left + cells + [' '] * (pad - left)))
    out = {'rendered': '\n'.join(lines), 'lines': lines, 'line_count': len(lines)}
    if 'board_id' in body:
        board = body['board_id']
        out['charset'] = BOARD_CHARSETS.get(board) if board in BOARD_CHARSETS else None
        out['charset_issues'] = [] if board in BOARD_CHARSETS else None
    return out


def toy_validate(body):
    errors = []
    for line_no, row in enumerate(body.get('template') or [], start=1):
        if row.count('{{') != row.count('}}'):
            errors.append({'line': line_no, 'column': 1, 'message': 'Mismatched variable braces'})
            continue
        for match in TOKEN.finditer(row):
            inner = match.group(1)
            if not inner.strip().startswith('='):
                continue
            expression = inner.strip()[1:]
            if expression.count('(') != expression.count(')'):
                errors.append({'line': line_no, 'column': match.start() + 1,
                               'message': 'Formula #ERROR!: Mismatched parentheses'})
                continue
            for name in re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(', expression):
                if name.upper() not in functions():
                    errors.append({'line': line_no, 'column': match.start() + 1,
                                   'message': f'Formula #NAME?: Unknown function: {name.upper()}'})
    return {'valid': not errors, 'errors': errors}


def handle(prefix, route, method, body, query, store):
    """Return (status, body) or None. `/mixed-` keeps its own physical-frame render."""
    if method != 'POST' or prefix.startswith('/mixed-'):
        return None
    if route not in ('templates/render', 'templates/validate', 'pages/preview/batch'):
        return None
    hit = TABLE.get(('/' + route, canonical(body)))
    if hit is not None:
        return hit.get('status', 200), hit['body']
    if route == 'templates/render':
        if not isinstance(body.get('template'), list) or not body['template']:
            return 422, {'detail': 'template must be a non-empty list of strings'}
        return 200, toy_render(body)
    if route == 'templates/validate':
        return 200, toy_validate(body)
    if route == 'pages/preview/batch':
        return 200, toy_batch(prefix, body)
    return None


def _pages_for(prefix):
    """The page documents this prefix serves (board scenarios, else the corpus page)."""
    if prefix.startswith('/board-'):
        import fixture_boards
        return {p['id']: fixture_boards.page_body(p) | {'shows': p.get('shows')} for p in fixture_boards.PAGES}
    corpus = json.loads((ROOT / 'Fixtures/contracts/10.1.20/bootstrap-control.json').read_text())
    page = next((c['response']['body'] for c in corpus['cases'] if c['id'] == 'page_get'), None)
    return {page['id']: page} if page else {}


def toy_batch(prefix, body):
    """`POST /pages/preview/batch` fallback: each page through the toy renderer."""
    pages = _pages_for(prefix)
    board_id = body.get('board_id')
    previews = {}
    for page_id in body.get('page_ids') or []:
        page = pages.get(page_id)
        if page is None:
            previews[page_id] = {'available': False, 'error': f'Page not found: {page_id}'}
            continue
        request = {k: page.get(k) for k in ('device_type', 'notes_wide', 'notes_tall', 'grid_rows', 'grid_cols')}
        if board_id:
            request['board_id'] = board_id
        if page.get('template'):
            request['template'] = page['template']
            request['line_metadata'] = page.get('line_metadata')
            # The exact render case for this page when the table has one (the
            # editor's request shape), else the toy fallback.
            exact = {k: page.get(k) for k in ('template', 'line_metadata', 'device_type', 'notes_wide',
                                              'notes_tall', 'grid_rows', 'grid_cols')}
            hit = TABLE.get(('/templates/render', canonical(exact)))
            lines = hit['body']['lines'] if hit and hit.get('status', 200) == 200 else toy_render(request)['lines']
        elif page.get('shows'):
            request['template'] = [re.sub(r'\{(red|orange|yellow|green|blue|violet|white|black)\}', r'{{\1}}', line)
                                   for line in page['shows']]
            request['line_metadata'] = [{'alignment': 'center', 'wrap': False}] * len(page['shows'])
            lines = toy_render(request)['lines']
        else:
            previews[page_id] = {'available': False, 'error': 'This page has no fixed grid to preview'}
            continue
        previews[page_id] = {'available': True, 'page_id': page_id, 'message': '\n'.join(lines), 'lines': lines,
                             'display_type': page.get('device_type') or 'flagship', 'raw': {}}
    ok = sum(1 for v in previews.values() if v['available'])
    return {'previews': previews, 'total': len(previews), 'successful': ok}

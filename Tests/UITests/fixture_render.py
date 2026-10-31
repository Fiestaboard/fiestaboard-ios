"""`POST /templates/render`, `POST /templates/validate` (and `/pages/preview/batch`)
for the fixture server, from one shared table plus a deterministic toy fallback.

Table: every `Fixtures/shared/render-cases*.json` mirror (PLAN §4.4). Each case is
`{"id", "route", "request": <body>, "response": {"status", "body"}}`; a request
matches when its body equals the case's body exactly (canonical JSON). The
same request key in two files is an error at start-up.

Fallback (unlisted inputs), deliberately tiny: uppercase on flap boards (keep case
on LED), per-row alignment from `line_metadata`, cut at `cols`, `{{color}}` →
`{63}`… markers, `{{fill_space}}` → a space, any other `{{…}}` rendered as its
uppercased source; no formula evaluation and no variable lookup, ever.
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


def render_row(source, keep_case):
    """Template row → list of cells (strings; markers like '{63}' are one cell)."""
    cells, pos = [], 0
    for match in TOKEN.finditer(source):
        cells += list(source[pos:match.start()] if keep_case else source[pos:match.start()].upper())
        inner = match.group(1).strip()
        name = inner.lower()
        if name in COLOR_CODES:
            cells.append('{%d}' % COLOR_CODES[name])
        elif name == 'fill_space' or name.startswith('fill_space_repeat'):
            cells.append(' ')
        else:
            cells += list(inner if keep_case else inner.upper())
        pos = match.end()
    cells += list(source[pos:] if keep_case else source[pos:].upper())
    return cells


def toy_render(body):
    rows, cols = dimensions(body)
    keep_case = body.get('board_id') in LED_BOARDS
    template = list(body.get('template') or [])
    metadata = body.get('line_metadata') or []
    lines = []
    for index in range(rows):
        source = template[index] if index < len(template) else ''
        meta = metadata[index] if index < len(metadata) and isinstance(metadata[index], dict) else {}
        cells = render_row(source, keep_case)[:cols]
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
    return None  # /pages/preview/batch: table only in D1.

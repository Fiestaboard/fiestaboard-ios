"""Editor catalogs for the `/board-<scenario>-<n>/` prefix family (PLAN §4.4, iOS-F1).

Mock content only, shaped like FiestaBoard 10.3.2 (`src/v1/routes_meta.py`,
`src/v1/models.py` `VariableCatalog`, `src/templates/models.py`
`FormulaFunctionsResponse`):

- `GET /v1/variables`: plugins `weather` (grouped), `date_time`, `stocks`,
  `baywheels` (array `stations`, two items), no `home_assistant`;
  `variable_metadata`, `variable_groups`, `colors`, `formatting`.
  Scenario `no-plugins` answers empty variables (B32).
- `GET /v1/functions`: the dict keyed by NAME with a representative subset of each
  category plus one unknown category, `experimental`.
- `GET /plugins/{id}/manifest`: name, icon and the `baywheels` array schema.

`fixture_render.functions()` reads FUNCTION_NAMES for the validate fallback, so a
formula is valid here iff it only calls these functions. Other prefixes (/signin-,
/mixed-, /flexible-) are not served: the app falls back to its built-in sample.
"""

import copy

# Values match fixture_render.VALUES so the picker's previews and the stage agree.
VARIABLES = {
    'variables': {
        'weather': ['temperature', 'condition', 'feels_like', 'high', 'low', 'humidity', 'wind_speed'],
        'date_time': ['time', 'date', 'day_of_week', 'day', 'month', 'year'],
        'stocks': ['AAPL.price', 'AAPL.change'],
        'baywheels': ['station_count', 'stations.*.name', 'stations.*.bikes', 'stations.*.docks',
                      'stations.0.name', 'stations.0.bikes', 'stations.0.docks',
                      'stations.1.name', 'stations.1.bikes', 'stations.1.docks'],
    },
    'max_lengths': {'weather.temperature': 3, 'weather.condition': 12, 'date_time.time': 5},
    'variable_metadata': {
        'weather': {
            'temperature': {'description': 'Current temperature', 'type': 'number', 'preview': '72', 'group': 'now'},
            'condition': {'description': 'Sky right now', 'type': 'string', 'preview': 'SUNNY', 'group': 'now'},
            'feels_like': {'description': 'Feels-like temperature', 'preview': '70', 'group': 'now'},
            'wind_speed': {'description': 'Wind speed', 'preview': '8', 'group': 'now'},
            'high': {'description': "Today's high", 'preview': '75', 'group': 'today'},
            'low': {'description': "Today's low", 'preview': '58', 'group': 'today'},
            'humidity': {'description': 'Relative humidity', 'preview': '40'},
        },
        'date_time': {
            'time': {'preview': '08:15'}, 'date': {'preview': '2026-10-31'}, 'day_of_week': {'preview': 'SATURDAY'},
            'day': {'preview': '31'}, 'month': {'preview': 'OCTOBER'}, 'year': {'preview': '2026'},
        },
        'stocks': {'AAPL.price': {'preview': '227.50'}, 'AAPL.change': {'preview': '+1.2%'}},
        'baywheels': {
            'station_count': {'preview': '2'},
            'stations.0.name': {'preview': 'MARKET ST'}, 'stations.0.bikes': {'preview': '7'}, 'stations.0.docks': {'preview': '12'},
            'stations.1.name': {'preview': 'FERRY BUILDING'}, 'stations.1.bikes': {'preview': '3'}, 'stations.1.docks': {'preview': '20'},
        },
    },
    'variable_groups': {'weather': {'now': {'label': 'Right now'}, 'today': {'label': 'Today'}}},
    'colors': {'red': 63, 'orange': 64, 'yellow': 65, 'green': 66, 'blue': 67, 'violet': 68, 'white': 69, 'black': 70},
    'symbols': ['sun', 'star', 'cloud', 'rain', 'snow', 'storm', 'fog', 'partly', 'heart', 'check', 'x'],
    'filters': ['pad:N', 'truncate:N', 'zeropad:N', 'upper', 'lower', 'wrap'],
    'formatting': {
        'fill_space': {'syntax': '{{fill_space}}',
                       'description': 'Expands to fill remaining space on the line. Use multiple for multi-column layouts.'},
        'fill_space_repeat': {'syntax': '{{fill_space_repeat:pattern}}',
                              'description': 'Fills remaining space with repeating colors or characters. '
                                             'Examples: {{fill_space_repeat:red}} or {{fill_space_repeat:-}}'},
    },
    'syntax_examples': {'variable': '{{weather.temperature}}', 'variable_with_filter': '{{weather.temperature|pad:3}}'},
    'plugin_system_enabled': True,
}

MANIFESTS = {
    'weather': {'id': 'weather', 'name': 'Weather', 'icon': 'cloud-sun', 'variables': {'groups': {'now': {'label': 'Right now'}}}},
    'date_time': {'id': 'date_time', 'name': 'Date & Time', 'icon': 'clock', 'variables': {}},
    'stocks': {'id': 'stocks', 'name': 'Stocks', 'icon': 'trending-up', 'variables': {}},
    'baywheels': {'id': 'baywheels', 'name': 'Bay Wheels', 'icon': 'bike', 'variables': {
        'arrays': {'stations': {'label_field': 'name', 'item_fields': ['name', 'bikes', 'docks']}}}},
}

FUNCTIONS = {
    'IF': ('logic', 'IF(condition, then, else)', 'Returns then when the condition is true, else otherwise.'),
    'AND': ('logic', 'AND(a, b, ...)', 'True when every argument is true.'),
    'OR': ('logic', 'OR(a, b, ...)', 'True when any argument is true.'),
    'NOT': ('logic', 'NOT(value)', 'The opposite of a true/false value.'),
    'COUNT': ('array', 'COUNT(list)', 'How many items a list has.'),
    'JOIN': ('array', 'JOIN(list, separator)', "Joins a list's items into text."),
    'FIRST': ('array', 'FIRST(list)', 'The first item of a list.'),
    'LAST': ('array', 'LAST(list)', 'The last item of a list.'),
    'NOW': ('date', 'NOW()', 'The current date and time.'),
    'TODAY': ('date', 'TODAY()', "Today's date."),
    'FORMAT_DATE': ('date', 'FORMAT_DATE(date, format)', 'Formats a date.'),
    'DAYS_UNTIL': ('date', 'DAYS_UNTIL(date)', 'Days from today until a date.'),
    'ROUND': ('math', 'ROUND(number, digits)', 'Rounds a number.'),
    'FLOOR': ('math', 'FLOOR(number)', 'Rounds down.'),
    'CEIL': ('math', 'CEIL(number)', 'Rounds up.'),
    'ABS': ('math', 'ABS(number)', 'A number without its sign.'),
    'MIN': ('math', 'MIN(a, b, ...)', 'The smallest argument.'),
    'MAX': ('math', 'MAX(a, b, ...)', 'The largest argument.'),
    'SUM': ('math', 'SUM(a, b, ...)', 'Adds the arguments.'),
    'AVG': ('math', 'AVG(a, b, ...)', 'The mean of the arguments.'),
    'UPPER': ('text', 'UPPER(text)', 'Text in capitals.'),
    'LOWER': ('text', 'LOWER(text)', 'Text in lower case.'),
    'LEN': ('text', 'LEN(text)', 'How many characters text has.'),
    'CONCAT': ('text', 'CONCAT(a, b, ...)', 'Joins text.'),
    'LEFT': ('text', 'LEFT(text, count)', 'The first characters of text.'),
    'RIGHT': ('text', 'RIGHT(text, count)', 'The last characters of text.'),
    'TRIM': ('text', 'TRIM(text)', 'Text without surrounding spaces.'),
    'REPLACE': ('text', 'REPLACE(text, old, new)', 'Replaces part of text.'),
    'TEXT': ('convert', 'TEXT(value)', 'A value as text.'),
    'NUMBER': ('convert', 'NUMBER(text)', 'Text as a number.'),
    'COLOR': ('color', 'COLOR(name)', 'A colour tile by name.'),
    'WOBBLE': ('experimental', 'WOBBLE(value)', 'Mock-only: a category the app does not know yet.'),
}
FUNCTION_NAMES = set(FUNCTIONS)


def variables_for(scenario):
    body = copy.deepcopy(VARIABLES)
    if scenario == 'no-plugins':
        body['variables'] = {}
        body['max_lengths'] = {}
        body['variable_metadata'] = {}
        body['variable_groups'] = {}
    return body


def handle(prefix, route, method, body, query, store):
    """Return (status, body) or None. Only the board prefix family serves catalogs."""
    if method != 'GET' or not prefix.startswith('/board-'):
        return None
    scenario = prefix[len('/board-'):].rsplit('-', 1)[0]
    if route == 'v1/variables':
        return 200, variables_for(scenario)
    if route == 'v1/functions':
        return 200, {'functions': {name: {'category': c, 'signature': s, 'summary': d}
                                   for name, (c, s, d) in FUNCTIONS.items()}}
    if route.startswith('plugins/') and route.endswith('/manifest'):
        plugin = route[len('plugins/'):-len('/manifest')]
        if scenario != 'no-plugins' and plugin in MANIFESTS:
            return 200, MANIFESTS[plugin]
        return 404, {'detail': f'Plugin not found: {plugin}'}
    return None

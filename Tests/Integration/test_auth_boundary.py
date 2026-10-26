"""Container-only HTTP contract proof against real middleware, no app lifespan.

All credentials are fake and in process memory. No auth dependency overrides.
"""
import pytest
import json
from pathlib import Path
from fastapi.testclient import TestClient
from src.api_server import app
from src.auth import routes as auth_routes
from src.auth import service as auth_service

PASSWORD = 'test-contract-password-123'


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('FIESTABOARD_DATA_DIR', str(tmp_path/'data'))
    monkeypatch.setenv('FIESTABOARD_AUTH_ENABLED', 'true')
    monkeypatch.setattr(auth_service, '_service', auth_service.AuthService(tmp_path/'auth.json'))
    auth_routes._FAILED_ATTEMPTS.clear()
    # Deliberately no context manager: entering app lifespan starts workers.
    return TestClient(app)


def login(client):
    assert client.post('/auth/setup', json={'username':'test_admin','password':PASSWORD}).status_code == 201
    client.cookies.clear()
    response = client.post('/auth/login',json={'username':'test_admin','password':PASSWORD})
    assert response.status_code == 200
    assert auth_service.SESSION_COOKIE_NAME in response.cookies
    return client


def csrf(client):
    result = client.get('/auth/sessions/context')
    assert result.status_code == 200
    return {'Origin':'http://testserver','X-CSRF-Token':result.json()['csrf_token']}


def test_cookie_login_logout_and_replayed_cookie_rejected(client):
    login(client)
    assert client.get('/auth/status').json()['authenticated'] is True
    copy = TestClient(app)
    copy.cookies.update(client.cookies)
    assert copy.get('/auth/sessions').status_code == 200
    assert client.post('/auth/logout').status_code == 200
    assert client.get('/auth/status').json()['authenticated'] is False
    assert copy.get('/auth/sessions').status_code == 401


@pytest.mark.parametrize('mode,expected,first_run', [('true','enabled',False),('false','disabled',False),(None,'undecided',True)])
def test_modes_and_secure_first_run(client, monkeypatch, mode, expected, first_run):
    if mode is None:
        monkeypatch.delenv('FIESTABOARD_AUTH_ENABLED')
    else:
        monkeypatch.setenv('FIESTABOARD_AUTH_ENABLED',mode)
    body = client.get('/auth/status').json()
    fixture = json.loads(Path('/contract-fixtures/auth-status.json').read_text())['modes'][expected]
    assert {key:body[key] for key in fixture} == fixture
    response = client.get('/settings/polling')
    if mode != 'false':
        assert response.status_code == 409
        assert response.json()['setup_required'] is True
    else:
        assert response.status_code == 200
        assert {'interval_seconds','board_read_interval_local','board_read_interval_cloud'} <= response.json().keys()


@pytest.mark.parametrize('headers', [{}, {'Origin':'http://testserver'}, {'Origin':'https://evil.invalid','X-CSRF-Token':'wrong'}])
def test_session_mutation_requires_csrf_and_same_origin(client, headers):
    login(client)
    before = client.get('/auth/sessions').json()['current_session_id']
    assert client.post('/auth/sessions/revoke',json={'include_current':True},headers=headers).status_code == 403
    assert client.get('/auth/sessions').json()['current_session_id'] == before
    assert client.get('/auth/status').json()['authenticated'] is True


def test_session_revocation_invalidates_cookie(client):
    login(client)
    headers = csrf(client)
    assert client.post('/auth/sessions/revoke',json={'include_current':True},headers=headers).status_code == 200
    assert client.get('/auth/sessions').status_code == 401
    assert client.get('/auth/status').json()['authenticated'] is False


def test_tv_token_cannot_be_admin_or_general_api_credential(client):
    login(client)
    tv = TestClient(app)
    result = tv.post('/auth/device/login',json={'username':'test_admin','password':PASSWORD,'client_id':'fiestaboard-tvos','device_name':'Test TV','app_version':'1'})
    assert result.status_code == 200
    credential = result.json()
    assert credential['scope'] == 'tv_panels'
    tv.headers['Authorization'] = 'Bearer ' + credential['access_token']
    assert tv.get('/auth/status').json()['auth_kind'] == 'tv'
    assert tv.get('/panels').status_code == 200
    for path in ['/auth/sessions','/auth/sessions/context','/settings','/v1/health']:
        assert tv.get(path).status_code == 403
    assert client.delete('/auth/sessions/'+credential['session_id'],headers=csrf(client)).status_code == 200
    assert tv.get('/panels').status_code == 401
    assert client.get('/auth/status').json()['authenticated'] is True


def test_non_auth_conflict_preserves_authenticated_session(client):
    login(client)
    # A panel owns its backing board; deleting that board conflicts.
    # Replace only the stored panel lookup, keeping real auth middleware active.
    from src.settings import routes as settings_routes
    from types import SimpleNamespace
    from unittest.mock import patch
    with patch.object(settings_routes, 'get_panel_service') as panels:
        panels.return_value.list_panels.return_value = [SimpleNamespace(board_id='test_board',name='Test panel')]
        response = client.delete('/settings/board/test_board')
    assert response.status_code == 409
    assert 'in use' in response.json()['detail']
    assert response.json().get('setup_required') is not True
    assert client.get('/auth/status').json()['authenticated'] is True

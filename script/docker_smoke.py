#!/usr/bin/env python3
"""Isolated, reproducible clean-source Docker persistence/recovery acceptance test."""
import argparse
import http.cookiejar
import html
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
PASSWORD = "synthetic-pass-123"
EMAIL = "demo@example.test"

class Client:
    def __init__(self, base):
        self.base = base
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.csrf = None
    def request(self, path, data=None, method=None, json_body=False, headers=None):
        hdr = headers or {}
        if data is not None and not isinstance(data, bytes):
            if json_body:
                data = json.dumps(data).encode()
                hdr["Content-Type"] = "application/json"
                hdr["Accept"] = "application/json"
            else:
                data = urllib.parse.urlencode(data).encode()
                hdr["Content-Type"] = "application/x-www-form-urlencoded"
        if self.csrf:
            hdr["X-CSRF-Token"] = self.csrf
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=hdr)
        try:
            response = self.opener.open(req, timeout=30)
        except urllib.error.HTTPError as error:
            response = error
        text = response.read().decode()
        token = re.search(r'<meta name="csrf-token" content="([^"]+)"', text)
        if token:
            self.csrf = html.unescape(token[1])
        return response.status, text, response.geturl(), response.headers
    def login(self, email=EMAIL):
        assert self.request('/session/new')[0] == 200
        status, text, _, _ = self.request('/session', {"email_address": email, "password": PASSWORD})
        assert status == 200 and "Your health, over time." in text, "Login failed"
    def document(self):
        status, text, _, headers = self.request('/settings/export/json')
        assert status == 200 and 'no-store' in headers.get('Cache-Control', '')
        return json.loads(text)
    def import_document(self, document):
        boundary = 'waypoint-health-smoke-boundary'
        body = ('--'+boundary+'\r\nContent-Disposition: form-data; name="format_kind"\r\n\r\njson\r\n'
                '--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="personal.json"\r\nContent-Type: application/json\r\n\r\n'+json.dumps(document)+'\r\n--'+boundary+'--\r\n').encode()
        status, text, location, _ = self.request('/imports', body, headers={'Content-Type':'multipart/form-data; boundary='+boundary})
        assert status == 200 and "Import preview" in text
        path = urllib.parse.urlparse(location).path
        assert '/imports/' in path
        status, text, _, _ = self.request(path+'/commit', {"apply_preferences":"1"})
        assert status == 200 and "Import committed" in text
        return path


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    args = argparse.ArgumentParser()
    args.add_argument('--browser', action='store_true')
    options = args.parse_args()
    prefix = 'waypoint-health-smoke-'+secrets.token_hex(4)
    with tempfile.TemporaryDirectory(prefix='waypoint-health-smoke-') as temp:
        temp = Path(temp)
        checkout = temp/'checkout'
        ignored = shutil.ignore_patterns('.git', '.env', '.env.production', 'RENPHO*.csv', '.bundle', '.idea', 'node_modules', 'backups', 'test-results', 'playwright-report', '__pycache__')
        def ignore(path, names):
            skip = set(ignored(path, names))
            relative = Path(path).relative_to(ROOT)
            if str(relative) == 'vendor': skip.add('bundle')
            if str(relative) in ['storage', 'log', 'tmp']: skip.update(n for n in names if n != '.keep')
            if str(relative) == 'public': skip.add('assets')
            if str(relative) == 'config': skip.update(n for n in names if n == 'master.key' or n.startswith('credentials'))
            if str(relative) == 'test': skip.add('artifacts')
            return skip
        shutil.copytree(ROOT, checkout, ignore=ignore)
        secret = secrets.token_hex(64)
        port, recovery_port = free_port(), free_port()
        env_file = checkout/'.env'
        env_file.write_text(f'SECRET_KEY_BASE={secret}\nAPP_HOST=localhost,127.0.0.1\nFORCE_SSL=false\nBIND_ADDRESS=127.0.0.1\nPORT={port}\n')
        env_file.chmod(0o600)
        def compose(project, *arguments, input=None, recovery=False):
            env = os.environ.copy()
            env['PORT'] = str(recovery_port if recovery else port)
            command = ['docker','compose','--project-directory',str(checkout),'--env-file',str(env_file),'-f',str(checkout/'compose.yaml'),'-p',project,*arguments]
            result = subprocess.run(command, input=input, text=not isinstance(input, bytes), capture_output=True, env=env)
            if result.returncode:
                print(result.stdout[-5000:]); print(result.stderr[-5000:])
                raise RuntimeError('Docker command failed: '+' '.join(arguments[:3]))
            return (result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout).strip()
        def counts(project, recovery=False):
            return json.loads(compose(project,'exec','-T','app','bin/verify',recovery=recovery))
        successful = False
        try:
            print('Building from a clean temporary source copy; booting a fresh volume.', flush=True)
            compose(prefix, 'up','-d','--build','--wait','--wait-timeout','180')
            for address in [EMAIL,'other@example.test']:
                compose(prefix,'exec','-T','app','bin/account','create',address,input=PASSWORD+'\n'+PASSWORD+'\n')
            owner = Client(f'http://127.0.0.1:{port}')
            owner.login()
            values = [('208.4','lb','2026-11-01T23:55'),('94.3','kg','2026-11-02T00:05'),('207.8','lb','2026-11-02T08:20')]
            for value, unit, stamp in values:
                data = {'entry': {'id':str(uuid.uuid4()),'value':value,'unit':unit,'local_time':stamp}}
                assert owner.request('/entries?kind=weight', data, json_body=True)[0] == 200
                assert owner.request('/entries?kind=weight', data, json_body=True)[0] == 200
            assert owner.request('/entries?kind=injection', {'entry':{'id':str(uuid.uuid4()),'dose':'5','site':'Thigh','side':'Left','notes':'Actual dose','local_time':'2026-11-03T09:30'}},json_body=True)[0] == 200
            assert owner.request('/journal/2026-11-04', {'day_note':{'notes':'Synthetic journal 🌿','metrics':{'sleep_hours':'7.5'}}},method='PUT',json_body=True)[0] == 200
            document = owner.document()
            assert len(document['records']['weights']) == 3
            assert len(document['records']['injections']) == len(document['records']['day_notes']) == 1
            status, text, _, _ = owner.request('/?range=custom&from=2026-11-02&to=2026-11-04')
            payload = json.loads(html.unescape(re.search(r'data-timeline-payload-value="([^"]+)"',text)[1]))
            assert len(payload['raw']) == 2
            assert payload['injections'][0]['day'] == '2026-11-03' and 'y' not in payload['injections'][0]
            assert payload['notes'][0]['day'] == '2026-11-04'
            status, day, _, _ = owner.request('/journal/2026-11-02')
            edit_path = html.unescape(re.search(r'href="(/entries/[^\"]+/edit[^\"]+)"',day)[1])
            import_path = owner.import_document(document)
            owner.import_document(document)
            assert owner.document()['records'] == document['records']
            other = Client(f'http://127.0.0.1:{port}')
            other.login('other@example.test')
            assert all(not records for records in other.document()['records'].values())
            assert other.request(edit_path)[0] == 404
            assert other.request(import_path)[0] == 404
            print('PASS: login, duplicate-safe logging, local midnight, independent events, JSON repeated imports and account isolation.', flush=True)
            if options.browser:
                env = os.environ.copy()
                env.update(BASE_URL=f'http://127.0.0.1:{port}',TEST_EMAIL=EMAIL,TEST_PASSWORD=PASSWORD)
                subprocess.run(['npm','run','test:browser'],cwd=ROOT,env=env,check=True)
            assert owner.request('/charts/injections/preferences', {'preferences': {'range':'30','mode':'aligned','site':'Thigh'}}, method='PATCH', json_body=True)[0] == 200
            assert owner.document()['preferences']['chart_preferences']['injections']['mode'] == 'aligned'
            assert other.document()['preferences']['chart_preferences'] == {}
            before = counts(prefix)
            before_records = owner.document()['records']
            print(compose(prefix,'exec','-T','app','bin/backup','/data/snapshot.sqlite3'),flush=True)
            backup_dir = temp/'backups'; backup_dir.mkdir()
            compose(prefix,'cp','app:/data/snapshot.sqlite3',str(backup_dir/'waypoint-health.sqlite3'))
            # Use stdin: the backup never needs to be made world-readable.
            compose(prefix,'up','-d','--force-recreate','--wait','--wait-timeout','120')
            assert counts(prefix) == before
            owner = Client(f'http://127.0.0.1:{port}'); owner.login()
            assert owner.document()['records'] == before_records
            print('PASS: container recreation preserved accounts, login and all records.',flush=True)
            print(compose(prefix+'-recovery','run','--rm','-T','app','bin/restore','-',input=(backup_dir/'waypoint-health.sqlite3').read_bytes(),recovery=True),flush=True)
            compose(prefix+'-recovery','up','-d','--wait','--wait-timeout','120',recovery=True)
            assert counts(prefix+'-recovery',recovery=True) == before
            restored = Client(f'http://127.0.0.1:{recovery_port}'); restored.login()
            assert restored.document()['records'] == before_records
            assert restored.document()['preferences'] == owner.document()['preferences']
            print('PASS: fresh-volume restore preserved login, counts, exact personal records and preferences: '+json.dumps(before),flush=True)
            # Password reset is email-free and invalidates an existing signed-in session.
            compose(prefix+'-recovery','exec','-T','app','bin/account','reset',EMAIL,input=PASSWORD+'\n'+PASSWORD+'\n',recovery=True)
            assert '/session/new' in restored.request('/')[2]
            restored.login()
            print('PASS: password reset revoked existing sessions and the account can sign in again.',flush=True)
            successful = True
        finally:
            # These are unique projects/volumes created exclusively for this synthetic test.
            for project in [prefix+'-recovery',prefix]:
                compose(project,'down','--volumes','--remove-orphans',recovery=project.endswith('-recovery'))
            print('Synthetic test containers and volumes removed.' if successful else 'Test failed; synthetic containers/volumes removed.',flush=True)

if __name__ == '__main__':
    main()

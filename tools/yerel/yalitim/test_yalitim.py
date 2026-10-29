"""Yalitim aracinin testleri. Dis aga ERISMEZ: yalniz loopback, .invalid adlari ve TEST-NET-1 (192.0.2.1).

Calistirma (depo kokunden):
    python -B -m unittest discover -s tools/yerel/yalitim -p "test_*.py" -v
Node bulunamazsa Node'a bagli testler atlanir.
"""
import hashlib, http.client, http.server, json, os, re, shutil, socket, subprocess, sys, tempfile
import threading, time, unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import profil, proxy, surecler, tarayici  # noqa: E402

NODE = surecler.which_path_only('node')
SAMPLE = HERE / 'profil.yerel.ornek'
GUARD = HERE / 'node_guard.cjs'
CALISTIR = HERE / 'calistir.py'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def run_cli(*args, env_extra=None, timeout=90):
    env = dict(os.environ)
    env.pop('ASTRA_LOCAL_RUNS_PATH', None)
    env.update(env_extra or {})
    return subprocess.run([sys.executable, '-B', str(CALISTIR), *args], capture_output=True, text=True,
                          timeout=timeout, env=env, cwd=tempfile.gettempdir())


def raw_request(port, payload):
    with socket.socket(socket.AF_INET) as s:
        s.settimeout(5)
        s.connect(('127.0.0.1', port))
        s.sendall(payload)
        chunks = []
        while True:
            try:
                part = s.recv(65536)
            except socket.timeout:
                break
            if not part:
                break
            chunks.append(part)
    return b''.join(chunks)


class ProfileTests(unittest.TestCase):
    def profile_with(self, edit):
        text = SAMPLE.read_text(encoding='utf-8')
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / 'p.ornek'
        path.write_text(edit(text), encoding='utf-8')
        return path

    def test_sample_profile_is_valid_and_loopback(self):
        values = profil.load_profile(SAMPLE)
        self.assertEqual(values['DB_HOST'], '127.0.0.1')
        self.assertEqual(values['SMS_PROVIDER'], '')
        self.assertEqual(values['JWT_SECRET'], '', 'ornek dosyada sabit JWT anahtari olmamali')
        for key in ('DB_PASSWORD', 'SMTP_PASSWORD', 'MQTT_PASSWORD', 'NETGSM_PASSWORD', 'WEB_PUSH_VAPID_PRIVATE'):
            self.assertEqual(values[key], '', key + ' ornek dosyada bos olmali')

    def test_rejects_unsafe_profiles(self):
        cases = {
            'bilinmeyen anahtar': lambda t: t + 'FOO=bar\n',
            'tekrar eden anahtar': lambda t: t + 'PORT=9090\n',
            'esitlik isareti yok': lambda t: t + 'bozuk satir\n',
            'dis veritabani': lambda t: t.replace('DB_HOST=127.0.0.1', 'DB_HOST=db.example.invalid'),
            'dis smtp': lambda t: t.replace('SMTP_HOST=127.0.0.1', 'SMTP_HOST=smtp.example.invalid'),
            'dinleme adresi': lambda t: t.replace('LISTEN_HOST=127.0.0.1', 'LISTEN_HOST=0.0.0.0'),
            'sms saglayici': lambda t: t.replace('SMS_PROVIDER=', 'SMS_PROVIDER=netgsm'),
            'baska push iletisimi': lambda t: t.replace('yerel@example.invalid', 'biri@example.com'),
        }
        for name, edit in cases.items():
            with self.subTest(name), self.assertRaises(ValueError):
                profil.load_profile(self.profile_with(edit))

    def test_clean_environment_drops_ambient_settings(self):
        ambient = {'NODE_OPTIONS': '--inspect', 'NODE_PATH': 'x', 'HTTPS_PROXY': 'http://p:1',
                   'DB_PASSWORD': 'ortam-degeri', 'SMTP_PASSWORD': 'ortam-degeri', 'JWT_SECRET': 'ortam-degeri',
                   'GOOGLE_CLIENT_ID': 'ortam-degeri'}
        with mock.patch.dict(os.environ, ambient), tempfile.TemporaryDirectory() as work:
            first = profil.clean_environment(profil.load_profile(SAMPLE), work)
            second = profil.clean_environment(profil.load_profile(SAMPLE), work)
        for key in ambient:
            self.assertNotIn(key, first.keys() - {'JWT_SECRET'}, key + ' ortamdan gecmemeli')
        self.assertNotEqual(first['JWT_SECRET'], 'ortam-degeri')
        self.assertGreaterEqual(len(first['JWT_SECRET']), 48)
        self.assertNotEqual(first['JWT_SECRET'], second['JWT_SECRET'], 'her kosuda yeni anahtar')
        self.assertEqual(first['HOME'], work)
        self.assertEqual(first['DB_HOST'], '127.0.0.1')

    def test_browser_environment_is_minimal(self):
        with tempfile.TemporaryDirectory() as work:
            env = profil.clean_environment(profil.load_profile(SAMPLE), work)
        browser = profil.browser_environment(env)
        self.assertLessEqual(set(browser), set(profil.BASE_KEYS))
        for key in ('JWT_SECRET', 'DB_HOST', 'SMTP_HOST', 'MQTT_HOST', 'ASTRA_LOCAL_WORKDIR'):
            self.assertNotIn(key, browser)


class BrowserArgsTests(unittest.TestCase):
    def test_start_url_must_be_loopback_http(self):
        for url in ('https://127.0.0.1/', 'http://example.invalid/', 'http://u:p@127.0.0.1/', 'file:///c:/x'):
            with self.subTest(url), self.assertRaises(ValueError):
                tarayici.browser_args('chrome', 'profil', 1234, url)

    def test_flags_isolate_profile_and_network(self):
        args = tarayici.browser_args('chrome', 'profil', 4321, 'http://127.0.0.1:8080/')
        self.assertEqual(args[-1], 'http://127.0.0.1:8080/')
        self.assertIn('--proxy-server=http://127.0.0.1:4321', args)
        self.assertIn('--proxy-bypass-list=<-loopback>', args)
        self.assertTrue(any(a.startswith('--host-resolver-rules=MAP * ~NOTFOUND') for a in args))
        self.assertTrue(any(a.startswith('--user-data-dir=') for a in args))
        joined = ' '.join(args)
        for yasak in ('--no-sandbox', '--disable-web-security', '--remote-debugging', '--allow-running-insecure',
                      '--disable-site-isolation', '--ignore-certificate-errors'):
            self.assertNotIn(yasak, joined)


class WhichTests(unittest.TestCase):
    def test_path_only_lookup_ignores_cwd_and_relative_entries(self):
        name = 'yalitim_sahte_arac'
        with tempfile.TemporaryDirectory() as tmp:
            suffix = '.exe' if os.name == 'nt' else ''
            fake = Path(tmp) / (name + suffix)
            fake.write_bytes(b'')
            fake.chmod(0o755)
            old = Path.cwd()
            os.chdir(tmp)
            try:
                for path_value in ('', '.', os.pathsep.join(['.', 'goreli'])):
                    with mock.patch.dict(os.environ, {'PATH': path_value}):
                        self.assertIsNone(surecler.which_path_only(name), repr(path_value))
                with mock.patch.dict(os.environ, {'PATH': tmp}):
                    self.assertEqual(Path(surecler.which_path_only(name)), fake)
            finally:
                os.chdir(old)


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, body):
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.reply(b'merhaba ' + self.path.encode())

    def do_POST(self):
        self.reply(self.rfile.read(int(self.headers.get('Content-Length', '0'))))


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.audit = Path(self.tmp.name) / 'engellenen.jsonl'
        self.audit.touch()
        self.upstream = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        threading.Thread(target=self.upstream.serve_forever, daemon=True).start()
        self.proxy = proxy.start_proxy(self.audit)
        self.port = self.proxy.server_port
        self.up = self.upstream.server_port

        def stop():
            for server in (self.proxy, self.upstream):
                server.shutdown()
                server.server_close()
        self.addCleanup(stop)

    def events(self):
        return [json.loads(line) for line in self.audit.read_text(encoding='utf-8').splitlines() if line]

    def test_loopback_get_and_post_are_forwarded(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('GET', f'http://127.0.0.1:{self.up}/x?y=1')
        response = conn.getresponse()
        self.assertEqual((response.status, response.read()), (200, b'merhaba /x?y=1'))
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('POST', f'http://127.0.0.1:{self.up}/e', body=b'abc')
        response = conn.getresponse()
        self.assertEqual((response.status, response.read()), (200, b'abc'))
        self.assertEqual(self.events(), [])

    def test_external_target_is_rejected_and_audited_by_hash_only(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('GET', 'http://example.invalid/gizli-yol?token=abc123')
        self.assertEqual(conn.getresponse().status, 403)
        reply = raw_request(self.port, b'CONNECT example.invalid:443 HTTP/1.1\r\nHost: example.invalid:443\r\n\r\n')
        self.assertIn(b' 403 ', reply.split(b'\r\n')[0])
        events = self.events()
        self.assertEqual(len(events), 2)
        digest = hashlib.sha256(b'example.invalid').hexdigest()
        for event in events:
            self.assertEqual(set(event), {'channel', 'target_sha256', 'reason'})
            self.assertEqual(event['target_sha256'], digest)
        text = self.audit.read_text(encoding='utf-8')
        for sizinti in ('example.invalid', 'gizli-yol', 'abc123'):
            self.assertNotIn(sizinti, text)

    def test_https_to_loopback_is_not_proxied(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('GET', f'https://127.0.0.1:{self.up}/')
        self.assertEqual(conn.getresponse().status, 403)
        self.assertEqual(self.events()[0]['reason'], 'https-proxy-disabled')

    def test_localhost_name_is_pinned_to_127_0_0_1(self):
        seen = []
        real = socket.create_connection

        def spy(address, *args, **kwargs):
            seen.append(address[0])
            return real(address, *args, **kwargs)
        with mock.patch('socket.create_connection', spy):
            reply = raw_request(self.port, f'GET http://localhost:{self.up}/a HTTP/1.1\r\nHost: localhost:{self.up}\r\n\r\n'.encode())
        self.assertIn(b'merhaba /a', reply)
        self.assertEqual(seen, ['127.0.0.1'])

    def test_malformed_bodies_are_refused(self):
        base = f'POST http://127.0.0.1:{self.up}/e HTTP/1.1\r\nHost: 127.0.0.1:{self.up}\r\n'
        cases = {
            b' 501 ': base + 'Transfer-Encoding: chunked\r\n\r\n',
            b' 400 ': base + 'Content-Length: abc\r\n\r\n',
            b' 413 ': base + 'Content-Length: 99999999999\r\n\r\n',
        }
        for code, request in cases.items():
            with self.subTest(code):
                reply = raw_request(self.port, request.encode())
                self.assertIn(code, reply.split(b'\r\n')[0])
        reply = raw_request(self.port, (base + 'Content-Length: -5\r\n\r\n').encode())
        self.assertIn(b' 400 ', reply.split(b'\r\n')[0])


PROBE = r"""
const net = require('node:net'), dns = require('node:dns'), dgram = require('node:dgram'), cp = require('node:child_process');
const http = require('node:http'), tls = require('node:tls'), wt = require('node:worker_threads');
dns.setServers(['127.0.0.1:9']);
const PIPE = process.platform === 'win32' ? '\\\\.\\pipe\\yalitim_test' : '/tmp/yalitim_test.sock';
const out = {};
// Koruma bozulursa asenkron ag hatalari yoklamayi cokertmesin; sonuc yine yazilsin (test __uncaught'u da denetler).
process.on('uncaughtException', () => { out.__uncaught = (out.__uncaught || 0) + 1; });
const note = (k, fn) => {
  try { fn(); out[k] = 'allowed'; }
  catch (e) { out[k] = (e && (e.code === 'ASTRA_LOOPBACK_ONLY' || e.code === 'ERR_ACCESS_DENIED')) ? 'denied' : 'error:' + (e && e.code || e); }
};
note('connect_ip', () => { net.connect({host: '192.0.2.1', port: 81}); });
note('connect_name', () => { net.connect({host: 'x.invalid', port: 81}); });
note('connect_pipe', () => { net.connect({path: PIPE}); });
note('custom_lookup', () => { net.connect({host: 'localhost', port: 9, lookup: (h, o, cb) => cb(null, '127.0.0.2', 4)}); });
note('tls', () => { tls.connect({host: 'x.invalid', port: 443}); });
note('http_url', () => { http.get('http://x.invalid/'); });
note('http_options', () => { http.request({host: 'x.invalid', port: 80}); });
note('dns_lookup', () => { dns.lookup('x.invalid', () => {}); });
note('dns_resolveAny', () => { dns.resolveAny('x.invalid', () => {}); });
note('dns_resolver_resolve6', () => { new dns.Resolver().resolve6('x.invalid', () => {}); });
note('dns_resolver_resolveTxt', () => { new dns.Resolver().resolveTxt('x.invalid', () => {}); });
note('dns_promises_resolver', () => { new dns.promises.Resolver().resolve4('x.invalid'); });
note('dns_lookupService', () => { dns.lookupService('127.0.0.1', 80, () => {}); });
note('udp_send', () => { dgram.createSocket('udp4').send('merhaba', 9, '127.0.0.1'); });
note('spawn', () => { cp.spawn(process.execPath, ['-v']); });
note('execFileSync', () => { cp.execFileSync(process.execPath, ['-v']); });
note('execFile', () => { cp.execFile(process.execPath, ['-v'], () => {}); });
note('worker', () => { new wt.Worker('1', {eval: true}); });
note('env_external_host', () => { process.env.SMTP_HOST = 'smtp.example.invalid'; });
note('env_new_secret', () => { process.env.DB_PASSWORD = 'x'; });
const quiet = () => { const s = net.createServer(); s.on('error', () => {}); return s; };
note('listen_all_interfaces', () => { quiet().listen(0, '0.0.0.0'); });
note('listen_pipe', () => { quiet().listen(PIPE); });
note('listen_handle', () => { quiet().listen({fd: 3}); });
note('binding', () => { process.binding('tcp_wrap'); });
const listen = (label, start) => new Promise((resolve) => {
  const s = net.createServer();
  s.on('error', (e) => { out[label] = 'error:' + e.code; resolve(); });
  start(s, () => { out[label] = s.address().address; s.close(); resolve(); });
});
(async () => {
  await listen('listen_no_host', (s, cb) => s.listen(0, cb));
  await listen('listen_options', (s, cb) => s.listen({port: 0}, cb));
  await listen('listen_callback_only', (s, cb) => s.listen(cb));
  await listen('listen_backlog', (s, cb) => s.listen(0, 511, cb));
  await listen('listen_localhost', (s, cb) => s.listen(0, 'localhost', cb));
  const server = http.createServer((q, r) => r.end('selam'));
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;
  out.http_roundtrip = await new Promise((resolve, reject) => http.get({host: '127.0.0.1', port, path: '/'}, (res) => {
    let body = ''; res.on('data', (c) => body += c); res.on('end', () => resolve(body));
  }).on('error', reject));
  out.http_localhost_name = await new Promise((resolve, reject) => http.get('http://localhost:' + port + '/', (res) => {
    let body = ''; res.on('data', (c) => body += c); res.on('end', () => resolve(body));
  }).on('error', reject));
  out.fetch_roundtrip = await (await fetch('http://127.0.0.1:' + port + '/')).text();
  try { await fetch('http://x.invalid/'); out.fetch_external = 'allowed'; } catch (e) { out.fetch_external = e.code === 'ASTRA_LOOPBACK_ONLY' ? 'denied' : 'error:' + e.code; }
  server.close();
  console.log(JSON.stringify(out));
  process.exit(0);
})().catch((e) => { console.log(JSON.stringify({fatal: String(e && e.stack || e)})); process.exit(1); });
"""


@unittest.skipUnless(NODE, 'Node bulunamadi')
class NodeGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.runs = Path(cls.tmp.name)
        cls.log = cls.runs / 'engellenen.jsonl'
        cls.log.touch()
        script = cls.runs / 'probe.cjs'
        script.write_text(PROBE, encoding='utf-8')
        done = cls.run_guard(script, cls.runs, cls.log)
        cls.stdout, cls.stderr, cls.returncode = done.stdout, done.stderr, done.returncode
        try:
            cls.result = json.loads(done.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            cls.result = {}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @staticmethod
    def run_guard(script, runs, log, with_env=True):
        env = {'PATH': os.environ.get('PATH', ''), 'SYSTEMROOT': os.environ.get('SYSTEMROOT', '')}
        if with_env:
            env.update(ASTRA_LOCAL_ONLY='1', ASTRA_EGRESS_LOG=str(log), ASTRA_LOCAL_RUNS_PATH=str(runs))
        return subprocess.run([NODE, '--require', str(GUARD), str(script)], capture_output=True, text=True,
                              timeout=60, env=env, cwd=str(runs))

    def test_probe_ran(self):
        self.assertEqual(self.returncode, 0, self.stderr)
        self.assertNotIn('fatal', self.result, self.result)
        self.assertNotIn('__uncaught', self.result, 'koruma altinda beklenmeyen asenkron hata olmamali')

    def test_external_and_dangerous_channels_are_denied(self):
        denied = ['connect_ip', 'connect_name', 'connect_pipe', 'custom_lookup', 'tls', 'http_url', 'http_options',
                  'dns_lookup', 'dns_resolveAny', 'dns_resolver_resolve6', 'dns_resolver_resolveTxt',
                  'dns_promises_resolver', 'dns_lookupService', 'udp_send', 'spawn', 'execFileSync', 'execFile',
                  'worker', 'env_external_host', 'env_new_secret', 'listen_all_interfaces', 'listen_pipe',
                  'listen_handle', 'binding', 'fetch_external']
        for name in denied:
            with self.subTest(name):
                self.assertEqual(self.result.get(name), 'denied')

    def test_listen_without_host_binds_loopback_only(self):
        for name in ('listen_no_host', 'listen_options', 'listen_callback_only', 'listen_backlog', 'listen_localhost'):
            with self.subTest(name):
                self.assertEqual(self.result.get(name), '127.0.0.1')

    def test_loopback_traffic_still_works(self):
        for name in ('http_roundtrip', 'http_localhost_name', 'fetch_roundtrip'):
            with self.subTest(name):
                self.assertEqual(self.result.get(name), 'selam')

    def test_audit_log_holds_hashes_only(self):
        text = self.log.read_text(encoding='utf-8')
        events = [json.loads(line) for line in text.splitlines() if line]
        self.assertGreaterEqual(len(events), 15)
        for event in events:
            self.assertEqual(set(event), {'channel', 'target_sha256', 'reason'})
            self.assertRegex(event['target_sha256'], r'^[0-9a-f]{64}$')
        for sizinti in ('x.invalid', '192.0.2.1', 'smtp.example', 'merhaba'):
            self.assertNotIn(sizinti, text)
        self.assertIn(hashlib.sha256(b'x.invalid').hexdigest(), text)
        # UDP gonderiminde hash yukun (iletinin) degil hedef adresin ozeti olmali.
        self.assertNotIn(hashlib.sha256(b'merhaba').hexdigest(), text)

    def test_guard_refuses_incomplete_environment(self):
        script = self.runs / 'noop.cjs'
        script.write_text('console.log("calisti")', encoding='utf-8')
        done = self.run_guard(script, self.runs, self.log, with_env=False)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn('ASTRA_LOCAL_GUARD_ENV_REQUIRED', done.stderr)
        self.assertNotIn('calisti', done.stdout)

    def test_guard_refuses_log_outside_runs_root(self):
        script = self.runs / 'noop2.cjs'
        script.write_text('console.log("calisti")', encoding='utf-8')
        with tempfile.TemporaryDirectory() as other:
            done = self.run_guard(script, self.runs, Path(other) / 'baska.jsonl')
        self.assertNotEqual(done.returncode, 0)
        self.assertIn('ASTRA_EGRESS_LOG_OUTSIDE_RUNS', done.stderr)


class CliTests(unittest.TestCase):
    def test_help_works(self):
        done = run_cli('--help')
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn('--dry-run', done.stdout)

    def test_dry_run_checks_everything_and_creates_nothing(self):
        if not NODE:
            self.skipTest('Node bulunamadi')
        port = free_port()
        runs = HERE / ('_test_kuru_' + str(time.time_ns()))
        self.addCleanup(shutil.rmtree, runs, True)
        done = run_cli('--dry-run', '--no-browser', '--port', str(port), '--url', f'http://127.0.0.1:{port}/health',
                       env_extra={'ASTRA_LOCAL_RUNS_PATH': str(runs)})
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn('KURU_CALISMA_TAMAM', done.stdout)
        self.assertIn('ortam_anahtarlari=', done.stdout)
        self.assertFalse(runs.exists(), 'kuru calistirma dizin olusturmamali')
        # Ortam degerleri (rastgele JWT anahtari dahil) yazdirilmaz.
        self.assertNotRegex(done.stdout, r'JWT_SECRET=')

    def test_rejections(self):
        port = free_port()
        good = ('--dry-run', '--no-browser', '--port', str(port), '--url', f'http://127.0.0.1:{port}/')
        cases = {
            'dis hazirlik adresi': (('--dry-run', '--url', 'http://example.invalid/'), None, 'loopback'),
            'dis dinleme adresi': (good + ('--host', '0.0.0.0'), None, 'loopback'),
            'depo disi giris': (good + ('--entry', '../x.js'), None, 'Entry'),
            'mutlak yol giris': (good + ('--entry', str(Path(tempfile.gettempdir()) / 'x.js')), None, 'Entry'),
            'depo disi kosu koku': (good, {'ASTRA_LOCAL_RUNS_PATH': tempfile.gettempdir()}, 'subdirectory'),
            'depo kokunun kendisi': (good, {'ASTRA_LOCAL_RUNS_PATH': str(ROOT)}, 'subdirectory'),
        }
        for name, (args, env, message) in cases.items():
            with self.subTest(name):
                done = run_cli(*args, env_extra=env)
                self.assertEqual(done.returncode, 2, done.stdout)
                self.assertIn(message, done.stderr)

    @unittest.skipUnless(NODE, 'Node bulunamadi')
    def test_synthetic_run_start_and_stop(self):
        work = HERE / ('_test_kosu_' + str(time.time_ns()))
        work.mkdir()
        self.addCleanup(shutil.rmtree, work, True)
        (work / 'servis.cjs').write_text(
            "require('node:http').createServer((q, r) => r.end('ok')).listen(Number(process.env.PORT), process.env.LISTEN_HOST);\n",
            encoding='utf-8')
        runs = work / 'runs'
        port = free_port()
        done = run_cli('--entry', str((work / 'servis.cjs').relative_to(ROOT)), '--no-browser', '--port', str(port),
                       '--url', f'http://127.0.0.1:{port}/', '--duration', '1', '--ready-timeout', '30',
                       env_extra={'ASTRA_LOCAL_RUNS_PATH': str(runs)})
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn('YEREL_HAZIR', done.stdout)
        self.assertEqual((runs / '.gitignore').read_text(encoding='utf-8'), '*\n')
        kosular = [p for p in runs.iterdir() if p.name.startswith('calisma-')]
        self.assertEqual(len(kosular), 1)
        for ad in ('kapandi', 'durdur', 'engellenen.jsonl', 'pid', 'node-stderr.log'):
            self.assertTrue((kosular[0] / ad).exists(), ad)
        with self.assertRaises(OSError):
            socket.create_connection(('127.0.0.1', port), timeout=2).close()


class StaticSafetyTests(unittest.TestCase):
    """Arac hicbir dosya silmez/kabuk calistirmaz; sir, parola veya sabit mutlak yol icermez."""

    def sources(self):
        return [p for p in HERE.iterdir() if p.suffix in ('.py', '.cjs') and not p.name.startswith('test_')]

    def test_no_destructive_or_shell_calls(self):
        yasak = re.compile(r'rmtree|os\.remove|os\.unlink|\.unlink\(|os\.rmdir|rmSync|unlinkSync|rmdirSync|'
                           r'os\.system|shell\s*=\s*True|taskkill|Remove-Item|\bkillall\b|os\.kill')
        for path in self.sources():
            with self.subTest(path.name):
                self.assertIsNone(yasak.search(path.read_text(encoding='utf-8')))

    def test_no_machine_specific_paths_or_secrets(self):
        desen = re.compile(r'[A-Za-z]:[\\/](Users|site|temp)|/home/|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}', re.I)
        for path in self.sources() + [SAMPLE]:
            with self.subTest(path.name):
                self.assertIsNone(desen.search(path.read_text(encoding='utf-8')))


if __name__ == '__main__':
    unittest.main()

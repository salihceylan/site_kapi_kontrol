"""Local-only entry point. Child processes inherit a clean explicit profile."""
import argparse, os, socket, subprocess, sys, tempfile, time, urllib.request, urllib.error
from pathlib import Path
from profil import browser_environment, clean_environment, load_profile
from surecler import OwnedProcesses, which_path_only
from tarayici import browser_args, find_browser
from proxy import start_proxy

ROOT=Path(__file__).resolve().parents[3]
# [kap/yalitim] Profil ornegi aracin kendi klasorundedir (kaynak dalda tools/yerel/.env.yerel.ornek idi).
PROFILE=Path(__file__).resolve().parent/'profil.yerel.ornek'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl): return None
def node_args(node, entry, work):
    from pathlib import Path
    root=Path(__file__).resolve().parent
    return [node,'--require',str(root/'node_guard.cjs'),str(entry)]
def check_port(host, port):
    """Fail before spawning; never treat an existing listener as our service."""
    family = socket.AF_INET6 if host == '::1' else socket.AF_INET
    with socket.socket(family, socket.SOCK_STREAM) as probe:
        if os.name == 'nt':
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        probe.bind(('127.0.0.1' if host == 'localhost' else host, port))

def node_version(node, env, cwd):
    """[kap/yalitim] (major, 'vX.Y.Z'): surum sorgusu da temiz ortamda calisir."""
    out = subprocess.run([node, '--version'], env=env, cwd=cwd, capture_output=True, text=True,
                         check=True, timeout=5).stdout.strip()
    return int(out.lstrip('v').split('.')[0]), out

def wait_ready(process, url, run_dir, timeout):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError('Node exited before readiness; see node-stderr.log')
        if (run_dir / 'durdur').exists():
            raise RuntimeError('Stopped before readiness')
        try:
            with opener.open(url, timeout=min(1, max(.01, deadline-time.monotonic()))) as response:
                if 200 <= response.status < 300 and process.poll() is None:
                    return
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()
            if 300 <= code < 400:
                raise RuntimeError('Readiness redirect denied') from None
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(.05)
    raise RuntimeError('Readiness timed out')

def run(argv=None):
    p=argparse.ArgumentParser(description='Sunucuyu yalitilmis (yalniz loopback) bir ortamda baslatir. '
                              'Hicbir dosya silmez; yalniz kendi baslattigi surecleri kapatir.')
    p.add_argument('--entry',default='server/src/server.js',help='Sunucu giris dosyasi (depo icinde olmali)')
    p.add_argument('--url',default='http://127.0.0.1:8080/health',help='Hazirlik adresi (loopback http, --host/--port ile ayni)')
    p.add_argument('--no-browser',action='store_true',help='Tarayici ve vekil baslatma')
    p.add_argument('--ready-timeout',type=float,default=10,help='Hazirlik bekleme suresi (sn)')
    p.add_argument('--duration',type=int,default=3600,help='Hazir olduktan sonra en fazla calisma suresi (sn)')
    p.add_argument('--port',type=int,default=8080,help='Sunucu portu')
    p.add_argument('--host',default='127.0.0.1',help='Dinleme adresi (yalniz 127.0.0.1, localhost veya ::1)')
    # [kap/yalitim] Kuru calistirma: hicbir sey baslatmadan/olusturmadan on kontrolleri yapar.
    p.add_argument('--dry-run',action='store_true',help='Kuru calistirma: kontrolleri yap, plani yazdir, hicbir sey baslatma/olusturma')
    args=p.parse_args(argv)
    from urllib.parse import urlsplit
    u=urlsplit(args.url)
    if u.scheme!='http' or u.hostname not in ('127.0.0.1','localhost','::1'):
        raise ValueError('Readiness URL must be loopback HTTP')
    if u.username or u.password:
        raise ValueError('Readiness credentials are forbidden')
    entry=(ROOT/args.entry).resolve()
    if not entry.is_relative_to(ROOT) or not entry.is_file(): raise ValueError('Entry must be an existing file inside this worktree')
    host=args.host
    if host not in ('127.0.0.1','localhost','::1'): raise ValueError('Bind address must be loopback')
    if not 1 <= args.port <= 65535 or args.duration < 0 or args.ready_timeout <= 0:
        raise ValueError('Invalid port or timeout')
    canonical = lambda value: '127.0.0.1' if value == 'localhost' else value
    if (u.port or 80) != args.port or canonical(u.hostname) != canonical(host):
        raise ValueError('Readiness must target the service bind address and port')
    # [kap/yalitim] Bos deger varsayilana duser, goreli yol depo kokune gore cozulur (cwd'ye gore degil).
    runs_env=os.environ.get('ASTRA_LOCAL_RUNS_PATH','').strip()
    workroot=Path(runs_env) if runs_env else ROOT/'tools/yerel/runs'
    if not workroot.is_absolute(): workroot=ROOT/workroot
    workroot=workroot.resolve()
    if workroot==ROOT or not workroot.is_relative_to(ROOT):
        raise ValueError('Run directory must be a subdirectory of this worktree')
    check_port(host, args.port)
    browser = None if args.no_browser else find_browser()
    node = which_path_only('node')
    if not node: raise RuntimeError('Node is required')
    profile = load_profile(PROFILE)
    if args.dry_run:
        env=clean_environment(profile,workroot/'calisma-KURU')
        major,version=node_version(node,env,tempfile.gettempdir())
        if major < 24: raise RuntimeError('Node 24+ is required')
        print('KURU_CALISMA_TAMAM')
        print('giris='+str(entry.relative_to(ROOT)))
        print('dinleme='+host+':'+str(args.port)+' hazirlik='+args.url)
        print('node='+node+' '+version)
        print('tarayici='+(browser or 'yok (--no-browser)'))
        print('profil='+str(PROFILE.relative_to(ROOT))+' anahtar_sayisi='+str(len(profile)))
        print('calisma_koku='+str(workroot)+' (olusturulmadi)')
        print('komut='+' '.join(node_args(node,entry,workroot)))
        print('ortam_anahtarlari='+','.join(sorted(env))+' (degerler yazdirilmaz)')
        return 0
    # [kap/yalitim] Yeni/bos kosu kokune '*' iceren .gitignore konur: kosu ciktilari (gunlukler, tarayici
    # profili) yanlislikla commit'e girmesin. Dolu bir dizinin icine hicbir sey yazilmaz.
    fresh = not workroot.exists() or not any(workroot.iterdir())
    workroot.mkdir(parents=True,exist_ok=True)
    if fresh and not (workroot/'.gitignore').exists(): (workroot/'.gitignore').write_text('*\n',encoding='utf-8')
    run_dir=workroot/('calisma-'+str(time.time_ns())); run_dir.mkdir()
    (run_dir/'engellenen.jsonl').touch()
    env=clean_environment(profile,run_dir)
    env.update(PORT=str(args.port),LISTEN_HOST=host,ASTRA_LOCAL_ONLY='1',ASTRA_EGRESS_LOG=str(run_dir/'engellenen.jsonl'),ASTRA_LOCAL_RUNS_PATH=str(workroot))
    proxy = None
    try:
        major,_version=node_version(node,env,run_dir)
        if major < 24:
            raise RuntimeError('Node 24+ is required')
        command=node_args(node,entry,run_dir)
        with OwnedProcesses() as owned, (run_dir/'node-stderr.log').open('wb') as node_error, \
                (run_dir/'browser-stderr.log').open('wb') as browser_error:
            proc=owned.add(subprocess.Popen(command,cwd=run_dir,env=env,
                                           stdout=subprocess.DEVNULL,stderr=node_error))
            (run_dir/'pid').write_text(str(proc.pid), encoding='utf-8')
            wait_ready(proc, args.url, run_dir, args.ready_timeout)
            browser_process = None
            if browser:
                proxy = start_proxy(run_dir/'engellenen.jsonl')
                cmd = browser_args(browser, run_dir/'browser', proxy.server_port, args.url)
                # [kap/yalitim] Tarayici uygulama ayarlarini (JWT_SECRET, DB_*, ...) almaz.
                browser_process = owned.add(subprocess.Popen(cmd,cwd=run_dir,env=browser_environment(env),
                                            stdout=subprocess.DEVNULL,stderr=browser_error))
                if browser_process.poll() is not None:
                    raise RuntimeError('Browser exited; see browser-stderr.log')
            print('YEREL_HAZIR '+str(run_dir),flush=True)
            deadline=time.monotonic()+args.duration
            while time.monotonic()<deadline and not (run_dir/'durdur').exists():
                if proc.poll() is not None:
                    # An external stopper may kill Node immediately before writing the 'durdur' marker.
                    time.sleep(.2)
                    if (run_dir/'durdur').exists(): break
                    raise RuntimeError('Node exited during run; see node-stderr.log')
                if browser_process and browser_process.poll() is not None:
                    raise RuntimeError('Browser exited during run; see browser-stderr.log')
                time.sleep(.1)
    finally:
        if proxy:
            proxy.shutdown()
            proxy.server_close()
        (run_dir/'durdur').touch()
        (run_dir/'kapandi').touch()
    return 0
if __name__=='__main__':
    try: raise SystemExit(run())
    except Exception as e: print(str(e),file=sys.stderr); raise SystemExit(2)

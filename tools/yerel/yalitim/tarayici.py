"""Chromium launch configuration with an explicit loopback proxy."""
import os
from pathlib import Path
from urllib.parse import urlsplit
from surecler import which_path_only

def find_browser():
    for relative in ('Google/Chrome/Application/chrome.exe', 'Microsoft/Edge/Application/msedge.exe'):
        for root in (os.environ.get('ProgramFiles', 'C:/Program Files'),
                     os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')):
            candidate = Path(root) / relative
            if candidate.is_file():
                return str(candidate)
    # [kap/yalitim] shutil.which yerine yalniz-PATH aramasi (calisma dizinindeki ikili secilmez).
    for name in ('chromium', 'chromium-browser', 'google-chrome', 'msedge'):
        if candidate := which_path_only(name):
            return candidate
    raise FileNotFoundError('Yerel Chromium/Edge gerekli; otomatik indirme yapilmaz')

def browser_args(executable, profile_dir, proxy_port, url, headless=False):
    parsed = urlsplit(url)
    if (parsed.scheme != 'http' or parsed.hostname not in {'127.0.0.1', '::1', 'localhost'}
            or parsed.username or parsed.password):
        raise ValueError('Baslangic URLsi yalniz loopback HTTP olabilir')
    # A run-owned profile prevents reuse of a running personal browser.
    # This isolation predates sandbox diagnostics; GPU/sandbox overrides do not belong here.
    flags = [executable, '--user-data-dir=' + str(Path(profile_dir).resolve()),
             '--no-first-run', '--no-default-browser-check', '--disable-extensions',
             '--disable-background-networking', '--disable-component-update', '--disable-sync',
             '--disable-domain-reliability', '--disable-quic', '--disable-breakpad',
             '--disable-features=DnsOverHttps,AsyncDns,MediaRouter,OptimizationHints,PreconnectToSearch,'
             'HttpsUpgrades,HttpsFirstBalancedMode,HttpsFirstBalancedModeAutoEnable',
             '--dns-prefetch-disable', '--disable-preconnect', '--disable-pings',
             '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
             '--webrtc-ip-handling-policy=disable_non_proxied_udp',
             '--proxy-bypass-list=<-loopback>',
             f'--proxy-server=http://127.0.0.1:{proxy_port}',
             '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1, EXCLUDE localhost, EXCLUDE [::1]']
    if headless:
        flags += ['--headless=new', '--dump-dom', '--timeout=15000']
    return flags + [url]

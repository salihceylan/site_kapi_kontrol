"""Strict local profile loading and inherited environment isolation."""
from pathlib import Path
import os
import secrets

ALLOWED = {
    'NODE_ENV', 'HOST', 'LISTEN_HOST', 'PORT', 'DB_HOST', 'DB_PORT', 'DB_NAME',
    'DB_USER', 'DB_PASSWORD', 'MQTT_HOST', 'MQTT_PORT', 'MQTT_USERNAME',
    'MQTT_PASSWORD', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASSWORD',
    'JWT_SECRET', 'SMS_PROVIDER', 'NETGSM_USERCODE', 'NETGSM_PASSWORD',
    'NETGSM_HEADER', 'SMS_CODE_PEPPER', 'WEB_PUSH_VAPID_PUBLIC',
    'WEB_PUSH_VAPID_PRIVATE', 'WEB_PUSH_SUBJECT'
}
LOCAL_DEFAULTS = {'DB_HOST': '127.0.0.1', 'MQTT_HOST': '127.0.0.1', 'SMTP_HOST': '127.0.0.1'}
# [kap/yalitim] Ortak temel degiskenler (tarayiciya da yalniz bunlar verilir).
BASE_KEYS = ('PATH', 'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'HOME', 'USERPROFILE')

def load_profile(path):
    values = {}
    for line_no, raw in enumerate(Path(path).read_text(encoding='utf-8-sig').splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if '=' not in line:
            raise ValueError(f'Invalid profile line {line_no}')
        key, value = line.split('=', 1)
        key, value = key.strip(), value.strip()
        if key not in ALLOWED or key in values:
            raise ValueError(f'Unexpected profile key at line {line_no}')
        values[key] = value
    for key, value in LOCAL_DEFAULTS.items():
        if values.get(key) != value:
            raise ValueError(f'{key} must be loopback')
    for key in ('HOST', 'LISTEN_HOST'):
        if values.get(key, '127.0.0.1') not in ('127.0.0.1', 'localhost', '::1'):
            raise ValueError(f'{key} must be loopback')
    if values.get('SMS_PROVIDER', ''):
        raise ValueError('External SMS provider must remain disabled')
    if values.get('WEB_PUSH_SUBJECT') != 'mailto:yerel@example.invalid':
        raise ValueError('Only the reserved local contact is allowed')
    return values

def clean_environment(profile, workdir):
    env = {'PATH': os.environ.get('PATH', ''), 'SYSTEMROOT': os.environ.get('SYSTEMROOT', ''),
           'WINDIR': os.environ.get('WINDIR', ''), 'TEMP': os.environ.get('TEMP', ''),
           'TMP': os.environ.get('TMP', ''), 'HOME': str(workdir), 'USERPROFILE': str(workdir)}
    env.update(profile)
    env['JWT_SECRET'] = secrets.token_urlsafe(48)
    env.update(DB_HOST='127.0.0.1', MQTT_HOST='127.0.0.1', SMTP_HOST='127.0.0.1',
               ASTRA_LOCAL_WORKDIR=str(Path(workdir).resolve()))
    return {k: v for k, v in env.items() if v != '' or k in ('SMS_PROVIDER', 'NETGSM_USERCODE', 'NETGSM_PASSWORD',
            'NETGSM_HEADER', 'SMS_CODE_PEPPER', 'WEB_PUSH_VAPID_PUBLIC', 'WEB_PUSH_VAPID_PRIVATE')}

def browser_environment(env):
    """[kap/yalitim] Tarayici sureci yalniz temel degiskenleri alir; JWT_SECRET, DB_*, SMTP_* gibi
    uygulama ayarlari tarayiciya gecmez (en az yetki)."""
    return {k: env[k] for k in BASE_KEYS if k in env}

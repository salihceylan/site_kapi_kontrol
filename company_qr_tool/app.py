from __future__ import annotations

import base64
import io
import ipaddress
import json
import hashlib
import os
import queue
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, cast
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

import qrcode
from qrcode.constants import ERROR_CORRECT_H
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageTk
import serial
from serial.tools import list_ports

from ui_kit import C, Kit, Pill, Sidebar, SmoothProgress, Spinner, Stepper, Tooltip, enable_dpi_awareness

BASE_DIR = Path(__file__).resolve().parent
ASSETS_DIR = BASE_DIR / "assets"
OUTPUT_DIR = BASE_DIR / "output"
QRCODES_DIR = OUTPUT_DIR / "qrcodes"
LABELED_DEVICES_FILE = OUTPUT_DIR / "labeled_devices.json"
LOGO_PATH = ASSETS_DIR / "smartkeypass_logo.png"

DEVICE_PROJECT_DIR = (BASE_DIR / ".." / "cihaz_kontrol").resolve()
PLATFORMIO_INI_PATH = DEVICE_PROJECT_DIR / "platformio.ini"
BUILD_DIR = DEVICE_PROJECT_DIR / ".pio" / "build"
RELEASES_DIR = DEVICE_PROJECT_DIR / "firmware_releases"
RELEASE_INDEX = RELEASES_DIR / "index.json"

DISPLAY_PROJECT_DIR = (BASE_DIR / ".." / "ekran_yazilimi").resolve()
DISPLAY_PLATFORMIO_INI_PATH = DISPLAY_PROJECT_DIR / "platformio.ini"
DISPLAY_ENV = "esp32c3_display"
DISPLAY_TARGET = "esp32c3-display"
DISPLAY_BUILD_DIR = DISPLAY_PROJECT_DIR / ".pio" / "build" / DISPLAY_ENV
DISPLAY_RELEASES_DIR = DISPLAY_PROJECT_DIR / "firmware_releases"
DISPLAY_RELEASE_INDEX = DISPLAY_RELEASES_DIR / "index.json"
DISPLAY_CONFIG_H_PATH = DISPLAY_PROJECT_DIR / "include" / "config.h"
LOCAL_SERVER_FIRMWARE_BASE_DIR = (BASE_DIR / ".." / "server" / "firmware").resolve()


def _load_local_env_file() -> None:
    """company_qr_tool/.env (git'e GIRMEZ) icindeki KEY=VALUE satirlarini ortama ekler.

    Zaten tanimli ortam degiskenlerini EZMEZ. Sirlar (COMPANY_API_KEY, SSH parolasi vb.)
    yalnizca burada veya kullanici ortam degiskenlerinde tutulur; kaynak koda yazilmaz.
    Ornek icin env.example dosyasina bakin.
    """
    env_path = BASE_DIR / ".env"
    try:
        if not env_path.is_file():
            return
        for raw_line in env_path.read_text(encoding="utf-8-sig").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            if key and key.replace("_", "").isalnum() and key not in os.environ:
                os.environ[key] = value
    except Exception:
        pass


def _env_str(name: str, default: str = "") -> str:
    value = os.environ.get(name, "").strip()
    return value or default


_load_local_env_file()

# Sunucu/VPS ayarlari: varsayilanlar korunur; ortam degiskenleriyle (veya .env ile) ezilebilir.
# Bu degerlerin hicbiri sir DEGILDIR (sirlar: COMPANY_API_KEY, AHBU_VPS_PASSWORD, SSH_KEY_PASSPHRASE).
VPS_HOST = _env_str("AHBU_VPS_HOST", "178.210.161.55")
VPS_PORT = _env_str("AHBU_VPS_PORT", "22667")
VPS_USER = _env_str("AHBU_VPS_USER", "salihceylan")
VPS_FIRMWARE_BASE_DIR = _env_str("AHBU_VPS_FIRMWARE_DIR", "/var/www/site_kapi_kontrol/server/firmware")
VPS_LABELED_DEVICES_DIR = _env_str("AHBU_VPS_DATA_DIR", "/var/www/site_kapi_kontrol/server/data")
VPS_QRCODES_DIR = _env_str("AHBU_VPS_QRCODES_DIR", "/var/www/site_kapi_kontrol/server/public/qrcodes")
PUBLIC_API_URL = _env_str("AHBU_API_URL", "https://api.gudeteknoloji.com.tr").rstrip("/")
# Duz HTTP yedek uc (eski: http://<IP>:3000). Artik VARSAYILAN KAPALI: sirket anahtari ve
# QR gorselleri sifresiz gitmesin. Gerekirse ornek: AHBU_API_FALLBACK_URL=http://127.0.0.1:3000
API_FALLBACK_URL = _env_str("AHBU_API_FALLBACK_URL", "").rstrip("/")

# C9: sirket uclari (/api/company/*) yetkisi = "X-Company-Key" basligi == sunucudaki COMPANY_API_KEY
COMPANY_KEY_ENV = "COMPANY_API_KEY"
COMPANY_KEY_MISSING_MESSAGE = (
    "COMPANY_API_KEY tanimli degil.\n\n"
    "Sunucudaki sirket uclari (cihaz kaydi / liste / silme) bu anahtar olmadan reddedilir (401).\n"
    "Sunucudaki server/.env dosyasinda tanimli COMPANY_API_KEY degerini bu bilgisayarda tanimlayin:\n"
    "  - company_qr_tool klasorune .env dosyasi olusturup  COMPANY_API_KEY=...  yazin "
    "(ornek: env.example), veya\n"
    "  - Windows'ta:  setx COMPANY_API_KEY \"...\"  komutuyla kullanici ortam degiskeni ekleyin.\n"
    "Sonra uygulamayi kapatip yeniden acin."
)


def get_company_api_key() -> str:
    return os.environ.get(COMPANY_KEY_ENV, "").strip()


def _is_key_safe_url(url: str) -> bool:
    """Anahtar yalnizca HTTPS (veya yerel makine) uzerinden gonderilir; duz HTTP ile ASLA."""
    try:
        parsed = urllib.parse.urlparse(url)
    except Exception:
        return False
    if parsed.scheme == "https":
        return True
    return parsed.scheme == "http" and (parsed.hostname or "") in ("localhost", "127.0.0.1", "::1")


def company_request_headers(url: str, extra: dict | None = None) -> dict:
    headers = {"User-Agent": "SmartKeyPass-Device-Tool/1.0"}
    if extra:
        headers.update(extra)
    key = get_company_api_key()
    if key and _is_key_safe_url(url):
        headers["X-Company-Key"] = key
    return headers


def _http_error_body(error) -> bytes:
    """HTTPError gövdesini güvenle (en fazla 4 KB) okur; okunamazsa boş döner."""
    try:
        return error.read()[:4096]
    except Exception:
        return b""


def _company_http_error_text(code: int, body: bytes | None = None) -> str:
    if code in (401, 403):
        return (
            f"Sunucu yetkilendirmeyi reddetti (HTTP {code}). "
            f"{COMPANY_KEY_ENV} sunucudaki degerle ayni mi?"
        )
    detail = ""
    if body:
        # Sunucu hata gövdesi: {"error": "...", "errorId": "..."} — kullanıcıya gerçek nedeni göster.
        try:
            payload = json.loads(body.decode("utf-8", errors="replace"))
            if isinstance(payload, dict):
                message = str(payload.get("error") or "").strip()
                error_id = str(payload.get("errorId") or payload.get("error_id") or "").strip()
                if message:
                    detail = f" - {message[:200]}"
                if error_id:
                    detail += f" (Hata kodu: {error_id[:40]})"
        except Exception:
            pass
    return f"Sunucu hatasi: HTTP {code}{detail}"


def chip_to_hardware_type(chip: str) -> str:
    """Çip adından sunucunun beklediği donanım türünü çıkarır; belirsizse '' (sunucu tahmin ETMEZ)."""
    value = (chip or "").upper()
    if "C3" in value:
        return "esp32_c3"
    if "WROOM" in value or "WROVER" in value or "D0WD" in value:
        return "esp32_wroom"
    return ""


# SFTP: sunucu kimligi known_hosts ile dogrulanir (otomatik "guven" YOK).
def known_hosts_path() -> Path:
    configured = os.environ.get("SSH_KNOWN_HOSTS", "").strip()
    return Path(configured).expanduser() if configured else Path.home() / ".ssh" / "known_hosts"


def known_hosts_setup_help() -> str:
    return (
        f"Sunucu kimligi dogrulanamadi: {VPS_HOST}:{VPS_PORT} known_hosts dosyasinda ({known_hosts_path()}) yok.\n\n"
        "ILK KURULUM (bir kez):\n"
        "  1) Sunucuda parmak izini ogrenin:  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub\n"
        f"  2) Bu bilgisayarda:  ssh-keyscan -p {VPS_PORT} -H {VPS_HOST} >> \"{known_hosts_path()}\"\n"
        "  3) Eklenen anahtarin parmak izini 1. adimdaki degerle KARSILASTIRIN "
        "(ssh-keygen -lf <known_hosts>); eslesmiyorsa kaydi silin.\n"
        "Alternatif: SSH_KNOWN_HOSTS ortam degiskeniyle baska bir known_hosts dosyasi gosterin."
    )


def open_verified_ssh_client(paramiko, password: str):
    """known_hosts ile dogrulanan SSH baglantisi acar (RejectPolicy; AutoAddPolicy YOK).

    Kimlik dogrulama: SSH_KEY_FILE (+ opsiyonel SSH_KEY_PASSPHRASE) varsa anahtar ile;
    yoksa verilen parola ile.
    """
    known_hosts = known_hosts_path()
    if not known_hosts.is_file():
        raise RuntimeError(known_hosts_setup_help())

    client = paramiko.SSHClient()
    client.load_host_keys(str(known_hosts))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())

    connect_kwargs: dict = {
        "port": int(VPS_PORT),
        "username": VPS_USER,
        "timeout": 12,
    }
    key_file = os.environ.get("SSH_KEY_FILE", "").strip()
    if key_file:
        key_path = Path(key_file).expanduser()
        if not key_path.is_file():
            raise RuntimeError(f"SSH_KEY_FILE bulunamadi: {key_path}")
        connect_kwargs["key_filename"] = str(key_path)
        passphrase = os.environ.get("SSH_KEY_PASSPHRASE", "")
        if passphrase:
            connect_kwargs["passphrase"] = passphrase
        connect_kwargs["look_for_keys"] = False
        connect_kwargs["allow_agent"] = False
    else:
        connect_kwargs["password"] = password

    try:
        client.connect(VPS_HOST, **connect_kwargs)
    except paramiko.BadHostKeyException as exc:
        raise RuntimeError(
            f"UYARI: {VPS_HOST} sunucusunun anahtari known_hosts kaydiyla UYUSMUYOR "
            "(sunucu yeniden kurulmus olabilir veya araya girilmis olabilir). "
            "Parmak izini sunucudan dogrulamadan baglanmayin.\n\n"
            f"Ayrinti: {exc}"
        ) from exc
    except paramiko.PasswordRequiredException as exc:
        raise RuntimeError(
            "SSH anahtari parola ile korunuyor: SSH_KEY_PASSPHRASE ortam degiskenini tanimlayin."
        ) from exc
    except paramiko.SSHException as exc:
        if "known_hosts" in str(exc):
            raise RuntimeError(known_hosts_setup_help()) from exc
        raise
    return client


def target_for_env(env: str) -> str:
    env_clean = str(env).lower()
    if "wroom" in env_clean or "esp32dev" in env_clean:
        return "esp32-wroom"
    return "esp32-c3"


def bootloader_offset_for_env(env: str) -> str:
    return "0x1000" if target_for_env(env) == "esp32-wroom" else "0x0"


PLATFORMIO_HOME = Path.home() / ".platformio"
BUNDLED_PYTHON_DIR = PLATFORMIO_HOME / "python3"
BUNDLED_ESPTOOL_DIR = PLATFORMIO_HOME / "packages" / "tool-esptoolpy"
BUNDLED_SITE_PACKAGES_DIR = PLATFORMIO_HOME / "penv" / "Lib" / "site-packages"

MAC_RE = re.compile(r"MAC:\s*([0-9A-Fa-f:]{17})")
CHIP_RE = re.compile(r"Chip is\s+([^\r\n]+)")
ENV_RE = re.compile(r"^\s*\[env:([^\]]+)\]")
UPL_RE = re.compile(r"^\s*upload_speed\s*=\s*(\d+)")
PROG_RE = re.compile(r"\((\d{1,3})\s*%\)")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
OTA_VERSION_C3_RE = re.compile(r'OTA_VERSION_C3\[\]\s*=\s*"(\d+\.\d+\.\d+)"')
OTA_VERSION_WROOM_RE = re.compile(r'OTA_VERSION_WROOM\[\]\s*=\s*"(\d+\.\d+\.\d+)"')
OTA_VERSION_RE = re.compile(r'OTA_(?:CURRENT_)?VERSION(?:_[A-Z0-9]+)?\[\]\s*=\s*"(\d+\.\d+\.\d+)"')
QR_SIZE = 1200
QR_LABEL_HEIGHT = 150
# Arayuz: karekod onizleme kutusu (96 dpi pikseli; yuksek DPI'da olceklenir) ve port izleme araligi.
QR_PREVIEW_PX = 220
PORT_POLL_MS = 1500
FW_OP_LABELS = {
    "build": "Derleniyor",
    "release": "Sürüm hazırlanıyor",
    "upload": "Karta yükleniyor",
    "server": "Sunucuya gönderiliyor",
    "zip": "ZIP hazırlanıyor",
}


def format_when(value: object) -> str:
    """ISO zaman damgasini yerel saatle 'GG.AA.YYYY SS:DD' yazar; cozulemezse oldugu gibi birakir."""
    text = str(value or "-").strip()
    if "T" not in text:
        return text
    try:
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if dt.tzinfo is not None:
            dt = dt.astimezone()
        return dt.strftime("%d.%m.%Y %H:%M")
    except ValueError:
        return text


@dataclass
class EspDevice:
    port: str
    description: str
    chip: str
    unique_id: str = ""


@dataclass
class DeviceStatus:
    values: dict[str, str] = field(default_factory=lambda: {})

    def get(self, key: str) -> str:
        value = self.values.get(key, "-").strip()
        return value if value else "-"


class SerialWorker:
    def __init__(
        self,
        port: str,
        on_line: Callable[[str], None],
        on_error: Callable[[str], None],
        baud_rate: int = 115200,
    ) -> None:
        self.port = port
        self.baud_rate = baud_rate
        self.on_line = on_line
        self.on_error = on_error
        self._serial: serial.Serial | None = None
        self._stop = threading.Event()
        self._write_queue: queue.Queue[str] = queue.Queue()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        try:
            if self._serial is not None:
                self._serial.close()
                self._serial = None
        except Exception:
            pass
        if self._thread.is_alive() and threading.current_thread() != self._thread:
            try:
                self._thread.join(timeout=0.5)
            except Exception:
                pass

    def write(self, text: str) -> None:
        if not text.endswith("\n"):
            text += "\r\n"
        self._write_queue.put(text)

    def _run(self) -> None:
        try:
            # DTR/RTS MUTLAKA open() oncesinde False yapilmali!
            # Eger port=None ile olusturup sonra open() cagrilirsa,
            # pyserial Windows CH340 surucusunun brief assertion yapmasini onler.
            # Aksi takdirde Serial(port=...) direk acarken Windows driver
            # kisaca DTR/RTS'i assert eder -> chip download mode'a girer.
            self._serial = serial.Serial()
            self._serial.port = self.port
            self._serial.baudrate = self.baud_rate
            self._serial.timeout = 0.2
            self._serial.rtscts = False
            self._serial.dsrdtr = False
            self._serial.dtr = False
            self._serial.rts = False
            self._serial.open()
            self.on_line(f"[baglandi] {self.port} @ {self.baud_rate}")
            try:
                self._serial.write(b"\r\n?\r\n")
            except Exception:
                pass
            while not self._stop.is_set():
                self._flush_writes()
                raw = self._serial.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").rstrip()
                if line:
                    self.on_line(line)
        except Exception as exc:
            self.on_error(str(exc))
        finally:
            try:
                if self._serial is not None:
                    self._serial.close()
            except Exception:
                pass

    def _flush_writes(self) -> None:
        if self._serial is None:
            return
        while not self._write_queue.empty():
            text = self._write_queue.get_nowait()
            self._serial.write(text.encode("utf-8"))
            self._serial.flush()


def ensure_logo() -> Path:
    if LOGO_PATH.exists():
        return LOGO_PATH
    raise FileNotFoundError(f"Logo bulunamadi: {LOGO_PATH}")


def sanitize_filename(text: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]", "_", text.strip())
    return value[:80] or "device"


def mac_to_firmware_uid(mac: str) -> str:
    parts = [part.strip().upper() for part in mac.split(":")]
    if len(parts) != 6 or any(not re.fullmatch(r"[0-9A-F]{2}", part) for part in parts):
        return mac.strip().upper()
    return "".join(reversed(parts))


def trim_image(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    bbox = rgba.getbbox()
    return rgba if bbox is None else rgba.crop(bbox)


def load_label_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/arialbd.ttf"),
        Path("C:/Windows/Fonts/arial.ttf"),
        Path("C:/Windows/Fonts/segoeuib.ttf"),
        Path("C:/Windows/Fonts/segoeui.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def generate_qr(unique_id: str, logo_path: Path) -> Image.Image:
    normalized_uid = unique_id.strip().upper()
    qr = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECT_H,
        box_size=20,
        border=2,
    )
    qr.add_data(normalized_uid)
    qr.make(fit=True)
    pil_raw = cast(Image.Image, qr.make_image(fill_color="black", back_color="white"))
    qr_img = pil_raw.convert("RGBA").resize((QR_SIZE, QR_SIZE), Image.Resampling.LANCZOS)

    logo = trim_image(Image.open(logo_path))
    logo = ImageOps.contain(logo, (264, 264), Image.Resampling.LANCZOS)

    badge = Image.new("RGBA", (322, 322), (255, 255, 255, 0))
    draw = ImageDraw.Draw(badge)
    draw.ellipse((0, 0, 321, 321), fill=(255, 255, 255, 245))
    badge.alpha_composite(logo, ((322 - logo.width) // 2, (322 - logo.height) // 2))
    qr_img.alpha_composite(badge, ((QR_SIZE - 322) // 2, (QR_SIZE - 322) // 2))

    output = Image.new("RGBA", (QR_SIZE, QR_SIZE + QR_LABEL_HEIGHT), "white")
    output.alpha_composite(qr_img, (0, 0))
    draw = ImageDraw.Draw(output)
    font = load_label_font(48)
    label = f"Unique ID: {normalized_uid}"
    bbox = draw.textbbox((0, 0), label, font=font)
    x = (QR_SIZE - (bbox[2] - bbox[0])) // 2
    y = QR_SIZE + (QR_LABEL_HEIGHT - (bbox[3] - bbox[1])) // 2 - 6
    draw.text((x, y), label, fill=(19, 40, 29, 255), font=font)
    return output


def load_regular_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arial.ttf"),
        Path("C:/Windows/Fonts/calibri.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def load_local_labeled_devices() -> list[dict]:
    if not LABELED_DEVICES_FILE.exists():
        return []
    try:
        raw = json.loads(LABELED_DEVICES_FILE.read_text(encoding="utf-8"))
        if isinstance(raw, list):
            return raw
    except Exception:
        pass
    return []


def save_local_labeled_device(device_info: dict, qr_image: Image.Image | None = None) -> list[dict]:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    QRCODES_DIR.mkdir(parents=True, exist_ok=True)

    uid = str(device_info.get("device_uid", "")).strip().upper()
    if not uid:
        return load_local_labeled_devices()

    qr_path = QRCODES_DIR / f"{uid}.png"
    if qr_image is not None:
        qr_image.save(qr_path, format="PNG")

    devices = load_local_labeled_devices()
    existing_idx = next((i for i, d in enumerate(devices) if str(d.get("device_uid", "")).upper() == uid), -1)

    entry = {
        "device_uid": uid,
        "chip": device_info.get("chip", "ESP32"),
        "port": device_info.get("port", ""),
        "description": device_info.get("description", ""),
        "created_at": device_info.get("created_at") or (devices[existing_idx].get("created_at") if existing_idx >= 0 else datetime.now().isoformat()),
        "updated_at": datetime.now().isoformat(),
        "qr_path": str(qr_path),
    }

    if existing_idx >= 0:
        devices[existing_idx] = entry
    else:
        devices.insert(0, entry)

    LABELED_DEVICES_FILE.write_text(json.dumps(devices, ensure_ascii=False, indent=2), encoding="utf-8")
    return devices


def fetch_server_labeled_devices_with_status() -> tuple[list[dict], str]:
    """(cihaz listesi, hata metni). Basariliysa hata metni bos doner."""
    if not get_company_api_key():
        return [], f"{COMPANY_KEY_ENV} tanimli degil: sunucu listesi alinamadi, yalnizca yerel kayitlar kullaniliyor."
    url = f"{PUBLIC_API_URL}/api/company/labeled-devices"
    req = urllib.request.Request(url, headers=company_request_headers(url))
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            if response.status == 200:
                data = json.loads(response.read().decode("utf-8"))
                if isinstance(data, dict) and isinstance(data.get("devices"), list):
                    return data["devices"], ""
                return [], "Sunucu beklenmeyen bir yanit dondurdu."
            return [], f"Sunucu yaniti: HTTP {response.status}"
    except urllib.error.HTTPError as he:
        return [], _company_http_error_text(he.code, _http_error_body(he))
    except Exception as exc:
        return [], f"Sunucuya ulasilamadi: {exc}"


def fetch_server_labeled_devices() -> list[dict]:
    devices, _error = fetch_server_labeled_devices_with_status()
    return devices


def delete_local_labeled_device(device_uid: str) -> list[dict]:
    uid = str(device_uid).strip().upper()
    if not uid:
        return load_local_labeled_devices()

    qr_path = QRCODES_DIR / f"{uid}.png"
    if qr_path.exists():
        try:
            qr_path.unlink()
        except Exception:
            pass

    devices = load_local_labeled_devices()
    devices = [d for d in devices if str(d.get("device_uid", "")).strip().upper() != uid]
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    LABELED_DEVICES_FILE.write_text(json.dumps(devices, ensure_ascii=False, indent=2), encoding="utf-8")
    return devices


def delete_server_labeled_device(device_uid: str) -> tuple[bool, str]:
    uid = str(device_uid).strip().upper()
    if not uid:
        return False, "Gecersiz cihaz UID."
    if not get_company_api_key():
        return False, f"{COMPANY_KEY_ENV} tanimli degil; sunucudan silinemedi (yalnizca yerel kayit silindi)."
    url = f"{PUBLIC_API_URL}/api/company/labeled-devices/{urllib.parse.quote(uid)}"
    req = urllib.request.Request(url, method="DELETE", headers=company_request_headers(url))
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode("utf-8"))
                return True, data.get("message", f"{uid} basariyla silindi.")
            return False, f"Sunucu yaniti: HTTP {response.status}"
    except urllib.error.HTTPError as he:
        if he.code in (401, 403):
            return False, _company_http_error_text(he.code, _http_error_body(he))
        try:
            err_body = json.loads(he.read().decode("utf-8"))
            return False, err_body.get("error", f"Sunucu hatasi: HTTP {he.code}")
        except Exception:
            return False, f"Sunucu hatasi: HTTP {he.code}"
    except Exception as exc:
        return False, f"Baglanti hatasi: {exc}"


# F20: "Cihaz testi" sayfasindaki "Genel IP (WAN)" alani. Sunucu kartin genel IP'sini, kartin OTA manifest isteginin
# kaynak adresinden kaydeder; arac yalniz BAGLI kartin kaydini sirket anahtariyla okur (salt okunur uc).
DEVICE_RUNTIME_TIMEOUT_S = 4
_DEVICE_UID_RE = re.compile(r"[0-9A-F]{12}")


def fetch_device_public_ip(device_uid: str) -> str:
    """Kartin sunucudaki genel IP'sini dondurur; yoksa / anahtar yoksa / sunucuya ulasilamazsa bos metin.

    Arka plan is parcaciginda cagrilir (arayuz donmasin). Hicbir zaman istisna firlatmaz ve hata penceresi acmaz.
    """
    uid = str(device_uid or "").strip().upper().replace(":", "").replace("-", "")
    if not _DEVICE_UID_RE.fullmatch(uid) or not get_company_api_key():
        return ""
    url = f"{PUBLIC_API_URL}/api/company/devices/{urllib.parse.quote(uid)}/runtime"
    if not _is_key_safe_url(url):
        # Anahtar duz HTTP ile gonderilmez; anahtarsiz istek zaten 401 alir.
        return ""
    req = urllib.request.Request(url, headers=company_request_headers(url, {"Accept": "application/json"}))
    try:
        with urllib.request.urlopen(req, timeout=DEVICE_RUNTIME_TIMEOUT_S) as response:
            if response.status != 200:
                return ""
            data = json.loads(response.read(4096).decode("utf-8"))
    except Exception:
        return ""
    if not isinstance(data, dict) or str(data.get("device_uid", "")).strip().upper() != uid:
        return ""
    raw_ip = data.get("public_ip")
    if not isinstance(raw_ip, str):
        return ""
    try:
        return str(ipaddress.ip_address(raw_ip.strip()))
    except ValueError:
        return ""


def generate_devices_catalog_pdf(
    devices: list[dict],
    output_pdf_path: Path,
    logo_path: Path,
    report_title: str = "SmartKeyPass CİHAZ VE KAREKOD ENVANTER RAPORU",
) -> Path:
    PAGE_WIDTH = 2480
    PAGE_HEIGHT = 3508
    MARGIN_X = 100
    MARGIN_TOP = 80
    MARGIN_BOTTOM = 80

    font_title = load_label_font(42)
    font_subtitle = load_regular_font(28)
    font_meta = load_regular_font(26)
    font_card_title = load_label_font(32)
    font_card_label = load_regular_font(24)
    font_card_val = load_label_font(24)
    font_footer = load_regular_font(22)

    CARDS_PER_PAGE = 6
    COLS = 2
    ROWS = 3

    CARD_W = 1080
    CARD_H = 920
    CARD_GAP_X = 120
    CARD_GAP_Y = 60

    pages: list[Image.Image] = []
    total_devices = len(devices)
    total_pages = max(1, (total_devices + CARDS_PER_PAGE - 1) // CARDS_PER_PAGE)
    current_time_str = datetime.now().strftime("%d.%m.%Y %H:%M")

    for page_idx in range(total_pages):
        page_img = Image.new("RGB", (PAGE_WIDTH, PAGE_HEIGHT), "#F8FAFC")
        draw = ImageDraw.Draw(page_img)

        # 1. Header Banner
        header_top = MARGIN_TOP
        header_h = 240
        draw.rounded_rectangle(
            [MARGIN_X, header_top, PAGE_WIDTH - MARGIN_X, header_top + header_h],
            radius=24,
            fill="#0F3A29",
        )

        # Header Logo
        logo_x = MARGIN_X + 30
        logo_y = header_top + 30
        if logo_path.exists():
            try:
                logo_im = trim_image(Image.open(logo_path))
                logo_im = ImageOps.contain(logo_im, (180, 180), Image.Resampling.LANCZOS)
                badge = Image.new("RGBA", (180, 180), (255, 255, 255, 0))
                d_badge = ImageDraw.Draw(badge)
                d_badge.ellipse((0, 0, 179, 179), fill=(255, 255, 255, 250))
                badge.alpha_composite(logo_im, ((180 - logo_im.width) // 2, (180 - logo_im.height) // 2))
                page_img.paste(badge, (logo_x, logo_y), badge)
            except Exception:
                pass

        # Header Texts
        text_x = logo_x + 210
        draw.text((text_x, header_top + 45), report_title, fill="#FFFFFF", font=font_title)
        draw.text((text_x, header_top + 105), "SmartKeyPass Akıllı Geçiş ve Kapı Kontrol Sistemleri", fill="#DDF3E5", font=font_subtitle)
        draw.text((text_x, header_top + 155), f"Rapor Tarihi: {current_time_str}   |   Toplam Kayıtlı Cihaz: {total_devices}", fill="#93C5FD", font=font_meta)

        # 2. Devices Grid
        start_device_idx = page_idx * CARDS_PER_PAGE
        page_devices = devices[start_device_idx : start_device_idx + CARDS_PER_PAGE]

        grid_top = header_top + header_h + 50

        for idx_in_page, dev in enumerate(page_devices):
            row_idx = idx_in_page // COLS
            col_idx = idx_in_page % COLS

            cx = MARGIN_X + col_idx * (CARD_W + CARD_GAP_X)
            cy = grid_top + row_idx * (CARD_H + CARD_GAP_Y)

            # Card Container
            draw.rounded_rectangle(
                [cx, cy, cx + CARD_W, cy + CARD_H],
                radius=20,
                fill="#FFFFFF",
                outline="#CBD5E1",
                width=3,
            )

            # Card Top Header (Green Pill)
            draw.rounded_rectangle(
                [cx + 3, cy + 3, cx + CARD_W - 3, cy + 85],
                radius=18,
                fill="#16A34A",
            )
            uid_str = str(dev.get("device_uid", "")).strip().upper()
            draw.text((cx + 30, cy + 22), f"CİHAZ UID: {uid_str}", fill="#FFFFFF", font=font_card_title)

            # QR Code Generation / Render
            qr_img = generate_qr(uid_str, logo_path)
            qr_display_size = 540
            qr_thumb = qr_img.resize((qr_display_size, int(qr_display_size * (QR_SIZE + QR_LABEL_HEIGHT) / QR_SIZE)), Image.Resampling.LANCZOS)

            # Paste QR Code on left
            qr_x = cx + 30
            qr_y = cy + 115
            page_img.paste(qr_thumb, (qr_x, qr_y))

            # Details on right side of card
            details_x = qr_x + qr_display_size + 40
            details_y = cy + 130
            line_spacing = 58

            chip_val = str(dev.get("chip", "ESP32-C3")).strip()
            date_val = str(dev.get("created_at", dev.get("labeled_at", "-"))).strip()
            if "T" in date_val:
                try:
                    dt = datetime.fromisoformat(date_val.replace("Z", "+00:00"))
                    date_val = dt.strftime("%d.%m.%Y %H:%M")
                except Exception:
                    pass
            port_val = str(dev.get("port", "-")).strip()
            desc_val = str(dev.get("description", "SmartKeyPass Geçiş Kontrol")).strip()
            if len(desc_val) > 28:
                desc_val = desc_val[:26] + "..."

            meta_items = [
                ("Çip Modeli:", chip_val),
                ("Kayıt Tarihi:", date_val),
                ("Seri Port:", port_val or "USB"),
                ("Durum:", "Etiketlendi (Hazır)"),
                ("Açıklama:", desc_val),
            ]

            for l_idx, (lbl, val) in enumerate(meta_items):
                curr_y = details_y + l_idx * line_spacing
                draw.text((details_x, curr_y), lbl, fill="#64748B", font=font_card_label)
                draw.text((details_x, curr_y + 26), val, fill="#0F172A", font=font_card_val)

        # 3. Footer
        footer_y = PAGE_HEIGHT - MARGIN_BOTTOM - 40
        draw.line([MARGIN_X, footer_y, PAGE_WIDTH - MARGIN_X, footer_y], fill="#CBD5E1", width=2)
        draw.text((MARGIN_X, footer_y + 15), "SmartKeyPass Akıllı Geçiş Sistemleri • Güde Teknoloji • www.gudeteknoloji.com.tr", fill="#64748B", font=font_footer)
        page_str = f"Sayfa {page_idx + 1} / {total_pages}"
        bbox = draw.textbbox((0, 0), page_str, font=font_footer)
        draw.text((PAGE_WIDTH - MARGIN_X - (bbox[2] - bbox[0]), footer_y + 15), page_str, fill="#0F3A29", font=font_footer)

        pages.append(page_img)

    output_pdf_path.parent.mkdir(parents=True, exist_ok=True)
    if pages:
        pages[0].save(
            output_pdf_path,
            "PDF",
            resolution=300.0,
            save_all=True,
            append_images=pages[1:],
        )
    return output_pdf_path


def find_platformio() -> str:
    exe = shutil.which("platformio")
    if exe:
        return exe
    candidate = Path.home() / ".platformio" / "penv" / "Scripts" / "platformio.exe"
    if candidate.exists():
        return str(candidate)
    raise FileNotFoundError("PlatformIO bulunamadi.")


def find_esptool_python() -> str:
    try:
        res = subprocess.run([sys.executable, "-m", "esptool", "version"], capture_output=True, timeout=3, check=False)
        if res.returncode == 0:
            return sys.executable
    except Exception:
        pass
    pio_py = Path.home() / ".platformio" / "penv" / "Scripts" / "python.exe"
    if pio_py.exists():
        return str(pio_py)
    return sys.executable


def read_mac(port: str) -> tuple[str, str]:
    # 1. Once calisan firmware'den seri port uzerinden dogrudan Unique ID oku (0.3 sn - reset/bootloader gerekmez)
    try:
        with serial.Serial(
            port,
            115200,
            timeout=0.3,
            write_timeout=0.5,
            rtscts=False,
            dsrdtr=False,
        ) as s:
            s.dtr = False
            s.rts = False
            time.sleep(0.05)
            s.reset_input_buffer()
            try:
                s.write(b"\r\n?\r\n")
            except Exception:
                pass
            time.sleep(0.1)
            buf = ""
            uid_found = ""
            start = time.time()
            while time.time() - start < 2.0:
                waiting = s.in_waiting
                chunk = s.read(waiting if waiting > 0 else 1)
                if chunk:
                    buf += chunk.decode("utf-8", errors="ignore")
                    m_uid = re.search(r"Cihaz Unique ID:\s*([0-9A-Fa-f]{6,20})", buf)
                    m_hw = re.search(r"Hardware Target:\s*([^\r\n]+)", buf)
                    if m_uid:
                        uid_found = m_uid.group(1).strip().upper()
                        # UID satiri donanim hedefinden ONCE gelir: hedef satirini da bekle ki cip adi dogru olsun
                        # (sunucu belirsiz "ESP32" cipinden donanim turu TAHMIN ETMEZ).
                        if m_hw:
                            target_str = m_hw.group(1).lower()
                            chip = "ESP32-WROOM" if "wroom" in target_str else ("ESP32-C3" if "c3" in target_str else "ESP32")
                            return chip, uid_found
                else:
                    time.sleep(0.05)
            if uid_found:
                # Eski firmware: Hardware Target satiri gelmedi; UID ile don (cip belirsiz kalir).
                return "ESP32", uid_found
    except Exception:
        pass

    # 2. Eger calisan firmware yanit vermediyse (bos flash veya ROM bootloader modunda):
    # esptool ile MAC oku (115200 baud ile kilitlenmeyi onle)
    py_exe = find_esptool_python()
    for cmd_try in [
        [py_exe, "-m", "esptool", "--port", port, "--baud", "115200", "--connect-attempts", "4", "read-mac"],
        [py_exe, "-m", "esptool", "--port", port, "--baud", "115200", "--connect-attempts", "4", "read_mac"],
        [py_exe, "-m", "esptool", "--port", port, "read-mac"],
        [py_exe, "-m", "esptool", "--port", port, "read_mac"],
    ]:
        try:
            out = subprocess.run(cmd_try, capture_output=True, text=True, timeout=8, check=False)
            text = f"{out.stdout}\n{out.stderr}"
            mm = MAC_RE.search(text)
            cm = CHIP_RE.search(text)
            if mm:
                chip = cm.group(1).strip() if cm else "ESP32"
                return chip, mac_to_firmware_uid(mm.group(1))
        except Exception:
            continue

    raise RuntimeError(
        "Cihaz Unique ID okunamadi!\n\n"
        "Olası Nedenler ve Çözümler:\n"
        "1. Port meşgul olabilir: 'Cihaz Dene' veya başka bir seri monitör açıksa kapatın.\n"
        "2. Harici CH340 / USB-TTL dönüştürücü kullanıyorsanız:\n"
        "   - ESP32 kartındaki BOOT (IO0) butonuna BASILI TUTUN.\n"
        "   - EN (RST) butonuna bir kez basıp bırakın.\n"
        "   - Ardından BOOT butonunu bırakın.\n"
        "   - Şimdi 'Seçili cihaz UID oku' butonuna tekrar basın.\n"
        "3. USB kablosunu çıkarıp tekrar takmayı deneyin."
    )


def parse_envs(path: Path) -> tuple[list[str], dict[str, int]]:
    if not path.exists():
        return [], {}
    envs: list[str] = []
    speeds: dict[str, int] = {}
    current: str | None = None
    default_speed = 460800
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        trimmed = line.strip()
        if trimmed == "[env]":
            current = "__base__"
            continue
        em = ENV_RE.match(line)
        if em:
            current = em.group(1).strip()
            envs.append(current)
            speeds[current] = default_speed
            continue
        if current is None:
            continue
        um = UPL_RE.match(line)
        if um:
            val = int(um.group(1))
            if current == "__base__":
                default_speed = val
                for k in envs:
                    speeds[k] = val
            else:
                speeds[current] = val
    return envs, speeds


def load_releases() -> list[dict]:
    if not RELEASE_INDEX.exists():
        return []
    try:
        raw = json.loads(RELEASE_INDEX.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and isinstance(raw.get("releases"), list):
            return list(raw["releases"])
    except Exception:
        pass
    return []


def save_releases(releases: list[dict]) -> None:
    RELEASES_DIR.mkdir(parents=True, exist_ok=True)
    RELEASE_INDEX.write_text(json.dumps({"releases": releases}, ensure_ascii=False, indent=2), encoding="utf-8")


def read_firmware_source_version(env: str | None = None) -> str | None:
    header = DEVICE_PROJECT_DIR / "include" / "ota_guncelleme.h"
    try:
        text = header.read_text(encoding="utf-8")
    except Exception:
        return None
    target = target_for_env(env) if env else None
    if target == "esp32-wroom":
        match = OTA_VERSION_WROOM_RE.search(text)
        if match:
            return match.group(1)
    elif target == "esp32-c3":
        match = OTA_VERSION_C3_RE.search(text)
        if match:
            return match.group(1)
    for rgx in (OTA_VERSION_C3_RE, OTA_VERSION_WROOM_RE, OTA_VERSION_RE):
        match = rgx.search(text)
        if match:
            return match.group(1)
    return None


def write_firmware_source_version(version: str, env: str | None = None) -> bool:
    header = DEVICE_PROJECT_DIR / "include" / "ota_guncelleme.h"
    try:
        text = header.read_text(encoding="utf-8")
        target = target_for_env(env) if env else None
        if target == "esp32-wroom":
            if OTA_VERSION_WROOM_RE.search(text):
                updated = OTA_VERSION_WROOM_RE.sub(f'OTA_VERSION_WROOM[] = "{version}"', text)
                header.write_text(updated, encoding="utf-8")
                return True
        else:
            if OTA_VERSION_C3_RE.search(text):
                updated = OTA_VERSION_C3_RE.sub(f'OTA_VERSION_C3[] = "{version}"', text)
                header.write_text(updated, encoding="utf-8")
                return True
        if OTA_VERSION_RE.search(text):
            updated = OTA_VERSION_RE.sub(f'OTA_CURRENT_VERSION[] = "{version}"', text)
            header.write_text(updated, encoding="utf-8")
            return True
    except Exception:
        pass
    return False


def load_display_releases() -> list[dict]:
    if not DISPLAY_RELEASE_INDEX.exists():
        return []
    try:
        raw = json.loads(DISPLAY_RELEASE_INDEX.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and isinstance(raw.get("releases"), list):
            return list(raw["releases"])
        if isinstance(raw, list):
            return list(raw)
    except Exception:
        pass
    return []


def save_display_releases(releases: list[dict]) -> None:
    DISPLAY_RELEASES_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"releases": releases}
    DISPLAY_RELEASE_INDEX.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def read_display_source_version() -> str:
    if not DISPLAY_CONFIG_H_PATH.exists():
        return "1.0.0"
    try:
        content = DISPLAY_CONFIG_H_PATH.read_text(encoding="utf-8")
        m = re.search(r'#define\s+DISPLAY_FIRMWARE_VERSION\s+"(\d+\.\d+\.\d+)"', content)
        return m.group(1) if m else "1.0.0"
    except Exception:
        return "1.0.0"


def write_display_source_version(new_version: str) -> bool:
    if not DISPLAY_CONFIG_H_PATH.exists():
        return False
    try:
        content = DISPLAY_CONFIG_H_PATH.read_text(encoding="utf-8")
        pat = re.compile(r'(#define\s+DISPLAY_FIRMWARE_VERSION\s+)"[^"]+"')
        if pat.search(content):
            updated = pat.sub(rf'\1"{new_version}"', content)
        else:
            updated = f'#define DISPLAY_FIRMWARE_VERSION "{new_version}"\n' + content
        DISPLAY_CONFIG_H_PATH.write_text(updated, encoding="utf-8")
        return True
    except Exception:
        return False


def file_hash(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def zip_directory(zf: zipfile.ZipFile, source: Path, arc_root: str) -> None:
    ignored_dirs = {".git", "__pycache__", ".pytest_cache"}
    ignored_suffixes = {".pyc", ".pyo"}
    for item in source.rglob("*"):
        if any(part in ignored_dirs for part in item.parts):
            continue
        if item.is_dir():
            continue
        if item.suffix.lower() in ignored_suffixes:
            continue
        arc_name = Path(arc_root) / item.relative_to(source)
        zf.write(item, arc_name.as_posix())


def suggest_version(releases: list[dict], env: str | None = None) -> str:
    target = target_for_env(env) if env else None
    versions: list[tuple[int, int, int]] = []
    for r in releases:
        if target:
            r_env = str(r.get("env", ""))
            if target_for_env(r_env) != target:
                continue
        v = str(r.get("version", "")).strip()
        if SEMVER_RE.match(v):
            a, b, c = v.split(".")
            versions.append((int(a), int(b), int(c)))
    if not versions:
        return "1.0.0"
    a, b, c = sorted(versions)[-1]
    return f"{a}.{b}.{c + 1}"



def suggest_env_for_chip(chip: str, envs: list[str]) -> str | None:
    chip_lower = (chip or "").lower()
    if "c3" in chip_lower:
        for e in envs:
            if "c3" in e.lower():
                return e
        return "lolin_c3_mini" if "lolin_c3_mini" in envs else (envs[0] if envs else None)
    elif "esp32" in chip_lower or "wroom" in chip_lower or "d0wd" in chip_lower:
        for e in envs:
            if "wroom" in e.lower() or "esp32dev" in e.lower():
                return e
        return "esp32_relay_wroom" if "esp32_relay_wroom" in envs else (envs[0] if envs else None)
    if "lolin_c3_mini" in envs:
        return "lolin_c3_mini"
    return envs[0] if envs else None


class App:
    def __init__(self) -> None:
        enable_dpi_awareness()
        self.root = tk.Tk()
        self.root.title("SmartKeyPass Cihaz Etiketleyici")
        self.kit = Kit(self.root)
        px = self.kit.px
        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        self.root.minsize(min(px(1120), sw - 40), min(px(700), sh - 80))
        try:
            self.root.state("zoomed")
        except tk.TclError:
            try:
                self.root.attributes("-zoomed", True)
            except tk.TclError:
                self.root.geometry(f"{sw}x{sh}+0+0")

        self.logo_path = ensure_logo()
        self.devices: list[EspDevice] = []
        self.releases = load_releases()
        self.envs, self.upload_speeds = parse_envs(PLATFORMIO_INI_PATH)

        self.latest_qr: Image.Image | None = None
        self.latest_uid: str | None = None
        self._preview_uid: str | None = None
        self.brand_photo: ImageTk.PhotoImage | None = None
        self.icon_photo: ImageTk.PhotoImage | None = None

        self.status_var = tk.StringVar(value="Hazır.")
        self.uid_var = tk.StringVar(value="—")
        self.qr_meta_var = tk.StringVar(value="Listeden bir cihaz seçin.")
        self.env_var = tk.StringVar(value=self.envs[0] if self.envs else "lolin_c3_mini")
        self.version_var = tk.StringVar(
            value=read_firmware_source_version(self.env_var.get())
            or suggest_version(self.releases, self.env_var.get())
        )
        self.latest_release_var = tk.StringVar(value="Son sürüm: -")
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_text_var = tk.StringVar(value="%0")
        self.fw_device_var = tk.StringVar(value="")

        self.scanning = False
        self.uid_reading = False
        self.saving_device = False
        self.fw_busy = False
        self.fw_build_ready = False
        self.fw_release_ready = False
        self.fw_build_key: tuple[str, str] | None = None
        self.fw_release_key: tuple[str, str] | None = None
        self.fw_op = ""
        self.fw_result: tuple[bool, str] | None = None
        self.fw_dispatched_key: tuple[str, str] | None = None
        self.saved_uids: set[str] = set()
        self._jobs = 0
        self._was_busy = False
        self._was_hw_busy = False
        self._port_hwids: dict[str, str] = {}
        self._port_poll_running = False
        self._port_cooldown_until = 0.0
        self.screen_window: ScreenFirmwarePage | None = None
        self.device_tester: DeviceTesterPage | None = None
        self.labeled_page: LabeledDevicesPage | None = None
        self.pages: dict[str, ttk.Frame] = {}
        self.current_page: ttk.Frame | None = None
        self.current_key = ""

        self.brand_photo = self._load_brand(px(42))
        self.icon_photo = self._load_brand(32)
        if self.icon_photo is not None:
            self.root.iconphoto(True, self.icon_photo)

        self._ui()
        self.version_var.trace_add("write", lambda *_args: self._on_fw_input_changed())
        self.refresh_latest_release()
        self._apply_fw_button_state()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        # Port listesi karta dokunmaz (yalnizca isletim sisteminden okunur): acilista ve sonra duzenli yenilenir.
        self.root.after(120, lambda: self.scan_devices(manual=False))
        self.root.after(PORT_POLL_MS, self._poll_ports)
        self.root.after(200, self._tick_busy)

    def _load_brand(self, size: int) -> ImageTk.PhotoImage | None:
        try:
            logo = trim_image(Image.open(self.logo_path))
        except Exception:
            return None
        logo = ImageOps.contain(logo, (int(size * 0.72), int(size * 0.72)), Image.Resampling.LANCZOS)
        badge = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        d = ImageDraw.Draw(badge)
        d.ellipse((0, 0, size - 1, size - 1), fill=(255, 255, 255, 250), outline=(226, 232, 240, 255), width=2)
        badge.alpha_composite(logo, ((size - logo.width) // 2, (size - logo.height) // 2))
        return ImageTk.PhotoImage(badge)

    def _ui(self) -> None:
        kit = self.kit
        px = kit.px
        shell = ttk.Frame(self.root, style="page.TFrame")
        shell.pack(fill=tk.BOTH, expand=True)
        shell.columnconfigure(1, weight=1)
        shell.rowconfigure(0, weight=1)

        self.sidebar = Sidebar(shell, kit, self.brand_photo, "SmartKeyPass", "Cihaz Etiketleyici", self.show_page)
        self.sidebar.grid(row=0, column=0, sticky="nsw")
        self.sidebar.add_group("ÜRETİM")
        self.sidebar.add_item("label", "Etiketle", "qr", "Ctrl+1")
        self.sidebar.add_item("devices", "Kayıtlı cihazlar", "library", "Ctrl+2")
        self.sidebar.add_group("BAKIM")
        self.sidebar.add_item("tester", "Cihaz testi", "diag", "Ctrl+3")
        self.sidebar.add_item("firmware", "Cihaz yazılımı", "chip", "Ctrl+4")
        self.sidebar.add_item("screen", "Ekran yazılımı", "monitor", "Ctrl+5")
        key_ok = bool(get_company_api_key())
        key_label = kit.label(
            self.sidebar.footer,
            "Sunucu anahtarı hazır" if key_ok else "Sunucu anahtarı yok",
            "body",
            "nav",
            image=kit.dot("#4ADE80" if key_ok else "#FBBF24"),
            compound="left",
        )
        key_label.pack(anchor="w")
        if not key_ok:
            Tooltip(key_label, COMPANY_KEY_MISSING_MESSAGE, kit, side="right")
        host = urllib.parse.urlparse(PUBLIC_API_URL).netloc or PUBLIC_API_URL
        kit.label(self.sidebar.footer, host, "caption", "nav").pack(anchor="w", pady=(px(2), 0))

        main = ttk.Frame(shell, style="page.TFrame")
        main.grid(row=0, column=1, sticky="nsew")
        main.columnconfigure(0, weight=1)
        main.rowconfigure(0, weight=1)
        self.page_host = ttk.Frame(main, style="page.TFrame")
        self.page_host.grid(row=0, column=0, sticky="nsew")
        kit.separator(main).grid(row=1, column=0, sticky="ew")
        footer = ttk.Frame(main, style="page.TFrame", padding=(px(28), px(8)))
        footer.grid(row=2, column=0, sticky="ew")
        self.footer_spinner = Spinner(footer, kit, surface="page")
        self.footer_spinner.pack(side=tk.LEFT, padx=(0, px(8)))
        kit.label(footer, "Ctrl+1…5 sayfalar  ·  F5 yenile", "caption", "page").pack(side=tk.RIGHT, padx=(px(16), 0))
        kit.label(footer, textvariable=self.status_var, kind="body2", surface="page", anchor="w").pack(side=tk.LEFT, fill=tk.X, expand=True)

        self._page_builders: dict[str, Callable[[ttk.Frame], None]] = {
            "label": self._build_label_page,
            "devices": self._build_devices_page,
            "tester": self._build_tester_page,
            "firmware": self._build_firmware_page,
            "screen": self._build_screen_page,
        }
        for i, key in enumerate(("label", "devices", "tester", "firmware", "screen"), start=1):
            self.root.bind_all(f"<Control-Key-{i}>", lambda _e, k=key: self.show_page(k))
        self.root.bind_all("<F5>", self._on_refresh_key)
        # Yazilim sayfasinin dugmeleri baslangicta durum hesaplarinda kullanilir: hemen kur.
        self._ensure_page("firmware")
        self.show_page("label", animate=False)

    def _ensure_page(self, key: str) -> ttk.Frame:
        page = self.pages.get(key)
        if page is None:
            px = self.kit.px
            page = ttk.Frame(self.page_host, style="page.TFrame", padding=(px(28), px(22), px(28), px(14)))
            self.pages[key] = page
            self._page_builders[key](page)
        return page

    def show_page(self, key: str, animate: bool = True) -> None:
        first = key not in self.pages
        page = self._ensure_page(key)
        if page is self.current_page:
            return
        if self.current_page is not None:
            self.current_page.place_forget()
        self.current_page = page
        self.current_key = key
        self.sidebar.select(key, animate=animate)
        dx = self.kit.px(28) if animate and self.kit.motion else 0
        page.place(x=dx, y=0, relwidth=1, relheight=1)
        if dx:
            self.kit.anim.run("page", 260, lambda t: page.place_configure(x=int(round(dx * (1 - t)))))
        if first:
            return
        if key == "devices" and self.labeled_page is not None:
            self.labeled_page.refresh_devices()
        elif key == "tester" and self.device_tester is not None:
            self.device_tester.refresh_ports()
        elif key == "firmware":
            self._sync_fw_device_choices()

    def _build_devices_page(self, page: ttk.Frame) -> None:
        self.labeled_page = LabeledDevicesPage(page, self.kit, self.logo_path, self.download_pdf_report)

    def _build_tester_page(self, page: ttk.Frame) -> None:
        self.device_tester = DeviceTesterPage(page, self.kit)

    def _build_screen_page(self, page: ttk.Frame) -> None:
        self.screen_window = ScreenFirmwarePage(page, self.kit, self.logo_path)

    def _build_label_page(self, page: ttk.Frame) -> None:
        kit = self.kit
        px = kit.px
        page.columnconfigure(0, weight=1)
        page.columnconfigure(1, weight=0, minsize=px(360))
        page.rowconfigure(1, weight=1)
        header, slot = kit.page_header(
            page,
            "Cihaz etiketle",
            "Kartı USB ile bağlayın ve kimliğini okuyun; karekod kendiliğinden hazırlanır. Sonra sunucuya kaydedip yazdırın.",
            icon="qr",
        )
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, px(18)))
        self.label_stepper = Stepper(slot, kit, ["Cihazı seç", "Kimliği oku", "Kaydet ve yazdır"])
        self.label_stepper.pack()

        left = kit.card(page)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, px(18)))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(2, weight=1)
        top = ttk.Frame(left, style="card.TFrame")
        top.grid(row=0, column=0, sticky="ew")
        top.columnconfigure(2, weight=1)
        kit.label(top, "Bağlı cihazlar", "title").grid(row=0, column=0, sticky="w")
        self.device_count_pill = Pill(top, kit, "Port yok", "neutral")
        self.device_count_pill.grid(row=0, column=1, sticky="w", padx=(px(10), 0))
        self.scan_btn = kit.button(top, "Yeniden tara", self.scan_devices, icon="refresh")
        self.scan_btn.grid(row=0, column=3, sticky="e")
        Tooltip(self.scan_btn, "Listeyi baştan oluşturur (F5). Kart takılıp çıkarıldığında liste zaten kendiliğinden yenilenir.", kit)
        kit.label(left, "Kart takılınca burada belirir. Satırı seçin; çift tıklamak kimliği okur.", "caption").grid(
            row=1, column=0, sticky="w", pady=(px(4), px(12))
        )
        box, self.tree = kit.tree(
            left,
            [
                ("port", "Port", 76, "w", False),
                ("state", "Durum", 126, "w", False),
                ("chip", "Çip", 104, "w", False),
                ("unique_id", "Kimlik (UID)", 140, "w", False),
                ("description", "Aygıt açıklaması", 170, "w", True),
            ],
            height=10,
        )
        box.grid(row=2, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self.on_select, add="+")
        self.tree.bind(
            "<Double-1>",
            lambda e: self.read_selected_uid() if self.tree.identify_region(e.x, e.y) == "cell" else None,
        )
        self.tree.bind("<Return>", lambda _e: self.read_selected_uid())
        self.devices_empty = kit.empty_state(box, "usb", "Bağlı kart yok", "Kartı USB kablosuyla bağlayın; liste kendiliğinden yenilenir.")
        actions = ttk.Frame(left, style="card.TFrame")
        actions.grid(row=3, column=0, sticky="ew", pady=(px(16), 0))
        actions.columnconfigure(1, weight=1)
        self.read_uid_btn = kit.button(actions, "Kimliği oku", self.read_selected_uid, "primary", icon="scan")
        self.read_uid_btn.grid(row=0, column=0, sticky="w")
        kit.label(actions, "Okuma sırasında kart yeniden başlayabilir.", "caption").grid(row=0, column=1, sticky="w", padx=(px(12), 0))

        right = kit.card(page)
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        head = ttk.Frame(right, style="card.TFrame")
        head.grid(row=0, column=0, sticky="ew")
        head.columnconfigure(0, weight=1)
        kit.label(head, "Karekod", "title").grid(row=0, column=0, sticky="w")
        self.qr_state_pill = Pill(head, kit, "Bekliyor", "neutral")
        self.qr_state_pill.grid(row=0, column=1, sticky="e")
        self.preview = ttk.Label(right, style=kit.label_style("body"), anchor="center")
        self.preview.grid(row=1, column=0, pady=(px(16), px(12)))
        uid_row = ttk.Frame(right, style="card.TFrame")
        uid_row.grid(row=2, column=0)
        kit.label(uid_row, textvariable=self.uid_var, kind="uid").pack(side=tk.LEFT)
        self.copy_uid_btn = kit.icon_button(uid_row, "copy", self.copy_uid, "Kimliği panoya kopyala")
        self.copy_uid_btn.pack(side=tk.LEFT, padx=(px(6), 0))
        kit.label(right, textvariable=self.qr_meta_var, kind="caption", justify="center", wraplength=px(300)).grid(
            row=3, column=0, pady=(px(2), 0)
        )
        kit.separator(right).grid(row=4, column=0, sticky="ew", pady=px(16))
        self.server_save_device_btn = kit.button(right, "Sunucuya kaydet", self.save_device_to_server, "primary", icon="cloud")
        self.server_save_device_btn.grid(row=5, column=0, sticky="ew")
        row2 = ttk.Frame(right, style="card.TFrame")
        row2.grid(row=6, column=0, sticky="ew", pady=(px(8), 0))
        row2.columnconfigure(0, weight=1, uniform="qa")
        row2.columnconfigure(1, weight=1, uniform="qa")
        self.print_btn = kit.button(row2, "Yazdır", self.print_qr, icon="print")
        self.print_btn.grid(row=0, column=0, sticky="ew", padx=(0, px(4)))
        self.save_btn = kit.button(row2, "PNG kaydet", self.save_qr, icon="save")
        self.save_btn.grid(row=0, column=1, sticky="ew", padx=(px(4), 0))
        kit.label(right, "Kaydet: cihaz ve karekodu bu bilgisayara ve sunucuya yazılır.", "caption", wraplength=px(300), justify="left").grid(
            row=7, column=0, sticky="w", pady=(px(14), 0)
        )
        self._set_qr_preview(None)

    def _build_firmware_page(self, page: ttk.Frame) -> None:
        kit = self.kit
        px = kit.px
        page.columnconfigure(0, weight=1, uniform="fw")
        page.columnconfigure(1, weight=1, uniform="fw")
        page.rowconfigure(3, weight=1)
        header, slot = kit.page_header(
            page,
            "Cihaz yazılımı",
            "Kapı kartının yazılımını derleyin, sürüm paketi oluşturun ve dağıtın.",
            icon="chip",
        )
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, px(18)))
        self.fw_stepper = Stepper(slot, kit, ["Derle", "Sürüm oluştur", "Dağıt"])
        self.fw_stepper.pack()

        left = kit.card(page)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, px(18)))
        left.columnconfigure(0, weight=1)
        kit.label(left, "Sürüm hazırla", "title").grid(row=0, column=0, sticky="w")
        kit.label(
            left,
            "Kart türünü ve sürüm numarasını seçin, derleyin, ardından sürüm paketini oluşturun.",
            "caption",
            wraplength=px(420),
            justify="left",
        ).grid(row=1, column=0, sticky="w", pady=(px(4), px(14)))
        kit.label(left, "Kart türü (PlatformIO ortamı)", "value").grid(row=2, column=0, sticky="w")
        self.env_combo = kit.combobox(left, self.env_var, self.envs)
        self.env_combo.grid(row=3, column=0, sticky="ew", pady=(px(6), px(12)))
        self.env_combo.bind("<<ComboboxSelected>>", lambda _e: self._on_env_changed())
        kit.label(left, "Sürüm numarası", "value").grid(row=4, column=0, sticky="w")
        self.version_entry = kit.entry(left, self.version_var)
        self.version_entry.grid(row=5, column=0, sticky="ew", pady=(px(6), px(4)))
        kit.label(left, "Biçim 1.2.3. Derleme, sürüm numarasını kaynak koda da yazar.", "caption").grid(row=6, column=0, sticky="w")
        kit.label(
            left,
            textvariable=self.latest_release_var,
            kind="muted",
            image=kit.icon("history", px(16), C.TEXT_3, gap=px(6)),
            compound="left",
        ).grid(row=7, column=0, sticky="w", pady=(px(12), 0))
        btns = ttk.Frame(left, style="card.TFrame")
        btns.grid(row=8, column=0, sticky="ew", pady=(px(18), 0))
        btns.columnconfigure(0, weight=1, uniform="fwb")
        btns.columnconfigure(1, weight=1, uniform="fwb")
        self.build_btn = kit.button(btns, "Derle", self.start_build, "primary", icon="build")
        self.build_btn.grid(row=0, column=0, sticky="ew", padx=(0, px(5)))
        self.release_btn = kit.button(btns, "Sürüm oluştur", self.start_release, icon="package")
        self.release_btn.grid(row=0, column=1, sticky="ew", padx=(px(5), 0))

        right = kit.card(page)
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        kit.label(right, "Dağıt", "title").grid(row=0, column=0, sticky="w")
        kit.label(
            right,
            "Oluşturulan sürümü USB ile karta yükleyin, sunucuya gönderin ya da çalışma arkadaşınız için paket hazırlayın.",
            "caption",
            wraplength=px(420),
            justify="left",
        ).grid(row=1, column=0, sticky="w", pady=(px(4), px(14)))
        kit.label(right, "Hedef kart (USB)", "value").grid(row=2, column=0, sticky="w")
        devrow = ttk.Frame(right, style="card.TFrame")
        devrow.grid(row=3, column=0, sticky="ew", pady=(px(6), px(14)))
        devrow.columnconfigure(0, weight=1)
        self.fw_device_combo = kit.combobox(devrow, self.fw_device_var, [])
        self.fw_device_combo.grid(row=0, column=0, sticky="ew")
        self.fw_device_combo.bind("<<ComboboxSelected>>", self._on_fw_device_chosen)
        kit.icon_button(devrow, "refresh", self.scan_devices, "Portları yeniden tara").grid(row=0, column=1, padx=(px(6), 0))
        self.upload_btn = kit.button(right, "USB ile karta yükle", self.start_upload, icon="usb")
        self.upload_btn.grid(row=4, column=0, sticky="ew")
        self.server_upload_btn = kit.button(right, "Sunucuya gönder (OTA)", self.start_server_upload, icon="cloud")
        self.server_upload_btn.grid(row=5, column=0, sticky="ew", pady=(px(8), 0))
        self.coworker_zip_btn = kit.button(right, "Çalışma arkadaşı için ZIP", self.start_coworker_zip, icon="zip")
        self.coworker_zip_btn.grid(row=6, column=0, sticky="ew", pady=(px(8), 0))
        kit.label(
            right,
            "Sunucuya gönderilen sürümü sahadaki kartlar OTA ile kendiliğinden indirir.",
            "caption",
            wraplength=px(420),
            justify="left",
        ).grid(row=7, column=0, sticky="w", pady=(px(12), 0))

        prog = kit.card(page)
        prog.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(px(18), 0))
        prog.columnconfigure(0, weight=1)
        top = ttk.Frame(prog, style="card.TFrame")
        top.grid(row=0, column=0, sticky="ew")
        top.columnconfigure(2, weight=1)
        kit.label(top, "İlerleme", "title").grid(row=0, column=0, sticky="w")
        self.fw_pill = Pill(top, kit, "Hazır", "neutral")
        self.fw_pill.grid(row=0, column=1, sticky="w", padx=(px(10), 0))
        kit.label(top, textvariable=self.progress_text_var, kind="value").grid(row=0, column=3, sticky="e")
        self.pbar = SmoothProgress(prog, kit, self.progress_var)
        self.pbar.grid(row=1, column=0, sticky="ew", pady=(px(12), px(10)))
        kit.label(prog, textvariable=self.status_var, kind="mono").grid(row=2, column=0, sticky="w")
        kit.label(prog, "Yükleme sırasında yüzde görünür; bitince TMM bildirimi gelir.", "caption").grid(
            row=3, column=0, sticky="w", pady=(px(6), 0)
        )

    def _on_refresh_key(self, _event: object = None) -> None:
        if self.current_key in ("label", "firmware"):
            self.scan_devices()
        elif self.current_key == "devices" and self.labeled_page is not None:
            self.labeled_page.refresh_devices()
        elif self.current_key == "tester" and self.device_tester is not None:
            self.device_tester.refresh_ports()

    def _on_close(self) -> None:
        for page in (self.device_tester, self.screen_window):
            if page is not None:
                try:
                    page.shutdown()
                except Exception:
                    pass
        self.root.destroy()

    def toast(self, text: str, kind: str = "info", duration: int | None = None) -> None:
        self.kit.toast(text, kind, duration)

    def _tracked(self, fn: Callable, on_exit: Callable[[], None] | None = None) -> Callable:
        """Arka plan isini alt cubuktaki mesgul gostergesine bagla; bitince (hata olsa da) on_exit calisir."""
        self._jobs += 1

        def run(*args: object) -> None:
            try:
                fn(*args)
            finally:
                self.root.after(0, self._job_done)
                if on_exit is not None:
                    self.root.after(0, on_exit)

        return run

    def _job_done(self) -> None:
        self._jobs = max(0, self._jobs - 1)

    def _screen_busy(self) -> bool:
        s = self.screen_window
        return bool(s is not None and (s.fw_busy or s.scanning))

    def _tick_busy(self) -> None:
        busy = self.scanning or self.uid_reading or self.fw_busy or self._jobs > 0
        if busy != self._was_busy:
            self._was_busy = busy
            if busy:
                self.footer_spinner.start()
            else:
                self.footer_spinner.stop()
        hw_busy = busy or self._screen_busy()
        if self._was_hw_busy and not hw_busy:
            # Kart yeniden baslatildiysa USB yeniden listelenene kadar port izlemeyi beklet.
            self._port_cooldown_until = max(self._port_cooldown_until, time.monotonic() + 4.0)
        self._was_hw_busy = hw_busy
        self.root.after(200, self._tick_busy)

    def _poll_ports(self) -> None:
        try:
            idle = not (self.scanning or self.uid_reading or self.fw_busy or self._screen_busy())
            if idle and not self._port_poll_running and time.monotonic() >= self._port_cooldown_until:
                self._port_poll_running = True
                threading.Thread(target=self._poll_ports_worker, daemon=True).start()
        finally:
            self.root.after(PORT_POLL_MS, self._poll_ports)

    def _poll_ports_worker(self) -> None:
        try:
            ports: list[tuple[str, str, str]] | None = [
                (p.device, p.description or "", p.hwid or "") for p in list_ports.comports()
            ]
        except Exception:
            ports = None
        self.root.after(0, lambda: self._apply_port_poll(ports))

    def _apply_port_poll(self, ports: list[tuple[str, str, str]] | None) -> None:
        self._port_poll_running = False
        if ports is None or self.scanning or self.uid_reading or self.fw_busy or self._screen_busy():
            return
        old = {d.port: d for d in self.devices}
        seen = {port for port, _desc, _hwid in ports}
        removed = [p for p in old if p not in seen]
        added: list[str] = []
        new_devices: list[EspDevice] = []
        for port, desc, hwid in ports:
            prev = old.get(port)
            if prev is not None and self._port_hwids.get(port, hwid) == hwid:
                new_devices.append(prev)
            else:
                # Yeni ya da degismis donanim: onceki kimlik bilgisi TASINMAZ (yanlis etiket riski).
                new_devices.append(EspDevice(port=port, description=desc, chip="Okunmadi", unique_id=""))
                added.append(port)
        if not added and not removed:
            return
        self.devices = new_devices
        self._port_hwids = {port: hwid for port, _desc, hwid in ports}
        self._render_devices()
        if added:
            self.toast(f"Kart bağlandı: {', '.join(added)}", "info", 3000)
        if removed:
            self.toast(f"Kart çıkarıldı: {', '.join(removed)}", "info", 3000)
        self.set_status(f"{len(new_devices)} port bağlı." if new_devices else "Bağlı seri port yok.")

    def _device_row(self, d: EspDevice) -> tuple[str, str, str, str, str]:
        if d.unique_id:
            state = "✓ Kaydedildi" if d.unique_id in self.saved_uids else "Karekod hazır"
        else:
            state = "Kimlik okunmadı"
        chip = d.chip if d.chip and d.chip != "Okunmadi" else "—"
        return (d.port, state, chip, d.unique_id or "—", d.description)

    def _render_devices(self, keep_port: str | None = None) -> None:
        sel = self.tree.selection()
        port = keep_port if keep_port is not None else (sel[0] if sel else None)
        self.tree.delete(*self.tree.get_children())
        for d in self.devices:
            self.tree.insert("", tk.END, iid=d.port, values=self._device_row(d))
        if port and self.tree.exists(port):
            self.tree.selection_set(port)
            self.tree.see(port)
        elif len(self.devices) == 1:
            # Tek kart bagliysa onu kendiliginden sec (bir tik az).
            self.tree.selection_set(self.devices[0].port)
        self.kit.zebra(self.tree)
        if self.devices:
            self.devices_empty.place_forget()
        else:
            self.devices_empty.place(relx=0.5, rely=0.55, anchor="center")
        n = len(self.devices)
        self.device_count_pill.set(f"{n} port" if n else "Port yok", "info" if n else "neutral")
        self._sync_fw_device_choices()
        self.on_select()

    def _qr_meta(self, d: EspDevice) -> str:
        chip = d.chip if d.chip and d.chip != "Okunmadi" else "Çip bilinmiyor"
        return f"{chip}  ·  {d.port}"

    def _set_qr_preview(self, img: Image.Image | None, uid: str | None = None) -> None:
        if not hasattr(self, "preview"):
            return
        if img is not None and uid is not None and uid == self._preview_uid:
            return
        self._preview_uid = uid if img is not None else None
        size = self.kit.px(QR_PREVIEW_PX)
        if img is None:
            self.kit.anim.cancel("qr-preview")
            self.preview.configure(image=self.kit.placeholder_tile(size))
            return
        self.kit.pop_image(self.preview, self.kit.framed(img, size), "qr-preview")

    def _refresh_label_ui(self) -> None:
        if not hasattr(self, "read_uid_btn"):
            return
        d = self.selected_device()
        busy = self.scanning or self.uid_reading
        has_uid = bool(d is not None and d.unique_id)
        qr_ready = bool(d is not None and has_uid and self.latest_qr is not None and self.latest_uid == d.unique_id)
        saved = bool(d is not None and has_uid and d.unique_id in self.saved_uids)
        self.scan_btn.configure(state=tk.DISABLED if busy else tk.NORMAL)
        self.read_uid_btn.configure(state=tk.NORMAL if d is not None and not busy else tk.DISABLED)
        text = "Kimliği yeniden oku" if has_uid else "Kimliği oku"
        if self.read_uid_btn.cget("text") != text:
            self.kit.restyle(self.read_uid_btn, variant="secondary" if has_uid else "primary", text=text)
        self.server_save_device_btn.configure(state=tk.NORMAL if qr_ready and not busy and not self.saving_device else tk.DISABLED)
        for b in (self.print_btn, self.save_btn):
            b.configure(state=tk.NORMAL if qr_ready and not busy else tk.DISABLED)
        self.copy_uid_btn.configure(state=tk.NORMAL if has_uid else tk.DISABLED)
        if d is None:
            self.label_stepper.set(0, 0)
        elif not has_uid:
            self.label_stepper.set(1, 1)
        elif not saved:
            self.label_stepper.set(2, 2)
        else:
            self.label_stepper.set(3, None)
        if self.uid_reading:
            self.qr_state_pill.set("Kimlik okunuyor", "busy")
        elif self.saving_device:
            self.qr_state_pill.set("Kaydediliyor", "busy")
        elif saved:
            self.qr_state_pill.set("Kaydedildi", "ok")
        elif qr_ready:
            self.qr_state_pill.set("Hazır", "info")
        else:
            self.qr_state_pill.set("Bekliyor", "neutral")

    def copy_uid(self) -> None:
        d = self.selected_device()
        if d is None or not d.unique_id:
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(d.unique_id)
        self.toast(f"Kopyalandı: {d.unique_id}", "info", 2200)

    def _device_choice_label(self, d: EspDevice) -> str:
        chip = d.chip if d.chip and d.chip != "Okunmadi" else "çip bilinmiyor"
        return f"{d.port}  ·  {chip}" + (f"  ·  {d.unique_id}" if d.unique_id else "")

    def _sync_fw_device_choices(self) -> None:
        if not hasattr(self, "fw_device_combo"):
            return
        self.fw_device_combo.configure(values=[self._device_choice_label(d) for d in self.devices])
        d = self.selected_device() if hasattr(self, "tree") else None
        if d is not None:
            self.fw_device_var.set(self._device_choice_label(d))
        else:
            self.fw_device_var.set("Kart seçin" if self.devices else "Bağlı kart yok")

    def _on_fw_device_chosen(self, _event: object = None) -> None:
        idx = self.fw_device_combo.current()
        if 0 <= idx < len(self.devices) and hasattr(self, "tree"):
            port = self.devices[idx].port
            self.tree.selection_set(port)
            self.tree.see(port)
            self.on_select()

    def _begin_fw_op(self, op: str) -> None:
        self.fw_op = op
        self.fw_result = None
        self._refresh_fw_ui()

    def _fw_done(self, ok: bool, text: str, dispatched: tuple[str, str] | None = None, duration: int | None = None) -> None:
        self.fw_result = (ok, text)
        if ok and dispatched is not None:
            self.fw_dispatched_key = dispatched
        if ok:
            self.toast(text, "success", duration)
        self._refresh_fw_ui()

    def _fw_failed(self, title: str, message: str) -> None:
        self.fw_result = (False, message)
        self._refresh_fw_ui()
        messagebox.showerror(title, message)

    def _refresh_fw_ui(self) -> None:
        if not hasattr(self, "fw_stepper"):
            return
        key = self._fw_current_key()
        built = self.fw_build_ready and self.fw_build_key == key
        released = self.fw_release_ready and self.fw_release_key == key
        sent = released and self.fw_dispatched_key == key
        done = 3 if sent else (2 if released else (1 if built else 0))
        self.fw_stepper.set(done, None if done >= 3 else done)
        # Siradaki adimin dugmesi vurgulanir.
        emphasis = {self.build_btn: done == 0, self.release_btn: done == 1, self.upload_btn: done >= 2}
        for btn, primary in emphasis.items():
            variant = "primary" if primary else "secondary"
            if btn._kit["variant"] != variant:  # type: ignore[attr-defined]
                self.kit.restyle(btn, variant=variant)
        self.pbar.set_busy(self.fw_busy)
        if self.fw_busy:
            self.fw_pill.set(FW_OP_LABELS.get(self.fw_op, "Çalışıyor"), "busy")
        elif self.fw_result is not None:
            ok = self.fw_result[0]
            self.fw_pill.set("Tamamlandı" if ok else "Başarısız", "ok" if ok else "error")
        else:
            self.fw_pill.set("Hazır", "neutral")

    def run(self) -> None:
        self.root.mainloop()

    def open_device_tester(self) -> None:
        self.show_page("tester")

    def set_status(self, text: str) -> None:
        self.status_var.set(text)
        self.root.update_idletasks()

    def selected_device(self) -> EspDevice | None:
        sel = self.tree.selection()
        if not sel:
            return None
        return next((d for d in self.devices if d.port == sel[0]), None)

    def on_select(self, _event: object = None) -> None:
        if not hasattr(self, "tree"):
            return
        d = self.selected_device()
        if d is None:
            self.uid_var.set("—")
            self.qr_meta_var.set("Listeden bir cihaz seçin.")
            self._set_qr_preview(None)
            if hasattr(self, "fw_device_combo"):
                self.fw_device_var.set("Kart seçin" if self.devices else "Bağlı kart yok")
        else:
            if hasattr(self, "fw_device_combo"):
                self.fw_device_var.set(self._device_choice_label(d))
            if d.unique_id:
                if self.latest_qr is None or self.latest_uid != d.unique_id:
                    self.make_qr()
                else:
                    self.uid_var.set(d.unique_id)
                    self.qr_meta_var.set(self._qr_meta(d))
                    self._set_qr_preview(self.latest_qr, d.unique_id)
            else:
                self.uid_var.set("—")
                self.qr_meta_var.set("Kimliği okuyun; karekod kendiliğinden hazırlanır.")
                self._set_qr_preview(None)
            suggested = suggest_env_for_chip(d.chip, self.envs)
            if suggested and suggested != self.env_var.get():
                self.env_var.set(suggested)
                self.refresh_latest_release()
                self._on_fw_input_changed()
                self.set_status(f"Cihaza göre kart türü seçildi: {suggested}")
        self._refresh_label_ui()

    def scan_devices(self, manual: bool = True) -> None:
        if self.scanning or self.uid_reading:
            return
        self.scanning = True
        self._refresh_label_ui()
        self.set_status("Portlar listeleniyor…")
        threading.Thread(target=self._scan_worker, args=(manual,), daemon=True).start()

    def _scan_worker(self, manual: bool = True) -> None:
        try:
            ports = list(list_ports.comports())
        except Exception:
            ports = []
        found: list[EspDevice] = []
        hwids: dict[str, str] = {}
        for p in ports:
            found.append(
                EspDevice(
                    port=p.device,
                    description=p.description or "",
                    chip="Okunmadi",
                    unique_id="",
                )
            )
            hwids[p.device] = p.hwid or ""
        self.root.after(0, lambda: self._finish_scan(found, hwids, manual))

    def _finish_scan(self, found: list[EspDevice], hwids: dict[str, str] | None = None, manual: bool = True) -> None:
        self.scanning = False
        self.devices = found
        self._port_hwids = dict(hwids or {})
        self._render_devices()
        if found:
            self.set_status(f"{len(found)} port listelendi. Kimlik okuma ayrı bir adımdır ve kartı yeniden başlatabilir.")
        else:
            self.set_status("Bağlı seri port bulunamadı.")
            if manual:
                self.toast("Bağlı seri port bulunamadı. USB kablosunu ve sürücüyü (CH340 / CP210x) kontrol edin.", "warning")

    def read_selected_uid(self) -> None:
        if self.uid_reading or self.scanning:
            return
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Seçim gerekli", "Lütfen listeden bir port seçin.")
            return
        self.uid_reading = True
        self._refresh_label_ui()
        self.set_status(f"Kimlik okunuyor: {d.port}. Kart yeniden başlayabilir…")
        threading.Thread(target=self._read_uid_worker, args=(d.port, d), daemon=True).start()

    def _read_uid_worker(self, port: str, dev: EspDevice) -> None:
        try:
            if getattr(self, "device_tester", None) is not None:
                try:
                    self.device_tester.disconnect()
                    time.sleep(0.3)
                except Exception:
                    pass
            chip, uid = read_mac(dev.port)
            updated = EspDevice(
                port=dev.port,
                description=dev.description,
                chip=chip,
                unique_id=uid,
            )
            self.root.after(0, lambda: self._finish_uid_read(port, updated, None))
        except Exception as exc:
            self.root.after(0, lambda m=str(exc): self._finish_uid_read(port, dev, m))

    def _finish_uid_read(self, port: str, dev: EspDevice, error: str | None) -> None:
        self.uid_reading = False
        self._port_cooldown_until = time.monotonic() + 4.0
        if error is not None:
            self.set_status("Kimlik okunamadı.")
            self._refresh_label_ui()
            messagebox.showerror("Kimlik okunamadı", error)
            return
        for i, x in enumerate(self.devices):
            if x.port == port:
                self.devices[i] = dev
                break
        else:
            self.devices.append(dev)
        self._render_devices(keep_port=port)
        self.set_status(f"Kimlik okundu: {dev.unique_id}. Karekod hazır.")
        self.toast(f"Kimlik okundu: {dev.unique_id}", "success")

    def make_qr(self) -> None:
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Seçim gerekli", "Lütfen listeden bir cihaz seçin.")
            return
        if not d.unique_id:
            messagebox.showinfo(
                "Kimlik gerekli",
                "Önce seçili cihazın kimliğini okuyun. Okuma kartı yeniden başlatabilir.",
            )
            return
        img = generate_qr(d.unique_id, self.logo_path)
        self.latest_qr = img
        self.latest_uid = d.unique_id
        self.uid_var.set(d.unique_id)
        self.qr_meta_var.set(self._qr_meta(d))
        self._set_qr_preview(img, d.unique_id)
        self.set_status(f"Karekod hazır: {d.unique_id}")
        self._refresh_label_ui()

    def save_qr(self) -> None:
        if self.latest_qr is None or self.latest_uid is None:
            messagebox.showinfo("Karekod yok", "Önce cihazın kimliğini okuyun.")
            return
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        name = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{sanitize_filename(self.latest_uid)}.png"
        path = OUTPUT_DIR / name
        self.latest_qr.save(path, format="PNG")
        self.set_status(f"Kaydedildi: {path}")
        self.toast(f"Karekod kaydedildi: output\\{path.name}", "success")

    def print_qr(self) -> None:
        if self.latest_qr is None or self.latest_uid is None:
            messagebox.showinfo("Karekod yok", "Önce cihazın kimliğini okuyun.")
            return
        if os.name != "nt":
            messagebox.showerror("Yazdırma", "Yalnızca Windows destekleniyor.")
            return
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        name = f"print_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{sanitize_filename(self.latest_uid)}.png"
        path = OUTPUT_DIR / name
        self.latest_qr.save(path, format="PNG")
        os.startfile(str(path), "print")
        self.set_status(f"Yazdırma gönderildi: {path.name}")
        self.toast("Karekod yazdırmaya gönderildi.", "success")

    def save_device_to_server(self) -> None:
        if self.saving_device:
            return
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Seçim gerekli", "Lütfen listeden bir cihaz seçin.")
            return
        if not d.unique_id:
            messagebox.showinfo("Kimlik gerekli", "Önce seçili cihazın kimliğini okuyun.")
            return

        if self.latest_qr is None or self.latest_uid != d.unique_id:
            self.make_qr()

        if self.latest_qr is None:
            messagebox.showerror("Karekod hatası", "Karekod oluşturulamadı.")
            return

        # 1. Yerel veritabanına ve klasöre kaydet
        save_local_labeled_device(
            {
                "device_uid": d.unique_id,
                "chip": d.chip,
                "port": d.port,
                "description": d.description,
                "created_at": datetime.now().isoformat(),
            },
            self.latest_qr,
        )

        self.set_status(f"Cihaz sunucuya gönderiliyor: {d.unique_id}…")

        # 2. QR görselini base64 formatına çevir
        buffer = io.BytesIO()
        self.latest_qr.save(buffer, format="PNG")
        qr_b64 = base64.b64encode(buffer.getvalue()).decode("utf-8")

        payload = {
            "device_uid": d.unique_id,
            "chip": d.chip,
            "port": d.port,
            "description": d.description,
            "qr_image_base64": qr_b64,
        }
        hardware_type = chip_to_hardware_type(d.chip)
        if hardware_type:
            # Sunucu hardware_type/hardware_target/chip alanlarindan donanim turunu okur (OTA hedef izolasyonu icin).
            payload["hardware_type"] = hardware_type

        self.saving_device = True
        self._refresh_label_ui()
        worker = self._tracked(self._server_device_save_worker, on_exit=self._end_device_save)
        threading.Thread(target=worker, args=(d, payload), daemon=True).start()

    def _end_device_save(self) -> None:
        self.saving_device = False
        self._refresh_label_ui()

    def _on_device_saved(self, dev: EspDevice, ok: bool, info: str) -> None:
        self.saving_device = False
        if ok:
            self.saved_uids.add(dev.unique_id)
            self._render_devices()
            self.set_status(f"Cihaz sunucuya kaydedildi: {dev.unique_id}  ·  {info}")
            self.toast(f"Sunucuya kaydedildi: {dev.unique_id}", "success")
            return
        self._refresh_label_ui()
        self.set_status(f"Sunucu kayıt uyarısı: {info}")
        messagebox.showwarning(
            "Yerel kayıt tamam, sunucuya gönderilemedi",
            f"Cihaz bu bilgisayara kaydedildi ancak sunucu API'sine ulaşılamadı:\n{info}\n\n"
            f"Cihaz kimliği: {dev.unique_id}",
        )

    def _server_device_save_worker(self, dev: EspDevice, payload: dict) -> None:
        success = False
        error_msg = None

        api_endpoints = [f"{PUBLIC_API_URL}/api/company/labeled-devices"]
        if API_FALLBACK_URL:
            api_endpoints.append(f"{API_FALLBACK_URL}/api/company/labeled-devices")

        if not get_company_api_key():
            # Anahtar yokken sunucu 401 dondurecegi icin ag istegi hic yapilmaz.
            error_msg = COMPANY_KEY_MISSING_MESSAGE
        else:
            data_bytes = json.dumps(payload).encode("utf-8")

            for endpoint in api_endpoints:
                try:
                    req = urllib.request.Request(
                        endpoint,
                        data=data_bytes,
                        headers=company_request_headers(endpoint, {"Content-Type": "application/json"}),
                        method="POST",
                    )
                    with urllib.request.urlopen(req, timeout=10) as resp:
                        if resp.status == 200:
                            success = True
                            break
                except urllib.error.HTTPError as he:
                    error_msg = _company_http_error_text(he.code, _http_error_body(he))
                except Exception as exc:
                    error_msg = str(exc)

        if success:
            url = f"{PUBLIC_API_URL}/qrcodes/{dev.unique_id}.png"
            self.root.after(0, lambda: self._on_device_saved(dev, True, url))
        else:
            msg = error_msg or "Bilinmeyen hata."
            self.root.after(0, lambda: self._on_device_saved(dev, False, msg))

    def download_pdf_report(self) -> None:
        self.set_status("Cihaz listesi alınıyor ve PDF hazırlanıyor…")
        threading.Thread(target=self._tracked(self._pdf_report_worker), daemon=True).start()

    def _pdf_report_worker(self) -> None:
        server_devices, server_error = fetch_server_labeled_devices_with_status()
        if server_error:
            self.root.after(0, lambda msg=server_error: self.set_status(msg))
        local_devices = load_local_labeled_devices()

        device_map: dict[str, dict] = {}
        for d in server_devices:
            uid = str(d.get("device_uid", "")).strip().upper()
            if uid:
                device_map[uid] = d

        for d in local_devices:
            uid = str(d.get("device_uid", "")).strip().upper()
            if uid and uid not in device_map:
                device_map[uid] = d

        if self.latest_uid and self.latest_uid not in device_map:
            sel_dev = self.selected_device()
            device_map[self.latest_uid] = {
                "device_uid": self.latest_uid,
                "chip": getattr(sel_dev, "chip", "ESP32") if sel_dev else "ESP32",
                "port": getattr(sel_dev, "port", "") if sel_dev else "",
                "description": getattr(sel_dev, "description", "") if sel_dev else "",
                "created_at": datetime.now().isoformat(),
            }

        all_devices = list(device_map.values())

        if not all_devices:
            self.root.after(0, lambda: self.set_status("Raporlanacak kayıtlı cihaz bulunamadı."))
            self.root.after(
                0,
                lambda: self.toast("Rapor için önce en az bir cihazı etiketleyip kaydedin.", "warning"),
            )
            return

        all_devices.sort(key=lambda d: str(d.get("created_at", "")), reverse=True)
        self.root.after(0, lambda: self._prompt_save_pdf(all_devices))

    def _prompt_save_pdf(self, devices: list[dict]) -> None:
        default_name = f"SmartKeyPass_Cihaz_Karekod_Raporu_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        target_path = filedialog.asksaveasfilename(
            title="Karekodlu Cihaz Listesi PDF Raporunu Kaydet",
            defaultextension=".pdf",
            initialfile=default_name,
            filetypes=[("PDF Dosyası", "*.pdf"), ("Tüm Dosyalar", "*.*")],
        )
        if not target_path:
            self.set_status("PDF kaydetme iptal edildi.")
            return

        out_path = Path(target_path)
        try:
            self.set_status(f"PDF raporu oluşturuluyor ({len(devices)} cihaz)...")
            generate_devices_catalog_pdf(devices, out_path, self.logo_path)
            self.set_status(f"PDF hazırlandı: {out_path.name}")

            if os.name == "nt":
                try:
                    os.startfile(str(out_path))
                except Exception:
                    pass

            self.set_status(f"PDF hazırlandı ({len(devices)} cihaz): {out_path}")
            self.toast(f"PDF raporu hazır: {len(devices)} cihaz  ·  {out_path.name}", "success", 6000)
        except Exception as exc:
            self.set_status("PDF oluşturma hatası.")
            messagebox.showerror("PDF Hatası", f"PDF raporu oluşturulurken hata oluştu:\n{exc}")

    def open_labeled_devices_window(self) -> None:
        self.show_page("devices")

    def open_screen_firmware_window(self) -> None:
        self.show_page("screen")

    def refresh_latest_release(self) -> None:
        env = self.env_var.get().strip()
        items = [r for r in self.releases if r.get("env") == env]
        if not items:
            self.latest_release_var.set(f"{env} için henüz sürüm yok.")
            return
        items.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        last = items[0]
        self.latest_release_var.set(f"Son sürüm: v{last['version']}  ·  {format_when(last.get('created_at'))}")

    def _fw_current_key(self) -> tuple[str, str]:
        return (self.env_var.get().strip(), self.version_var.get().strip())

    def _on_env_changed(self) -> None:
        env = self.env_var.get().strip()
        self.refresh_latest_release()
        suggested = read_firmware_source_version(env) or suggest_version(self.releases, env)
        self.version_var.set(suggested)
        self._on_fw_input_changed()

    def _on_fw_input_changed(self) -> None:
        key = self._fw_current_key()
        if self.fw_build_key != key:
            self.fw_build_ready = False
        if self.fw_release_key != key:
            self.fw_release_ready = False
        self._apply_fw_button_state()

    def _apply_fw_button_state(self) -> None:
        if not hasattr(self, "build_btn"):
            return
        if self.fw_busy:
            self.build_btn.configure(state=tk.DISABLED)
            self.release_btn.configure(state=tk.DISABLED)
            self.upload_btn.configure(state=tk.DISABLED)
            self.server_upload_btn.configure(state=tk.DISABLED)
            self.coworker_zip_btn.configure(state=tk.DISABLED)
            self.env_combo.configure(state="disabled")
            self.version_entry.configure(state=tk.DISABLED)
        else:
            self.build_btn.configure(state=tk.NORMAL)
            self.release_btn.configure(state=tk.NORMAL if self.fw_build_ready else tk.DISABLED)
            self.upload_btn.configure(state=tk.NORMAL if self.fw_release_ready else tk.DISABLED)
            self.server_upload_btn.configure(state=tk.NORMAL if self.fw_release_ready else tk.DISABLED)
            self.coworker_zip_btn.configure(state=tk.NORMAL if self.fw_release_ready else tk.DISABLED)
            self.env_combo.configure(state="readonly")
            self.version_entry.configure(state=tk.NORMAL)
        self._refresh_fw_ui()

    def _set_fw_state(self, enabled: bool) -> None:
        self.fw_busy = not enabled
        self._apply_fw_button_state()

    def _run_stream(self, cmd: list[str], cwd: Path, on_line=None) -> tuple[int, list[str]]:
        p = subprocess.Popen(cmd, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        lines: list[str] = []
        assert p.stdout is not None
        for line in p.stdout:
            s = line.strip()
            if s:
                lines.append(s)
                if on_line:
                    on_line(s)
        rc = p.wait()
        return rc, lines[-30:]

    def _latest_release_for_current_key(self) -> dict | None:
        env, version = self._fw_current_key()
        items = [
            r
            for r in self.releases
            if r.get("env") == env and str(r.get("version", "")).strip() == version
        ]
        if not items:
            return None
        items.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        return items[0]

    def _release_file_paths(self, rel: dict) -> tuple[Path, Path, Path, Path]:
        files = rel["files"]
        boot = (DEVICE_PROJECT_DIR / files["bootloader_bin"]).resolve()
        part = (DEVICE_PROJECT_DIR / files["partitions_bin"]).resolve()
        firm = (DEVICE_PROJECT_DIR / files["firmware_bin"]).resolve()
        manifest = (DEVICE_PROJECT_DIR / rel.get("manifest", "")).resolve()
        return boot, part, firm, manifest

    def start_build(self) -> None:
        if self.fw_busy:
            return
        env = self.env_var.get().strip()
        version = self.version_var.get().strip()
        if not env:
            messagebox.showerror("Env", "Env secin.")
            return
        if not SEMVER_RE.match(version):
            messagebox.showerror("Surum", "Surum formati 1.2.3 olmali.")
            return
        # Otomatik versiyon senkronizasyonu: ota_guncelleme.h dosyasini guncelle
        write_firmware_source_version(version, env)
        self.fw_build_ready = False
        self.fw_release_ready = False
        self.fw_build_key = None
        self.fw_release_key = None
        self.fw_busy = True
        self._apply_fw_button_state()
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        self._begin_fw_op("build")
        threading.Thread(target=self._build_worker, args=(env, version), daemon=True).start()

    def _build_worker(self, env: str, version: str) -> None:
        try:
            pio = find_platformio()
            self.root.after(0, lambda: self.set_status(f"Derleme basladi: {env} v{version}"))
            rc, tail = self._run_stream(
                [pio, "run", "-d", str(DEVICE_PROJECT_DIR), "-e", env],
                DEVICE_PROJECT_DIR,
                on_line=lambda ln: self.root.after(0, lambda t=ln: self.set_status(f"Derleniyor: {t[:90]}")),
            )
            if rc != 0:
                raise RuntimeError("\n".join(tail[-8:]) if tail else "Derleme hatasi.")
            self.fw_build_key = (env, version)
            self.fw_build_ready = True
            self.fw_release_ready = False
            self.fw_release_key = None
            self.root.after(0, lambda: self.set_status(f"Derleme tamamlandı: v{version}"))
            self.root.after(0, lambda: self._fw_done(True, f"Derleme tamamlandı: v{version}"))
        except Exception as exc:
            self.fw_build_ready = False
            self.fw_release_ready = False
            self.fw_build_key = None
            self.fw_release_key = None
            self.root.after(0, lambda m=str(exc): self._fw_failed("Derleme hatası", m))
            self.root.after(0, lambda: self.set_status("Derleme başarısız."))
        finally:
            self.fw_busy = False
            self.root.after(0, self._apply_fw_button_state)

    def start_release(self) -> None:
        if self.fw_busy:
            return
        env = self.env_var.get().strip()
        version = self.version_var.get().strip()
        if not env:
            messagebox.showerror("Env", "Env secin.")
            return
        if not SEMVER_RE.match(version):
            messagebox.showerror("Surum", "Surum formati 1.2.3 olmali.")
            return
        # Otomatik versiyon senkronizasyonu
        write_firmware_source_version(version, env)
        self.fw_busy = True
        self.fw_release_ready = False
        self.fw_release_key = None
        self._apply_fw_button_state()
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        self._begin_fw_op("release")
        threading.Thread(target=self._release_worker, args=(env, version), daemon=True).start()

    def _release_worker(self, env: str, version: str) -> None:
        try:
            pio = find_platformio()
            self.root.after(0, lambda: self.set_status(f"Surum icin derleniyor: {env}"))
            rc, tail = self._run_stream(
                [pio, "run", "-d", str(DEVICE_PROJECT_DIR), "-e", env],
                DEVICE_PROJECT_DIR,
                on_line=lambda ln: self.root.after(0, lambda t=ln: self.set_status(f"Derleniyor: {t[:90]}")),
            )
            if rc != 0:
                raise RuntimeError("\n".join(tail[-8:]) if tail else "Derleme hatasi.")

            env_dir = BUILD_DIR / env
            files = {
                "firmware_bin": env_dir / "firmware.bin",
                "bootloader_bin": env_dir / "bootloader.bin",
                "partitions_bin": env_dir / "partitions.bin",
            }
            missing = [k for k, p in files.items() if not p.exists()]
            if missing:
                raise FileNotFoundError(f"Build ciktilari eksik: {', '.join(missing)}")

            rid = datetime.now().strftime("%Y%m%d_%H%M%S")
            folder = RELEASES_DIR / f"{rid}_v{version.replace('.', '_')}"
            folder.mkdir(parents=True, exist_ok=True)
            out_files: dict[str, str] = {}
            hashes: dict[str, dict[str, str]] = {}
            for k, src in files.items():
                dst = folder / src.name
                shutil.copy2(src, dst)
                out_files[k] = str(dst.relative_to(DEVICE_PROJECT_DIR))
                hashes[k] = {
                    "sha256": file_hash(dst, "sha256"),
                    "md5": file_hash(dst, "md5"),
                }

            target = target_for_env(env)
            ota_manifest = {
                "enabled": True,
                "target": target,
                "version": version,
                "filename": "firmware.bin",
                "force": True,
                "usb_required": False,
                "partition_scheme": "ota_4mb_littlefs_v1",
                "interval_hours": 1,
                "allowed_uids": [],
                "sha256": hashes["firmware_bin"]["sha256"],
                "md5": hashes["firmware_bin"]["md5"],
                "notes": f"SmartKeyPass firmware v{version} ({target}).",
            }
            manifest_path = folder / "manifest.json"
            manifest_path.write_text(json.dumps(ota_manifest, ensure_ascii=False, indent=2), encoding="utf-8")

            entry = {
                "id": folder.name,
                "version": version,
                "env": env,
                "target": target,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "files": out_files,
                "hashes": hashes,
                "manifest": str(manifest_path.relative_to(DEVICE_PROJECT_DIR)),
            }
            self.releases.append(entry)
            save_releases(self.releases)
            self.fw_release_key = (env, version)
            self.fw_release_ready = True

            self.root.after(0, self.refresh_latest_release)
            self.root.after(0, lambda: self.version_var.set(read_firmware_source_version(env) or suggest_version(self.releases, env)))
            self.root.after(0, lambda: self.set_status(f"Sürüm oluşturuldu: v{version}  ·  {folder}"))
            self.root.after(0, lambda: self._fw_done(True, f"Sürüm oluşturuldu: v{version}"))
        except Exception as exc:
            self.fw_release_ready = False
            self.fw_release_key = None
            self.root.after(0, lambda m=str(exc): self._fw_failed("Sürüm hatası", m))
            self.root.after(0, lambda: self.set_status("Sürüm oluşturma başarısız."))
        finally:
            self.fw_busy = False
            self.root.after(0, self._apply_fw_button_state)

    def start_upload(self) -> None:
        if self.fw_busy:
            return
        if not self.fw_release_ready or self.fw_release_key != self._fw_current_key():
            messagebox.showwarning("Surum gerekli", "Once derleme ve surum olusturma adimlarini basariyla tamamlayin.")
            return
        dev = self.selected_device()
        if dev is None:
            messagebox.showinfo("Secim gerekli", "Lutfen cihaz secin.")
            return
        env = self.env_var.get().strip()
        rel = self._latest_release_for_current_key()
        if rel is None:
            messagebox.showwarning("Surum yok", "Bu env icin surum yok. Once surum olusturun.")
            return
        self.fw_busy = True
        self._apply_fw_button_state()
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        self._begin_fw_op("upload")
        threading.Thread(target=self._upload_worker, args=(dev, rel), daemon=True).start()

    def _upload_worker(self, dev: EspDevice, rel: dict) -> None:
        try:
            # Otomatik baglanti kesme: Cihaz deneme penceresi bu portu tutuyorsa kapat
            if getattr(self, "device_tester", None) is not None:
                try:
                    self.device_tester.disconnect()
                    time.sleep(0.3)
                except Exception:
                    pass

            speed = int(self.upload_speeds.get(rel["env"], 460800))
            boot, part, firm, _manifest = self._release_file_paths(rel)
            for p in (boot, part, firm):
                if not p.exists():
                    raise FileNotFoundError(f"Firmware dosyasi yok: {p}")

            py_exe = find_esptool_python()
            boot_offset = bootloader_offset_for_env(rel.get("env", "lolin_c3_mini"))
            cmd_flash = "write_flash"
            try:
                ver_res = subprocess.run([py_exe, "-m", "esptool", "version"], capture_output=True, text=True, timeout=2, check=False)
                if "v5." in (ver_res.stdout + ver_res.stderr):
                    cmd_flash = "write-flash"
            except Exception:
                pass

            cmd = [
                py_exe,
                "-m",
                "esptool",
                "--chip",
                "auto",
                "--port",
                dev.port,
                "--baud",
                str(speed),
                "--before",
                "default-reset",
                "--after",
                "hard-reset",
                cmd_flash,
                "-z",
                boot_offset,
                str(boot),
                "0x8000",
                str(part),
                "0x10000",
                str(firm),
            ]

            self.root.after(0, lambda: self.set_status(f"Yukleme basladi: {dev.port}"))

            def on_line(line: str) -> None:
                m = PROG_RE.search(line)
                if m:
                    pct = max(0, min(100, int(m.group(1))))
                    self.root.after(0, lambda v=pct: self.progress_var.set(v))
                    self.root.after(0, lambda v=pct: self.progress_text_var.set(f"%{v}"))
                self.root.after(0, lambda t=line: self.set_status(f"Yukleniyor: {t[:90]}"))

            rc, tail = self._run_stream(cmd, DEVICE_PROJECT_DIR, on_line=on_line)
            if rc != 0:
                raw_err = "\n".join(tail[-8:]) if tail else "Yukleme hatasi."
                err_lower = raw_err.lower()
                if "permissionerror" in err_lower or "port is busy" in err_lower or "erişim engellendi" in err_lower:
                    raise RuntimeError(
                        f"{dev.port} portu meşgul (Erişim engellendi).\n\n"
                        "Çözüm Adımları:\n"
                        "1. 'Cihaz Dene' penceresi açıksa 'Bağlantıyı Kes' butonuna basın.\n"
                        "2. VS Code Seri Monitörü açıksa terminaldeki çöp kutusu simgesinden kapatın.\n"
                        "3. Cihazı USB'den çıkarıp tekrar takın."
                    )
                if "write timeout" in err_lower or "failed to connect" in err_lower or "timed out waiting" in err_lower or "no serial data" in err_lower:
                    raise RuntimeError(
                        f"{dev.port} portuna yükleme yapılamadı (Bağlantı / Yazma Zaman Aşımı).\n\n"
                        "Önemli: Harici CH340 / USB dönüştürücü kullanıyorsanız kart otomatik indirme moduna geçemez.\n\n"
                        "Lütfen şu adımları izleyin:\n"
                        "1. ESP32 kartı üzerindeki BOOT (IO0) butonuna BASILI TUTUN.\n"
                        "2. EN (RST) butonuna bir kez basıp bırakın.\n"
                        "3. Ardından BOOT butonunu bırakın (Kart indirme moduna geçer).\n"
                        "4. Şimdi 'Sürümü USB ile cihaza yükle' butonuna tekrar basın.\n\n"
                        f"Detay:\n{raw_err}"
                    )
            # OTA bolumu kullanan kartlarda (app1'de kalan cihazlar) yeni surumun (app0) acilmasini garanti et
            try:
                cmd_erase_ota = [
                    py_exe,
                    "-m",
                    "esptool",
                    "--chip",
                    "auto",
                    "--port",
                    dev.port,
                    "--baud",
                    str(speed),
                    "--after",
                    "hard-reset",
                    "erase_region",
                    "0xe000",
                    "0x2000",
                ]
                self._run_stream(cmd_erase_ota, DEVICE_PROJECT_DIR)
            except Exception:
                pass

            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.progress_text_var.set("%100"))
            self.root.after(0, lambda: self.set_status(f"TMM: Yazılım yükleme tamamlandı ({dev.port}, v{rel['version']})."))
            self.root.after(
                0,
                lambda: self._fw_done(
                    True,
                    f"TMM · Yükleme tamamlandı ({dev.port}, v{rel['version']})",
                    (str(rel.get("env", "")), str(rel.get("version", ""))),
                    7000,
                ),
            )
        except Exception as exc:
            self.root.after(0, lambda m=str(exc): self._fw_failed("Yükleme hatası", m))
            self.root.after(0, lambda: self.set_status("Yükleme başarısız."))
        finally:
            self.fw_busy = False
            self.root.after(0, self._apply_fw_button_state)

    def start_server_upload(self) -> None:
        if self.fw_busy:
            return
        if not self.fw_release_ready or self.fw_release_key != self._fw_current_key():
            messagebox.showwarning("Surum gerekli", "Once derleme ve surum olusturma adimlarini basariyla tamamlayin.")
            return
        rel = self._latest_release_for_current_key()
        if rel is None:
            messagebox.showwarning("Surum yok", "Sunucuya gonderilecek surum bulunamadi.")
            return
        # OTA IMZASI (Dalga F): bu yontem firmware.bin ve manifest.json'u sunucu klasorune DOGRUDAN kopyalar, yani imzayi ve sunucunun yukleme
        # dogrulamasini ATLAR. Kopru surumden (C3 4.4.0 / WROOM 5.3.0) itibaren cihazlar imzasiz paketi KURMAZ; sunucuda OTA_SERVE_UNSIGNED=0 oldugunda
        # da sunulmaz. Yeni surumler docs/OTA_IMZA.md akisiyla yayinlanir (tools/ota_imza ile imzalama + sunucunun yukleme ucu).
        if not messagebox.askyesno(
            "OTA imzasi",
            "UYARI: Bu yontem firmware.bin ve manifest.json dosyalarini sunucu klasorune DOGRUDAN kopyalar; OTA IMZASINI ve sunucunun yukleme "
            "dogrulamasini ATLAR.\n\n"
            "Kopru surumden (ESP32-C3 4.4.0 / ESP32-WROOM 5.3.0) itibaren cihazlar imzasiz paketi KURMAZ. Yeni surumleri docs/OTA_IMZA.md akisiyla "
            "yayinlayin: tools/ota_imza ile imzalayin, sunucunun yukleme ucuyla (POST /admin/firmware/<hedef>/releases) yukleyin.\n\n"
            "Bu eski (imzasiz) yontemi yalnizca kopru oncesi eski cihazlar icin kullanin. Yine de gondermek istiyor musunuz?",
            icon="warning",
            default="no",
            parent=self.root,
        ):
            return
        if not known_hosts_path().is_file():
            messagebox.showerror("Sunucu kimligi dogrulanamiyor", known_hosts_setup_help())
            return
        password = ""
        if not os.environ.get("SSH_KEY_FILE", "").strip():
            # Anahtar tanimli degilse parola: once AHBU_VPS_PASSWORD ortami, yoksa diyalog.
            # (Daha guvenli yol: SSH_KEY_FILE ile anahtar kimlik dogrulamasi.)
            password = os.environ.get("AHBU_VPS_PASSWORD", "").strip()
            if not password:
                password = simpledialog.askstring(
                    "VPS sifresi",
                    f"{VPS_USER}@{VPS_HOST} icin VPS sifresini girin:\n(Oneri: SSH_KEY_FILE ile anahtar kullanin)",
                    show="*",
                    parent=self.root,
                ) or ""
            if not password:
                return
        self.fw_busy = True
        self._apply_fw_button_state()
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        self._begin_fw_op("server")
        threading.Thread(target=self._server_upload_worker, args=(rel, password), daemon=True).start()

    def _server_upload_worker(self, rel: dict, password: str) -> None:
        try:
            _boot, _part, firm, manifest = self._release_file_paths(rel)
            if not firm.exists():
                raise FileNotFoundError(f"Firmware dosyasi yok: {firm}")
            if not manifest.exists():
                raise FileNotFoundError(f"Manifest dosyasi yok: {manifest}")

            target = target_for_env(rel.get("env", "lolin_c3_mini"))
            local_target_dir = LOCAL_SERVER_FIRMWARE_BASE_DIR / target
            local_target_dir.mkdir(parents=True, exist_ok=True)
            local_firm = local_target_dir / "firmware.bin"
            local_manifest = local_target_dir / "manifest.json"
            shutil.copy2(firm, local_firm)
            shutil.copy2(manifest, local_manifest)

            self.root.after(0, lambda: self.set_status("VPS sunucusuna baglaniliyor (SFTP)..."))
            self.root.after(0, lambda: self.progress_var.set(20))
            self.root.after(0, lambda: self.progress_text_var.set("%20"))

            import paramiko
            client = open_verified_ssh_client(paramiko, password)

            sftp = client.open_sftp()
            vps_target_dir = f"{VPS_FIRMWARE_BASE_DIR}/{target}"
            try:
                sftp.stat(vps_target_dir)
            except IOError:
                try:
                    sftp.mkdir(vps_target_dir)
                except Exception:
                    pass

            self.root.after(0, lambda: self.set_status(f"firmware.bin ({target}) sunucuya gonderiliyor..."))
            self.root.after(0, lambda: self.progress_var.set(50))
            self.root.after(0, lambda: self.progress_text_var.set("%50"))
            sftp.put(str(local_firm), f"{vps_target_dir}/firmware.bin")

            self.root.after(0, lambda: self.set_status(f"manifest.json ({target}) sunucuya gonderiliyor..."))
            self.root.after(0, lambda: self.progress_var.set(80))
            self.root.after(0, lambda: self.progress_text_var.set("%80"))
            sftp.put(str(local_manifest), f"{vps_target_dir}/manifest.json")
            sftp.close()
            client.close()

            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.progress_text_var.set("%100"))
            self.root.after(0, lambda: self.set_status(f"TMM: v{rel['version']} ({target}) güncelleme dosyası sunucuya ({VPS_HOST}) gönderildi."))
            self.root.after(
                0,
                lambda: self._fw_done(
                    True,
                    f"TMM · v{rel['version']} ({target}) sunucuya gönderildi. Sahadaki {target} kartları bu sürümü OTA ile indirecek.",
                    (str(rel.get("env", "")), str(rel.get("version", ""))),
                    9000,
                ),
            )
        except Exception as exc:
            self.root.after(0, lambda m=str(exc): self._fw_failed("Sunucuya gönderme hatası", m))
            self.root.after(0, lambda: self.set_status("Sunucuya gönderme başarısız."))
        finally:
            self.fw_busy = False
            self.root.after(0, self._apply_fw_button_state)

    def start_coworker_zip(self) -> None:
        if self.fw_busy:
            return
        if not self.fw_release_ready or self.fw_release_key != self._fw_current_key():
            messagebox.showwarning("Surum gerekli", "Once derleme ve surum olusturma adimlarini basariyla tamamlayin.")
            return
        rel = self._latest_release_for_current_key()
        if rel is None:
            messagebox.showwarning("Surum yok", "ZIP yapilacak surum bulunamadi.")
            return
        env = str(rel.get("env", "env")).replace(" ", "_")
        version = str(rel.get("version", "0.0.0")).replace(".", "_")
        target = filedialog.asksaveasfilename(
            title="Guncelleme ZIP dosyasini kaydet",
            defaultextension=".zip",
            initialfile=f"SmartKeyPass_guncelleme_{env}_v{version}.zip",
            filetypes=[("ZIP dosyasi", "*.zip"), ("Tum dosyalar", "*.*")],
        )
        if not target:
            return
        self.fw_busy = True
        self._apply_fw_button_state()
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        self._begin_fw_op("zip")
        threading.Thread(target=self._coworker_zip_worker, args=(rel, Path(target)), daemon=True).start()

    def _coworker_zip_worker(self, rel: dict, target: Path) -> None:
        try:
            boot, part, firm, manifest = self._release_file_paths(rel)
            for p in (boot, part, firm, manifest):
                if not p.exists():
                    raise FileNotFoundError(f"Guncelleme dosyasi yok: {p}")
            required_tool_dirs = [
                BUNDLED_PYTHON_DIR,
                BUNDLED_ESPTOOL_DIR,
                BUNDLED_SITE_PACKAGES_DIR / "serial",
            ]
            for tool_dir in required_tool_dirs:
                if not tool_dir.exists():
                    raise FileNotFoundError(f"ZIP icin gerekli arac klasoru yok: {tool_dir}")

            speed = int(self.upload_speeds.get(rel["env"], 460800))
            version = str(rel.get("version", ""))
            env = str(rel.get("env", ""))
            # Donanim hedefi; 'target' (ZIP dosya yolu) ile karismasin diye ayri ad.
            hw_target = target_for_env(env)
            boot_offset = bootloader_offset_for_env(env)
            required_bundle_paths = [
                ("Paket Python", BUNDLED_PYTHON_DIR),
                ("esptool", BUNDLED_ESPTOOL_DIR),
                ("pyserial", BUNDLED_SITE_PACKAGES_DIR / "serial"),
            ]
            missing_bundle_paths = [
                f"{label}: {path}"
                for label, path in required_bundle_paths
                if not path.exists()
            ]
            if missing_bundle_paths:
                raise FileNotFoundError(
                    "Calisma arkadasi ZIP paketi icin gerekli araclar eksik:\n" +
                    "\n".join(missing_bundle_paths)
                )
            bat = f"""@echo off
setlocal
cd /d "%~dp0"
set PORT=%~1
set PYEXE=%~dp0tools\\python3\\python.exe
if not exist "%PYEXE%" (
  echo Paket icindeki Python bulunamadi.
  echo ZIP dosyasini tamamen cikardiginizdan emin olun.
  pause
  exit /b 1
)
set PYTHONPATH=%~dp0tools\\site-packages;%~dp0tools\\tool-esptoolpy;%~dp0tools\\tool-esptoolpy\\_contrib
if "%PORT%"=="" (
  echo ESP32 ({hw_target}) COM portu otomatik araniyor...
  for /f "delims=" %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Get-CimInstance Win32_SerialPort | Where-Object {{ $_.Name -match 'USB|UART|CP210|CH340|CH910|ESP|Silicon|Serial' }} | Select-Object -First 1 -ExpandProperty DeviceID; if(-not $p){{ $n=Get-CimInstance Win32_PnPEntity | Where-Object {{ $_.Name -match '(COM[0-9]+)' -and $_.Name -match 'USB|UART|CP210|CH340|CH910|ESP|Silicon|Serial' }} | Select-Object -First 1 -ExpandProperty Name; if($n -match '(COM[0-9]+)'){{ $p=$Matches[1] }} }}; if($p){{ $p.ToUpper() }}"') do set PORT=%%P
)
if "%PORT%"=="" (
  echo ESP32 COM portu otomatik bulunamadi.
  echo.
  echo Gorunen seri portlar:
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_PnPEntity | Where-Object {{ $_.Name -match 'COM[0-9]+' }} | Select-Object -ExpandProperty Name"
  echo.
  echo Cihazi USB ile baglayip tekrar deneyin.
  pause
  exit /b 1
)
echo Kullanilacak port: %PORT%
%PYEXE% -m esptool version >nul 2>&1
if errorlevel 1 (
  echo Paket icindeki esptool calistirilamadi.
  echo ZIP dosyasini tamamen cikardiginizdan emin olun.
  pause
  exit /b 1
)
%PYEXE% -m esptool --chip auto --port "%PORT%" --baud {speed} --before default_reset --after hard_reset write_flash -z {boot_offset} firmware\\bootloader.bin 0x8000 firmware\\partitions.bin 0x10000 firmware\\firmware.bin
if errorlevel 1 (
  echo.
  echo Yukleme basarisiz oldu.
  pause
  exit /b 1
)
echo.
echo SmartKeyPass firmware yukleme tamamlandi. Surum: v{version} ({hw_target})
pause
"""
            readme = f"""SmartKeyPass cihaz USB guncelleme paketi

Surum: v{version}
Hedef Donanim: {hw_target}
PlatformIO env: {env}
Bootloader offset: {boot_offset}

Kullanim:
1. ZIP dosyasini bir klasore cikarin.
2. {hw_target} cihazini USB ile bilgisayara baglayin.
3. flash_smartkeypass_usb.bat dosyasina cift tiklayin.
4. Program COM portunu otomatik bulur ve firmware yukler.

Gerekli yazilim:
- Python, pip veya esptool kurulu olmak zorunda degildir.
- Gerekli yukleme araci bu ZIP paketinin icindedir.
- Windows cihazi COM portu olarak gormuyorsa USB seri surucusu gerekebilir.

Paket icerigi:
- firmware/bootloader.bin
- firmware/partitions.bin
- firmware/firmware.bin
- firmware/manifest.json
- flash_smartkeypass_usb.bat
- tools/python3/
- tools/tool-esptoolpy/
- tools/site-packages/
"""

            target.parent.mkdir(parents=True, exist_ok=True)
            self.root.after(0, lambda: self.set_status("ZIP paketi olusturuluyor..."))
            with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.write(boot, "firmware/bootloader.bin")
                zf.write(part, "firmware/partitions.bin")
                zf.write(firm, "firmware/firmware.bin")
                zf.write(manifest, "firmware/manifest.json")
                zf.writestr("flash_smartkeypass_usb.bat", bat)
                zf.writestr("README.txt", readme)
                zip_directory(zf, BUNDLED_PYTHON_DIR, "tools/python3")
                zip_directory(zf, BUNDLED_ESPTOOL_DIR, "tools/tool-esptoolpy")
                zip_directory(zf, BUNDLED_SITE_PACKAGES_DIR / "serial", "tools/site-packages/serial")
                pyserial_info = next(BUNDLED_SITE_PACKAGES_DIR.glob("pyserial-*.dist-info"), None)
                if pyserial_info is not None:
                    zip_directory(zf, pyserial_info, f"tools/site-packages/{pyserial_info.name}")

            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.progress_text_var.set("%100"))
            self.root.after(0, lambda: self.set_status(f"ZIP hazır: {target}"))
            self.root.after(0, lambda: self._fw_done(True, f"ZIP hazır: {target.name}", (env, version)))
        except Exception as exc:
            self.root.after(0, lambda m=str(exc): self._fw_failed("ZIP hatası", m))
            self.root.after(0, lambda: self.set_status("ZIP oluşturma başarısız."))
        finally:
            self.fw_busy = False
            self.root.after(0, self._apply_fw_button_state)


class LabeledDevicesPage:
    def __init__(self, parent: ttk.Frame, kit: Kit, logo_path: Path, on_download_pdf: Callable[[], None]) -> None:
        # Ana penceredeki sayfa cercevesi; eski kodla uyum icin adi 'window' kaldi.
        self.window = parent
        self.kit = kit
        self.logo_path = logo_path
        self.on_download_pdf = on_download_pdf

        self.devices: list[dict] = []
        self.filtered_devices: list[dict] = []
        self.selected_qr: Image.Image | None = None
        self._preview_uid: str | None = None
        self._server_note = ""

        self.search_var = tk.StringVar(value="")
        self.status_var = tk.StringVar(value="Cihazlar yükleniyor…")
        self.selected_uid_var = tk.StringVar(value="—")
        self.meta_var = tk.StringVar(value="")

        self._ui()
        self.search_var.trace_add("write", lambda *_args: self._on_search_changed())
        self.refresh_devices()

    def _ui(self) -> None:
        kit = self.kit
        px = kit.px
        main = self.window
        main.columnconfigure(0, weight=1)
        main.columnconfigure(1, weight=0, minsize=px(340))
        main.rowconfigure(1, weight=1)

        header, slot = kit.page_header(
            main,
            "Kayıtlı cihazlar",
            "Etiketlenmiş tüm cihazlar ve karekodları. Sunucudaki kayıtlar ile bu bilgisayardakiler birlikte listelenir.",
            icon="library",
        )
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, px(18)))
        kit.button(slot, "Yenile", self.refresh_devices, icon="refresh", surface="page").pack(side=tk.LEFT)
        kit.button(slot, "Karekodlu PDF raporu", self.on_download_pdf, "primary", icon="pdf", surface="page").pack(
            side=tk.LEFT, padx=(px(8), 0)
        )

        left = kit.card(main)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, px(18)))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(1, weight=1)
        bar = ttk.Frame(left, style="card.TFrame")
        bar.grid(row=0, column=0, sticky="ew", pady=(0, px(12)))
        bar.columnconfigure(0, weight=1)
        search = kit.entry(bar, self.search_var, placeholder="Kimlik, çip ya da açıklama ara…", icon="search")
        search.grid(row=0, column=0, sticky="ew")
        search.bind("<Escape>", lambda _e: self.search_var.set(""))
        self.count_pill = Pill(bar, kit, "Yükleniyor", "busy")
        self.count_pill.grid(row=0, column=1, padx=(px(10), 0))

        box, self.tree = kit.tree(
            left,
            [
                ("device_uid", "Cihaz kimliği (UID)", 180, "w", False),
                ("chip", "Çip", 110, "w", False),
                ("created_at", "Kayıt tarihi", 140, "w", False),
                ("description", "Açıklama", 200, "w", True),
            ],
            height=14,
        )
        box.grid(row=1, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self._on_select, add="+")
        self.tree.bind("<Delete>", lambda _e: self._delete_selected_device())
        self.empty = kit.empty_state(
            box,
            "library",
            "Henüz kayıtlı cihaz yok",
            "Etiketle sayfasında bir cihazı kaydettiğinizde burada görünür.",
        )
        self.status_label = kit.label(left, textvariable=self.status_var, kind="caption", justify="left", wraplength=px(640))
        self.status_label.grid(row=2, column=0, sticky="w", pady=(px(10), 0))

        # Sag tik menusu
        self.context_menu = tk.Menu(self.window, tearoff=0, font=kit.fonts["body"])
        self.context_menu.add_command(label="Karekodu yazdır", command=self._print_selected_qr)
        self.context_menu.add_command(label="Karekodu PNG kaydet", command=self._save_selected_qr)
        self.context_menu.add_command(label="Kimliği kopyala", command=self._copy_uid_to_clipboard)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="Cihazı kalıcı olarak sil…", command=self._delete_selected_device)

        def _popup_menu(event):
            item = self.tree.identify_row(event.y)
            if item:
                self.tree.selection_set(item)
                self.context_menu.post(event.x_root, event.y_root)

        self.tree.bind("<Button-3>", _popup_menu)

        right = kit.card(main)
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        kit.label(right, "Karekod", "title").grid(row=0, column=0, sticky="w")
        self.preview_label = ttk.Label(right, style=kit.label_style("body"), anchor="center")
        self.preview_label.grid(row=1, column=0, pady=(px(16), px(12)))
        uid_row = ttk.Frame(right, style="card.TFrame")
        uid_row.grid(row=2, column=0)
        kit.label(uid_row, textvariable=self.selected_uid_var, kind="uid").pack(side=tk.LEFT)
        self.copy_btn = kit.icon_button(uid_row, "copy", self._copy_uid_to_clipboard, "Kimliği panoya kopyala")
        self.copy_btn.pack(side=tk.LEFT, padx=(px(6), 0))
        kit.label(right, textvariable=self.meta_var, kind="caption", justify="center").grid(row=3, column=0, pady=(px(2), 0))
        kit.separator(right).grid(row=4, column=0, sticky="ew", pady=px(16))
        row2 = ttk.Frame(right, style="card.TFrame")
        row2.grid(row=5, column=0, sticky="ew")
        row2.columnconfigure(0, weight=1, uniform="lq")
        row2.columnconfigure(1, weight=1, uniform="lq")
        self.print_btn = kit.button(row2, "Yazdır", self._print_selected_qr, icon="print")
        self.print_btn.grid(row=0, column=0, sticky="ew", padx=(0, px(4)))
        self.save_btn = kit.button(row2, "PNG kaydet", self._save_selected_qr, icon="save")
        self.save_btn.grid(row=0, column=1, sticky="ew", padx=(px(4), 0))
        self.delete_btn = kit.button(right, "Cihazı sil", self._delete_selected_device, "danger_soft", icon="delete")
        self.delete_btn.grid(row=6, column=0, sticky="ew", pady=(px(8), 0))
        kit.label(
            right,
            "Silme, cihazı sunucudan ve bu bilgisayardan kalıcı olarak kaldırır.",
            "caption",
            wraplength=px(290),
            justify="left",
        ).grid(row=7, column=0, sticky="w", pady=(px(12), 0))
        self._set_preview(None)

    def _set_preview(self, img: Image.Image | None, uid: str | None = None) -> None:
        size = self.kit.px(QR_PREVIEW_PX)
        state = tk.NORMAL if img is not None else tk.DISABLED
        for b in (self.print_btn, self.save_btn, self.delete_btn, self.copy_btn):
            b.configure(state=state)
        if img is None:
            self._preview_uid = None
            self.selected_uid_var.set("—")
            self.meta_var.set("")
            self.kit.anim.cancel("labeled-preview")
            self.preview_label.configure(image=self.kit.placeholder_tile(size))
            return
        if uid == self._preview_uid:
            return
        self._preview_uid = uid
        self.kit.pop_image(self.preview_label, self.kit.framed(img, size), "labeled-preview")

    def _show_server_note(self, msg: str) -> None:
        self._server_note = msg
        self.status_var.set(msg)
        self.status_label.configure(image=self.kit.icon("warning", self.kit.px(16), C.WARNING, gap=self.kit.px(6)), compound="left")

    def refresh_devices(self) -> None:
        self._server_note = ""
        self.status_label.configure(image="")
        self.status_var.set("Cihazlar güncelleniyor…")
        self.count_pill.set("Yükleniyor", "busy")
        threading.Thread(target=self._fetch_worker, daemon=True).start()

    def _fetch_worker(self) -> None:
        server_devices, server_error = fetch_server_labeled_devices_with_status()
        local_devices = load_local_labeled_devices()

        device_map: dict[str, dict] = {}
        for d in server_devices:
            uid = str(d.get("device_uid", "")).strip().upper()
            if uid:
                device_map[uid] = d

        for d in local_devices:
            uid = str(d.get("device_uid", "")).strip().upper()
            if uid and uid not in device_map:
                device_map[uid] = d

        devices = list(device_map.values())
        devices.sort(key=lambda d: str(d.get("created_at", "")), reverse=True)
        self.devices = devices
        self.window.after(0, self._apply_search_and_render)
        if server_error:
            self.window.after(50, lambda msg=server_error: self._show_server_note(msg))

    def _on_search_changed(self) -> None:
        self._apply_search_and_render()

    def _apply_search_and_render(self) -> None:
        q = self.search_var.get().strip().upper()
        if not q:
            self.filtered_devices = list(self.devices)
        else:
            self.filtered_devices = [
                d
                for d in self.devices
                if q in str(d.get("device_uid", "")).upper()
                or q in str(d.get("chip", "")).upper()
                or q in str(d.get("description", "")).upper()
            ]

        for x in self.tree.get_children():
            self.tree.delete(x)

        for i, d in enumerate(self.filtered_devices):
            uid = str(d.get("device_uid", "")).upper()
            chip = str(d.get("chip", "ESP32"))
            date_val = format_when(d.get("created_at", "-"))
            desc = str(d.get("description", ""))
            self.tree.insert("", tk.END, iid=str(i), values=(uid, chip, date_val, desc))

        total = len(self.devices)
        shown = len(self.filtered_devices)
        self.count_pill.set(f"{shown} / {total} cihaz" if q else f"{total} cihaz", "info" if total else "neutral")
        if not self._server_note:
            self.status_var.set("Sağ tık: yazdır, kaydet, kopyala, sil. Delete tuşu seçili cihazı siler.")

        if self.filtered_devices:
            self.empty.place_forget()
            self.tree.selection_set("0")
            self._show_device_preview(self.filtered_devices[0])
        else:
            if q:
                self.empty.title_label.configure(text="Eşleşen cihaz yok")
                self.empty.text_label.configure(text="Aramayı değiştirin ya da Esc ile temizleyin.")
            else:
                self.empty.title_label.configure(text="Henüz kayıtlı cihaz yok")
                self.empty.text_label.configure(text="Etiketle sayfasında bir cihazı kaydettiğinizde burada görünür.")
            self.empty.place(relx=0.5, rely=0.5, anchor="center")
            self.selected_qr = None
            self._set_preview(None)
        self.kit.zebra(self.tree)

    def _on_select(self, _event: object) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        if 0 <= idx < len(self.filtered_devices):
            self._show_device_preview(self.filtered_devices[idx])

    def _show_device_preview(self, dev: dict) -> None:
        uid = str(dev.get("device_uid", "")).upper()
        self.selected_uid_var.set(uid or "—")
        chip = str(dev.get("chip", "ESP32"))
        self.meta_var.set(f"{chip}  ·  {format_when(dev.get('created_at', '-'))}")
        if uid == self._preview_uid and self.selected_qr is not None:
            return
        qr_img = generate_qr(uid, self.logo_path)
        self.selected_qr = qr_img
        self._set_preview(qr_img, uid)

    def _delete_selected_device(self) -> None:
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Seçim Gerekli", "Lütfen silmek istediğiniz cihazı tablodan seçin.", parent=self.window)
            return

        idx = int(sel[0])
        if idx < 0 or idx >= len(self.filtered_devices):
            return

        target_dev = self.filtered_devices[idx]
        uid = str(target_dev.get("device_uid", "")).strip().upper()
        if not uid:
            return

        confirm = messagebox.askyesno(
            "Cihazı Sil",
            f"'{uid}' kodlu cihazı kalıcı olarak silmek istediğinize emin misiniz?\n\n"
            f"• Cihaz yerel envanter listesinden silinecektir.\n"
            f"• Cihaz merkezi sunucudan ve varsa tanımlı kapısından tamamen silinecektir.\n"
            f"• Cihaza ait yerel karekod görseli silinecektir.\n\n"
            f"Bu işlem geri alınamaz!",
            icon="warning",
            parent=self.window,
        )
        if not confirm:
            return

        self.status_var.set(f"'{uid}' siliniyor…")
        self.count_pill.set("Siliniyor", "busy")

        def _delete_worker():
            # 1. Yerel JSON ve QR dosyasından sil
            delete_local_labeled_device(uid)
            # 2. Sunucudan ve DB'den sil
            server_ok, server_msg = delete_server_labeled_device(uid)

            def _done():
                self.refresh_devices()
                if server_ok:
                    self.kit.toast(f"{uid} hem bu bilgisayardan hem sunucudan silindi.", "success")
                else:
                    messagebox.showwarning("Kısmi Silme", f"'{uid}' yerelden silindi fakat sunucu bildirimi:\n{server_msg}", parent=self.window)

            self.window.after(0, _done)

        threading.Thread(target=_delete_worker, daemon=True).start()

    def _copy_uid_to_clipboard(self) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        if 0 <= idx < len(self.filtered_devices):
            uid = str(self.filtered_devices[idx].get("device_uid", "")).upper()
            self.window.clipboard_clear()
            self.window.clipboard_append(uid)
            self.kit.toast(f"Kopyalandı: {uid}", "info", 2200)

    def _print_selected_qr(self) -> None:
        if self.selected_qr is None:
            messagebox.showinfo("Seçim Gerekli", "Lütfen bir cihaz seçin.", parent=self.window)
            return
        if os.name != "nt":
            messagebox.showerror("Yazdırma", "Yalnızca Windows işletim sisteminde desteklenir.", parent=self.window)
            return
        sel = self.tree.selection()
        uid = self.filtered_devices[int(sel[0])].get("device_uid", "device") if sel else "device"
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        path = OUTPUT_DIR / f"print_{sanitize_filename(uid)}.png"
        self.selected_qr.save(path, format="PNG")
        os.startfile(str(path), "print")
        self.kit.toast("Karekod yazdırmaya gönderildi.", "success")

    def _save_selected_qr(self) -> None:
        if self.selected_qr is None:
            messagebox.showinfo("Seçim Gerekli", "Lütfen bir cihaz seçin.", parent=self.window)
            return
        sel = self.tree.selection()
        uid = self.filtered_devices[int(sel[0])].get("device_uid", "device") if sel else "device"
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        path = OUTPUT_DIR / f"{sanitize_filename(uid)}.png"
        self.selected_qr.save(path, format="PNG")
        self.kit.toast(f"Karekod kaydedildi: output\\{path.name}", "success")


class DeviceTesterPage:
    STATUS_START = "--- ESP32 SISTEM BILGISI ---"
    STATUS_START_ALT = "----- CIHAZ DURUMU -----"
    STATUS_END = "------------------------"

    SECTIONS = (
        (0, "KİMLİK VE YAZILIM", ("Cihaz UID", "Hedef mimari", "Firmware surumu", "OTA durum")),
        (0, "BLUETOOTH", ("Bluetooth provisioning", "Bluetooth adi")),
        (0, "DONANIM", ("Role GPIO", "Role pin okuma", "Kamera / QR Okuyucu", "WiFi LED GPIO", "Bluetooth LED GPIO")),
        (1, "WI-FI VE AĞ", ("WiFi kayitli", "WiFi SSID", "WiFi bagli", "WiFi IP", "WiFi gucu", "Yerel Beacon (UDP)", "Genel IP (WAN)")),
        (1, "MQTT", ("MQTT", "MQTT kimligi", "MQTT sunucu")),
    )
    # Anahtarlar kartin durum blogundaki adlardir (degismez); yalnizca ekrandaki etiketler Turkcelestirildi.
    FIELD_LABELS = {
        "Cihaz UID": "Cihaz kimliği",
        "Hedef mimari": "Hedef mimari",
        "Firmware surumu": "Yazılım sürümü",
        "OTA durum": "OTA durumu",
        "Bluetooth provisioning": "Kurulum modu",
        "Bluetooth adi": "Bluetooth adı",
        "Role GPIO": "Röle pini",
        "Role pin okuma": "Röle pin okuma",
        "Kamera / QR Okuyucu": "Karekod okuyucu",
        "WiFi LED GPIO": "Wi-Fi LED pini",
        "Bluetooth LED GPIO": "Bluetooth LED pini",
        "WiFi kayitli": "Kayıtlı ağ",
        "WiFi SSID": "Ağ adı (SSID)",
        "WiFi bagli": "Bağlantı",
        "WiFi IP": "Yerel IP",
        "WiFi gucu": "Sinyal gücü",
        "Yerel Beacon (UDP)": "Yerel yayın (UDP)",
        "Genel IP (WAN)": "Genel IP (WAN)",
        "MQTT": "Durum",
        "MQTT kimligi": "Kimlik",
        "MQTT sunucu": "Sunucu",
    }

    def __init__(self, parent: ttk.Frame, kit: Kit) -> None:
        # Ana penceredeki sayfa cercevesi; eski kodla uyum icin adi 'window' kaldi.
        self.window = parent
        self.kit = kit

        self.worker: SerialWorker | None = None
        self.line_queue: queue.Queue[str] = queue.Queue()
        self.status = DeviceStatus()
        self._collecting_status = False
        self._status_lines: list[str] = []
        self._stop_beacon = False
        # F20 genel IP (WAN): alanda IP'si gosterilen/istenen kart, sonraki sorgu zamani, suren sorgunun karti.
        self._wan_uid = ""
        self._wan_next_fetch = 0.0
        self._wan_inflight_uid = ""

        self.port_var = tk.StringVar()
        self.connection_var = tk.StringVar(value="Bağlı değil")
        self.last_command_var = tk.StringVar(value="—")
        self.status_vars: dict[str, tk.StringVar] = {}

        self._ui()
        self.refresh_ports()
        self._start_beacon_listener()
        self.window.after(100, self._drain_lines)

    def _ui(self) -> None:
        kit = self.kit
        px = kit.px
        main = self.window
        # Bilgi karti genis (%60): kimlik ve sunucu adresi gibi uzun degerler bolunmesin.
        main.columnconfigure(0, weight=3, uniform="tst")
        main.columnconfigure(1, weight=2, uniform="tst", minsize=px(340))
        main.rowconfigure(1, weight=1)

        header, slot = kit.page_header(
            main,
            "Cihaz testi",
            "Kartı seri porttan canlı izleyin; röle ve karekod okuyucu testlerini çalıştırın.",
            icon="diag",
        )
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, px(18)))
        self.conn_pill = Pill(slot, kit, "Bağlı değil", "neutral", surface="page")
        self.conn_pill.pack()

        info = kit.card(main)
        info.grid(row=1, column=0, sticky="nsew", padx=(0, px(18)))
        info.columnconfigure(0, weight=1, uniform="info")
        info.columnconfigure(1, weight=1, uniform="info")
        kit.label(info, "Cihaz bilgileri", "title").grid(row=0, column=0, sticky="w")
        kit.label(info, "Kart durum bloğunu yazdıkça kendiliğinden güncellenir.", "caption").grid(
            row=1, column=0, columnspan=2, sticky="w", pady=(px(2), px(12))
        )
        cols = [ttk.Frame(info, style="card.TFrame") for _ in range(2)]
        cols[0].grid(row=2, column=0, sticky="nsew", padx=(0, px(6)))
        cols[1].grid(row=2, column=1, sticky="nsew", padx=(px(6), 0))
        for col, title, keys in self.SECTIONS:
            sec = kit.inset(cols[col], padding=10)
            sec.pack(fill=tk.X, pady=(0, px(10)))
            sec.columnconfigure(1, weight=1)
            kit.label(sec, title, "caps", "inset").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, px(4)))
            for r, key in enumerate(keys, start=1):
                kit.label(sec, self.FIELD_LABELS.get(key, key), "caption", "inset").grid(
                    row=r, column=0, sticky="nw", pady=px(2), padx=(0, px(10))
                )
                var = tk.StringVar(value="-")
                self.status_vars[key] = var
                value = tk.Label(
                    sec,
                    textvariable=var,
                    bg=C.SURFACE_ALT,
                    fg=C.TEXT,
                    font=kit.fonts["body_sb"],
                    anchor="w",
                    justify="left",
                    wraplength=px(160),
                    bd=0,
                    padx=px(4),
                    pady=0,
                )
                value.grid(row=r, column=1, sticky="ew", pady=px(1))
                # Uzun degerler (or. MQTT sunucusu) sutun genisliginde alt satira gecer.
                value.bind("<Configure>", lambda e, w=value: w.configure(wraplength=max(px(60), e.width - px(8))))
                self._watch_value(key, var, value)

        side = ttk.Frame(main, style="page.TFrame")
        side.grid(row=1, column=1, sticky="nsew")
        side.columnconfigure(0, weight=1)
        side.rowconfigure(2, weight=1)

        conn = kit.card(side, padding=16)
        conn.grid(row=0, column=0, sticky="ew")
        conn.columnconfigure(0, weight=1)
        kit.label(conn, "Seri port", "title", image=kit.icon("usb", px(18), C.TEXT_2, gap=px(8)), compound="left").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, px(10))
        )
        self.port_combo = kit.combobox(conn, self.port_var, [])
        self.port_combo.grid(row=1, column=0, sticky="ew")
        kit.icon_button(conn, "refresh", self.refresh_ports, "Port listesini yenile").grid(row=1, column=1, padx=(px(6), 0))
        self.connect_btn = kit.button(conn, "Bağlan", self.toggle_connection, "primary", icon="connect")
        self.connect_btn.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(px(10), 0))

        tools = kit.card(side, padding=16)
        tools.grid(row=1, column=0, sticky="ew", pady=(px(16), 0))
        tools.columnconfigure(0, weight=1, uniform="t")
        tools.columnconfigure(1, weight=1, uniform="t")
        kit.label(tools, "Hızlı testler", "title").grid(row=0, column=0, sticky="w")
        last = ttk.Frame(tools, style="card.TFrame")
        last.grid(row=0, column=1, sticky="e")
        kit.label(last, "Son komut:", "caption").pack(side=tk.LEFT)
        kit.label(last, textvariable=self.last_command_var, kind="value").pack(side=tk.LEFT, padx=(px(6), 0))
        tests = (
            ("Röle HIGH", "h", "bolt"),
            ("Röle LOW", "l", "bolt"),
            ("Röle pulse", "r", "play"),
            ("Kamera testi", "k", "camera"),
            ("Pin bulma", "p", "search"),
        )
        for i, (text, cmd, icon) in enumerate(tests):
            b = kit.button(tools, text, lambda c=cmd: self.send_command(c), icon=icon)
            b.grid(row=1 + i // 2, column=i % 2, sticky="ew", padx=(0, px(4)) if i % 2 == 0 else (px(4), 0), pady=(px(8) if i < 2 else px(3), px(3)))
            Tooltip(b, f"Seri komut: {cmd}. Sonucu seri kayıtta izleyin.", kit)

        log = kit.card(side, padding=16)
        log.grid(row=2, column=0, sticky="nsew", pady=(px(16), 0))
        log.columnconfigure(0, weight=1)
        log.rowconfigure(1, weight=1)
        lh = ttk.Frame(log, style="card.TFrame")
        lh.grid(row=0, column=0, sticky="ew")
        lh.columnconfigure(0, weight=1)
        kit.label(lh, "Seri kayıt", "title").grid(row=0, column=0, sticky="w")
        kit.button(lh, "Temizle", self.clear_log, "ghost", icon="delete").grid(row=0, column=1, sticky="e")
        box, self.log_text = kit.console(log, height=6)
        box.grid(row=1, column=0, sticky="nsew", pady=(px(8), 0))

    def _watch_value(self, key: str, var: tk.StringVar, widget: tk.Label) -> None:
        last = {"value": var.get()}

        def changed(*_args: object) -> None:
            value = var.get()
            if value != last["value"]:
                last["value"] = value
                if value and value != "-":
                    self.kit.flash(widget, C.PRIMARY_SOFT, C.SURFACE_ALT, f"fv{id(self)}{key}")

        var.trace_add("write", changed)

    def _set_conn(self, text: str, kind: str) -> None:
        self.connection_var.set(text)
        self.conn_pill.set(text, kind)

    def clear_log(self) -> None:
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _start_beacon_listener(self) -> None:
        def _worker():
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                if hasattr(socket, "SO_BROADCAST"):
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                s.bind(("", 8765))
                s.settimeout(1.0)
                while not self._stop_beacon:
                    try:
                        data, addr = s.recvfrom(1024)
                        if data:
                            text = data.decode("utf-8", errors="ignore")
                            obj = json.loads(text)
                            uid = str(obj.get("device_uid", "")).strip().upper()
                            ip = str(obj.get("ip", addr[0])).strip()
                            port = obj.get("port", 8765)
                            rssi = obj.get("rssi", "")
                            self.window.after(0, lambda u=uid, i=ip, p=port, r=rssi: self._on_beacon(u, i, p, r))
                    except socket.timeout:
                        continue
                    except Exception:
                        time.sleep(0.5)
            except Exception:
                pass

        threading.Thread(target=_worker, daemon=True).start()

    def _on_beacon(self, uid: str, ip: str, port: int, rssi: object) -> None:
        current_uid = self.status_vars.get("Cihaz UID", tk.StringVar()).get().strip().upper()
        if not current_uid or current_uid == "-" or current_uid == uid:
            rssi_str = f" ({rssi} dBm)" if rssi != "" and rssi is not None else ""
            if "Yerel Beacon (UDP)" in self.status_vars:
                self.status_vars["Yerel Beacon (UDP)"].set(f"{ip}:{port}{rssi_str} · canlı")
            if "WiFi IP" in self.status_vars and (not self.status_vars["WiFi IP"].get() or self.status_vars["WiFi IP"].get() == "-"):
                self.status_vars["WiFi IP"].set(ip)

    def refresh_ports(self) -> None:
        ports = list(list_ports.comports())
        values = [f"{p.device} - {p.description}" for p in ports]
        self.port_combo.configure(values=values)
        if values and not self.port_var.get():
            self.port_var.set(values[0])

    def disconnect(self) -> None:
        if self.worker is not None:
            self.worker.stop()
            self.worker = None
            try:
                self.kit.restyle(self.connect_btn, variant="primary", text="Bağlan", icon="connect")
                self._set_conn("Bağlı değil", "neutral")
            except Exception:
                pass

    def toggle_connection(self) -> None:
        if self.worker is not None:
            self.disconnect()
            return

        port_text = self.port_var.get().strip()
        if not port_text:
            messagebox.showinfo("Port gerekli", "Lütfen bir seri port seçin.")
            return
        port = port_text.split(" - ", 1)[0].strip()
        self.worker = SerialWorker(
            port=port,
            on_line=self.line_queue.put,
            on_error=lambda text: self.line_queue.put(f"[hata] {text}"),
        )
        self.worker.start()
        self.kit.restyle(self.connect_btn, variant="danger_soft", text="Bağlantıyı kes", icon="close")
        self._set_conn(f"Bağlanıyor: {port}", "busy")

    def send_command(self, command: str) -> None:
        if self.worker is None:
            self.kit.toast("Önce karta seri porttan bağlanın.", "warning")
            return
        self.worker.write(command)
        self.last_command_var.set(command)
        self._append_log(f">>> {command}")

    def _drain_lines(self) -> None:
        while not self.line_queue.empty():
            line = self.line_queue.get_nowait()
            self._handle_line(line)
        self.window.after(100, self._drain_lines)

    def _handle_line(self, line: str) -> None:
        self._append_log(line)
        if line.startswith("[baglandi]"):
            self._set_conn(line.replace("[baglandi] ", "Bağlı: "), "ok")
        if line.startswith("[hata]"):
            self._set_conn("Bağlantı hatası", "error")

        if line.strip() in (self.STATUS_START, self.STATUS_START_ALT, "--- ESP32 SISTEM BILGISI ---", "----- CIHAZ DURUMU -----"):
            self._collecting_status = True
            self._status_lines = []
            return
        if line.strip().startswith("---") and self._collecting_status and len(self._status_lines) >= 3:
            self._collecting_status = False
            self._apply_status_block(self._status_lines)
            return
        if self._collecting_status:
            self._status_lines.append(line)
            return

        if line.startswith("Role pin okuma GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role pin okuma ", ""))
        elif line.startswith("Role manuel GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role manuel ", ""))
        elif line.startswith("Role tetik okuma GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role tetik okuma ", ""))
        elif line.startswith("Role birak okuma GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role birak okuma ", ""))

    def _apply_status_block(self, lines: list[str]) -> None:
        values: dict[str, str] = {}
        for line in lines:
            if ": " not in line:
                continue
            key, value = line.split(": ", 1)
            values[key.strip()] = value.strip()
        # Anahtar donusumleri (firmware cikisi ile UI uyumu)
        key_map = {
            "Cihaz Unique ID": "Cihaz UID",
            "Hardware Target": "Hedef mimari",
            "Firmware Versiyon": "Firmware surumu",
            "Wi-Fi Durumu": "WiFi bagli",
            "GM60 QR Okuyucu": "Kamera / QR Okuyucu",
        }
        for k_src, k_dst in key_map.items():
            if k_src in values and k_dst not in values:
                values[k_dst] = values[k_src]
        self.status.values = values
        for key, var in self.status_vars.items():
            if key in values:
                var.set(values[key])
        role_line = next((line for line in lines if line.startswith("Role pin okuma GPIO")), None)
        if role_line:
            self.status_vars["Role pin okuma"].set(role_line.replace("Role pin okuma ", ""))

        uid = values.get("Cihaz UID", "").strip().upper()
        if uid and uid != "-":
            self._request_public_ip(uid)

    # Kart durum blogunu seri oturumda ~5 sn'de bir yazar: sunucu her blokta sorgulanmaz. Genel IP sunucuda en sik
    # kartin OTA kontrolunde (acilista ve 24 saatte bir) degisir; basarisizlikta (anahtar/ag/henuz IP yok) daha erken denenir.
    WAN_REFRESH_OK_S = 120.0
    WAN_REFRESH_RETRY_S = 30.0

    def _request_public_ip(self, uid: str) -> None:
        wan_var = self.status_vars.get("Genel IP (WAN)")
        if wan_var is None:
            return
        if uid != self._wan_uid:
            # Baska kart baglandi: onceki kartin genel IP'si bu kartinmis gibi gosterilmez.
            self._wan_uid = uid
            self._wan_next_fetch = 0.0
            wan_var.set("-")
        if not get_company_api_key():
            return  # Anahtar yok: sessizce "-" kalir (anahtar ancak uygulama yeniden acilinca okunur).
        now = time.monotonic()
        if self._wan_inflight_uid == uid or now < self._wan_next_fetch:
            return
        self._wan_inflight_uid = uid
        self._wan_next_fetch = now + self.WAN_REFRESH_RETRY_S
        threading.Thread(target=self._fetch_public_ip, args=(uid,), daemon=True).start()

    def _fetch_public_ip(self, uid: str) -> None:
        """Arka plan is parcacigi: sunucudan yalniz bu kartin genel IP'sini okur (kisa zaman asimi, hata penceresi yok)."""
        public_ip = fetch_device_public_ip(uid)
        try:
            self.window.after(0, lambda: self._apply_public_ip(uid, public_ip))
        except Exception:
            pass  # Pencere kapanmis olabilir.

    def _apply_public_ip(self, uid: str, public_ip: str) -> None:
        if self._wan_inflight_uid == uid:
            self._wan_inflight_uid = ""
        # Yanit gelene kadar baska kart baglandiysa ya da kimlik degistiyse sonuc atilir.
        uid_var = self.status_vars.get("Cihaz UID")
        current_uid = uid_var.get().strip().upper() if uid_var is not None else ""
        if uid != self._wan_uid or uid != current_uid:
            return
        if public_ip:
            self._wan_next_fetch = time.monotonic() + self.WAN_REFRESH_OK_S
            # Deger degisince _watch_value alani kisa sure vurgular (kit.flash).
            self.status_vars["Genel IP (WAN)"].set(public_ip)

    def _append_log(self, line: str) -> None:
        tag = None
        if line.startswith(">>>"):
            tag = "tx"
        elif line.startswith("[hata]"):
            tag = "err"
        elif line.startswith("[baglandi]"):
            tag = "ok"
        elif line.startswith("---"):
            tag = "dim"
        self.kit.console_append(self.log_text, line, tag)

    def shutdown(self) -> None:
        self._stop_beacon = True
        if self.worker is not None:
            self.worker.stop()
            self.worker = None


class ScreenFirmwarePage:
    def __init__(self, parent: ttk.Frame, kit: Kit, logo_path: Path | None = None) -> None:
        # Ana penceredeki sayfa cercevesi; eski kodla uyum icin adi 'window' kaldi.
        self.window = parent
        self.kit = kit

        self.logo_path = logo_path
        self.worker: SerialWorker | None = None
        self.line_queue: queue.Queue[str] = queue.Queue()
        self.scanning = False
        self.fw_busy = False
        self.fw_build_ready = False
        self.fw_release_ready = False
        self.has_release = False
        self.uploaded_ok = False

        self.port_var = tk.StringVar()
        self.ports: list[str] = []
        self.detected_screen_var = tk.StringVar(value="Ekran taranıyor…")
        self.version_var = tk.StringVar(value=read_display_source_version())
        self.latest_release_var = tk.StringVar(value="Henüz sürüm yok.")
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_text_var = tk.StringVar(value="%0")
        self.status_var = tk.StringVar(value="Hazır.")
        self.connected_var = tk.StringVar(value="Bağlı değil")

        self._ui()
        self.refresh_latest_release()
        self.find_screen()
        self.window.after(100, self._drain_lines)

    def _ui(self) -> None:
        kit = self.kit
        px = kit.px
        main = self.window
        main.columnconfigure(0, weight=1, uniform="scr")
        main.columnconfigure(1, weight=1, uniform="scr")
        main.rowconfigure(1, weight=1)

        header, slot = kit.page_header(
            main,
            "Ekran yazılımı",
            '2.4" ST7789 dokunmatik ekran modülü (ESP32-C3): ekranı bulun, sürüm oluşturun ve USB ile yükleyin.',
            icon="monitor",
        )
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, px(18)))
        self.screen_stepper = Stepper(slot, kit, ["Ekranı bul", "Sürüm oluştur", "Yükle"])
        self.screen_stepper.pack()

        leftcol = ttk.Frame(main, style="page.TFrame")
        leftcol.grid(row=1, column=0, sticky="nsew", padx=(0, px(18)))
        leftcol.columnconfigure(0, weight=1)

        conn = kit.card(leftcol)
        conn.grid(row=0, column=0, sticky="ew")
        conn.columnconfigure(0, weight=1)
        kit.label(conn, "Ekran bağlantısı", "title").grid(row=0, column=0, columnspan=3, sticky="w")
        self.detect_pill = Pill(conn, kit, "Ekran aranıyor…", "busy")
        self.detect_pill.grid(row=1, column=0, columnspan=3, sticky="w", pady=(px(8), px(12)))
        self.port_combo = kit.combobox(conn, self.port_var, [])
        self.port_combo.grid(row=2, column=0, sticky="ew")
        self.port_combo.bind("<<ComboboxSelected>>", self._on_port_changed)
        self.find_btn = kit.button(conn, "Ekranı bul", self.find_screen, icon="search")
        self.find_btn.grid(row=2, column=1, padx=(px(8), 0))
        Tooltip(self.find_btn, "Portlara ping gönderir; yanıt yoksa esptool ile ESP32-C3 arar (kartlar yeniden başlayabilir).", kit)
        self.connect_btn = kit.button(conn, "Bağlan", self.toggle_serial, icon="connect", width=15)
        self.connect_btn.grid(row=2, column=2, padx=(px(8), 0))

        fw = kit.card(leftcol)
        fw.grid(row=1, column=0, sticky="ew", pady=(px(18), 0))
        fw.columnconfigure(0, weight=1, uniform="sb")
        fw.columnconfigure(1, weight=1, uniform="sb")
        kit.label(fw, "Sürüm ve yükleme", "title").grid(row=0, column=0, columnspan=2, sticky="w")
        kit.label(fw, f"Hedef: {DISPLAY_TARGET}  ·  ortam: {DISPLAY_ENV}", "caption").grid(
            row=1, column=0, columnspan=2, sticky="w", pady=(px(4), px(12))
        )
        kit.label(fw, "Sürüm numarası", "value").grid(row=2, column=0, columnspan=2, sticky="w")
        self.version_entry = kit.entry(fw, self.version_var)
        self.version_entry.grid(row=3, column=0, columnspan=2, sticky="ew", pady=(px(6), px(8)))
        kit.label(
            fw,
            textvariable=self.latest_release_var,
            kind="muted",
            image=kit.icon("history", px(16), C.TEXT_3, gap=px(6)),
            compound="left",
            wraplength=px(440),
            justify="left",
        ).grid(row=4, column=0, columnspan=2, sticky="w")
        self.build_btn = kit.button(fw, "Derle", self.start_build, icon="build")
        self.build_btn.grid(row=5, column=0, sticky="ew", padx=(0, px(4)), pady=(px(14), 0))
        self.release_btn = kit.button(fw, "Sürüm oluştur", self.start_release, "primary", icon="package")
        self.release_btn.grid(row=5, column=1, sticky="ew", padx=(px(4), 0), pady=(px(14), 0))
        kit.separator(fw).grid(row=6, column=0, columnspan=2, sticky="ew", pady=px(16))
        self.upload_btn = kit.button(fw, "USB ile ekrana yükle", self.start_upload, icon="usb")
        self.upload_btn.grid(row=7, column=0, columnspan=2, sticky="ew")
        prow = ttk.Frame(fw, style="card.TFrame")
        prow.grid(row=8, column=0, columnspan=2, sticky="ew", pady=(px(14), px(6)))
        prow.columnconfigure(0, weight=1)
        self.pbar = SmoothProgress(prow, kit, self.progress_var)
        self.pbar.grid(row=0, column=0, sticky="ew")
        kit.label(prow, textvariable=self.progress_text_var, kind="value").grid(row=0, column=1, sticky="e", padx=(px(10), 0))
        kit.label(fw, textvariable=self.status_var, kind="mono").grid(row=9, column=0, columnspan=2, sticky="w")
        kit.label(
            fw,
            "ESP32-C3 doğrudan USB CDC ya da CH340 üzerinden 460800 baud ile yazılır.",
            "caption",
            wraplength=px(440),
            justify="left",
        ).grid(row=10, column=0, columnspan=2, sticky="w", pady=(px(6), 0))

        right = kit.card(main)
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(4, weight=1)
        kit.label(right, "Canlı test", "title").grid(row=0, column=0, sticky="w")
        kit.label(right, "Komutlar ekrana seri porttan gönderilir; bağlı değilse önce bağlanılır.", "caption").grid(
            row=1, column=0, sticky="w", pady=(px(2), px(10))
        )
        grid = ttk.Frame(right, style="card.TFrame")
        grid.grid(row=2, column=0, sticky="ew")
        for c in range(3):
            grid.columnconfigure(c, weight=1, uniform="cmd")
        commands = (
            ("Ping", lambda: self.send_command("DISP_PING"), "broadcast", "secondary"),
            ("Test karekodu", lambda: self.send_command("SHOW_QR|AHBU:DOOR:00861A0D5020"), "qr", "secondary"),
            ("Kapı açıldı", lambda: self.send_command("DOOR_OPENED"), "unlock", "secondary"),
            ("Ayarlar", lambda: self.send_command("SHOW_SETTINGS"), "settings", "secondary"),
            ("Ana ekran", lambda: self.send_command("SHOW_HOME"), "home", "secondary"),
            ("Yeniden başlat", self.reset_screen, "power", "danger_soft"),
        )
        for i, (text, cmd, icon, variant) in enumerate(commands):
            b = kit.button(grid, text, cmd, variant, icon=icon)
            b.grid(row=i // 3, column=i % 3, sticky="ew", padx=px(3), pady=px(3))

        lh = ttk.Frame(right, style="card.TFrame")
        lh.grid(row=3, column=0, sticky="ew", pady=(px(16), px(8)))
        lh.columnconfigure(0, weight=1)
        kit.label(lh, "Seri kayıt  ·  115200 baud", "title").grid(row=0, column=0, sticky="w")
        kit.button(lh, "Temizle", self.clear_log, "ghost", icon="delete").grid(row=0, column=1, sticky="e")
        box, self.log_text = kit.console(right, height=14)
        box.grid(row=4, column=0, sticky="nsew")
        self._sync_ui()

    def _set_detected(self, text: str, kind: str) -> None:
        self.detected_screen_var.set(text)
        self.detect_pill.set(text, kind)
        self._sync_ui()

    def _sync_ui(self) -> None:
        if not hasattr(self, "screen_stepper"):
            return
        found = self.worker is not None or self.detect_pill.kind in ("ok", "info")
        released = self.fw_release_ready or self.has_release
        done = 0
        if found:
            done = 1
            if released:
                done = 3 if self.uploaded_ok else 2
        self.screen_stepper.set(done, None if done >= 3 else done)
        for btn, primary in ((self.release_btn, not released), (self.upload_btn, released)):
            variant = "primary" if primary else "secondary"
            if btn._kit["variant"] != variant:  # type: ignore[attr-defined]
                self.kit.restyle(btn, variant=variant)
        self.pbar.set_busy(self.fw_busy)

    def refresh_latest_release(self) -> None:
        releases = load_display_releases()
        self.has_release = bool(releases)
        if not releases:
            self.latest_release_var.set("Henüz sürüm yok. 'Sürüm oluştur' ile ilk paketi hazırlayın.")
            self._sync_ui()
            return
        releases.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        last = releases[0]
        v = last.get("version", "?")
        self.latest_release_var.set(f"Son sürüm: v{v}  ·  {format_when(last.get('created_at', ''))}")
        self._sync_ui()

    def find_screen(self) -> None:
        if self.scanning:
            return
        self.scanning = True
        self.find_btn.configure(state=tk.DISABLED)
        self._set_detected("Bağlı portlar taranıyor…", "busy")
        self.status_var.set("Portlar taranıyor…")
        threading.Thread(target=self._find_screen_worker, daemon=True).start()

    def _find_screen_worker(self) -> None:
        ports = list(list_ports.comports())
        port_names = [p.device for p in ports]
        detected_port = None
        detected_info = ""
        detected_kind = "ok"

        # 1. Önce doğrudan USB seri port üzerinden ping ile ekran yazılımı tespiti dene
        for p in ports:
            p_name = p.device
            if self.worker is not None and self.worker.port == p_name:
                detected_port = p_name
                detected_info = f"{p_name}  ·  şu anda bağlı ekran"
                break
            try:
                with serial.Serial(
                    p_name,
                    115200,
                    timeout=0.3,
                    write_timeout=0.5,
                    rtscts=False,
                    dsrdtr=False,
                ) as s:
                    s.dtr = False
                    s.rts = False
                    time.sleep(0.04)
                    s.reset_input_buffer()
                    s.write(b"\r\nDISP_PING\r\n")
                    time.sleep(0.12)
                    buf = s.read(s.in_waiting or 64).decode("utf-8", errors="ignore")
                    if "AHBU_DEVICE:DISPLAY" in buf or "Display Controller" in buf:
                        detected_port = p_name
                        detected_info = f"{p_name}  ·  SmartKeyPass 2.4\" ekran yanıt verdi"
                        break
            except Exception:
                pass

        # 2. Eğer ping yanıt vermediyse (henüz boş kart veya bootloader'da ise)
        if not detected_port:
            py_exe = find_esptool_python()
            for p in ports:
                p_name = p.device
                p_desc = (p.description or "").lower()
                # USB JTAG / CDC veya CP210/CH340 kontrolü
                try:
                    cmd = [py_exe, "-m", "esptool", "--port", p_name, "--baud", "115200", "--connect-attempts", "2", "chip_id"]
                    out = subprocess.run(cmd, capture_output=True, text=True, timeout=3, check=False)
                    text = (out.stdout + out.stderr).lower()
                    if "esp32-c3" in text:
                        detected_port = p_name
                        detected_info = f"{p_name}  ·  ESP32-C3 ekran modülü bulundu (yazılım yanıt vermedi)"
                        detected_kind = "info"
                        break
                except Exception:
                    pass

        self.window.after(0, lambda: self._finish_find_screen(port_names, detected_port, detected_info, detected_kind))

    def _finish_find_screen(self, port_names: list[str], detected_port: str | None, detected_info: str, kind: str = "ok") -> None:
        self.scanning = False
        self.find_btn.configure(state=tk.NORMAL)
        self.ports = port_names
        self.port_combo.configure(values=port_names)

        if detected_port:
            self.port_var.set(detected_port)
            self._set_detected(detected_info, kind)
            self.status_var.set(f"Ekran bulundu: {detected_port}")
            self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] {detected_info}")
        elif port_names:
            if not self.port_var.get() or self.port_var.get() not in port_names:
                self.port_var.set(port_names[0])
            self._set_detected(f"Otomatik doğrulanamadı  ·  seçili port: {self.port_var.get()}", "warn")
            self.status_var.set("Ekran otomatik doğrulanamadı, listeden seçebilirsiniz.")
        else:
            self.port_var.set("")
            self._set_detected("Bağlı COM port bulunamadı", "error")
            self.status_var.set("Bağlı COM port bulunamadı.")

    def _on_port_changed(self, _event: object) -> None:
        p = self.port_var.get().strip()
        if p:
            self._set_detected(f"Seçili port: {p}", "info")
            self.status_var.set(f"Port seçildi: {p}")

    def toggle_serial(self) -> None:
        if self.worker is not None:
            self.disconnect_serial()
        else:
            self.connect_serial()

    def connect_serial(self) -> None:
        port = self.port_var.get().strip()
        if not port:
            messagebox.showinfo("Port Gerekli", "Lütfen bağlanılacak COM portunu seçin.", parent=self.window)
            return
        try:
            self.worker = SerialWorker(
                port=port,
                on_line=self.line_queue.put,
                on_error=lambda err: self.line_queue.put(f"[HATA] {err}"),
                baud_rate=115200,
            )
            self.worker.start()
            self.kit.restyle(self.connect_btn, variant="danger_soft", text="Bağlantıyı kes", icon="close")
            self.connected_var.set(f"Bağlı: {port}")
            self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] {port} portuna 115200 baud ile bağlanıldı.")
            self._sync_ui()
            # Bağlanınca bir ping atalım
            time.sleep(0.1)
            self.send_command("DISP_PING")
        except Exception as exc:
            messagebox.showerror("Bağlantı Hatası", f"Port açılamadı:\n{exc}", parent=self.window)

    def disconnect_serial(self) -> None:
        if self.worker is not None:
            try:
                self.worker.stop()
            except Exception:
                pass
            self.worker = None
        self.kit.restyle(self.connect_btn, variant="secondary", text="Bağlan", icon="connect")
        self.connected_var.set("Bağlı değil")
        self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] Seri port bağlantısı kapatıldı.")
        self._sync_ui()

    def send_command(self, cmd: str) -> None:
        if self.worker is None:
            self.connect_serial()
        if self.worker is not None:
            self.worker.write(cmd)
            self._append_log(f"> TX: {cmd}")

    def reset_screen(self) -> None:
        port = self.port_var.get().strip()
        if not port:
            return
        self.disconnect_serial()
        try:
            with serial.Serial(port, 115200, timeout=0.5) as s:
                s.dtr = False
                s.rts = True
                time.sleep(0.1)
                s.rts = False
                time.sleep(0.1)
            self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] {port} donanımsal resetlendi (RTS/DTR).")
            self.window.after(300, self.connect_serial)
        except Exception as exc:
            self._append_log(f"[RESET HATA] {exc}")

    def clear_log(self) -> None:
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _drain_lines(self) -> None:
        while True:
            try:
                line = self.line_queue.get_nowait()
                self._append_log(line)
            except queue.Empty:
                break
        self.window.after(100, self._drain_lines)

    def _append_log(self, text: str) -> None:
        tag = None
        if text.startswith("> TX:"):
            tag = "tx"
        elif text.startswith("[HATA]") or text.startswith("[RESET HATA]"):
            tag = "err"
        elif text.startswith("---"):
            tag = "dim"
        elif "bağlanıldı" in text or "Ekran bulundu" in text:
            tag = "ok"
        self.kit.console_append(self.log_text, text, tag)

    def start_build(self) -> None:
        if self.fw_busy:
            return
        version = self.version_var.get().strip()
        if not SEMVER_RE.match(version):
            messagebox.showerror("Sürüm Hatası", "Sürüm formatı 1.0.0 gibi semver olmalıdır.", parent=self.window)
            return

        write_display_source_version(version)
        self.fw_busy = True
        self.build_btn.configure(state=tk.DISABLED)
        self.release_btn.configure(state=tk.DISABLED)
        self.upload_btn.configure(state=tk.DISABLED)
        self.status_var.set("Derleme başladı...")
        self.progress_var.set(10)
        self.progress_text_var.set("%10")
        self._append_log(f"--- EKRAN FIRMWARE DERLEME BAŞLADI (v{version}) ---")

        self._sync_ui()
        threading.Thread(target=self._build_worker, args=(version,), daemon=True).start()

    def _build_worker(self, version: str) -> None:
        try:
            pio = find_platformio()
            cmd = [pio, "run", "-d", str(DISPLAY_PROJECT_DIR), "-e", DISPLAY_ENV]
            proc = subprocess.Popen(
                cmd,
                cwd=str(DISPLAY_PROJECT_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            for line in proc.stdout or []:
                clean = line.strip()
                if clean:
                    self.window.after(0, lambda t=clean: self._append_log(t))
            proc.wait()
            if proc.returncode != 0:
                raise RuntimeError("PlatformIO derleme hatası oluştu.")

            self.fw_build_ready = True
            self.window.after(0, lambda: self.status_var.set(f"Derleme tamamlandı: v{version}"))
            self.window.after(0, lambda: self.progress_var.set(100))
            self.window.after(0, lambda: self.progress_text_var.set("%100"))
            self.window.after(0, lambda: self.kit.toast(f"Ekran yazılımı v{version} derlendi.", "success"))
        except Exception as exc:
            self.fw_build_ready = False
            self.window.after(0, lambda: self.status_var.set("Derleme başarısız."))
            self.window.after(0, lambda m=str(exc): messagebox.showerror("Derleme Hatası", m, parent=self.window))
        finally:
            self.fw_busy = False
            self.window.after(0, self._restore_buttons)

    def start_release(self) -> None:
        if self.fw_busy:
            return
        version = self.version_var.get().strip()
        if not SEMVER_RE.match(version):
            messagebox.showerror("Sürüm Hatası", "Sürüm formatı 1.0.0 gibi semver olmalıdır.", parent=self.window)
            return

        write_display_source_version(version)
        self.fw_busy = True
        self.build_btn.configure(state=tk.DISABLED)
        self.release_btn.configure(state=tk.DISABLED)
        self.upload_btn.configure(state=tk.DISABLED)
        self.status_var.set("Sürüm için derleniyor ve paketleniyor...")
        self.progress_var.set(20)
        self.progress_text_var.set("%20")
        self._append_log(f"--- EKRAN SÜRÜM OLUŞTURMA BAŞLADI (v{version}) ---")

        self._sync_ui()
        threading.Thread(target=self._release_worker, args=(version,), daemon=True).start()

    def _release_worker(self, version: str) -> None:
        try:
            pio = find_platformio()
            cmd = [pio, "run", "-d", str(DISPLAY_PROJECT_DIR), "-e", DISPLAY_ENV]
            proc = subprocess.Popen(
                cmd,
                cwd=str(DISPLAY_PROJECT_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            for line in proc.stdout or []:
                clean = line.strip()
                if clean:
                    self.window.after(0, lambda t=clean: self._append_log(t))
            proc.wait()
            if proc.returncode != 0:
                raise RuntimeError("PlatformIO derleme hatası oluştu.")

            files = {
                "firmware_bin": DISPLAY_BUILD_DIR / "firmware.bin",
                "bootloader_bin": DISPLAY_BUILD_DIR / "bootloader.bin",
                "partitions_bin": DISPLAY_BUILD_DIR / "partitions.bin",
            }
            missing = [k for k, p in files.items() if not p.exists()]
            if missing:
                raise FileNotFoundError(f"Build çıktıları eksik: {', '.join(missing)}")

            rid = datetime.now().strftime("%Y%m%d_%H%M%S")
            folder = DISPLAY_RELEASES_DIR / f"{rid}_v{version.replace('.', '_')}"
            folder.mkdir(parents=True, exist_ok=True)

            out_files: dict[str, str] = {}
            hashes: dict[str, dict[str, str]] = {}
            for k, src in files.items():
                dst = folder / src.name
                shutil.copy2(src, dst)
                out_files[k] = str(dst.relative_to(DISPLAY_PROJECT_DIR))
                hashes[k] = {
                    "sha256": file_hash(dst, "sha256"),
                    "md5": file_hash(dst, "md5"),
                }

            manifest = {
                "enabled": True,
                "target": DISPLAY_TARGET,
                "env": DISPLAY_ENV,
                "version": version,
                "filename": "firmware.bin",
                "sha256": hashes["firmware_bin"]["sha256"],
                "md5": hashes["firmware_bin"]["md5"],
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            (folder / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

            rel_entry = {
                "id": f"{rid}_v{version.replace('.', '_')}",
                "version": version,
                "env": DISPLAY_ENV,
                "target": DISPLAY_TARGET,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "files": out_files,
                "hashes": hashes,
                "manifest": str((folder / "manifest.json").relative_to(DISPLAY_PROJECT_DIR)),
            }
            existing = load_display_releases()
            existing.append(rel_entry)
            save_display_releases(existing)

            self.fw_release_ready = True
            self.window.after(0, self.refresh_latest_release)
            self.window.after(0, lambda: self.status_var.set(f"Sürüm v{version} başarıyla oluşturuldu."))
            self.window.after(0, lambda: self.progress_var.set(100))
            self.window.after(0, lambda: self.progress_text_var.set("%100"))
            self.window.after(0, lambda: self.kit.toast(f"Ekran yazılımı v{version} sürüm paketi hazır.", "success"))
        except Exception as exc:
            self.fw_release_ready = False
            self.window.after(0, lambda: self.status_var.set("Sürüm oluşturma başarısız."))
            self.window.after(0, lambda m=str(exc): messagebox.showerror("Sürüm Hatası", m, parent=self.window))
        finally:
            self.fw_busy = False
            self.window.after(0, self._restore_buttons)

    def start_upload(self) -> None:
        if self.fw_busy:
            return
        port = self.port_var.get().strip()
        if not port:
            messagebox.showinfo("Port Gerekli", "Lütfen ekranın bağlı olduğu COM portunu seçin.", parent=self.window)
            return

        releases = load_display_releases()
        if not releases:
            messagebox.showwarning("Sürüm Gerekli", "Yüklenecek sürüm bulunamadı. Lütfen önce 'Sürüm Oluştur' butonuna basın.", parent=self.window)
            return

        releases.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        latest_rel = releases[0]

        # Port meşgulse seri monitorü kapat
        self.disconnect_serial()

        self.fw_busy = True
        self.build_btn.configure(state=tk.DISABLED)
        self.release_btn.configure(state=tk.DISABLED)
        self.upload_btn.configure(state=tk.DISABLED)
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        self.status_var.set(f"{port} portuna yükleniyor...")
        self._append_log(f"--- EKRANA YÜKLEME BAŞLADI ({port} - v{latest_rel.get('version')}) ---")

        self._sync_ui()
        threading.Thread(target=self._upload_worker, args=(port, latest_rel), daemon=True).start()

    def _upload_worker(self, port: str, rel: dict) -> None:
        try:
            boot = (DISPLAY_PROJECT_DIR / rel["files"]["bootloader_bin"]).resolve()
            part = (DISPLAY_PROJECT_DIR / rel["files"]["partitions_bin"]).resolve()
            firm = (DISPLAY_PROJECT_DIR / rel["files"]["firmware_bin"]).resolve()

            for p in (boot, part, firm):
                if not p.exists():
                    raise FileNotFoundError(f"Firmware dosyası bulunamadı: {p}")

            py_exe = find_esptool_python()
            cmd_flash = "write_flash"
            try:
                ver_res = subprocess.run([py_exe, "-m", "esptool", "version"], capture_output=True, text=True, timeout=2, check=False)
                if "v5." in (ver_res.stdout + ver_res.stderr):
                    cmd_flash = "write-flash"
            except Exception:
                pass

            cmd = [
                py_exe,
                "-m",
                "esptool",
                "--chip",
                "esp32c3",
                "--port",
                port,
                "--baud",
                "460800",
                "--before",
                "default-reset",
                "--after",
                "hard-reset",
                cmd_flash,
                "-z",
                "0x0",
                str(boot),
                "0x8000",
                str(part),
                "0x10000",
                str(firm),
            ]

            proc = subprocess.Popen(
                cmd,
                cwd=str(DISPLAY_PROJECT_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )

            for line in proc.stdout or []:
                clean = line.strip()
                if clean:
                    self.window.after(0, lambda t=clean: self._append_log(t))
                    m = PROG_RE.search(clean)
                    if m:
                        pct = max(0, min(100, int(m.group(1))))
                        self.window.after(0, lambda v=pct: self.progress_var.set(v))
                        self.window.after(0, lambda v=pct: self.progress_text_var.set(f"%{v}"))

            proc.wait()
            if proc.returncode != 0:
                raise RuntimeError(
                    f"{port} portuna yükleme yapılamadı.\n\n"
                    "Olası Nedenler ve Çözümler:\n"
                    "1. Port meşgul olabilir (başka bir seri monitör açıksa kapatın).\n"
                    "2. Kart otomatik indirme moduna geçemiyorsa:\n"
                    "   - ESP32-C3 kartındaki BOOT butonuna BASILI TUTUN.\n"
                    "   - RST butonuna bir kez basıp bırakın, ardından BOOT'u bırakın.\n"
                    "   - Tekrar yüklemeyi deneyin."
                )

            self.window.after(0, lambda: self.progress_var.set(100))
            self.window.after(0, lambda: self.progress_text_var.set("%100"))
            self.uploaded_ok = True
            self.window.after(0, lambda: self.status_var.set(f"TMM: Yükleme başarılı, v{rel.get('version')} ({port})"))
            self.window.after(
                0,
                lambda: self.kit.toast(
                    f"TMM · Ekran yazılımı v{rel.get('version')} {port} portuna yüklendi; ekran yeniden başlatıldı.",
                    "success",
                    7000,
                ),
            )
            # Otomatik seri konsolu bağla
            self.window.after(1000, self.connect_serial)
        except Exception as exc:
            self.window.after(0, lambda: self.status_var.set("Yükleme başarısız."))
            self.window.after(0, lambda m=str(exc): messagebox.showerror("Yükleme Hatası", m, parent=self.window))
        finally:
            self.fw_busy = False
            self.window.after(0, self._restore_buttons)

    def _restore_buttons(self) -> None:
        self.build_btn.configure(state=tk.NORMAL)
        self.release_btn.configure(state=tk.NORMAL)
        self.upload_btn.configure(state=tk.NORMAL)
        self._sync_ui()

    def shutdown(self) -> None:
        if self.worker is not None:
            try:
                self.worker.stop()
            except Exception:
                pass
            self.worker = None


def main() -> None:
    app = App()
    app.run()


if __name__ == "__main__":
    main()

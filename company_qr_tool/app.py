from __future__ import annotations

import base64
import io
import json
import hashlib
import os
import queue
import re
import shutil
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

BASE_DIR = Path(__file__).resolve().parent
ASSETS_DIR = BASE_DIR / "assets"
OUTPUT_DIR = BASE_DIR / "output"
QRCODES_DIR = OUTPUT_DIR / "qrcodes"
LABELED_DEVICES_FILE = OUTPUT_DIR / "labeled_devices.json"
LOGO_PATH = ASSETS_DIR / "ahbu_logo.png"
EXTERNAL_LOGO_PATH = (BASE_DIR / ".." / ".." / "ahbu" / "assets" / "images" / "app_logo.png").resolve()

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
    headers = {"User-Agent": "AHBU-Device-Tool/1.0"}
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
PREVIEW_SIZE = 180
QR_SIZE = 1200
QR_LABEL_HEIGHT = 150

CLR_APP_BG = "#F2F6F4"
CLR_CARD_BG = "#FFFFFF"
CLR_ACCENT = "#16A34A"
CLR_ACCENT_DARK = "#0F7A37"
CLR_ACCENT_SOFT = "#EAF7EF"
CLR_BORDER = "#D9E6DE"
CLR_TEXT_MAIN = "#13281D"
CLR_TEXT_SUB = "#5D7467"
CLR_STATUS = "#127741"
CLR_ROW_SEL_BG = "#DDF3E5"
CLR_ROW_SEL_TEXT = "#103423"
CLR_HEADER_BG = "#0F3A29"
CLR_HEADER_TEXT = "#F5FFF8"
CLR_DANGER = "#DC2626"
CLR_DANGER_DARK = "#B91C1C"
CLR_DANGER_SOFT = "#FEE2E2"


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
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    if LOGO_PATH.exists():
        return LOGO_PATH
    if EXTERNAL_LOGO_PATH.exists():
        shutil.copy2(EXTERNAL_LOGO_PATH, LOGO_PATH)
        return LOGO_PATH
    raise FileNotFoundError(f"Logo bulunamadi: {LOGO_PATH} / {EXTERNAL_LOGO_PATH}")


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


def generate_devices_catalog_pdf(
    devices: list[dict],
    output_pdf_path: Path,
    logo_path: Path,
    report_title: str = "AHBU CİHAZ VE KAREKOD ENVANTER RAPORU",
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
        draw.text((text_x, header_top + 105), "AHBU Akıllı Geçiş ve Kapı Kontrol Sistemleri", fill="#DDF3E5", font=font_subtitle)
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
            desc_val = str(dev.get("description", "AHBU Kapı Kontrol")).strip()
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
        draw.text((MARGIN_X, footer_y + 15), "AHBU Akıllı Geçiş Sistemleri • Güde Teknoloji • www.gudeteknoloji.com.tr", fill="#64748B", font=font_footer)
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
        self.root = tk.Tk()
        self.root.title("AHBU Cihaz Etiketleyici")
        self.root.configure(bg=CLR_APP_BG)
        self.root.minsize(1100, 760)
        try:
            self.root.state("zoomed")
        except tk.TclError:
            try:
                self.root.attributes("-zoomed", True)
            except tk.TclError:
                self.root.geometry(
                    f"{self.root.winfo_screenwidth()}x{self.root.winfo_screenheight()}+0+0"
                )

        self.logo_path = ensure_logo()
        self.devices: list[EspDevice] = []
        self.releases = load_releases()
        self.envs, self.upload_speeds = parse_envs(PLATFORMIO_INI_PATH)

        self.latest_qr: Image.Image | None = None
        self.latest_uid: str | None = None
        self.preview_photo: ImageTk.PhotoImage | None = None
        self.brand_photo: ImageTk.PhotoImage | None = None
        self.icon_photo: ImageTk.PhotoImage | None = None

        self.status_var = tk.StringVar(value="Hazir.")
        self.uid_var = tk.StringVar(value="Unique ID: -")
        self.env_var = tk.StringVar(value=self.envs[0] if self.envs else "lolin_c3_mini")
        self.version_var = tk.StringVar(
            value=read_firmware_source_version(self.env_var.get())
            or suggest_version(self.releases, self.env_var.get())
        )
        self.latest_release_var = tk.StringVar(value="Son surum: -")
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_text_var = tk.StringVar(value="%0")

        self.scanning = False
        self.uid_reading = False
        self.fw_busy = False
        self.fw_build_ready = False
        self.fw_release_ready = False
        self.fw_build_key: tuple[str, str] | None = None
        self.fw_release_key: tuple[str, str] | None = None
        self.screen_window: ScreenFirmwareWindow | None = None

        self._style()
        self.brand_photo = self._load_brand(64)
        self.icon_photo = self._load_brand(32)
        if self.icon_photo is not None:
            self.root.iconphoto(True, self.icon_photo)

        self._ui()
        self.version_var.trace_add("write", lambda *_args: self._on_fw_input_changed())
        self.refresh_latest_release()
        self._apply_fw_button_state()

    def _style(self) -> None:
        s = ttk.Style(self.root)
        if "clam" in s.theme_names():
            s.theme_use("clam")
        elif s.theme_names():
            s.theme_use(s.theme_names()[0])

        s.configure("App.TFrame", background=CLR_APP_BG)
        s.configure("Header.TFrame", background=CLR_HEADER_BG)
        s.configure("Card.TFrame", background=CLR_CARD_BG, borderwidth=0, relief="flat")
        s.configure("Card.TLabel", background=CLR_CARD_BG)
        s.configure("Header.TLabel", background=CLR_HEADER_BG)
        s.configure("Title.TLabel", background=CLR_HEADER_BG, foreground=CLR_HEADER_TEXT, font=("Segoe UI", 18, "bold"))
        s.configure("Sub.TLabel", background=CLR_HEADER_BG, foreground="#D2EDE0", font=("Segoe UI", 10))
        s.configure("Head.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_MAIN, font=("Segoe UI", 11, "bold"))
        s.configure("Text.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_SUB, font=("Segoe UI", 10))
        s.configure("Value.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_MAIN, font=("Segoe UI", 10, "bold"))
        s.configure("Status.TLabel", background=CLR_CARD_BG, foreground=CLR_STATUS, font=("Segoe UI", 10, "bold"))

        s.configure(
            "Accent.TButton",
            background=CLR_ACCENT,
            foreground="#FFFFFF",
            borderwidth=0,
            focusthickness=0,
            focuscolor=CLR_ACCENT,
            padding=(14, 8),
            font=("Segoe UI", 10, "bold"),
        )
        s.map(
            "Accent.TButton",
            background=[("active", CLR_ACCENT_DARK), ("disabled", "#9BC8AC")],
            foreground=[("disabled", "#EEF5F0")],
        )

        s.configure(
            "Soft.TButton",
            background=CLR_ACCENT_SOFT,
            foreground=CLR_TEXT_MAIN,
            borderwidth=0,
            focusthickness=0,
            focuscolor=CLR_ACCENT_SOFT,
            padding=(14, 8),
            font=("Segoe UI", 10),
        )
        s.map(
            "Soft.TButton",
            background=[("active", "#DDF3E8"), ("disabled", "#F2F7F4")],
            foreground=[("disabled", "#8DA394")],
        )

        s.configure(
            "Danger.TButton",
            background=CLR_DANGER,
            foreground="#FFFFFF",
            borderwidth=0,
            focusthickness=0,
            focuscolor=CLR_DANGER,
            padding=(14, 8),
            font=("Segoe UI", 10, "bold"),
        )
        s.map(
            "Danger.TButton",
            background=[("active", CLR_DANGER_DARK), ("disabled", "#FCA5A5")],
            foreground=[("disabled", "#FFFFFF")],
        )

        s.configure(
            "TCombobox",
            fieldbackground=CLR_CARD_BG,
            background=CLR_CARD_BG,
            foreground=CLR_TEXT_MAIN,
            bordercolor=CLR_BORDER,
            arrowsize=14,
            padding=4,
        )
        s.map(
            "TCombobox",
            fieldbackground=[("readonly", CLR_CARD_BG)],
            background=[("readonly", CLR_CARD_BG)],
            foreground=[("readonly", CLR_TEXT_MAIN)],
            selectbackground=[("readonly", CLR_CARD_BG)],
            selectforeground=[("readonly", CLR_TEXT_MAIN)],
        )
        self.root.option_add("*TCombobox*Listbox.background", CLR_CARD_BG)
        self.root.option_add("*TCombobox*Listbox.foreground", CLR_TEXT_MAIN)
        self.root.option_add("*TCombobox*Listbox.selectBackground", CLR_ROW_SEL_BG)
        self.root.option_add("*TCombobox*Listbox.selectForeground", CLR_ROW_SEL_TEXT)

        s.configure(
            "Treeview",
            rowheight=29,
            font=("Segoe UI", 10),
            background=CLR_CARD_BG,
            fieldbackground=CLR_CARD_BG,
            foreground=CLR_TEXT_MAIN,
            bordercolor=CLR_BORDER,
            lightcolor=CLR_BORDER,
            darkcolor=CLR_BORDER,
        )
        s.configure(
            "Treeview.Heading",
            font=("Segoe UI", 10, "bold"),
            background="#EDF5F0",
            foreground=CLR_TEXT_MAIN,
            relief="flat",
        )
        s.map(
            "Treeview",
            background=[("selected", CLR_ROW_SEL_BG)],
            foreground=[("selected", CLR_ROW_SEL_TEXT)],
        )

        s.configure(
            "Accent.Horizontal.TProgressbar",
            troughcolor="#E6F3EC",
            background=CLR_ACCENT,
            bordercolor="#E6F3EC",
            lightcolor=CLR_ACCENT,
            darkcolor=CLR_ACCENT,
        )

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
        main = ttk.Frame(self.root, style="App.TFrame", padding=16)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=3)
        main.columnconfigure(1, weight=2)
        main.rowconfigure(1, weight=1)

        header = ttk.Frame(main, style="Header.TFrame", padding=(16, 14))
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 12))
        header.columnconfigure(1, weight=1)
        hlogo = ttk.Label(header, image=self.brand_photo, style="Header.TLabel")
        hlogo.grid(row=0, column=0, rowspan=2, sticky="w")
        hlogo.image = self.brand_photo
        ttk.Label(header, text="AHBU Cihaz Etiketleyici", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(10, 0))
        ttk.Label(header, text="ID oku, QR uret, firmware surumle ve cihaza yukle.", style="Sub.TLabel").grid(row=1, column=1, sticky="w", padx=(10, 0))

        left = ttk.Frame(main, style="Card.TFrame", padding=14)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        left.rowconfigure(3, weight=1)
        left.columnconfigure(0, weight=1)

        row = ttk.Frame(left, style="Card.TFrame")
        row.grid(row=0, column=0, sticky="ew", pady=(0, 6))
        self.scan_btn = ttk.Button(row, text="Bagli cihazlari tara", command=self.scan_devices, style="Accent.TButton")
        self.scan_btn.pack(side=tk.LEFT)
        self.read_uid_btn = ttk.Button(row, text="Secili cihaz UID oku", command=self.read_selected_uid, style="Soft.TButton")
        self.read_uid_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.qr_btn = ttk.Button(row, text="Secili cihaz icin QR olustur", command=self.make_qr, style="Accent.TButton")
        self.qr_btn.pack(side=tk.LEFT, padx=8)
        self.save_btn = ttk.Button(row, text="QR kaydet", command=self.save_qr, style="Soft.TButton")
        self.save_btn.pack(side=tk.LEFT)
        self.print_btn = ttk.Button(row, text="QR yazdir", command=self.print_qr, style="Soft.TButton")
        self.print_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.test_btn = ttk.Button(row, text="Cihaz dene", command=self.open_device_tester, style="Soft.TButton")
        self.test_btn.pack(side=tk.LEFT, padx=(8, 0))

        row2 = ttk.Frame(left, style="Card.TFrame")
        row2.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        self.server_save_device_btn = ttk.Button(
            row2,
            text="Cihazı Sunucuya Kaydet",
            command=self.save_device_to_server,
            style="Accent.TButton",
        )
        self.server_save_device_btn.pack(side=tk.LEFT)
        self.pdf_report_btn = ttk.Button(
            row2,
            text="Karekodlu PDF Raporu İndir",
            command=self.download_pdf_report,
            style="Accent.TButton",
        )
        self.pdf_report_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.view_labeled_btn = ttk.Button(
            row2,
            text="Kayıtlı Cihazlar & Karekodlar",
            command=self.open_labeled_devices_window,
            style="Soft.TButton",
        )
        self.view_labeled_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.screen_fw_btn = ttk.Button(
            row2,
            text="🖥️ Ekran Yazılımı Güncelle",
            command=self.open_screen_firmware_window,
            style="Accent.TButton",
        )
        self.screen_fw_btn.pack(side=tk.LEFT, padx=(8, 0))

        ttk.Label(left, text="Bagli Cihazlar", style="Head.TLabel").grid(row=2, column=0, sticky="w", pady=(0, 6))
        cols = ("port", "chip", "unique_id", "description")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", height=15)
        self.tree.heading("port", text="Port")
        self.tree.heading("chip", text="Chip")
        self.tree.heading("unique_id", text="Unique ID")
        self.tree.heading("description", text="Aygit Aciklamasi")
        self.tree.column("port", width=90, anchor=tk.CENTER)
        self.tree.column("chip", width=170, anchor=tk.W)
        self.tree.column("unique_id", width=180, anchor=tk.CENTER)
        self.tree.column("description", width=320, anchor=tk.W)
        self.tree.grid(row=3, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self.on_select)
        sc = ttk.Scrollbar(left, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=sc.set)
        sc.grid(row=3, column=1, sticky="ns")
        ttk.Label(left, textvariable=self.status_var, style="Status.TLabel").grid(row=4, column=0, sticky="w", pady=(8, 0))

        right = ttk.Frame(main, style="Card.TFrame", padding=14)
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        ttk.Label(right, text="QR Onizleme", style="Head.TLabel").grid(row=0, column=0, sticky="w")
        self.preview = ttk.Label(right, style="Card.TLabel", anchor="center")
        self.preview.grid(row=1, column=0, sticky="ew", pady=(8, 8))
        ttk.Label(right, textvariable=self.uid_var, style="Text.TLabel").grid(row=2, column=0, sticky="w")
        ttk.Separator(right, orient=tk.HORIZONTAL).grid(row=3, column=0, sticky="ew", pady=12)

        ttk.Label(right, text="Firmware Yonetimi", style="Head.TLabel").grid(row=4, column=0, sticky="w")
        form = ttk.Frame(right, style="Card.TFrame")
        form.grid(row=5, column=0, sticky="ew", pady=(8, 6))
        form.columnconfigure(1, weight=1)
        ttk.Label(form, text="Env:", style="Text.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 8))
        self.env_combo = ttk.Combobox(form, state="readonly", values=self.envs, textvariable=self.env_var, width=30)
        self.env_combo.grid(row=0, column=1, sticky="ew")
        self.env_combo.bind("<<ComboboxSelected>>", lambda _e: self._on_env_changed())
        ttk.Label(form, text="Surum:", style="Text.TLabel").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=(8, 0))
        self.version_entry = ttk.Entry(form, textvariable=self.version_var)
        self.version_entry.grid(row=1, column=1, sticky="ew", pady=(8, 0))

        fw = ttk.Frame(right, style="Card.TFrame")
        fw.grid(row=6, column=0, sticky="ew", pady=(8, 6))
        self.build_btn = ttk.Button(fw, text="Firmware derle", command=self.start_build, style="Soft.TButton")
        self.build_btn.pack(side=tk.LEFT)
        self.release_btn = ttk.Button(fw, text="Surum olustur", command=self.start_release, style="Soft.TButton")
        self.release_btn.pack(side=tk.LEFT, padx=8)
        self.upload_btn = ttk.Button(fw, text="Surumu USB ile cihaza yukle", command=self.start_upload, style="Accent.TButton")
        self.upload_btn.pack(side=tk.LEFT)
        self.server_upload_btn = ttk.Button(
            fw,
            text="Guncelleme Dosyasini Sunucuya gonder",
            command=self.start_server_upload,
            style="Accent.TButton",
        )
        self.server_upload_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.coworker_zip_btn = ttk.Button(
            fw,
            text="Calisma arkadasina guncelleme ZIP'i olustur",
            command=self.start_coworker_zip,
            style="Soft.TButton",
        )
        self.coworker_zip_btn.pack(side=tk.LEFT, padx=(8, 0))

        ttk.Label(right, textvariable=self.latest_release_var, style="Text.TLabel").grid(row=7, column=0, sticky="w", pady=(2, 6))
        p = ttk.Frame(right, style="Card.TFrame")
        p.grid(row=8, column=0, sticky="ew")
        p.columnconfigure(0, weight=1)
        self.pbar = ttk.Progressbar(
            p,
            orient="horizontal",
            mode="determinate",
            maximum=100,
            variable=self.progress_var,
            style="Accent.Horizontal.TProgressbar",
        )
        self.pbar.grid(row=0, column=0, sticky="ew")
        ttk.Label(p, textvariable=self.progress_text_var, style="Text.TLabel").grid(row=0, column=1, sticky="e", padx=(8, 0))
        ttk.Label(right, text="Yukleme sirasinda yuzde gorunur, bitince TMM mesaji gelir.", style="Text.TLabel", wraplength=360).grid(row=9, column=0, sticky="w", pady=(8, 0))

    def run(self) -> None:
        self.root.mainloop()

    def open_device_tester(self) -> None:
        self.device_tester = DeviceTesterWindow(self.root)

    def set_status(self, text: str) -> None:
        self.status_var.set(text)
        self.root.update_idletasks()

    def selected_device(self) -> EspDevice | None:
        sel = self.tree.selection()
        if not sel:
            return None
        idx = int(sel[0])
        return self.devices[idx] if 0 <= idx < len(self.devices) else None

    def on_select(self, _event: object) -> None:
        d = self.selected_device()
        if d:
            self.uid_var.set(f"Unique ID: {d.unique_id or 'Okunmadi'}")
            suggested = suggest_env_for_chip(d.chip, self.envs)
            if suggested and suggested != self.env_var.get():
                self.env_var.set(suggested)
                self.refresh_latest_release()
                self.set_status(f"Cihaza gore env secildi: {suggested}")

    def scan_devices(self) -> None:
        if self.scanning:
            return
        self.scanning = True
        self.scan_btn.configure(state=tk.DISABLED)
        self.read_uid_btn.configure(state=tk.DISABLED)
        self.qr_btn.configure(state=tk.DISABLED)
        self.save_btn.configure(state=tk.DISABLED)
        self.print_btn.configure(state=tk.DISABLED)
        self.set_status("Portlar listeleniyor...")
        threading.Thread(target=self._scan_worker, daemon=True).start()

    def _scan_worker(self) -> None:
        ports = list(list_ports.comports())
        found: list[EspDevice] = []
        for p in ports:
            found.append(
                EspDevice(
                    port=p.device,
                    description=p.description or "",
                    chip="Okunmadi",
                    unique_id="",
                )
            )
        self.root.after(0, lambda: self._finish_scan(found))

    def _finish_scan(self, found: list[EspDevice]) -> None:
        self.scanning = False
        self.scan_btn.configure(state=tk.NORMAL)
        self.read_uid_btn.configure(state=tk.NORMAL)
        self.qr_btn.configure(state=tk.NORMAL)
        self.save_btn.configure(state=tk.NORMAL)
        self.print_btn.configure(state=tk.NORMAL)
        self.devices = found
        for x in self.tree.get_children():
            self.tree.delete(x)
        for i, d in enumerate(found):
            self.tree.insert("", tk.END, iid=str(i), values=(d.port, d.chip, d.unique_id or "Okunmadi", d.description))
        if found:
            self.set_status(f"{len(found)} port listelendi. UID okuma ayri islemdir ve cihazi resetleyebilir.")
        else:
            self.set_status("Bagli seri port bulunamadi.")
            messagebox.showwarning("Port bulunamadi", "USB/driver/COM baglantisini kontrol edin.")

    def read_selected_uid(self) -> None:
        if self.uid_reading:
            return
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Secim gerekli", "Lutfen listeden bir port secin.")
            return
        self.uid_reading = True
        self.scan_btn.configure(state=tk.DISABLED)
        self.read_uid_btn.configure(state=tk.DISABLED)
        self.qr_btn.configure(state=tk.DISABLED)
        self.set_status(f"UID okunuyor: {d.port}. Bu islem cihazi resetleyebilir.")
        idx = self.devices.index(d)
        threading.Thread(target=self._read_uid_worker, args=(idx, d), daemon=True).start()

    def _read_uid_worker(self, idx: int, dev: EspDevice) -> None:
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
            self.root.after(0, lambda: self._finish_uid_read(idx, updated, None))
        except Exception as exc:
            self.root.after(0, lambda: self._finish_uid_read(idx, dev, str(exc)))

    def _finish_uid_read(self, idx: int, dev: EspDevice, error: str | None) -> None:
        self.uid_reading = False
        self.scan_btn.configure(state=tk.NORMAL)
        self.read_uid_btn.configure(state=tk.NORMAL)
        self.qr_btn.configure(state=tk.NORMAL)
        if error is not None:
            self.set_status("UID okunamadi.")
            messagebox.showerror("UID okunamadi", error)
            return
        if 0 <= idx < len(self.devices):
            self.devices[idx] = dev
            self.tree.item(str(idx), values=(dev.port, dev.chip, dev.unique_id, dev.description))
            self.tree.selection_set(str(idx))
        self.uid_var.set(f"Unique ID: {dev.unique_id}")
        suggested = suggest_env_for_chip(dev.chip, self.envs)
        if suggested:
            self.env_var.set(suggested)
            self.refresh_latest_release()
        self.set_status(f"UID okundu: {dev.unique_id}")

    def make_qr(self) -> None:
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Secim gerekli", "Lutfen listeden bir cihaz secin.")
            return
        if not d.unique_id:
            messagebox.showinfo(
                "UID gerekli",
                "Once secili cihaz icin UID oku komutunu calistirin. Bu komut cihazi resetleyebilir.",
            )
            return
        img = generate_qr(d.unique_id, self.logo_path)
        self.latest_qr = img
        self.latest_uid = d.unique_id
        self.uid_var.set(f"Unique ID: {d.unique_id}")
        prev = img.copy()
        prev.thumbnail((PREVIEW_SIZE, PREVIEW_SIZE), Image.Resampling.LANCZOS)
        self.preview_photo = ImageTk.PhotoImage(prev)
        self.preview.configure(image=self.preview_photo)
        self.set_status(f"QR hazir: {d.unique_id}")

    def save_qr(self) -> None:
        if self.latest_qr is None or self.latest_uid is None:
            messagebox.showinfo("QR yok", "Once QR olusturun.")
            return
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        name = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{sanitize_filename(self.latest_uid)}.png"
        path = OUTPUT_DIR / name
        self.latest_qr.save(path, format="PNG")
        self.set_status(f"Kaydedildi: {path}")
        messagebox.showinfo("Kaydedildi", f"QR kaydedildi:\n{path}")

    def print_qr(self) -> None:
        if self.latest_qr is None or self.latest_uid is None:
            messagebox.showinfo("QR yok", "Once QR olusturun.")
            return
        if os.name != "nt":
            messagebox.showerror("Yazdirma", "Yalnizca Windows destekleniyor.")
            return
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        name = f"print_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{sanitize_filename(self.latest_uid)}.png"
        path = OUTPUT_DIR / name
        self.latest_qr.save(path, format="PNG")
        os.startfile(str(path), "print")
        self.set_status(f"Yazdirma gonderildi: {path.name}")

    def save_device_to_server(self) -> None:
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Secim gerekli", "Lutfen listeden bir cihaz secin.")
            return
        if not d.unique_id:
            messagebox.showinfo("UID gerekli", "Once secili cihaz icin UID oku komutunu calistirin.")
            return

        if self.latest_qr is None or self.latest_uid != d.unique_id:
            self.make_qr()

        if self.latest_qr is None:
            messagebox.showerror("QR hatasi", "QR kod olusturulamadi.")
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

        self.set_status(f"Cihaz sunucuya gonderiliyor: {d.unique_id}...")

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

        threading.Thread(target=self._server_device_save_worker, args=(d, payload), daemon=True).start()

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
            self.root.after(0, lambda: self.set_status(f"Cihaz sunucuya kaydedildi: {dev.unique_id}"))
            self.root.after(
                0,
                lambda: messagebox.showinfo(
                    "Sunucuya Kaydedildi",
                    f"Cihaz ve karekod görseli sunucuya başarıyla kaydedildi!\n\n"
                    f"Cihaz UID: {dev.unique_id}\n"
                    f"Çip: {dev.chip}\n"
                    f"Karekod URL: {PUBLIC_API_URL}/qrcodes/{dev.unique_id}.png",
                ),
            )
        else:
            self.root.after(0, lambda: self.set_status(f"Sunucu kayıt uyarısı: {error_msg}"))
            self.root.after(
                0,
                lambda: messagebox.showwarning(
                    "Yerel Kayıt Başarılı / Sunucu Uyarısı",
                    f"Cihaz yerel veritabanına kaydedildi ancak sunucu API'sine ulaşılamadı:\n{error_msg}\n\n"
                    f"Cihaz UID: {dev.unique_id}",
                ),
            )

    def download_pdf_report(self) -> None:
        self.set_status("Cihaz listesi alınıyor ve PDF hazırlanıyor...")
        threading.Thread(target=self._pdf_report_worker, daemon=True).start()

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
                lambda: messagebox.showinfo(
                    "Kayıtlı Cihaz Yok",
                    "Rapor oluşturmak için önce en az 1 cihazı etiketleyip kaydedin.",
                ),
            )
            return

        all_devices.sort(key=lambda d: str(d.get("created_at", "")), reverse=True)
        self.root.after(0, lambda: self._prompt_save_pdf(all_devices))

    def _prompt_save_pdf(self, devices: list[dict]) -> None:
        default_name = f"AHBU_Cihaz_Karekod_Raporu_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
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

            messagebox.showinfo(
                "PDF Raporu Hazır",
                f"Toplam {len(devices)} cihaz için karekodlu envanter PDF raporu başarıyla oluşturuldu:\n\n{out_path}",
            )
        except Exception as exc:
            self.set_status("PDF oluşturma hatası.")
            messagebox.showerror("PDF Hatası", f"PDF raporu oluşturulurken hata oluştu:\n{exc}")

    def open_labeled_devices_window(self) -> None:
        LabeledDevicesWindow(self.root, self.logo_path, self.download_pdf_report)

    def open_screen_firmware_window(self) -> None:
        if getattr(self, "screen_window", None) is not None:
            try:
                self.screen_window.window.lift()
                self.screen_window.window.focus_force()
                return
            except Exception:
                self.screen_window = None
        self.screen_window = ScreenFirmwareWindow(self.root, self.logo_path)

    def refresh_latest_release(self) -> None:
        env = self.env_var.get().strip()
        items = [r for r in self.releases if r.get("env") == env]
        if not items:
            self.latest_release_var.set(f"Son surum ({env}): -")
            return
        items.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        last = items[0]
        self.latest_release_var.set(f"Son surum ({env}): v{last['version']} [{last['created_at']}]")

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
            return

        self.build_btn.configure(state=tk.NORMAL)
        self.release_btn.configure(state=tk.NORMAL if self.fw_build_ready else tk.DISABLED)
        self.upload_btn.configure(state=tk.NORMAL if self.fw_release_ready else tk.DISABLED)
        self.server_upload_btn.configure(state=tk.NORMAL if self.fw_release_ready else tk.DISABLED)
        self.coworker_zip_btn.configure(state=tk.NORMAL if self.fw_release_ready else tk.DISABLED)
        self.env_combo.configure(state="readonly")
        self.version_entry.configure(state=tk.NORMAL)

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
            self.root.after(0, lambda: self.set_status(f"Derleme tamamlandi: v{version}"))
            self.root.after(0, lambda: messagebox.showinfo("Basarili", f"Firmware v{version} derleme tamamlandi."))
        except Exception as exc:
            self.fw_build_ready = False
            self.fw_release_ready = False
            self.fw_build_key = None
            self.fw_release_key = None
            self.root.after(0, lambda: messagebox.showerror("Derleme hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("Derleme basarisiz."))
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
                "notes": f"AHBU firmware v{version} ({target}).",
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
            self.root.after(0, lambda: self.set_status(f"Surum olusturuldu: v{version}"))
            self.root.after(0, lambda: messagebox.showinfo("Basarili", f"Surum olusturuldu: v{version}\n{folder}"))
        except Exception as exc:
            self.fw_release_ready = False
            self.fw_release_key = None
            self.root.after(0, lambda: messagebox.showerror("Surum hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("Surum olusturma basarisiz."))
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
            self.root.after(0, lambda: self.set_status("TMM: Firmware yukleme tamamlandi."))
            self.root.after(0, lambda: messagebox.showinfo("TMM", f"Yukleme tamamlandi.\nPort: {dev.port}\nSurum: v{rel['version']}"))
        except Exception as exc:
            self.root.after(0, lambda m=str(exc): messagebox.showerror("Yukleme hatasi", m))
            self.root.after(0, lambda: self.set_status("Yukleme basarisiz."))
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
            self.root.after(0, lambda: self.set_status(f"TMM: v{rel['version']} ({target}) guncelleme dosyasi sunucuya gonderildi."))
            self.root.after(
                0,
                lambda: messagebox.showinfo(
                    "TMM",
                    f"Firmware guncelleme paketi sunucuya basariyla gonderildi!\n\n"
                    f"Hedef Donanim: {target}\n"
                    f"Surum: v{rel['version']}\n"
                    f"Sunucu: {VPS_HOST}\n\n"
                    f"Sahadaki {target} cihazlari bu surumu OTA uzerinden otomatik olarak indirecektir.",
                ),
            )
        except Exception as exc:
            self.root.after(0, lambda: messagebox.showerror("Sunucu yukleme hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("Sunucuya gonderme basarisiz."))
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
            initialfile=f"AHBU_guncelleme_{env}_v{version}.zip",
            filetypes=[("ZIP dosyasi", "*.zip"), ("Tum dosyalar", "*.*")],
        )
        if not target:
            return
        self.fw_busy = True
        self._apply_fw_button_state()
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
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
            target = target_for_env(env)
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
  echo ESP32 ({target}) COM portu otomatik araniyor...
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
echo AHBU firmware yukleme tamamlandi. Surum: v{version} ({target})
pause
"""
            readme = f"""AHBU cihaz USB guncelleme paketi

Surum: v{version}
Hedef Donanim: {target}
PlatformIO env: {env}
Bootloader offset: {boot_offset}

Kullanim:
1. ZIP dosyasini bir klasore cikarin.
2. {target} cihazini USB ile bilgisayara baglayin.
3. flash_ahbu_usb.bat dosyasina cift tiklayin.
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
- flash_ahbu_usb.bat
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
                zf.writestr("flash_ahbu_usb.bat", bat)
                zf.writestr("README.txt", readme)
                zip_directory(zf, BUNDLED_PYTHON_DIR, "tools/python3")
                zip_directory(zf, BUNDLED_ESPTOOL_DIR, "tools/tool-esptoolpy")
                zip_directory(zf, BUNDLED_SITE_PACKAGES_DIR / "serial", "tools/site-packages/serial")
                pyserial_info = next(BUNDLED_SITE_PACKAGES_DIR.glob("pyserial-*.dist-info"), None)
                if pyserial_info is not None:
                    zip_directory(zf, pyserial_info, f"tools/site-packages/{pyserial_info.name}")

            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.progress_text_var.set("%100"))
            self.root.after(0, lambda: self.set_status(f"ZIP hazir: {target}"))
            self.root.after(0, lambda: messagebox.showinfo("ZIP hazir", f"Guncelleme ZIP dosyasi olusturuldu:\n{target}"))
        except Exception as exc:
            self.root.after(0, lambda: messagebox.showerror("ZIP hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("ZIP olusturma basarisiz."))
        finally:
            self.fw_busy = False
            self.root.after(0, self._apply_fw_button_state)


class LabeledDevicesWindow:
    def __init__(self, parent: tk.Tk, logo_path: Path, on_download_pdf: Callable[[], None]) -> None:
        self.window = tk.Toplevel(parent)
        self.window.title("AHBU Kayıtlı Cihazlar ve Karekod Envanteri")
        self.window.configure(bg=CLR_APP_BG)
        self.window.minsize(1080, 680)
        self.logo_path = logo_path
        self.on_download_pdf = on_download_pdf

        self.devices: list[dict] = []
        self.filtered_devices: list[dict] = []
        self.selected_qr: Image.Image | None = None
        self.preview_photo: ImageTk.PhotoImage | None = None

        self.search_var = tk.StringVar(value="")
        self.status_var = tk.StringVar(value="Cihazlar yükleniyor...")
        self.selected_uid_var = tk.StringVar(value="Seçili Cihaz: -")

        self._ui()
        self.search_var.trace_add("write", lambda *_args: self._on_search_changed())
        self.refresh_devices()

    def _ui(self) -> None:
        main = ttk.Frame(self.window, style="App.TFrame", padding=16)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=3)
        main.columnconfigure(1, weight=2)
        main.rowconfigure(1, weight=1)

        # Header
        header = ttk.Frame(main, style="Header.TFrame", padding=(16, 12))
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 12))
        ttk.Label(header, text="Kayıtlı Cihazlar ve Karekod Envanteri", style="Title.TLabel").pack(side=tk.LEFT)
        ttk.Label(header, textvariable=self.status_var, style="Sub.TLabel").pack(side=tk.RIGHT, padx=10)

        # Left: Devices list
        left = ttk.Frame(main, style="Card.TFrame", padding=14)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(2, weight=1)

        # Toolbar Buttons
        btn_row = ttk.Frame(left, style="Card.TFrame")
        btn_row.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(btn_row, text="🔄 Yenile", command=self.refresh_devices, style="Accent.TButton").pack(side=tk.LEFT)
        ttk.Button(btn_row, text="📄 Karekodlu PDF İndir", command=self.on_download_pdf, style="Accent.TButton").pack(side=tk.LEFT, padx=(8, 0))
        ttk.Button(btn_row, text="🗑️ Seçili Cihazı Sil", command=self._delete_selected_device, style="Danger.TButton").pack(side=tk.LEFT, padx=(12, 0))

        # Search / Filter Bar
        search_row = ttk.Frame(left, style="Card.TFrame")
        search_row.grid(row=1, column=0, sticky="ew", pady=(0, 8))
        ttk.Label(search_row, text="🔍 Ara:", style="Head.TLabel").pack(side=tk.LEFT, padx=(0, 6))
        search_entry = ttk.Entry(search_row, textvariable=self.search_var)
        search_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        ttk.Button(search_row, text="✕ Temizle", command=lambda: self.search_var.set(""), style="Soft.TButton").pack(side=tk.LEFT)

        cols = ("device_uid", "chip", "created_at", "description")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", height=16)
        self.tree.heading("device_uid", text="Cihaz Unique ID")
        self.tree.heading("chip", text="Çip Modeli")
        self.tree.heading("created_at", text="Kayıt Tarihi")
        self.tree.heading("description", text="Açıklama")
        self.tree.column("device_uid", width=190, anchor=tk.CENTER)
        self.tree.column("chip", width=110, anchor=tk.CENTER)
        self.tree.column("created_at", width=150, anchor=tk.CENTER)
        self.tree.column("description", width=200, anchor=tk.W)
        self.tree.grid(row=2, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self._on_select)
        self.tree.bind("<Delete>", lambda _e: self._delete_selected_device())
        self.tree.bind("<F5>", lambda _e: self.refresh_devices())

        # Context Menu (Right Click)
        self.context_menu = tk.Menu(self.window, tearoff=0)
        self.context_menu.add_command(label="🗑️ Seçili Cihazı Sil (Kalıcı)", command=self._delete_selected_device)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="🖨️ Karekodu Yazdır", command=self._print_selected_qr)
        self.context_menu.add_command(label="💾 Karekodu Kaydet", command=self._save_selected_qr)
        self.context_menu.add_command(label="📋 Unique ID Kopyala", command=self._copy_uid_to_clipboard)

        def _popup_menu(event):
            item = self.tree.identify_row(event.y)
            if item:
                self.tree.selection_set(item)
                self.context_menu.post(event.x_root, event.y_root)

        self.tree.bind("<Button-3>", _popup_menu)

        sc = ttk.Scrollbar(left, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=sc.set)
        sc.grid(row=2, column=1, sticky="ns")

        # Right: QR Preview
        right = ttk.Frame(main, style="Card.TFrame", padding=14)
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)

        ttk.Label(right, text="Karekod Önizleme", style="Head.TLabel").grid(row=0, column=0, sticky="w")
        self.preview_label = ttk.Label(right, style="Card.TLabel", anchor="center")
        self.preview_label.grid(row=1, column=0, sticky="ew", pady=(12, 12))
        ttk.Label(right, textvariable=self.selected_uid_var, style="Value.TLabel").grid(row=2, column=0, sticky="w")

        qr_actions = ttk.Frame(right, style="Card.TFrame")
        qr_actions.grid(row=3, column=0, sticky="ew", pady=(16, 0))
        ttk.Button(qr_actions, text="🖨️ Yazdır", command=self._print_selected_qr, style="Soft.TButton").pack(side=tk.LEFT)
        ttk.Button(qr_actions, text="💾 Kaydet", command=self._save_selected_qr, style="Soft.TButton").pack(side=tk.LEFT, padx=(8, 0))
        ttk.Button(qr_actions, text="🗑️ Sil", command=self._delete_selected_device, style="Danger.TButton").pack(side=tk.LEFT, padx=(8, 0))

    def refresh_devices(self) -> None:
        self.status_var.set("Cihazlar güncelleniyor...")
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
            self.window.after(50, lambda msg=server_error: self.status_var.set(msg))

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
            date_val = str(d.get("created_at", "-"))
            if "T" in date_val:
                try:
                    dt = datetime.fromisoformat(date_val.replace("Z", "+00:00"))
                    date_val = dt.strftime("%d.%m.%Y %H:%M")
                except Exception:
                    pass
            desc = str(d.get("description", ""))
            self.tree.insert("", tk.END, iid=str(i), values=(uid, chip, date_val, desc))

        if q:
            self.status_var.set(f"Filtrelendi: {len(self.filtered_devices)} / {len(self.devices)} cihaz")
        else:
            self.status_var.set(f"Toplam {len(self.devices)} kayıtlı cihaz")

        if self.filtered_devices:
            self.tree.selection_set("0")
            self._show_device_preview(self.filtered_devices[0])
        else:
            self.selected_uid_var.set("Seçili Cihaz: -")
            self.preview_label.configure(image="")
            self.selected_qr = None

    def _on_select(self, _event: object) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        if 0 <= idx < len(self.filtered_devices):
            self._show_device_preview(self.filtered_devices[idx])

    def _show_device_preview(self, dev: dict) -> None:
        uid = str(dev.get("device_uid", "")).upper()
        self.selected_uid_var.set(f"Seçili: {uid}")
        qr_img = generate_qr(uid, self.logo_path)
        self.selected_qr = qr_img
        prev = qr_img.copy()
        prev.thumbnail((PREVIEW_SIZE, PREVIEW_SIZE), Image.Resampling.LANCZOS)
        self.preview_photo = ImageTk.PhotoImage(prev)
        self.preview_label.configure(image=self.preview_photo)

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

        self.status_var.set(f"'{uid}' siliniyor...")

        def _delete_worker():
            # 1. Yerel JSON ve QR dosyasından sil
            delete_local_labeled_device(uid)
            # 2. Sunucudan ve DB'den sil
            server_ok, server_msg = delete_server_labeled_device(uid)

            def _done():
                self.refresh_devices()
                if server_ok:
                    messagebox.showinfo("Cihaz Silindi", f"'{uid}' kodlu cihaz hem yerelden hem sunucudan başarıyla silindi.", parent=self.window)
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
            self.status_var.set(f"Panoya kopyalandı: {uid}")

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
        self.status_var.set(f"Yazdırmaya gönderildi: {path.name}")

    def _save_selected_qr(self) -> None:
        if self.selected_qr is None:
            messagebox.showinfo("Seçim Gerekli", "Lütfen bir cihaz seçin.", parent=self.window)
            return
        sel = self.tree.selection()
        uid = self.filtered_devices[int(sel[0])].get("device_uid", "device") if sel else "device"
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        path = OUTPUT_DIR / f"{sanitize_filename(uid)}.png"
        self.selected_qr.save(path, format="PNG")
        messagebox.showinfo("Kaydedildi", f"Karekod kaydedildi:\n{path}", parent=self.window)


class DeviceTesterWindow:
    STATUS_START = "--- ESP32 SISTEM BILGISI ---"
    STATUS_START_ALT = "----- CIHAZ DURUMU -----"
    STATUS_END = "------------------------"

    def __init__(self, parent: tk.Tk) -> None:
        self.window = tk.Toplevel(parent)
        self.window.title("AHBU Cihaz Deneme")
        self.window.configure(bg=CLR_APP_BG)
        self.window.minsize(1040, 700)

        self.worker: SerialWorker | None = None
        self.line_queue: queue.Queue[str] = queue.Queue()
        self.status = DeviceStatus()
        self._collecting_status = False
        self._status_lines: list[str] = []
        self._stop_beacon = False

        self.port_var = tk.StringVar()
        self.connection_var = tk.StringVar(value="Bagli degil")
        self.last_command_var = tk.StringVar(value="-")
        self.status_vars: dict[str, tk.StringVar] = {}

        self._ui()
        self.refresh_ports()
        self._start_beacon_listener()
        self.window.after(100, self._drain_lines)
        self.window.protocol("WM_DELETE_WINDOW", self._on_close)

    def _ui(self) -> None:
        main = ttk.Frame(self.window, style="App.TFrame", padding=16)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=3)
        main.columnconfigure(1, weight=2)
        main.rowconfigure(2, weight=1)

        ttk.Label(main, text="AHBU Cihaz Deneme", style="Head.TLabel").grid(
            row=0,
            column=0,
            columnspan=2,
            sticky="w",
        )

        conn = ttk.Frame(main, style="Card.TFrame", padding=14)
        conn.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(12, 12))
        conn.columnconfigure(1, weight=1)
        ttk.Label(conn, text="Seri Port", style="Head.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 10))
        self.port_combo = ttk.Combobox(conn, textvariable=self.port_var, state="readonly", width=42)
        self.port_combo.grid(row=0, column=1, sticky="ew")
        ttk.Button(conn, text="Yenile", command=self.refresh_ports, style="Soft.TButton").grid(row=0, column=2, padx=(8, 0))
        self.connect_btn = ttk.Button(conn, text="Baglan", command=self.toggle_connection, style="Accent.TButton")
        self.connect_btn.grid(row=0, column=3, padx=(8, 0))
        ttk.Label(conn, textvariable=self.connection_var, style="Text.TLabel").grid(row=1, column=1, sticky="w", pady=(8, 0))

        status_card = ttk.Frame(main, style="Card.TFrame", padding=14)
        status_card.grid(row=2, column=0, sticky="nsew", padx=(0, 10))
        status_card.columnconfigure(1, weight=1)
        ttk.Label(status_card, text="Cihaz Bilgileri", style="Head.TLabel").grid(
            row=0,
            column=0,
            columnspan=2,
            sticky="w",
            pady=(0, 10),
        )

        fields = [
            "Cihaz UID",
            "Hedef mimari",
            "Firmware surumu",
            "OTA durum",
            "WiFi kayitli",
            "WiFi SSID",
            "WiFi bagli",
            "WiFi IP",
            "Yerel Beacon (UDP)",
            "Genel IP (WAN)",
            "WiFi gucu",
            "Bluetooth provisioning",
            "Bluetooth adi",
            "WiFi LED GPIO",
            "Bluetooth LED GPIO",
            "MQTT",
            "MQTT kimligi",
            "MQTT sunucu",
            "Role GPIO",
            "Kamera / QR Okuyucu",
            "Role pin okuma",
        ]
        for row, field_name in enumerate(fields, start=1):
            ttk.Label(status_card, text=f"{field_name}:", style="Text.TLabel").grid(row=row, column=0, sticky="w", pady=3)
            var = tk.StringVar(value="-")
            self.status_vars[field_name] = var
            ttk.Label(status_card, textvariable=var, style="Value.TLabel").grid(row=row, column=1, sticky="w", pady=3)

        tools = ttk.Frame(main, style="Card.TFrame", padding=14)
        tools.grid(row=2, column=1, sticky="nsew")
        tools.columnconfigure(0, weight=1)
        ttk.Label(tools, text="Temel Testler", style="Head.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
        ttk.Button(tools, text="Role Pin HIGH", command=lambda: self.send_command("h"), style="Accent.TButton").grid(row=1, column=0, sticky="ew", pady=4)
        ttk.Button(tools, text="Role Pin LOW", command=lambda: self.send_command("l"), style="Accent.TButton").grid(row=2, column=0, sticky="ew", pady=4)
        ttk.Button(tools, text="Role Pulse", command=lambda: self.send_command("r"), style="Accent.TButton").grid(row=3, column=0, sticky="ew", pady=4)
        ttk.Button(tools, text="Kamera Test (Isik/Bip)", command=lambda: self.send_command("k"), style="Accent.TButton").grid(row=4, column=0, sticky="ew", pady=4)
        ttk.Button(tools, text="Pin Bulma Testi", command=lambda: self.send_command("p"), style="Soft.TButton").grid(row=5, column=0, sticky="ew", pady=4)
        ttk.Separator(tools).grid(row=6, column=0, sticky="ew", pady=12)
        ttk.Label(tools, text="Son Komut", style="Head.TLabel").grid(row=7, column=0, sticky="w")
        ttk.Label(tools, textvariable=self.last_command_var, style="Value.TLabel").grid(row=8, column=0, sticky="w", pady=(4, 12))
        ttk.Label(
            tools,
            text="Cihaz seri porttan durum blogu yazdiginda bilgiler otomatik guncellenir. Komutlar: h=HIGH, l=LOW, r=pulse, k=kamera self-test, p=pin bulma.",
            style="Text.TLabel",
            wraplength=330,
        ).grid(row=9, column=0, sticky="ew")

        log_card = ttk.Frame(main, style="Card.TFrame", padding=14)
        log_card.grid(row=3, column=0, columnspan=2, sticky="nsew", pady=(12, 0))
        log_card.columnconfigure(0, weight=1)
        log_card.rowconfigure(1, weight=1)
        ttk.Label(log_card, text="Seri Log", style="Head.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 8))
        self.log_text = tk.Text(log_card, height=12, bg="#07111F", fg="#D6E8FF", insertbackground="#D6E8FF", relief=tk.FLAT)
        self.log_text.grid(row=1, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(log_card, orient=tk.VERTICAL, command=self.log_text.yview)
        scrollbar.grid(row=1, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=scrollbar.set)

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
                self.status_vars["Yerel Beacon (UDP)"].set(f"🟢 {ip}:{port}{rssi_str} (Canlı)")
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
                self.connect_btn.configure(text="Baglan")
                self.connection_var.set("Bagli degil")
            except Exception:
                pass

    def toggle_connection(self) -> None:
        if self.worker is not None:
            self.disconnect()
            return

        port_text = self.port_var.get().strip()
        if not port_text:
            messagebox.showinfo("Port gerekli", "Lutfen bir seri port secin.")
            return
        port = port_text.split(" - ", 1)[0].strip()
        self.worker = SerialWorker(
            port=port,
            on_line=self.line_queue.put,
            on_error=lambda text: self.line_queue.put(f"[hata] {text}"),
        )
        self.worker.start()
        self.connect_btn.configure(text="Kes")
        self.connection_var.set(f"Baglaniyor: {port}")

    def send_command(self, command: str) -> None:
        if self.worker is None:
            messagebox.showinfo("Baglanti yok", "Once cihaza seri porttan baglanin.")
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
            self.connection_var.set(line.replace("[baglandi] ", "Bagli: "))
        if line.startswith("[hata]"):
            self.connection_var.set("Hata")

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

        uid = values.get("Cihaz UID", "").strip()
        if uid and uid != "-":
            threading.Thread(target=self._fetch_public_ip, args=(uid,), daemon=True).start()

    def _fetch_public_ip(self, uid: str) -> None:
        try:
            url = f"{API_BASE_URL}/api/devices"
            req = urllib.request.Request(url, headers={"User-Agent": "AHBU-Tester/1.0"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    devices = data if isinstance(data, list) else data.get("devices", [])
                    for d in devices:
                        if str(d.get("device_uid", "")).upper() == uid.upper():
                            pub_ip = d.get("public_ip") or d.get("client_ip") or d.get("last_ip")
                            if pub_ip and "Genel IP (WAN)" in self.status_vars:
                                self.window.after(0, lambda p=pub_ip: self.status_vars["Genel IP (WAN)"].set(f"🌐 {p}"))
                            break
        except Exception:
            pass

    def _append_log(self, line: str) -> None:
        self.log_text.insert(tk.END, f"{line}\n")
        self.log_text.see(tk.END)

    def _on_close(self) -> None:
        self._stop_beacon = True
        if self.worker is not None:
            self.worker.stop()
        self.window.destroy()


class ScreenFirmwareWindow:
    def __init__(self, parent: tk.Tk, logo_path: Path | None = None) -> None:
        self.window = tk.Toplevel(parent)
        self.window.title("AHBU Ekran Yazılımı Güncelleyici (2.4\" ST7789)")
        self.window.configure(bg=CLR_APP_BG)
        self.window.minsize(1060, 720)

        self.logo_path = logo_path
        self.worker: SerialWorker | None = None
        self.line_queue: queue.Queue[str] = queue.Queue()
        self.scanning = False
        self.fw_busy = False
        self.fw_build_ready = False
        self.fw_release_ready = False

        self.port_var = tk.StringVar()
        self.ports: list[str] = []
        self.detected_screen_var = tk.StringVar(value="Ekran taranıyor...")
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
        self.window.protocol("WM_DELETE_WINDOW", self._on_close)

    def _ui(self) -> None:
        main = ttk.Frame(self.window, style="App.TFrame", padding=14)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=1)
        main.columnconfigure(1, weight=1)
        main.rowconfigure(1, weight=1)

        # 1. Header
        header = ttk.Frame(main, style="Header.TFrame", padding=(16, 12))
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))
        header.columnconfigure(1, weight=1)

        ttk.Label(header, text="🖥️ AHBU Ekran Yazılımı Güncelleyici", style="Title.TLabel").grid(
            row=0, column=0, sticky="w"
        )
        ttk.Label(
            header,
            text="2.4\" ST7789 Dokunmatik Ekran Modülü (ESP32-C3) — Otomatik Port Tespiti, Sürümleme ve USB Yükleme",
            style="Sub.TLabel",
        ).grid(row=1, column=0, sticky="w", pady=(2, 0))

        # 2. Sol Kart: Port Tespiti & Sürüm & Yükleme
        left = ttk.Frame(main, style="Card.TFrame", padding=14)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 8))
        left.columnconfigure(0, weight=1)

        # Donanım Port Tespiti
        ttk.Label(left, text="1. Ekran Donanımı Tespiti (Port)", style="Head.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 6)
        )
        port_frame = ttk.Frame(left, style="Card.TFrame")
        port_frame.grid(row=1, column=0, sticky="ew", pady=(0, 6))
        port_frame.columnconfigure(0, weight=1)

        self.port_combo = ttk.Combobox(port_frame, textvariable=self.port_var, state="readonly", width=18)
        self.port_combo.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self.port_combo.bind("<<ComboboxSelected>>", self._on_port_changed)

        self.find_btn = ttk.Button(
            port_frame,
            text="🔍 Ekranı Bul",
            command=self.find_screen,
            style="Accent.TButton",
        )
        self.find_btn.grid(row=0, column=1, padx=(0, 6))

        self.connect_btn = ttk.Button(
            port_frame,
            text="🔌 Bağlan",
            command=self.toggle_serial,
            style="Soft.TButton",
        )
        self.connect_btn.grid(row=0, column=2)

        ttk.Label(left, textvariable=self.detected_screen_var, style="Status.TLabel").grid(
            row=2, column=0, sticky="w", pady=(0, 10)
        )

        ttk.Separator(left, orient=tk.HORIZONTAL).grid(row=3, column=0, sticky="ew", pady=8)

        # Sürüm Yönetimi
        ttk.Label(left, text="2. Sürüm ve PlatformIO Derleme", style="Head.TLabel").grid(
            row=4, column=0, sticky="w", pady=(0, 6)
        )
        target_info = ttk.Label(
            left,
            text=f"Hedef: {DISPLAY_TARGET} (Ortam: {DISPLAY_ENV})",
            style="Text.TLabel",
        )
        target_info.grid(row=5, column=0, sticky="w", pady=(0, 6))

        v_frame = ttk.Frame(left, style="Card.TFrame")
        v_frame.grid(row=6, column=0, sticky="ew", pady=(0, 8))
        v_frame.columnconfigure(1, weight=1)
        ttk.Label(v_frame, text="Sürüm No:", style="Text.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 8))
        self.version_entry = ttk.Entry(v_frame, textvariable=self.version_var, width=15)
        self.version_entry.grid(row=0, column=1, sticky="w")

        btn_row = ttk.Frame(left, style="Card.TFrame")
        btn_row.grid(row=7, column=0, sticky="ew", pady=(0, 8))
        self.build_btn = ttk.Button(
            btn_row,
            text="🔨 Firmware Derle",
            command=self.start_build,
            style="Soft.TButton",
        )
        self.build_btn.pack(side=tk.LEFT)

        self.release_btn = ttk.Button(
            btn_row,
            text="📦 Sürüm Oluştur (Release)",
            command=self.start_release,
            style="Accent.TButton",
        )
        self.release_btn.pack(side=tk.LEFT, padx=(8, 0))

        ttk.Label(left, textvariable=self.latest_release_var, style="Text.TLabel", wraplength=460).grid(
            row=8, column=0, sticky="w", pady=(0, 8)
        )

        ttk.Separator(left, orient=tk.HORIZONTAL).grid(row=9, column=0, sticky="ew", pady=8)

        # USB Yükleme
        ttk.Label(left, text="3. USB ile Ekrana Yükle (Flaşlama)", style="Head.TLabel").grid(
            row=10, column=0, sticky="w", pady=(0, 6)
        )
        self.upload_btn = ttk.Button(
            left,
            text="⚡ Sürümü USB ile Ekrana Yükle",
            command=self.start_upload,
            style="Accent.TButton",
        )
        self.upload_btn.grid(row=11, column=0, sticky="ew", pady=(0, 8))

        p_frame = ttk.Frame(left, style="Card.TFrame")
        p_frame.grid(row=12, column=0, sticky="ew", pady=(0, 6))
        p_frame.columnconfigure(0, weight=1)
        self.pbar = ttk.Progressbar(
            p_frame,
            orient="horizontal",
            mode="determinate",
            maximum=100,
            variable=self.progress_var,
            style="Accent.Horizontal.TProgressbar",
        )
        self.pbar.grid(row=0, column=0, sticky="ew")
        ttk.Label(p_frame, textvariable=self.progress_text_var, style="Text.TLabel").grid(
            row=0, column=1, sticky="e", padx=(8, 0)
        )

        ttk.Label(left, textvariable=self.status_var, style="Status.TLabel").grid(
            row=13, column=0, sticky="w", pady=(4, 0)
        )
        ttk.Label(
            left,
            text="ESP32-C3 doğrudan USB CDC veya CH340 üzerinden 460800 baud hızında flash belleğe yazılır.",
            style="Text.TLabel",
            wraplength=460,
        ).grid(row=14, column=0, sticky="w", pady=(6, 0))

        # 3. Sağ Kart: Canlı Testler & Log Konsolu
        right = ttk.Frame(main, style="Card.TFrame", padding=14)
        right.grid(row=1, column=1, sticky="nsew", padx=(8, 0))
        right.columnconfigure(0, weight=1)
        right.rowconfigure(2, weight=1)

        ttk.Label(right, text="Ekran Canlı Test Komutları", style="Head.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 8)
        )
        t_row = ttk.Frame(right, style="Card.TFrame")
        t_row.grid(row=1, column=0, sticky="ew", pady=(0, 10))

        ttk.Button(t_row, text="📡 Ping", command=lambda: self.send_command("DISP_PING"), style="Soft.TButton").pack(
            side=tk.LEFT
        )
        ttk.Button(
            t_row,
            text="📷 Test QR",
            command=lambda: self.send_command("SHOW_QR|AHBU:DOOR:00861A0D5020"),
            style="Soft.TButton",
        ).pack(side=tk.LEFT, padx=4)
        ttk.Button(
            t_row,
            text="🚪 Kapı Açıldı",
            command=lambda: self.send_command("DOOR_OPENED"),
            style="Soft.TButton",
        ).pack(side=tk.LEFT, padx=4)
        ttk.Button(
            t_row,
            text="⚙️ Ayarlar",
            command=lambda: self.send_command("SHOW_SETTINGS"),
            style="Soft.TButton",
        ).pack(side=tk.LEFT, padx=4)
        ttk.Button(
            t_row,
            text="🏠 Ana Ekran",
            command=lambda: self.send_command("SHOW_HOME"),
            style="Soft.TButton",
        ).pack(side=tk.LEFT, padx=4)
        ttk.Button(
            t_row,
            text="🔄 Reset",
            command=self.reset_screen,
            style="Danger.TButton",
        ).pack(side=tk.LEFT, padx=4)

        # Log Konsolu
        log_header = ttk.Frame(right, style="Card.TFrame")
        log_header.grid(row=2, column=0, sticky="ew", pady=(4, 6))
        log_header.columnconfigure(0, weight=1)
        ttk.Label(log_header, text="Ekran Seri Logu (115200 baud)", style="Head.TLabel").grid(
            row=0, column=0, sticky="w"
        )
        ttk.Button(
            log_header,
            text="Temizle",
            command=self.clear_log,
            style="Soft.TButton",
        ).grid(row=0, column=1, sticky="e")

        log_box_frame = ttk.Frame(right, style="Card.TFrame")
        log_box_frame.grid(row=3, column=0, sticky="nsew")
        log_box_frame.columnconfigure(0, weight=1)
        log_box_frame.rowconfigure(0, weight=1)

        self.log_text = tk.Text(
            log_box_frame,
            height=20,
            bg="#07111F",
            fg="#D6E8FF",
            insertbackground="#D6E8FF",
            relief=tk.FLAT,
            font=("Consolas", 9),
        )
        self.log_text.grid(row=0, column=0, sticky="nsew")
        sc = ttk.Scrollbar(log_box_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        sc.grid(row=0, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=sc.set)

    def refresh_latest_release(self) -> None:
        releases = load_display_releases()
        if not releases:
            self.latest_release_var.set("Henüz sürüm yok. 'Sürüm Oluştur' ile ilk paketi derleyin.")
            return
        releases.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        last = releases[0]
        v = last.get("version", "?")
        created = last.get("created_at", "")[:19].replace("T", " ")
        self.latest_release_var.set(f"Son Sürüm: v{v} (Oluşturulma: {created})")

    def find_screen(self) -> None:
        if self.scanning:
            return
        self.scanning = True
        self.find_btn.configure(state=tk.DISABLED)
        self.detected_screen_var.set("🔍 Bağlı portlar taranıyor...")
        self.status_var.set("Portlar taranıyor...")
        threading.Thread(target=self._find_screen_worker, daemon=True).start()

    def _find_screen_worker(self) -> None:
        ports = list(list_ports.comports())
        port_names = [p.device for p in ports]
        detected_port = None
        detected_info = ""

        # 1. Önce doğrudan USB seri port üzerinden ping ile ekran yazılımı tespiti dene
        for p in ports:
            p_name = p.device
            if self.worker is not None and self.worker.port == p_name:
                detected_port = p_name
                detected_info = f"✅ {p_name} (Şu anda bağlı ekran)"
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
                        detected_info = f"✅ {p_name} (AHBU 2.4\" Ekran Aktif)"
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
                        detected_info = f"💡 {p_name} (ESP32-C3 Ekran Modülü Tespit Edildi)"
                        break
                except Exception:
                    pass

        self.window.after(0, lambda: self._finish_find_screen(port_names, detected_port, detected_info))

    def _finish_find_screen(self, port_names: list[str], detected_port: str | None, detected_info: str) -> None:
        self.scanning = False
        self.find_btn.configure(state=tk.NORMAL)
        self.ports = port_names
        self.port_combo.configure(values=port_names)

        if detected_port:
            self.port_var.set(detected_port)
            self.detected_screen_var.set(detected_info)
            self.status_var.set(f"Ekran bulundu: {detected_port}")
            self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] {detected_info}")
        elif port_names:
            if not self.port_var.get() or self.port_var.get() not in port_names:
                self.port_var.set(port_names[0])
            self.detected_screen_var.set(f"⚠️ Otomatik doğrulanamadı. Seçili port: {self.port_var.get()}")
            self.status_var.set("Ekran otomatik doğrulanamadı, listeden seçebilirsiniz.")
        else:
            self.port_var.set("")
            self.detected_screen_var.set("❌ Bağlı COM port bulunamadı.")
            self.status_var.set("Bağlı COM port bulunamadı.")

    def _on_port_changed(self, _event: object) -> None:
        p = self.port_var.get().strip()
        if p:
            self.detected_screen_var.set(f"Seçili port: {p}")
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
            self.connect_btn.configure(text="🔌 Bağlantıyı Kes")
            self.connected_var.set(f"Bağlı: {port}")
            self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] {port} portuna 115200 baud ile bağlanıldı.")
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
        self.connect_btn.configure(text="🔌 Bağlan")
        self.connected_var.set("Bağlı değil")
        self._append_log(f"[{datetime.now().strftime('%H:%M:%S')}] Seri port bağlantısı kapatıldı.")

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
        self.log_text.delete("1.0", tk.END)

    def _drain_lines(self) -> None:
        while True:
            try:
                line = self.line_queue.get_nowait()
                self._append_log(line)
            except queue.Empty:
                break
        self.window.after(100, self._drain_lines)

    def _append_log(self, text: str) -> None:
        self.log_text.insert(tk.END, f"{text}\n")
        self.log_text.see(tk.END)

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
            self.window.after(0, lambda: messagebox.showinfo("Başarılı", f"Ekran firmware v{version} derlendi.", parent=self.window))
        except Exception as exc:
            self.fw_build_ready = False
            self.window.after(0, lambda: self.status_var.set("Derleme başarısız."))
            self.window.after(0, lambda: messagebox.showerror("Derleme Hatası", str(exc), parent=self.window))
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
            self.window.after(0, lambda: messagebox.showinfo(
                "Sürüm Hazır",
                f"Ekran Yazılımı v{version} sürüm paketi oluşturuldu:\n\n{folder}",
                parent=self.window,
            ))
        except Exception as exc:
            self.fw_release_ready = False
            self.window.after(0, lambda: self.status_var.set("Sürüm oluşturma başarısız."))
            self.window.after(0, lambda: messagebox.showerror("Sürüm Hatası", str(exc), parent=self.window))
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
            self.window.after(0, lambda: self.status_var.set(f"✅ Yükleme Başarılı: v{rel.get('version')}"))
            self.window.after(0, lambda: messagebox.showinfo(
                "TMM - Yükleme Başarılı",
                f"Ekran yazılımı v{rel.get('version')} {port} portuna başarıyla yüklendi!\n\nCihaz donanımsal olarak yeniden başlatıldı.",
                parent=self.window,
            ))
            # Otomatik seri konsolu bağla
            self.window.after(1000, self.connect_serial)
        except Exception as exc:
            self.window.after(0, lambda: self.status_var.set("Yükleme başarısız."))
            self.window.after(0, lambda: messagebox.showerror("Yükleme Hatası", str(exc), parent=self.window))
        finally:
            self.fw_busy = False
            self.window.after(0, self._restore_buttons)

    def _restore_buttons(self) -> None:
        self.build_btn.configure(state=tk.NORMAL)
        self.release_btn.configure(state=tk.NORMAL)
        self.upload_btn.configure(state=tk.NORMAL)

    def _on_close(self) -> None:
        if self.worker is not None:
            try:
                self.worker.stop()
            except Exception:
                pass
        self.window.destroy()


def main() -> None:
    app = App()
    app.run()


if __name__ == "__main__":
    main()

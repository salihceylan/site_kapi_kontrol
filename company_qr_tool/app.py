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
LOCAL_SERVER_FIRMWARE_DIR = (BASE_DIR / ".." / "server" / "firmware" / "esp32-c3").resolve()
VPS_HOST = "178.210.161.55"
VPS_PORT = "22667"
VPS_USER = "salihceylan"
VPS_FIRMWARE_DIR = "/var/www/site_kapi_kontrol/server/firmware/esp32-c3"
VPS_LABELED_DEVICES_DIR = "/var/www/site_kapi_kontrol/server/data"
VPS_QRCODES_DIR = "/var/www/site_kapi_kontrol/server/public/qrcodes"
PUBLIC_API_URL = "https://api.gudeteknoloji.com.tr"
PUBLIC_FIRMWARE_MANIFEST_URL = "https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json"
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
OTA_VERSION_RE = re.compile(r'OTA_CURRENT_VERSION\[\]\s*=\s*"(\d+\.\d+\.\d+)"')
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
        self._write_queue.put(text)

    def _run(self) -> None:
        try:
            self._serial = serial.Serial(self.port, self.baud_rate, timeout=0.2)
            time.sleep(0.2)
            self.on_line(f"[baglandi] {self.port} @ {self.baud_rate}")
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


def fetch_server_labeled_devices() -> list[dict]:
    url = f"{PUBLIC_API_URL}/api/company/labeled-devices"
    req = urllib.request.Request(url, headers={"User-Agent": "AHBU-Device-Tool/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            if response.status == 200:
                data = json.loads(response.read().decode("utf-8"))
                if isinstance(data, dict) and isinstance(data.get("devices"), list):
                    return data["devices"]
    except Exception:
        pass
    return []


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
    py_exe = find_esptool_python()
    cmd = [py_exe, "-m", "esptool", "--port", port, "read_mac"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=20, check=False)
    text = f"{out.stdout}\n{out.stderr}"
    mm = MAC_RE.search(text)
    cm = CHIP_RE.search(text)
    if mm:
        chip = cm.group(1).strip() if cm else "ESP32"
        return chip, mac_to_firmware_uid(mm.group(1))
    lines = [x.strip() for x in text.splitlines() if x.strip()]
    raise RuntimeError(lines[-1] if lines else "Cihaz kimligi okunamadi.")


def parse_envs(path: Path) -> tuple[list[str], dict[str, int]]:
    if not path.exists():
        return [], {}
    envs: list[str] = []
    speeds: dict[str, int] = {}
    current: str | None = None
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        em = ENV_RE.match(line)
        if em:
            current = em.group(1).strip()
            envs.append(current)
            continue
        if current is None:
            continue
        um = UPL_RE.match(line)
        if um:
            speeds[current] = int(um.group(1))
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


def read_firmware_source_version() -> str | None:
    header = DEVICE_PROJECT_DIR / "include" / "ota_guncelleme.h"
    try:
        text = header.read_text(encoding="utf-8")
    except Exception:
        return None
    match = OTA_VERSION_RE.search(text)
    return match.group(1) if match else None


def write_firmware_source_version(version: str) -> bool:
    header = DEVICE_PROJECT_DIR / "include" / "ota_guncelleme.h"
    try:
        text = header.read_text(encoding="utf-8")
        if OTA_VERSION_RE.search(text):
            updated = OTA_VERSION_RE.sub(f'OTA_CURRENT_VERSION[] = "{version}"', text)
            header.write_text(updated, encoding="utf-8")
            return True
    except Exception:
        pass
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


def suggest_version(releases: list[dict]) -> str:
    versions: list[tuple[int, int, int]] = []
    for r in releases:
        v = str(r.get("version", "")).strip()
        if SEMVER_RE.match(v):
            a, b, c = v.split(".")
            versions.append((int(a), int(b), int(c)))
    if not versions:
        return "1.0.0"
    a, b, c = sorted(versions)[-1]
    return f"{a}.{b}.{c + 1}"


def suggest_env_for_chip(chip: str, envs: list[str]) -> str | None:
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
        self.version_var = tk.StringVar(value=read_firmware_source_version() or suggest_version(self.releases))
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

        threading.Thread(target=self._server_device_save_worker, args=(d, payload), daemon=True).start()

    def _server_device_save_worker(self, dev: EspDevice, payload: dict) -> None:
        success = False
        error_msg = None

        api_endpoints = [
            f"{PUBLIC_API_URL}/api/company/labeled-devices",
            f"http://{VPS_HOST}:3000/api/company/labeled-devices",
        ]

        data_bytes = json.dumps(payload).encode("utf-8")

        for endpoint in api_endpoints:
            try:
                req = urllib.request.Request(
                    endpoint,
                    data=data_bytes,
                    headers={
                        "Content-Type": "application/json",
                        "User-Agent": "AHBU-Device-Tool/1.0",
                    },
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    if resp.status == 200:
                        success = True
                        break
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
        server_devices = fetch_server_labeled_devices()
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
        self.refresh_latest_release()
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
        write_firmware_source_version(version)
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
        write_firmware_source_version(version)
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

            ota_manifest = {
                "enabled": True,
                "version": version,
                "filename": "firmware.bin",
                "force": True,
                "usb_required": False,
                "partition_scheme": "ota_4mb_littlefs_v1",
                "interval_hours": 1,
                "allowed_uids": [],
                "sha256": hashes["firmware_bin"]["sha256"],
                "md5": hashes["firmware_bin"]["md5"],
                "notes": f"AHBU firmware v{version}.",
            }
            manifest_path = folder / "manifest.json"
            manifest_path.write_text(json.dumps(ota_manifest, ensure_ascii=False, indent=2), encoding="utf-8")

            entry = {
                "id": folder.name,
                "version": version,
                "env": env,
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
            self.root.after(0, lambda: self.version_var.set(read_firmware_source_version() or suggest_version(self.releases)))
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

            speed = int(self.upload_speeds.get(rel["env"], 921600))
            boot, part, firm, _manifest = self._release_file_paths(rel)
            for p in (boot, part, firm):
                if not p.exists():
                    raise FileNotFoundError(f"Firmware dosyasi yok: {p}")

            py_exe = find_esptool_python()
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
                "write_flash",
                "-z",
                "0x0",
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
                if "PermissionError" in raw_err or "port is busy" in raw_err.lower() or "Erişim engellendi" in raw_err:
                    raise RuntimeError(
                        f"{dev.port} portu meşgul (Erişim engellendi).\n\n"
                        "Çözüm Adımları:\n"
                        "1. 'Cihaz Dene' penceresi açıksa 'Bağlantıyı Kes' butonuna basın.\n"
                        "2. VS Code Seri Monitörü açıksa terminaldeki çöp kutusu simgesinden kapatın.\n"
                        "3. Cihazı USB'den çıkarıp tekrar takın."
                    )
                raise RuntimeError(raw_err)

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
        password = os.environ.get("AHBU_VPS_PASSWORD", "").strip()
        if not password:
            password = simpledialog.askstring(
                "VPS sifresi",
                f"{VPS_USER}@{VPS_HOST} icin VPS sifresini girin:",
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

            LOCAL_SERVER_FIRMWARE_DIR.mkdir(parents=True, exist_ok=True)
            local_firm = LOCAL_SERVER_FIRMWARE_DIR / "firmware.bin"
            local_manifest = LOCAL_SERVER_FIRMWARE_DIR / "manifest.json"
            shutil.copy2(firm, local_firm)
            shutil.copy2(manifest, local_manifest)

            self.root.after(0, lambda: self.set_status("VPS sunucusuna baglaniliyor (SFTP)..."))
            self.root.after(0, lambda: self.progress_var.set(20))
            self.root.after(0, lambda: self.progress_text_var.set("%20"))

            import paramiko
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                VPS_HOST,
                port=int(VPS_PORT),
                username=VPS_USER,
                password=password,
                timeout=12,
            )

            sftp = client.open_sftp()
            self.root.after(0, lambda: self.set_status("firmware.bin sunucuya gonderiliyor..."))
            self.root.after(0, lambda: self.progress_var.set(50))
            self.root.after(0, lambda: self.progress_text_var.set("%50"))
            sftp.put(str(local_firm), f"{VPS_FIRMWARE_DIR}/firmware.bin")

            self.root.after(0, lambda: self.set_status("manifest.json sunucuya gonderiliyor..."))
            self.root.after(0, lambda: self.progress_var.set(80))
            self.root.after(0, lambda: self.progress_text_var.set("%80"))
            sftp.put(str(local_manifest), f"{VPS_FIRMWARE_DIR}/manifest.json")
            sftp.close()
            client.close()

            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.progress_text_var.set("%100"))
            self.root.after(0, lambda: self.set_status(f"TMM: v{rel['version']} guncelleme dosyasi sunucuya gonderildi."))
            self.root.after(
                0,
                lambda: messagebox.showinfo(
                    "TMM",
                    f"Firmware guncelleme paketi sunucuya basariyla gonderildi!\n\n"
                    f"Surum: v{rel['version']}\n"
                    f"Sunucu: {VPS_HOST}\n\n"
                    "Sahadaki tum cihazlar bu surumu OTA uzerinden otomatik olarak indirecektir.",
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
  echo ESP32 COM portu otomatik araniyor...
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
%PYEXE% -m esptool --chip auto --port "%PORT%" --baud {speed} --before default_reset --after hard_reset write_flash -z 0x0 firmware\\bootloader.bin 0x8000 firmware\\partitions.bin 0x10000 firmware\\firmware.bin
if errorlevel 1 (
  echo.
  echo Yukleme basarisiz oldu.
  pause
  exit /b 1
)
echo.
echo AHBU firmware yukleme tamamlandi. Surum: v{version}
pause
"""
            readme = f"""AHBU cihaz USB guncelleme paketi

Surum: v{version}
PlatformIO env: {env}

Kullanim:
1. ZIP dosyasini bir klasore cikarin.
2. ESP32 C3 cihazi USB ile bilgisayara baglayin.
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
        self.window.minsize(980, 640)
        self.logo_path = logo_path
        self.on_download_pdf = on_download_pdf

        self.devices: list[dict] = []
        self.selected_qr: Image.Image | None = None
        self.preview_photo: ImageTk.PhotoImage | None = None

        self.status_var = tk.StringVar(value="Cihazlar yükleniyor...")
        self.selected_uid_var = tk.StringVar(value="Seçili Cihaz: -")

        self._ui()
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

        # Left: Devices list
        left = ttk.Frame(main, style="Card.TFrame", padding=14)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(1, weight=1)

        btn_row = ttk.Frame(left, style="Card.TFrame")
        btn_row.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(btn_row, text="Sunucudan / Yerelden Yenile", command=self.refresh_devices, style="Accent.TButton").pack(side=tk.LEFT)
        ttk.Button(btn_row, text="Karekodlu PDF İndir", command=self.on_download_pdf, style="Accent.TButton").pack(side=tk.LEFT, padx=(8, 0))

        cols = ("device_uid", "chip", "created_at", "description")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", height=16)
        self.tree.heading("device_uid", text="Cihaz Unique ID")
        self.tree.heading("chip", text="Çip Modeli")
        self.tree.heading("created_at", text="Kayıt Tarihi")
        self.tree.heading("description", text="Açıklama")
        self.tree.column("device_uid", width=180, anchor=tk.CENTER)
        self.tree.column("chip", width=120, anchor=tk.CENTER)
        self.tree.column("created_at", width=160, anchor=tk.CENTER)
        self.tree.column("description", width=220, anchor=tk.W)
        self.tree.grid(row=1, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self._on_select)

        sc = ttk.Scrollbar(left, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=sc.set)
        sc.grid(row=1, column=1, sticky="ns")

        ttk.Label(left, textvariable=self.status_var, style="Status.TLabel").grid(row=2, column=0, sticky="w", pady=(8, 0))

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
        ttk.Button(qr_actions, text="Karekodu Yazdır", command=self._print_selected_qr, style="Soft.TButton").pack(side=tk.LEFT)
        ttk.Button(qr_actions, text="Karekodu Kaydet", command=self._save_selected_qr, style="Soft.TButton").pack(side=tk.LEFT, padx=(8, 0))

    def refresh_devices(self) -> None:
        self.status_var.set("Cihazlar güncelleniyor...")
        threading.Thread(target=self._fetch_worker, daemon=True).start()

    def _fetch_worker(self) -> None:
        server_devices = fetch_server_labeled_devices()
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
        self.window.after(0, self._apply_devices_list)

    def _apply_devices_list(self) -> None:
        for x in self.tree.get_children():
            self.tree.delete(x)
        for i, d in enumerate(self.devices):
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

        self.status_var.set(f"Toplam {len(self.devices)} kayıtlı cihaz listelendi.")
        if self.devices:
            self.tree.selection_set("0")
            self._show_device_preview(self.devices[0])

    def _on_select(self, _event: object) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        if 0 <= idx < len(self.devices):
            self._show_device_preview(self.devices[idx])

    def _show_device_preview(self, dev: dict) -> None:
        uid = str(dev.get("device_uid", "")).upper()
        self.selected_uid_var.set(f"Seçili: {uid}")
        qr_img = generate_qr(uid, self.logo_path)
        self.selected_qr = qr_img
        prev = qr_img.copy()
        prev.thumbnail((PREVIEW_SIZE, PREVIEW_SIZE), Image.Resampling.LANCZOS)
        self.preview_photo = ImageTk.PhotoImage(prev)
        self.preview_label.configure(image=self.preview_photo)

    def _print_selected_qr(self) -> None:
        if self.selected_qr is None:
            messagebox.showinfo("Seçim gerekli", "Lütfen bir cihaz seçin.")
            return
        if os.name != "nt":
            messagebox.showerror("Yazdırma", "Yalnızca Windows işletim sisteminde desteklenir.")
            return
        sel = self.tree.selection()
        uid = self.devices[int(sel[0])].get("device_uid", "device") if sel else "device"
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        path = OUTPUT_DIR / f"print_{sanitize_filename(uid)}.png"
        self.selected_qr.save(path, format="PNG")
        os.startfile(str(path), "print")
        self.status_var.set(f"Yazdırmaya gönderildi: {path.name}")

    def _save_selected_qr(self) -> None:
        if self.selected_qr is None:
            messagebox.showinfo("Seçim gerekli", "Lütfen bir cihaz seçin.")
            return
        sel = self.tree.selection()
        uid = self.devices[int(sel[0])].get("device_uid", "device") if sel else "device"
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        path = OUTPUT_DIR / f"{sanitize_filename(uid)}.png"
        self.selected_qr.save(path, format="PNG")
        messagebox.showinfo("Kaydedildi", f"Karekod kaydedildi:\n{path}")


class DeviceTesterWindow:
    STATUS_START = "----- CIHAZ DURUMU -----"
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

        self.port_var = tk.StringVar()
        self.connection_var = tk.StringVar(value="Bagli degil")
        self.last_command_var = tk.StringVar(value="-")
        self.status_vars: dict[str, tk.StringVar] = {}

        self._ui()
        self.refresh_ports()
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
            "Firmware surumu",
            "OTA durum",
            "WiFi kayitli",
            "WiFi SSID",
            "WiFi bagli",
            "WiFi IP",
            "WiFi gucu",
            "Bluetooth provisioning",
            "Bluetooth adi",
            "WiFi LED GPIO",
            "Bluetooth LED GPIO",
            "MQTT",
            "MQTT kimligi",
            "MQTT sunucu",
            "Role GPIO",
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
        ttk.Button(tools, text="Pin Bulma Testi", command=lambda: self.send_command("p"), style="Soft.TButton").grid(row=4, column=0, sticky="ew", pady=4)
        ttk.Separator(tools).grid(row=5, column=0, sticky="ew", pady=12)
        ttk.Label(tools, text="Son Komut", style="Head.TLabel").grid(row=6, column=0, sticky="w")
        ttk.Label(tools, textvariable=self.last_command_var, style="Value.TLabel").grid(row=7, column=0, sticky="w", pady=(4, 12))
        ttk.Label(
            tools,
            text="Cihaz seri porttan durum bloğu yazdığında bilgiler otomatik güncellenir. Role test komutlari: h=HIGH, l=LOW, r=pulse, p=pin bulma.",
            style="Text.TLabel",
            wraplength=330,
        ).grid(row=8, column=0, sticky="ew")

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

        if line == self.STATUS_START:
            self._collecting_status = True
            self._status_lines = []
            return
        if line == self.STATUS_END and self._collecting_status:
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
        self.status.values = values
        for key, var in self.status_vars.items():
            if key in values:
                var.set(values[key])
        role_line = next((line for line in lines if line.startswith("Role pin okuma GPIO")), None)
        if role_line:
            self.status_vars["Role pin okuma"].set(role_line.replace("Role pin okuma ", ""))

    def _append_log(self, line: str) -> None:
        self.log_text.insert(tk.END, f"{line}\n")
        self.log_text.see(tk.END)

    def _on_close(self) -> None:
        if self.worker is not None:
            self.worker.stop()
        self.window.destroy()


def main() -> None:
    app = App()
    app.run()


if __name__ == "__main__":
    main()

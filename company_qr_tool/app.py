from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, ttk

import qrcode
from PIL import Image, ImageDraw, ImageOps, ImageTk
from serial.tools import list_ports

BASE_DIR = Path(__file__).resolve().parent
ASSETS_DIR = BASE_DIR / "assets"
OUTPUT_DIR = BASE_DIR / "output"
LOGO_PATH = ASSETS_DIR / "ahbu_logo.png"
EXTERNAL_LOGO_PATH = (BASE_DIR / ".." / ".." / "ahbu" / "assets" / "images" / "app_logo.png").resolve()

DEVICE_PROJECT_DIR = (BASE_DIR / ".." / "cihaz_kontrol").resolve()
PLATFORMIO_INI_PATH = DEVICE_PROJECT_DIR / "platformio.ini"
BUILD_DIR = DEVICE_PROJECT_DIR / ".pio" / "build"
RELEASES_DIR = DEVICE_PROJECT_DIR / "firmware_releases"
RELEASE_INDEX = RELEASES_DIR / "index.json"

MAC_RE = re.compile(r"MAC:\s*([0-9A-Fa-f:]{17})")
CHIP_RE = re.compile(r"Chip is\s+([^\r\n]+)")
ENV_RE = re.compile(r"^\s*\[env:([^\]]+)\]")
UPL_RE = re.compile(r"^\s*upload_speed\s*=\s*(\d+)")
PROG_RE = re.compile(r"\((\d{1,3})\s*%\)")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
PREVIEW_SIZE = 180

CLR_APP_BG = "#EFF9F3"
CLR_CARD_BG = "#FFFFFF"
CLR_ACCENT = "#14A44D"
CLR_ACCENT_DARK = "#0D7F3B"
CLR_ACCENT_SOFT = "#E9F8EF"
CLR_BORDER = "#D2E8DB"
CLR_TEXT_MAIN = "#0C2318"
CLR_TEXT_SUB = "#4D6A5A"
CLR_STATUS = "#117C48"
CLR_ROW_SEL_BG = "#CEF3DD"
CLR_ROW_SEL_TEXT = "#0B2E1D"


@dataclass
class EspDevice:
    port: str
    description: str
    chip: str
    unique_id: str


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


def trim_image(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    bbox = rgba.getbbox()
    return rgba if bbox is None else rgba.crop(bbox)


def generate_qr(unique_id: str, logo_path: Path) -> Image.Image:
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_H,
        box_size=20,
        border=2,
    )
    qr.add_data(unique_id.strip().upper())
    qr.make(fit=True)
    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGBA")
    qr_img = qr_img.resize((1200, 1200), Image.Resampling.LANCZOS)

    logo = trim_image(Image.open(logo_path))
    logo = ImageOps.contain(logo, (264, 264), Image.Resampling.LANCZOS)

    badge = Image.new("RGBA", (322, 322), (255, 255, 255, 0))
    draw = ImageDraw.Draw(badge)
    draw.ellipse((0, 0, 321, 321), fill=(255, 255, 255, 245))
    badge.alpha_composite(logo, ((322 - logo.width) // 2, (322 - logo.height) // 2))
    qr_img.alpha_composite(badge, ((1200 - 322) // 2, (1200 - 322) // 2))
    return qr_img


def find_platformio() -> str:
    exe = shutil.which("platformio")
    if exe:
        return exe
    candidate = Path.home() / ".platformio" / "penv" / "Scripts" / "platformio.exe"
    if candidate.exists():
        return str(candidate)
    raise FileNotFoundError("PlatformIO bulunamadi.")


def read_mac(port: str) -> tuple[str, str]:
    cmd = [sys.executable, "-m", "esptool", "--port", port, "read_mac"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=20, check=False)
    text = f"{out.stdout}\n{out.stderr}"
    mm = MAC_RE.search(text)
    cm = CHIP_RE.search(text)
    if mm:
        chip = cm.group(1).strip() if cm else "ESP32"
        return chip, mm.group(1).upper()
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


class App:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("AHBU Cihaz Etiketleyici")
        self.root.geometry("1100x760")
        self.root.resizable(False, False)
        self.root.configure(bg=CLR_APP_BG)

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
        self.env_var = tk.StringVar(value=self.envs[0] if self.envs else "esp32-s3-devkitc-1")
        self.version_var = tk.StringVar(value=suggest_version(self.releases))
        self.latest_release_var = tk.StringVar(value="Son surum: -")
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_text_var = tk.StringVar(value="%0")

        self.scanning = False
        self.fw_busy = False

        self._style()
        self.brand_photo = self._load_brand(64)
        self.icon_photo = self._load_brand(32)
        if self.icon_photo is not None:
            self.root.iconphoto(True, self.icon_photo)

        self._ui()
        self.refresh_latest_release()

    def _style(self) -> None:
        s = ttk.Style(self.root)
        if "clam" in s.theme_names():
            s.theme_use("clam")
        elif s.theme_names():
            s.theme_use(s.theme_names()[0])

        s.configure("App.TFrame", background=CLR_APP_BG)
        s.configure("Card.TFrame", background=CLR_CARD_BG, borderwidth=1, relief="solid")
        s.configure("Card.TLabel", background=CLR_CARD_BG)
        s.configure("Title.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_MAIN, font=("Segoe UI", 17, "bold"))
        s.configure("Sub.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_SUB, font=("Segoe UI", 10))
        s.configure("Head.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_MAIN, font=("Segoe UI", 11, "bold"))
        s.configure("Text.TLabel", background=CLR_CARD_BG, foreground=CLR_TEXT_SUB, font=("Segoe UI", 10))
        s.configure("Status.TLabel", background=CLR_CARD_BG, foreground=CLR_STATUS, font=("Segoe UI", 10, "bold"))

        s.configure(
            "Accent.TButton",
            background=CLR_ACCENT,
            foreground="#FFFFFF",
            borderwidth=0,
            focusthickness=0,
            focuscolor=CLR_ACCENT,
            padding=(12, 7),
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
            borderwidth=1,
            focusthickness=0,
            focuscolor=CLR_ACCENT_SOFT,
            padding=(12, 7),
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
        s.map("TCombobox", fieldbackground=[("readonly", CLR_CARD_BG)], selectbackground=[("readonly", CLR_CARD_BG)])

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
            background="#F2FAF5",
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
        main = ttk.Frame(self.root, style="App.TFrame", padding=14)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=3)
        main.columnconfigure(1, weight=2)
        main.rowconfigure(1, weight=1)

        header = ttk.Frame(main, style="Card.TFrame", padding=(12, 10))
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))
        header.columnconfigure(1, weight=1)
        hlogo = ttk.Label(header, image=self.brand_photo, style="Card.TLabel")
        hlogo.grid(row=0, column=0, rowspan=2, sticky="w")
        hlogo.image = self.brand_photo
        ttk.Label(header, text="AHBU Cihaz Etiketleyici", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(10, 0))
        ttk.Label(header, text="ID oku, QR uret, firmware surumle ve cihaza yukle.", style="Sub.TLabel").grid(row=1, column=1, sticky="w", padx=(10, 0))

        left = ttk.Frame(main, style="Card.TFrame", padding=12)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 10))
        left.rowconfigure(2, weight=1)
        left.columnconfigure(0, weight=1)

        row = ttk.Frame(left, style="Card.TFrame")
        row.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        self.scan_btn = ttk.Button(row, text="Bagli cihazlari tara", command=self.scan_devices, style="Accent.TButton")
        self.scan_btn.pack(side=tk.LEFT)
        self.qr_btn = ttk.Button(row, text="Secili cihaz icin QR olustur", command=self.make_qr, style="Accent.TButton")
        self.qr_btn.pack(side=tk.LEFT, padx=8)
        self.save_btn = ttk.Button(row, text="QR kaydet", command=self.save_qr, style="Soft.TButton")
        self.save_btn.pack(side=tk.LEFT)
        self.print_btn = ttk.Button(row, text="QR yazdir", command=self.print_qr, style="Soft.TButton")
        self.print_btn.pack(side=tk.LEFT, padx=(8, 0))

        ttk.Label(left, text="Bagli Cihazlar", style="Head.TLabel").grid(row=1, column=0, sticky="w", pady=(0, 6))
        cols = ("port", "chip", "unique_id", "description")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", height=18)
        self.tree.heading("port", text="Port")
        self.tree.heading("chip", text="Chip")
        self.tree.heading("unique_id", text="Unique ID")
        self.tree.heading("description", text="Aygit Aciklamasi")
        self.tree.column("port", width=90, anchor=tk.CENTER)
        self.tree.column("chip", width=170, anchor=tk.W)
        self.tree.column("unique_id", width=180, anchor=tk.CENTER)
        self.tree.column("description", width=320, anchor=tk.W)
        self.tree.grid(row=2, column=0, sticky="nsew")
        self.tree.bind("<<TreeviewSelect>>", self.on_select)
        sc = ttk.Scrollbar(left, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=sc.set)
        sc.grid(row=2, column=1, sticky="ns")
        ttk.Label(left, textvariable=self.status_var, style="Status.TLabel").grid(row=3, column=0, sticky="w", pady=(8, 0))

        right = ttk.Frame(main, style="Card.TFrame", padding=12)
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
        self.env_combo = ttk.Combobox(form, state="readonly", values=self.envs, textvariable=self.env_var)
        self.env_combo.grid(row=0, column=1, sticky="ew")
        self.env_combo.bind("<<ComboboxSelected>>", lambda _e: self.refresh_latest_release())
        ttk.Label(form, text="Surum:", style="Text.TLabel").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=(8, 0))
        self.version_entry = ttk.Entry(form, textvariable=self.version_var)
        self.version_entry.grid(row=1, column=1, sticky="ew", pady=(8, 0))

        fw = ttk.Frame(right, style="Card.TFrame")
        fw.grid(row=6, column=0, sticky="ew", pady=(8, 6))
        self.build_btn = ttk.Button(fw, text="Firmware derle", command=self.start_build, style="Soft.TButton")
        self.build_btn.pack(side=tk.LEFT)
        self.release_btn = ttk.Button(fw, text="Surum olustur", command=self.start_release, style="Soft.TButton")
        self.release_btn.pack(side=tk.LEFT, padx=8)
        self.upload_btn = ttk.Button(fw, text="Sürümü Yükle", command=self.start_upload, style="Accent.TButton")
        self.upload_btn.pack(side=tk.LEFT)

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
            self.uid_var.set(f"Unique ID: {d.unique_id}")

    def scan_devices(self) -> None:
        if self.scanning:
            return
        self.scanning = True
        self.scan_btn.configure(state=tk.DISABLED)
        self.qr_btn.configure(state=tk.DISABLED)
        self.save_btn.configure(state=tk.DISABLED)
        self.print_btn.configure(state=tk.DISABLED)
        self.set_status("Tarama baslatildi...")
        threading.Thread(target=self._scan_worker, daemon=True).start()

    def _scan_worker(self) -> None:
        ports = list(list_ports.comports())
        found: list[EspDevice] = []
        for i, p in enumerate(ports, start=1):
            self.root.after(0, lambda msg=f"Taraniyor {i}/{len(ports)}: {p.device}": self.set_status(msg))
            try:
                chip, uid = read_mac(p.device)
                found.append(EspDevice(port=p.device, description=p.description or "", chip=chip, unique_id=uid))
            except Exception:
                continue
        self.root.after(0, lambda: self._finish_scan(found))

    def _finish_scan(self, found: list[EspDevice]) -> None:
        self.scanning = False
        self.scan_btn.configure(state=tk.NORMAL)
        self.qr_btn.configure(state=tk.NORMAL)
        self.save_btn.configure(state=tk.NORMAL)
        self.print_btn.configure(state=tk.NORMAL)
        self.devices = found
        for x in self.tree.get_children():
            self.tree.delete(x)
        for i, d in enumerate(found):
            self.tree.insert("", tk.END, iid=str(i), values=(d.port, d.chip, d.unique_id, d.description))
        if found:
            self.set_status(f"{len(found)} cihaz bulundu.")
        else:
            self.set_status("ESP32 bulunamadi.")
            messagebox.showwarning("Cihaz bulunamadi", "USB/driver/COM baglantisini kontrol edin.")

    def make_qr(self) -> None:
        d = self.selected_device()
        if d is None:
            messagebox.showinfo("Secim gerekli", "Lutfen listeden bir cihaz secin.")
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

    def refresh_latest_release(self) -> None:
        env = self.env_var.get().strip()
        items = [r for r in self.releases if r.get("env") == env]
        if not items:
            self.latest_release_var.set(f"Son surum ({env}): -")
            return
        items.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        last = items[0]
        self.latest_release_var.set(f"Son surum ({env}): v{last['version']} [{last['created_at']}]")

    def _set_fw_state(self, enabled: bool) -> None:
        state = tk.NORMAL if enabled else tk.DISABLED
        self.build_btn.configure(state=state)
        self.release_btn.configure(state=state)
        self.upload_btn.configure(state=state)
        self.env_combo.configure(state="readonly" if enabled else "disabled")
        self.version_entry.configure(state=state)

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

    def start_build(self) -> None:
        if self.fw_busy:
            return
        env = self.env_var.get().strip()
        if not env:
            messagebox.showerror("Env", "Env secin.")
            return
        self.fw_busy = True
        self._set_fw_state(False)
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        threading.Thread(target=self._build_worker, args=(env,), daemon=True).start()

    def _build_worker(self, env: str) -> None:
        try:
            pio = find_platformio()
            self.root.after(0, lambda: self.set_status(f"Derleme basladi: {env}"))
            rc, tail = self._run_stream(
                [pio, "run", "-d", str(DEVICE_PROJECT_DIR), "-e", env],
                DEVICE_PROJECT_DIR,
                on_line=lambda ln: self.root.after(0, lambda t=ln: self.set_status(f"Derleniyor: {t[:90]}")),
            )
            if rc != 0:
                raise RuntimeError("\n".join(tail[-8:]) if tail else "Derleme hatasi.")
            self.root.after(0, lambda: self.set_status("Derleme tamamlandi."))
            self.root.after(0, lambda: messagebox.showinfo("Basarili", "Firmware derleme tamamlandi."))
        except Exception as exc:
            self.root.after(0, lambda: messagebox.showerror("Derleme hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("Derleme basarisiz."))
        finally:
            self.fw_busy = False
            self.root.after(0, lambda: self._set_fw_state(True))

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
        self.fw_busy = True
        self._set_fw_state(False)
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
            for k, src in files.items():
                dst = folder / src.name
                shutil.copy2(src, dst)
                out_files[k] = str(dst.relative_to(DEVICE_PROJECT_DIR))

            entry = {
                "id": folder.name,
                "version": version,
                "env": env,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "files": out_files,
            }
            self.releases.append(entry)
            save_releases(self.releases)

            self.root.after(0, self.refresh_latest_release)
            self.root.after(0, lambda: self.version_var.set(suggest_version(self.releases)))
            self.root.after(0, lambda: self.set_status(f"Surum olusturuldu: v{version}"))
            self.root.after(0, lambda: messagebox.showinfo("Basarili", f"Surum olusturuldu: v{version}\n{folder}"))
        except Exception as exc:
            self.root.after(0, lambda: messagebox.showerror("Surum hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("Surum olusturma basarisiz."))
        finally:
            self.fw_busy = False
            self.root.after(0, lambda: self._set_fw_state(True))

    def start_upload(self) -> None:
        if self.fw_busy:
            return
        dev = self.selected_device()
        if dev is None:
            messagebox.showinfo("Secim gerekli", "Lutfen cihaz secin.")
            return
        env = self.env_var.get().strip()
        items = [r for r in self.releases if r.get("env") == env]
        if not items:
            messagebox.showwarning("Surum yok", "Bu env icin surum yok. Once surum olusturun.")
            return
        items.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        rel = items[0]
        self.fw_busy = True
        self._set_fw_state(False)
        self.progress_var.set(0)
        self.progress_text_var.set("%0")
        threading.Thread(target=self._upload_worker, args=(dev, rel), daemon=True).start()

    def _upload_worker(self, dev: EspDevice, rel: dict) -> None:
        try:
            speed = int(self.upload_speeds.get(rel["env"], 921600))
            f = rel["files"]
            boot = (DEVICE_PROJECT_DIR / f["bootloader_bin"]).resolve()
            part = (DEVICE_PROJECT_DIR / f["partitions_bin"]).resolve()
            firm = (DEVICE_PROJECT_DIR / f["firmware_bin"]).resolve()
            for p in (boot, part, firm):
                if not p.exists():
                    raise FileNotFoundError(f"Firmware dosyasi yok: {p}")

            cmd = [
                sys.executable,
                "-m",
                "esptool",
                "--chip",
                "auto",
                "--port",
                dev.port,
                "--baud",
                str(speed),
                "--before",
                "default_reset",
                "--after",
                "hard_reset",
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
                raise RuntimeError("\n".join(tail[-8:]) if tail else "Yukleme hatasi.")

            self.root.after(0, lambda: self.progress_var.set(100))
            self.root.after(0, lambda: self.progress_text_var.set("%100"))
            self.root.after(0, lambda: self.set_status("TMM: Firmware yukleme tamamlandi."))
            self.root.after(0, lambda: messagebox.showinfo("TMM", f"Yukleme tamamlandi.\nPort: {dev.port}\nSurum: v{rel['version']}"))
        except Exception as exc:
            self.root.after(0, lambda: messagebox.showerror("Yukleme hatasi", str(exc)))
            self.root.after(0, lambda: self.set_status("Yukleme basarisiz."))
        finally:
            self.fw_busy = False
            self.root.after(0, lambda: self._set_fw_state(True))


def main() -> None:
    app = App()
    app.run()


if __name__ == "__main__":
    main()

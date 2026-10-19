"""SmartKeyPass masaüstü aracı için ortak arayüz takımı.

Tema renkleri, yüksek DPI ölçekleme, Segoe Fluent simgeleri, yuvarlak köşeli ttk öğeleri,
animasyon yardımcısı ve küçük bileşenler (adım göstergesi, ilerleme çubuğu, durum rozeti,
bildirim, ipucu, yan menü) burada toplanır. Yalnızca tkinter/ttk ve Pillow kullanır.
"""
from __future__ import annotations

import ctypes
import sys
import time
import tkinter as tk
import tkinter.font as tkfont
from pathlib import Path
from tkinter import ttk
from typing import Callable

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageTk

WIN_FONTS = Path("C:/Windows/Fonts")
FRAME_MS = 15
# 9 parcali gorsellerin orta bolgesi genis tutulur: Tk ortayi DOSEYEREK cizer,
# dar orta bolge binlerce cizim ve yavas pencere demektir.
TILE = 120


class C:
    """Renkler. Marka: lacivert #283848, camgöbeği #088890 (SmartKeyPass logosu)."""

    BG = "#F3F6F8"
    SURFACE = "#FFFFFF"
    SURFACE_ALT = "#F6F8FA"
    FILL = "#EDF1F4"
    FILL_HOVER = "#E2E8ED"
    FILL_PRESSED = "#D5DDE4"
    BORDER = "#E1E7EC"
    BORDER_STRONG = "#C8D2DA"
    TEXT = "#17212B"
    TEXT_2 = "#475563"
    TEXT_3 = "#5F6C78"
    TEXT_DISABLED = "#A3AEB8"

    NAVY = "#283848"
    NAVY_HOVER = "#314457"
    NAVY_PRESSED = "#2C3E50"
    NAVY_SELECTED = "#3A5067"
    NAV_TEXT = "#D9E2EA"
    NAV_MUTED = "#93A4B5"

    PRIMARY = "#07787F"
    PRIMARY_HOVER = "#066A70"
    PRIMARY_PRESSED = "#055A5F"
    PRIMARY_DISABLED = "#BCD8DA"
    PRIMARY_SOFT = "#E1F2F3"
    PRIMARY_SOFT_TEXT = "#05585D"
    TEAL = "#088890"
    TEAL_BRIGHT = "#35C2CA"
    FOCUS = "#0B3F43"

    SUCCESS = "#12703A"
    SUCCESS_SOFT = "#DCF5E4"
    WARNING = "#96500A"
    WARNING_SOFT = "#FDF0D5"
    DANGER = "#C42B2B"
    DANGER_HOVER = "#AA2323"
    DANGER_PRESSED = "#8F1D1D"
    DANGER_SOFT = "#FCE8E8"
    DANGER_SOFT_HOVER = "#F8D6D6"
    DANGER_SOFT_PRESSED = "#F2C2C2"

    CONSOLE_BG = "#101C26"
    CONSOLE_TEXT = "#D3DEE8"
    CONSOLE_DIM = "#7F93A6"
    CONSOLE_TX = "#7DD3FC"
    CONSOLE_OK = "#86EFAC"
    CONSOLE_ERR = "#FCA5A5"
    CONSOLE_WARN = "#FCD34D"

    TOAST_BG = "#1C2833"
    TOAST_TEXT = "#F1F5F9"


SURFACES = {
    "page": C.BG,
    "card": C.SURFACE,
    "inset": C.SURFACE_ALT,
    "nav": C.NAVY,
    "console": C.CONSOLE_BG,
    "toast": C.TOAST_BG,
}

# Segoe Fluent Icons / Segoe MDL2 Assets kod noktalari (ikisinde de ayni).
ICONS = {
    "qr": "\uED14",
    "refresh": "\uE72C",
    "search": "\uE721",
    "delete": "\uE74D",
    "print": "\uE749",
    "save": "\uE74E",
    "copy": "\uE8C8",
    "check": "\uE73E",
    "close": "\uE711",
    "warning": "\uE7BA",
    "info": "\uE946",
    "error": "\uEA39",
    "settings": "\uE713",
    "home": "\uE80F",
    "wifi": "\uE701",
    "bluetooth": "\uE702",
    "bolt": "\uE945",
    "usb": "\uE88E",
    "upload": "\uE898",
    "download": "\uE896",
    "package": "\uE7B8",
    "monitor": "\uE7F4",
    "diag": "\uE9D9",
    "library": "\uE8F1",
    "connect": "\uE703",
    "pdf": "\uEA90",
    "folder": "\uE8B7",
    "build": "\uEC7A",
    "chip": "\uE950",
    "cloud": "\uE753",
    "zip": "\uF012",
    "play": "\uE768",
    "send": "\uE724",
    "unlock": "\uE785",
    "camera": "\uE722",
    "tag": "\uE8EC",
    "scan": "\uEE6F",
    "power": "\uE7E8",
    "history": "\uE81C",
    "chevron_down": "\uE70D",
    "broadcast": "\uE789",
}

LABEL_KINDS = {
    "heading": ("heading", C.TEXT),
    "title": ("title", C.TEXT),
    "body": ("body", C.TEXT),
    "body2": ("body", C.TEXT_2),
    "muted": ("small", C.TEXT_2),
    "caption": ("small", C.TEXT_3),
    "value": ("body_sb", C.TEXT),
    "mono": ("mono", C.TEXT_2),
    "uid": ("uid", C.TEXT),
    "caps": ("caps", C.TEXT_3),
    "brand": ("brand", "#FFFFFF"),
}

# Koyu zeminlerde (yan menu, konsol, bildirim) yazi renkleri.
DARK_FG = {
    "nav": {"caption": C.NAV_MUTED, "caps": C.NAV_MUTED, "muted": C.NAV_MUTED, "body": C.NAV_TEXT, "body2": C.NAV_TEXT},
    "console": {"mono": C.CONSOLE_TEXT, "caption": C.CONSOLE_DIM},
    "toast": {"body": C.TOAST_TEXT, "body2": C.TOAST_TEXT, "caption": "#B6C3CF"},
}

PILLS = {
    "neutral": (C.FILL, C.TEXT_2, "#8B98A5"),
    "info": (C.PRIMARY_SOFT, C.PRIMARY_SOFT_TEXT, C.TEAL),
    "busy": (C.PRIMARY_SOFT, C.PRIMARY_SOFT_TEXT, C.TEAL),
    "ok": (C.SUCCESS_SOFT, C.SUCCESS, "#22A55A"),
    "warn": (C.WARNING_SOFT, C.WARNING, "#E19A1C"),
    "error": (C.DANGER_SOFT, C.DANGER, "#DC3B3B"),
}

TOAST_KINDS = {
    "success": ("check", "#4ADE80"),
    "error": ("error", "#F87171"),
    "warning": ("warning", "#FBBF24"),
    "info": ("info", "#5EEAD4"),
}

# Dugme turleri: dolgu, uzerine gelince, basilinca, devre disi dolgu, yazi, devre disi yazi, odak halkasi.
BUTTONS = {
    "primary": (C.PRIMARY, C.PRIMARY_HOVER, C.PRIMARY_PRESSED, C.PRIMARY_DISABLED, "#FFFFFF", "#F2F8F8", C.FOCUS),
    "secondary": (C.FILL, C.FILL_HOVER, C.FILL_PRESSED, "#F1F4F6", C.TEXT, C.TEXT_DISABLED, C.PRIMARY),
    "danger": (C.DANGER, C.DANGER_HOVER, C.DANGER_PRESSED, "#EBC1C1", "#FFFFFF", "#FBEFEF", "#5C1010"),
    "danger_soft": (C.DANGER_SOFT, C.DANGER_SOFT_HOVER, C.DANGER_SOFT_PRESSED, "#F7F0F0", C.DANGER, "#D9A3A3", C.DANGER),
    "ghost": (None, C.FILL, C.FILL_HOVER, None, C.TEXT_2, C.TEXT_DISABLED, C.PRIMARY),
    "nav": (C.NAVY, C.NAVY_HOVER, C.NAVY_PRESSED, C.NAVY, C.NAV_TEXT, C.NAV_MUTED, C.TEAL_BRIGHT),
    "toast": (C.TOAST_BG, "#2A3947", "#33444F", C.TOAST_BG, "#B6C3CF", "#6B7884", C.TEAL_BRIGHT),
}


# ---------------------------------------------------------------------------
# Sistem yardimcilari
# ---------------------------------------------------------------------------

def enable_dpi_awareness() -> None:
    """Windows'ta bulanik (bitmap olceklenmis) yaziyi onler. Tk() olusturulmadan ONCE cagrilmali."""
    if sys.platform != "win32":
        return
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


def system_animations_enabled() -> bool:
    """Windows 'Animasyon efektleri' kapaliysa (hareket azaltma) animasyonlari kapatir."""
    if sys.platform != "win32":
        return True
    try:
        value = ctypes.c_int(1)
        spi_get_client_area_animation = 0x1042
        if ctypes.windll.user32.SystemParametersInfoW(spi_get_client_area_animation, 0, ctypes.byref(value), 0):
            return bool(value.value)
    except Exception:
        pass
    return True


def ease_out_cubic(t: float) -> float:
    return 1 - (1 - t) ** 3


def ease_in_out_cubic(t: float) -> float:
    return 4 * t * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def hex_rgb(color: str) -> tuple[int, int, int]:
    c = color.lstrip("#")
    return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)


def mix(a: str, b: str, t: float) -> str:
    ra, ga, ba = hex_rgb(a)
    rb, gb, bb = hex_rgb(b)
    t = max(0.0, min(1.0, t))
    return "#%02X%02X%02X" % (round(ra + (rb - ra) * t), round(ga + (gb - ga) * t), round(ba + (bb - ba) * t))


class Animator:
    """after() tabanli, sureye bagli animasyon. Ayni anahtarla yeni animasyon eskisini keser."""

    def __init__(self, root: tk.Misc, enabled: bool = True) -> None:
        self.root = root
        self.enabled = enabled
        self._jobs: dict[str, str] = {}

    def run(
        self,
        key: str,
        duration_ms: int,
        step: Callable[[float], None],
        easing: Callable[[float], float] = ease_out_cubic,
        on_done: Callable[[], None] | None = None,
    ) -> None:
        self.cancel(key)
        if not self.enabled or duration_ms <= 0:
            try:
                step(1.0)
            except tk.TclError:
                return
            if on_done:
                on_done()
            return
        start = time.perf_counter()

        def tick() -> None:
            t = min(1.0, (time.perf_counter() - start) * 1000.0 / duration_ms)
            try:
                step(easing(t))
            except tk.TclError:
                self._jobs.pop(key, None)
                return
            if t >= 1.0:
                self._jobs.pop(key, None)
                if on_done:
                    on_done()
            else:
                self._jobs[key] = self.root.after(FRAME_MS, tick)

        tick()

    def cancel(self, key: str) -> None:
        job = self._jobs.pop(key, None)
        if job:
            try:
                self.root.after_cancel(job)
            except tk.TclError:
                pass


# ---------------------------------------------------------------------------
# Gorsel uretimi (Pillow): yumusak kenarli yuvarlak dikdortgenler, simgeler
# ---------------------------------------------------------------------------

def _layers_image(size: tuple[int, int], layers: list[tuple[float, float, str]], bg: str | None, ss: int = 4) -> Image.Image:
    """Distan ice (iceri cekme, yaricap, renk) katmanlari. bg None ise saydam RGBA."""
    w, h = size
    mode, base = ("RGBA", (0, 0, 0, 0)) if bg is None else ("RGB", bg)
    im = Image.new(mode, (w * ss, h * ss), base)
    d = ImageDraw.Draw(im)
    for inset, radius, color in layers:
        x0 = y0 = round(inset * ss)
        x1 = w * ss - 1 - round(inset * ss)
        y1 = h * ss - 1 - round(inset * ss)
        if x1 <= x0 or y1 <= y0:
            continue
        d.rounded_rectangle((x0, y0, x1, y1), radius=max(0, round(radius * ss)), fill=color)
    return im.resize((w, h), Image.Resampling.LANCZOS)


def _pill_rgba(w: int, h: int, color: str, ss: int = 3) -> Image.Image:
    w = max(w, h)
    im = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=h * ss / 2, fill=color)
    return im.resize((w, h), Image.Resampling.LANCZOS)


class Kit:
    """Tema, olcek, stil ve gorsel onbellegi. Uygulama basina bir tane olusturulur."""

    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.scale = max(1.0, float(root.winfo_fpixels("1i")) / 96.0)
        self.motion = system_animations_enabled()
        self.anim = Animator(root, self.motion)
        self._keep: list[object] = []
        self._styles: set[str] = set()
        self._cache: dict[tuple, object] = {}
        self._pil_fonts: dict[tuple, ImageFont.FreeTypeFont] = {}
        self._icon_font_path = self._find_icon_font()
        self.fonts = self._make_fonts()
        self.style = ttk.Style(root)
        if "clam" in self.style.theme_names():
            self.style.theme_use("clam")
        self._base_styles()
        self.toasts = ToastManager(self)

    # -- olcek ve yazi tipleri ------------------------------------------------
    def px(self, value: float) -> int:
        return int(round(value * self.scale))

    def _find_icon_font(self) -> Path | None:
        for name in ("SegoeIcons.ttf", "segmdl2.ttf"):
            p = WIN_FONTS / name
            if p.exists():
                return p
        return None

    def _make_fonts(self) -> dict[str, tkfont.Font]:
        families = set(tkfont.families(self.root))

        def pick(*names: str) -> str:
            for n in names:
                if n in families:
                    return n
            return names[-1]

        ui = pick("Segoe UI Variable Text", "Segoe UI", "TkDefaultFont")
        ui_sb = pick("Segoe UI Variable Text Semibold", "Segoe UI Semibold", "Segoe UI")
        display = pick("Segoe UI Variable Display Semib", "Segoe UI Semibold", "Segoe UI")
        mono = pick("Cascadia Mono", "Consolas", "Courier New")
        mono_sb = pick("Cascadia Mono SemiBold", "Consolas", "Courier New")
        return {
            "heading": tkfont.Font(self.root, family=display, size=18),
            "title": tkfont.Font(self.root, family=ui_sb, size=12),
            "brand": tkfont.Font(self.root, family=display, size=13),
            "body": tkfont.Font(self.root, family=ui, size=10),
            "body_sb": tkfont.Font(self.root, family=ui_sb, size=10),
            "small": tkfont.Font(self.root, family=ui, size=9),
            "small_sb": tkfont.Font(self.root, family=ui_sb, size=9),
            "caps": tkfont.Font(self.root, family=ui_sb, size=8),
            "mono": tkfont.Font(self.root, family=mono, size=9),
            "uid": tkfont.Font(self.root, family=mono_sb, size=15),
        }

    def _pil_font(self, path: Path, size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
        key = (str(path), size)
        if key not in self._pil_fonts:
            try:
                self._pil_fonts[key] = ImageFont.truetype(str(path), size)
            except Exception:
                return ImageFont.load_default()
        return self._pil_fonts[key]

    def _photo(self, key: tuple, factory: Callable[[], Image.Image]) -> ImageTk.PhotoImage:
        if key not in self._cache:
            self._cache[key] = ImageTk.PhotoImage(factory(), master=self.root)
        return cast_photo(self._cache[key])

    # -- simgeler -------------------------------------------------------------
    def icon_pil(self, name: str, size: int, color: str) -> Image.Image:
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ch = ICONS.get(name)
        if self._icon_font_path is None or not ch:
            return im
        font = self._pil_font(self._icon_font_path, size)
        d = ImageDraw.Draw(im)
        bbox = d.textbbox((0, 0), ch, font=font)
        x = (size - (bbox[2] - bbox[0])) / 2 - bbox[0]
        y = (size - (bbox[3] - bbox[1])) / 2 - bbox[1]
        d.text((x, y), ch, font=font, fill=color)
        return im

    def icon(self, name: str, size: int | None = None, color: str = C.TEXT, gap: int = 0) -> ImageTk.PhotoImage:
        size = size or self.px(16)

        def make() -> Image.Image:
            glyph = self.icon_pil(name, size, color)
            if not gap:
                return glyph
            canvas = Image.new("RGBA", (size + gap, size), (0, 0, 0, 0))
            canvas.alpha_composite(glyph, (0, 0))
            return canvas

        return self._photo(("icon", name, size, color, gap), make)

    def icon_badge(self, name: str, size: int, fg: str = C.PRIMARY, fill: str = C.PRIMARY_SOFT, surface: str = "page") -> ImageTk.PhotoImage:
        def make() -> Image.Image:
            base = _layers_image((size, size), [(0, size * 0.28, fill)], SURFACES[surface]).convert("RGBA")
            glyph = self.icon_pil(name, int(size * 0.5), fg)
            base.alpha_composite(glyph, ((size - glyph.width) // 2, (size - glyph.height) // 2))
            return base

        return self._photo(("badge", name, size, fg, fill, surface), make)

    def blank(self, w: int, h: int | None = None) -> ImageTk.PhotoImage:
        h = h or w
        return self._photo(("blank", w, h), lambda: Image.new("RGBA", (w, h), (0, 0, 0, 0)))

    def dot(self, color: str, size: int | None = None, gap: int | None = None) -> ImageTk.PhotoImage:
        size = size or self.px(8)
        gap = self.px(6) if gap is None else gap

        def make() -> Image.Image:
            ss = 4
            im = Image.new("RGBA", ((size + gap) * ss, size * ss), (0, 0, 0, 0))
            ImageDraw.Draw(im).ellipse((0, 0, size * ss - 1, size * ss - 1), fill=color)
            return im.resize((size + gap, size), Image.Resampling.LANCZOS)

        return self._photo(("dot", color, size, gap), make)

    def spinner_frames(self, color: str, size: int, count: int = 12, gap: int = 0) -> list[ImageTk.PhotoImage]:
        frames = []
        for i in range(count):
            def make(i: int = i) -> Image.Image:
                ss = 4
                s = size * ss
                stroke = max(2, round(size * 0.14)) * ss
                im = Image.new("RGBA", (s + gap * ss, s), (0, 0, 0, 0))
                d = ImageDraw.Draw(im)
                r, g, b = hex_rgb(color)
                box = (stroke // 2, stroke // 2, s - stroke // 2 - 1, s - stroke // 2 - 1)
                d.ellipse(box, outline=(r, g, b, 48), width=stroke)
                start = i * (360 / count) - 90
                d.arc(box, start, start + 100, fill=(r, g, b, 255), width=stroke)
                return im.resize((size + gap, size), Image.Resampling.LANCZOS)

            frames.append(self._photo(("spin", color, size, count, gap, i), make))
        return frames

    # -- stiller --------------------------------------------------------------
    def _elem(self, name: str, default: ImageTk.PhotoImage, states: list[tuple], **kw) -> None:
        if name in self._styles:
            return
        self._styles.add(name)
        kw.setdefault("padding", 0)
        if "border" in kw:
            # En kucuk boyut yalnizca koseler kadar; yoksa Tk gorselin dogal boyutunu (TILE dahil) dayatir.
            b = kw["border"]
            bl, bt = (b[0], b[1] if len(b) > 1 else b[0]) if isinstance(b, (tuple, list)) else (b, b)
            kw.setdefault("width", 2 * bl + 2)
            kw.setdefault("height", 2 * bt + 2)
        self.style.element_create(name, "image", default, *states, **kw)

    def _base_styles(self) -> None:
        s = self.style
        px = self.px
        f = self.fonts
        self.root.configure(bg=C.BG)
        s.configure(
            ".",
            background=C.SURFACE,
            foreground=C.TEXT,
            font=f["body"],
            bordercolor=C.BORDER,
            lightcolor=C.SURFACE,
            darkcolor=C.SURFACE,
            troughcolor=C.FILL,
            focuscolor=C.PRIMARY,
            selectbackground=C.PRIMARY_SOFT,
            selectforeground=C.PRIMARY_SOFT_TEXT,
            insertcolor=C.TEXT,
        )
        for key, color in SURFACES.items():
            s.configure(f"{key}.TFrame", background=color)

        # Kart: hafif golgeli, 1 px kenarli, yuvarlak beyaz yuzey (sayfa zemini uzerinde).
        r, m = px(12), px(3)
        self.card_margin = m
        size = 2 * (r + m) + TILE
        self._elem("Kit.card.bg", self._photo(("card", size, r, m), lambda: self._card_image(size, r, m)), [], border=r + m + 1, sticky="nsew")
        s.layout("Card.TFrame", [("Kit.card.bg", {"sticky": "nsew"})])
        s.configure("Card.TFrame", background=C.SURFACE)

        ri = px(10)
        size_i = 2 * ri + TILE
        inset_img = self._photo(("inset", size_i, ri), lambda: _layers_image((size_i, size_i), [(0, ri, C.SURFACE_ALT)], C.SURFACE))
        self._elem("Kit.inset.bg", inset_img, [], border=ri + 1, sticky="nsew")
        s.layout("Inset.TFrame", [("Kit.inset.bg", {"sticky": "nsew"})])
        s.configure("Inset.TFrame", background=C.SURFACE_ALT)

        console_img = self._photo(("console", size_i, ri), lambda: _layers_image((size_i, size_i), [(0, ri, C.CONSOLE_BG)], C.SURFACE))
        self._elem("Kit.console.bg", console_img, [], border=ri + 1, sticky="nsew")
        s.layout("Console.TFrame", [("Kit.console.bg", {"sticky": "nsew"})])
        s.configure("Console.TFrame", background=C.CONSOLE_BG)

        rt = px(8)
        size_t = 2 * rt + TILE
        toast_img = self._photo(("toast", size_t, rt), lambda: _layers_image((size_t, size_t), [(0, rt, C.TOAST_BG)], C.BG))
        self._elem("Kit.toast.bg", toast_img, [], border=rt + 1, sticky="nsew")
        s.layout("Toast.TFrame", [("Kit.toast.bg", {"sticky": "nsew"})])
        s.configure("Toast.TFrame", background=C.TOAST_BG)

        # Giris alani ve acilir liste.
        rf = px(8)
        size_f = 2 * rf + TILE

        def field(border: str, bw: float, fill: str) -> ImageTk.PhotoImage:
            return self._photo(
                ("field", border, bw, fill, size_f),
                lambda: _layers_image((size_f, size_f), [(0, rf, border), (bw, rf - bw, fill)], C.SURFACE),
            )

        self._elem(
            "Kit.field",
            field(C.BORDER_STRONG, px(1), C.SURFACE),
            [("disabled", field(C.BORDER, px(1), C.FILL)), ("focus", field(C.PRIMARY, px(2), C.SURFACE))],
            border=rf + 2,
            sticky="nsew",
        )
        s.layout(
            "Kit.TEntry",
            [("Kit.field", {"sticky": "nsew", "children": [("Entry.padding", {"sticky": "nsew", "children": [("Entry.textarea", {"sticky": "nsew"})]})]})],
        )
        s.configure(
            "Kit.TEntry",
            padding=(px(10), px(7)),
            foreground=C.TEXT,
            fieldbackground=C.SURFACE,
            insertcolor=C.TEXT,
            selectbackground=C.PRIMARY_SOFT,
            selectforeground=C.TEXT,
        )
        s.map("Kit.TEntry", foreground=[("disabled", C.TEXT_DISABLED)])
        s.configure("Search.Kit.TEntry", padding=(px(34), px(7), px(10), px(7)))

        aw = px(14)
        arrow = self._photo(("arrow", aw, C.TEXT_3), lambda: self._arrow_image(aw, C.TEXT_3))
        arrow_dis = self._photo(("arrow", aw, C.TEXT_DISABLED), lambda: self._arrow_image(aw, C.TEXT_DISABLED))
        self._elem("Kit.combo.arrow", arrow, [("disabled", arrow_dis)], sticky="")
        s.layout(
            "Kit.TCombobox",
            [
                (
                    "Kit.field",
                    {
                        "sticky": "nsew",
                        "children": [
                            ("Kit.combo.arrow", {"side": "right", "sticky": ""}),
                            ("Combobox.padding", {"expand": "1", "sticky": "nsew", "children": [("Combobox.textarea", {"sticky": "nsew"})]}),
                        ],
                    },
                )
            ],
        )
        s.configure(
            "Kit.TCombobox",
            padding=(px(10), px(7), px(2), px(7)),
            foreground=C.TEXT,
            fieldbackground=C.SURFACE,
            selectbackground=C.SURFACE,
            selectforeground=C.TEXT,
        )
        s.map(
            "Kit.TCombobox",
            fieldbackground=[("readonly", C.SURFACE)],
            selectbackground=[("readonly", C.SURFACE)],
            selectforeground=[("readonly", C.TEXT)],
            foreground=[("disabled", C.TEXT_DISABLED)],
        )
        self.root.option_add("*TCombobox*Listbox.font", f["body"])
        self.root.option_add("*TCombobox*Listbox.background", C.SURFACE)
        self.root.option_add("*TCombobox*Listbox.foreground", C.TEXT)
        self.root.option_add("*TCombobox*Listbox.selectBackground", C.PRIMARY_SOFT)
        self.root.option_add("*TCombobox*Listbox.selectForeground", C.PRIMARY_SOFT_TEXT)
        self.root.option_add("*TCombobox*Listbox.borderWidth", 0)
        self.root.option_add("*TCombobox*Listbox.highlightThickness", 0)

        # Tablo.
        s.layout("Kit.Treeview", [("Treeview.treearea", {"sticky": "nsew"})])
        s.configure(
            "Kit.Treeview",
            background=C.SURFACE,
            fieldbackground=C.SURFACE,
            foreground=C.TEXT,
            rowheight=px(34),
            font=f["body"],
            borderwidth=0,
            relief="flat",
        )
        s.map("Kit.Treeview", background=[("selected", C.PRIMARY_SOFT)], foreground=[("selected", C.PRIMARY_SOFT_TEXT)])
        s.layout(
            "Kit.Treeview.Item",
            [
                (
                    "Treeitem.padding",
                    {
                        "sticky": "nsew",
                        "children": [
                            ("Treeitem.indicator", {"side": "left", "sticky": ""}),
                            ("Treeitem.image", {"side": "left", "sticky": ""}),
                            ("Treeitem.text", {"side": "left", "sticky": ""}),
                        ],
                    },
                )
            ],
        )
        s.configure(
            "Kit.Treeview.Heading",
            background=C.SURFACE_ALT,
            foreground=C.TEXT_3,
            font=f["small_sb"],
            relief="flat",
            borderwidth=1,
            padding=(px(8), px(7)),
            lightcolor=C.SURFACE_ALT,
            darkcolor=C.SURFACE_ALT,
            bordercolor=C.BORDER,
        )
        s.map("Kit.Treeview.Heading", background=[("active", C.FILL)], relief=[("pressed", "flat")])

        # Ince, yuvarlak kaydirma cubugu (karta ve konsola).
        for prefix, trough, normal, active in (
            ("Kit", C.SURFACE, "#C9D2DA", "#9FADB9"),
            ("Console", C.CONSOLE_BG, "#33475A", "#4C6378"),
        ):
            w, h = px(12), 2 * px(8) + TILE
            imgs = [self._photo(("thumb", prefix, c, w, h), lambda c=c: self._thumb_image(w, h, c, trough)) for c in (normal, active)]
            self._elem(f"{prefix}.Vertical.Scrollbar.thumb", imgs[0], [("pressed", imgs[1]), ("active", imgs[1])], border=(px(5), px(8)), sticky="nsew")
            s.layout(
                f"{prefix}.Vertical.TScrollbar",
                [("Vertical.Scrollbar.trough", {"sticky": "ns", "children": [(f"{prefix}.Vertical.Scrollbar.thumb", {"expand": "1", "sticky": "nsew"})]})],
            )
            s.configure(
                f"{prefix}.Vertical.TScrollbar",
                troughcolor=trough,
                background=trough,
                bordercolor=trough,
                lightcolor=trough,
                darkcolor=trough,
                gripcount=0,
            )

    def _card_image(self, size: int, r: int, m: int) -> Image.Image:
        ss = 4
        s = size * ss
        base = Image.new("RGBA", (s, s), hex_rgb(C.BG) + (255,))
        shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (m * ss, (m + 1) * ss, s - m * ss - 1, s - (m - 1) * ss - 1), radius=r * ss, fill=(15, 30, 45, 30)
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(max(1, m) * ss * 0.7))
        base.alpha_composite(shadow)
        d = ImageDraw.Draw(base)
        d.rounded_rectangle((m * ss, m * ss, s - m * ss - 1, s - m * ss - 1), radius=r * ss, fill=C.BORDER)
        d.rounded_rectangle(((m + 1) * ss, (m + 1) * ss, s - (m + 1) * ss - 1, s - (m + 1) * ss - 1), radius=(r - 1) * ss, fill=C.SURFACE)
        return base.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)

    def _arrow_image(self, size: int, color: str) -> Image.Image:
        gap = self.px(10)
        canvas = Image.new("RGBA", (size + gap, size), (0, 0, 0, 0))
        canvas.alpha_composite(self.icon_pil("chevron_down", size, color), (0, 0))
        return canvas

    def _thumb_image(self, w: int, h: int, color: str, bg: str) -> Image.Image:
        ss = 4
        im = Image.new("RGB", (w * ss, h * ss), bg)
        inset = self.px(3) * ss
        ImageDraw.Draw(im).rounded_rectangle(
            (inset, inset, w * ss - inset - 1, h * ss - inset - 1), radius=(w * ss - 2 * inset) / 2, fill=color
        )
        return im.resize((w, h), Image.Resampling.LANCZOS)

    def button_style(self, variant: str = "secondary", surface: str = "card", compact: bool = False) -> str:
        name = f"Kit.{variant}.{surface}{'.c' if compact else ''}.TButton"
        if name in self._styles:
            return name
        self._styles.add(name)
        px = self.px
        fill, hover, pressed, dis, fg, dis_fg, ring = BUTTONS[variant]
        bg = SURFACES[surface]
        fill = fill or bg
        dis = dis or bg
        r = px(8)
        size = 2 * (r + 3) + TILE
        light = variant in ("secondary", "ghost", "danger_soft", "nav", "toast")

        def img(color: str, focus: bool = False) -> ImageTk.PhotoImage:
            def make() -> Image.Image:
                if not focus:
                    return _layers_image((size, size), [(0, r, color)], bg)
                if light:
                    return _layers_image((size, size), [(0, r, ring), (px(2), r - px(2), color)], bg)
                return _layers_image((size, size), [(0, r, ring), (px(2), r - px(2), C.SURFACE), (px(3), r - px(3), color)], bg)

            return self._photo(("btn", color, focus, ring, bg, size, light), make)

        elem = f"Kit.btn.{variant}.{surface}.bg"
        states: list[tuple] = [("disabled", img(dis)), ("pressed", img(pressed))]
        if variant == "nav":
            states += [
                ("selected", "focus", img(C.NAVY_SELECTED, True)),
                ("selected", img(C.NAVY_SELECTED)),
            ]
        states += [("focus", "active", img(hover, True)), ("active", img(hover)), ("focus", img(fill, True))]
        self._elem(elem, img(fill), states, border=r + 3, sticky="nsew")
        self.style.layout(
            name,
            [(elem, {"sticky": "nsew", "children": [("Button.padding", {"sticky": "nsew", "children": [("Button.label", {"sticky": "nsew"})]})]})],
        )
        if variant == "nav":
            pad = (px(12), px(9))
        elif compact:
            pad = (px(8), px(7))
        else:
            pad = (px(14), px(8))
        self.style.configure(
            name,
            padding=pad,
            foreground=fg,
            background=bg,
            font=self.fonts["body" if variant == "nav" else "body_sb"],
            anchor="w" if variant == "nav" else "center",
            focusthickness=0,
        )
        fg_map = [("disabled", dis_fg)]
        if variant == "nav":
            fg_map.append(("selected", "#FFFFFF"))
            self.style.map(name, foreground=fg_map, font=[("selected", self.fonts["body_sb"])])
        else:
            self.style.map(name, foreground=fg_map)
        return name

    def label_style(self, kind: str = "body", surface: str = "card", fg: str | None = None) -> str:
        name = f"{kind}.{surface}{'.' + fg.lstrip('#') if fg else ''}.TLabel"
        if name not in self._styles:
            self._styles.add(name)
            font_key, color = LABEL_KINDS[kind]
            color = fg or DARK_FG.get(surface, {}).get(kind, color)
            self.style.configure(name, background=SURFACES[surface], foreground=color, font=self.fonts[font_key])
        return name

    def pill_style(self, kind: str, surface: str = "card") -> str:
        name = f"Kit.pill.{kind}.{surface}.TLabel"
        if name in self._styles:
            return name
        self._styles.add(name)
        px = self.px
        fill, fg, _dot = PILLS[kind]
        r = px(11)
        size = 2 * r + TILE
        elem = f"Kit.pill.{kind}.{surface}.bg"
        image = self._photo(("pill", fill, SURFACES[surface], size), lambda: _layers_image((size, size), [(0, r, fill)], SURFACES[surface]))
        self._elem(elem, image, [], border=r + 1, sticky="nsew")
        self.style.layout(
            name,
            [(elem, {"sticky": "nsew", "children": [("Label.padding", {"sticky": "nsew", "children": [("Label.label", {"sticky": "nsew"})]})]})],
        )
        self.style.configure(name, padding=(px(10), px(3), px(12), px(3)), foreground=fg, background=fill, font=self.fonts["small_sb"])
        return name

    # -- kisa yollar: bilesen olusturucular ------------------------------------
    def label(self, parent: tk.Misc, text: str | None = None, kind: str = "body", surface: str = "card", textvariable: tk.Variable | None = None, fg: str | None = None, **kw) -> ttk.Label:
        opts = dict(style=self.label_style(kind, surface, fg))
        if textvariable is not None:
            opts["textvariable"] = textvariable
        else:
            opts["text"] = text or ""
        opts.update(kw)
        return ttk.Label(parent, **opts)

    def button(self, parent: tk.Misc, text: str, command: Callable | None = None, variant: str = "secondary", icon: str | None = None, surface: str = "card", **kw) -> ttk.Button:
        b = ttk.Button(parent, text=text, command=command, style=self.button_style(variant, surface, compact=not text))
        if kw:
            b.configure(**kw)
        b._kit = {"variant": variant, "icon": icon, "surface": surface}  # type: ignore[attr-defined]
        self._apply_icon(b)
        return b

    def icon_button(self, parent: tk.Misc, icon: str, command: Callable | None = None, tooltip: str | None = None, surface: str = "card", variant: str = "ghost") -> ttk.Button:
        b = self.button(parent, "", command, variant=variant, icon=icon, surface=surface)
        if tooltip:
            Tooltip(b, tooltip, self)
        return b

    def restyle(self, b: ttk.Button, variant: str | None = None, text: str | None = None, icon: str | None = None) -> None:
        info = b._kit  # type: ignore[attr-defined]
        if variant:
            info["variant"] = variant
        if icon:
            info["icon"] = icon
        if text is not None:
            b.configure(text=text)
        b.configure(style=self.button_style(info["variant"], info["surface"], compact=not b.cget("text")))
        self._apply_icon(b)

    def _apply_icon(self, b: ttk.Button) -> None:
        info = b._kit  # type: ignore[attr-defined]
        if not info["icon"]:
            return
        fill, _h, _p, _d, fg, dis_fg, _r = BUTTONS[info["variant"]]
        has_text = bool(b.cget("text"))
        size = self.px(18 if info["variant"] == "nav" else 16)
        gap = self.px(10 if info["variant"] == "nav" else 8) if has_text else 0
        if info["variant"] == "nav":
            spec = (self.icon(info["icon"], size, C.NAV_MUTED, gap), "selected", self.icon(info["icon"], size, "#FFFFFF", gap))
        else:
            spec = (self.icon(info["icon"], size, fg, gap), "disabled", self.icon(info["icon"], size, dis_fg, gap))
        b.configure(image=spec, compound="left" if has_text else "image")

    def card(self, parent: tk.Misc, padding: float = 18) -> ttk.Frame:
        p = self.px(padding) + self.card_margin
        return ttk.Frame(parent, style="Card.TFrame", padding=p)

    def inset(self, parent: tk.Misc, padding: float = 12) -> ttk.Frame:
        return ttk.Frame(parent, style="Inset.TFrame", padding=self.px(padding))

    def separator(self, parent: tk.Misc, surface: str = "card") -> tk.Frame:
        return tk.Frame(parent, height=max(1, self.px(1)), bg=C.BORDER if surface != "nav" else C.NAVY_HOVER, bd=0, highlightthickness=0)

    def entry(self, parent: tk.Misc, textvariable: tk.Variable, placeholder: str | None = None, icon: str | None = None, width: int | None = None) -> ttk.Entry:
        style = "Search.Kit.TEntry" if icon else "Kit.TEntry"
        e = ttk.Entry(parent, textvariable=textvariable, style=style, font=self.fonts["body"])
        if width:
            e.configure(width=width)
        if icon:
            ttk.Label(e, image=self.icon(icon, self.px(16), C.TEXT_3), style=self.label_style("body", "card")).place(x=self.px(11), rely=0.5, anchor="w")
        if placeholder:
            ph = ttk.Label(e, text=placeholder, style=self.label_style("caption", "card"))
            x = self.px(35 if icon else 11)

            def refresh(*_a: object) -> None:
                try:
                    if textvariable.get():
                        ph.place_forget()
                    else:
                        ph.place(x=x, rely=0.5, anchor="w")
                except tk.TclError:
                    pass

            ph.bind("<Button-1>", lambda _e: e.focus_set())
            textvariable.trace_add("write", refresh)
            refresh()
        return e

    def combobox(self, parent: tk.Misc, textvariable: tk.Variable, values: list[str] | None = None, width: int | None = None) -> ttk.Combobox:
        cb = ttk.Combobox(parent, textvariable=textvariable, values=values or [], state="readonly", style="Kit.TCombobox", font=self.fonts["body"])
        if width:
            cb.configure(width=width)
        return cb

    def tree(self, parent: tk.Misc, columns: list[tuple[str, str, int, str, bool]], height: int = 10) -> tuple[ttk.Frame, ttk.Treeview]:
        box = ttk.Frame(parent, style="card.TFrame")
        box.columnconfigure(0, weight=1)
        box.rowconfigure(0, weight=1)
        tv = ttk.Treeview(box, columns=[c[0] for c in columns], show="headings", height=height, style="Kit.Treeview", selectmode="browse")
        for key, text, width, anchor, stretch in columns:
            tv.heading(key, text=text, anchor=anchor)
            tv.column(key, width=self.px(width), minwidth=self.px(56), anchor=anchor, stretch=stretch)
        tv.tag_configure("odd", background=C.SURFACE_ALT)
        sb = ttk.Scrollbar(box, orient=tk.VERTICAL, command=tv.yview, style="Kit.Vertical.TScrollbar")
        tv.configure(yscrollcommand=sb.set)
        tv.grid(row=0, column=0, sticky="nsew")
        sb.grid(row=0, column=1, sticky="ns", padx=(self.px(4), 0))
        tv.bind("<<TreeviewSelect>>", lambda _e: self.zebra(tv), add="+")
        return box, tv

    def zebra(self, tv: ttk.Treeview) -> None:
        """Satir cizgilerini yeniler; secili satira seritlik uygulanmaz (secim rengi gorunsun)."""
        selected = set(tv.selection())
        for i, iid in enumerate(tv.get_children()):
            tv.item(iid, tags=("odd",) if i % 2 and iid not in selected else ())

    def console(self, parent: tk.Misc, height: int = 10) -> tuple[ttk.Frame, tk.Text]:
        px = self.px
        box = ttk.Frame(parent, style="Console.TFrame", padding=(px(12), px(10), px(6), px(10)))
        box.columnconfigure(0, weight=1)
        box.rowconfigure(0, weight=1)
        txt = tk.Text(
            box,
            height=height,
            bg=C.CONSOLE_BG,
            fg=C.CONSOLE_TEXT,
            insertbackground=C.CONSOLE_TEXT,
            selectbackground="#2B4155",
            selectforeground="#FFFFFF",
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
            wrap="word",
            font=self.fonts["mono"],
            padx=0,
            pady=0,
            spacing1=1,
        )
        txt.grid(row=0, column=0, sticky="nsew")
        sb = ttk.Scrollbar(box, orient=tk.VERTICAL, command=txt.yview, style="Console.Vertical.TScrollbar")
        sb.grid(row=0, column=1, sticky="ns", padx=(px(6), 0))
        txt.configure(yscrollcommand=sb.set)
        txt.tag_configure("tx", foreground=C.CONSOLE_TX)
        txt.tag_configure("ok", foreground=C.CONSOLE_OK)
        txt.tag_configure("err", foreground=C.CONSOLE_ERR)
        txt.tag_configure("warn", foreground=C.CONSOLE_WARN)
        txt.tag_configure("dim", foreground=C.CONSOLE_DIM)
        txt.configure(state=tk.DISABLED)
        return box, txt

    def console_append(self, txt: tk.Text, line: str, tag: str | None = None, max_lines: int = 4000) -> None:
        try:
            txt.configure(state=tk.NORMAL)
            txt.insert(tk.END, f"{line}\n", (tag,) if tag else ())
            lines = int(txt.index("end-1c").split(".")[0])
            if lines > max_lines:
                txt.delete("1.0", f"{lines - max_lines}.0")
            txt.see(tk.END)
            txt.configure(state=tk.DISABLED)
        except tk.TclError:
            pass

    def page_header(self, parent: tk.Misc, title: str, subtitle: str, icon: str | None = None) -> tuple[ttk.Frame, ttk.Frame]:
        """Sayfa basligi. Sag yuva dar ekranda basligin altina iner."""
        px = self.px
        f = ttk.Frame(parent, style="page.TFrame")
        f.columnconfigure(1, weight=1)
        badge_w = 0
        if icon:
            badge = ttk.Label(f, image=self.icon_badge(icon, px(46)), style=self.label_style("body", "page"))
            badge.grid(row=0, column=0, rowspan=2, sticky="w", padx=(0, px(14)))
            badge_w = px(46) + px(14)
        title_lbl = self.label(f, title, "heading", "page")
        title_lbl.grid(row=0, column=1, sticky="sw")
        sub = self.label(f, subtitle, "body2", "page", justify="left")
        sub.grid(row=1, column=1, sticky="nw", pady=(px(2), 0))
        slot = ttk.Frame(f, style="page.TFrame")
        state = {"wide": None}

        def relayout(_e: object = None) -> None:
            w = f.winfo_width()
            if w <= 1:
                return
            slot_w = slot.winfo_reqwidth()
            wide = w >= badge_w + px(360) + slot_w + px(32)
            if wide != state["wide"]:
                state["wide"] = wide
                slot.grid_forget()
                if wide:
                    slot.grid(row=0, column=2, rowspan=2, sticky="e", padx=(px(24), 0))
                else:
                    slot.grid(row=2, column=0, columnspan=3, sticky="w", pady=(px(14), 0))
            room = w - badge_w - (slot_w + px(32) if wide else 0)
            sub.configure(wraplength=max(px(260), room))

        f.bind("<Configure>", relayout, add="+")
        slot.bind("<Configure>", lambda _e: relayout(), add="+")
        slot.grid(row=0, column=2, rowspan=2, sticky="e", padx=(px(24), 0))
        return f, slot

    def empty_state(self, parent: tk.Misc, icon: str, title: str, text: str) -> ttk.Frame:
        px = self.px
        f = ttk.Frame(parent, style="card.TFrame")
        ttk.Label(f, image=self.icon_badge(icon, px(52), fg=C.TEXT_3, fill=C.FILL, surface="card"), style=self.label_style("body", "card")).pack(pady=(0, px(10)))
        f.title_label = self.label(f, title, "value")  # type: ignore[attr-defined]
        f.title_label.pack()  # type: ignore[attr-defined]
        f.text_label = self.label(f, text, "caption", justify="center", wraplength=px(320))  # type: ignore[attr-defined]
        f.text_label.pack(pady=(px(3), 0))  # type: ignore[attr-defined]
        return f

    def placeholder_tile(self, size: int, icon: str = "qr") -> ImageTk.PhotoImage:
        def make() -> Image.Image:
            base = _layers_image((size, size), [(0, self.px(16), C.BORDER), (self.px(1), self.px(15), C.SURFACE_ALT)], C.SURFACE).convert("RGBA")
            glyph = self.icon_pil(icon, int(size * 0.26), C.BORDER_STRONG)
            base.alpha_composite(glyph, ((size - glyph.width) // 2, (size - glyph.height) // 2))
            return base

        return self._photo(("ph", size, icon), make)

    def framed(self, pil_img: Image.Image, size: int) -> Image.Image:
        """Gorseli ince kenarli, yuvarlak koseli kare bir kutuya ortalar (onizleme icin)."""
        base = _layers_image((size, size), [(0, self.px(16), C.BORDER), (self.px(1), self.px(15), C.SURFACE)], C.SURFACE)
        inner = size - 2 * self.px(12)
        img = pil_img.convert("RGB")
        img.thumbnail((inner, inner), Image.Resampling.LANCZOS)
        base.paste(img, ((size - img.width) // 2, (size - img.height) // 2))
        return base

    def pop_image(self, label: ttk.Label, pil_img: Image.Image, key: str, bg: str = C.SURFACE) -> None:
        """Gorseli hafif buyuyerek ve beliririk gosterir (200 ms)."""
        img = pil_img.convert("RGB")
        final = ImageTk.PhotoImage(img, master=self.root)
        label._kit_final = final  # type: ignore[attr-defined]
        if not self.motion:
            label.configure(image=final)
            return
        w, h = img.size
        back = Image.new("RGB", (w, h), bg)
        frames = []
        for t in (0.2, 0.45, 0.7, 0.9):
            sc = 0.93 + 0.07 * t
            small = img.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.Resampling.BILINEAR)
            canvas = back.copy()
            canvas.paste(small, ((w - small.width) // 2, (h - small.height) // 2))
            frames.append(ImageTk.PhotoImage(Image.blend(back, canvas, 0.25 + 0.75 * t), master=self.root))
        label._kit_frames = frames  # type: ignore[attr-defined]

        def step(t: float) -> None:
            if t >= 1.0:
                label.configure(image=final)
            else:
                label.configure(image=frames[min(len(frames) - 1, int(t * len(frames)))])

        self.anim.run(key, 220, step)

    def flash(self, widget: tk.Widget, start: str, end: str, key: str, duration: int = 900) -> None:
        self.anim.run(key, duration, lambda t: widget.configure(bg=mix(start, end, t)), easing=ease_in_out_cubic)

    def toast(self, text: str, kind: str = "info", duration: int | None = None) -> None:
        self.toasts.show(text, kind, duration)


def cast_photo(obj: object) -> ImageTk.PhotoImage:
    return obj  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# Bilesenler
# ---------------------------------------------------------------------------

class Pill(ttk.Label):
    """Durum rozeti: renkli nokta + kisa metin. 'busy' turunde nokta yerine donen halka."""

    def __init__(self, parent: tk.Misc, kit: Kit, text: str = "", kind: str = "neutral", surface: str = "card") -> None:
        super().__init__(parent, style=kit.pill_style(kind, surface), compound="left")
        self.kit = kit
        self.surface = surface
        self.kind = ""
        self._spin_job: str | None = None
        self._spin_i = 0
        self._frames = kit.spinner_frames(C.TEAL, kit.px(10), gap=kit.px(6))
        self.set(text, kind)

    def set(self, text: str, kind: str | None = None) -> None:
        kind = kind or self.kind or "neutral"
        self.configure(text=text, style=self.kit.pill_style(kind, self.surface))
        if kind == self.kind:
            return
        self.kind = kind
        self._stop_spin()
        if kind == "busy":
            self._spin()
        else:
            self.configure(image=self.kit.dot(PILLS[kind][2]))

    def _spin(self) -> None:
        try:
            self.configure(image=self._frames[self._spin_i % len(self._frames)])
        except tk.TclError:
            return
        self._spin_i += 1
        if self.kit.motion:
            self._spin_job = self.after(80, self._spin)

    def _stop_spin(self) -> None:
        if self._spin_job:
            try:
                self.after_cancel(self._spin_job)
            except tk.TclError:
                pass
            self._spin_job = None


class Spinner(ttk.Label):
    def __init__(self, parent: tk.Misc, kit: Kit, surface: str = "page", size: int = 16, color: str = C.TEAL) -> None:
        super().__init__(parent, style=kit.label_style("body", surface))
        self.kit = kit
        self._frames = kit.spinner_frames(color, kit.px(size))
        self._blank = kit.blank(kit.px(size))
        self._job: str | None = None
        self._i = 0
        self.running = False
        self.configure(image=self._blank)

    def start(self) -> None:
        if self.running:
            return
        self.running = True
        if not self.kit.motion:
            self.configure(image=self._frames[0])
            return
        self._tick()

    def _tick(self) -> None:
        if not self.running:
            return
        try:
            self.configure(image=self._frames[self._i % len(self._frames)])
        except tk.TclError:
            return
        self._i += 1
        self._job = self.after(70, self._tick)

    def stop(self) -> None:
        self.running = False
        if self._job:
            try:
                self.after_cancel(self._job)
            except tk.TclError:
                pass
            self._job = None
        try:
            self.configure(image=self._blank)
        except tk.TclError:
            pass


class SmoothProgress(tk.Canvas):
    """Yuvarlak uclu ilerleme cubugu: degere yumusak gecer; mesgulken yuzde yoksa gidip gelen serit."""

    def __init__(self, parent: tk.Misc, kit: Kit, variable: tk.DoubleVar | None = None, surface: str = "card", height: int = 8) -> None:
        self.kit = kit
        self._h = kit.px(height)
        super().__init__(parent, height=self._h, bg=SURFACES[surface], highlightthickness=0, bd=0)
        self._shown = 0.0
        self._target = 0.0
        self._busy = False
        self._phase = 0.0
        self._busy_job: str | None = None
        self._track_w = 0
        self._track: ImageTk.PhotoImage | None = None
        self._fill: ImageTk.PhotoImage | None = None
        self._seg: tuple[int, ImageTk.PhotoImage] | None = None
        self._track_id = self.create_image(0, 0, anchor="nw")
        self._fill_id = self.create_image(0, 0, anchor="nw", state="hidden")
        self.bind("<Configure>", lambda _e: self._redraw())
        self._var = variable
        if variable is not None:
            try:
                self._shown = self._target = float(variable.get() or 0)
            except (tk.TclError, ValueError):
                pass
            variable.trace_add("write", self._on_var)

    def _on_var(self, *_args: object) -> None:
        try:
            value = float(self._var.get()) if self._var is not None else 0.0
        except (tk.TclError, ValueError):
            return
        self.set(value)

    def set(self, value: float) -> None:
        v = max(0.0, min(100.0, value))
        if v == self._target:
            return
        start = self._shown
        self._target = v
        if v < start or not self.kit.motion:
            self.kit.anim.cancel(f"pb{id(self)}")
            self._shown = v
            self._redraw()
            return
        self.kit.anim.run(f"pb{id(self)}", 300, lambda t: self._step(start + (v - start) * t))

    def _step(self, value: float) -> None:
        self._shown = value
        self._redraw()

    def set_busy(self, busy: bool) -> None:
        if busy == self._busy:
            return
        self._busy = busy
        if self._busy_job:
            try:
                self.after_cancel(self._busy_job)
            except tk.TclError:
                pass
            self._busy_job = None
        if busy:
            self._phase = 0.0
            self._marquee()
        else:
            self._redraw()

    def _marquee(self) -> None:
        if not self._busy:
            return
        if self.kit.motion:
            self._phase = (self._phase + 0.03) % 2.0
        else:
            self._phase = 0.5
        self._redraw()
        if self.kit.motion:
            self._busy_job = self.after(FRAME_MS * 2, self._marquee)

    def _redraw(self) -> None:
        try:
            w = self.winfo_width()
        except tk.TclError:
            return
        h = self._h
        if w < 4:
            return
        if self._track is None or self._track_w != w:
            self._track = ImageTk.PhotoImage(_pill_rgba(w, h, C.FILL_HOVER), master=self)
            self._track_w = w
            self.itemconfigure(self._track_id, image=self._track)
        if self._busy and self._shown <= 0.5:
            seg_w = max(h * 3, int(w * 0.26))
            if self._seg is None or self._seg[0] != seg_w:
                self._seg = (seg_w, ImageTk.PhotoImage(_pill_rgba(seg_w, h, C.TEAL), master=self))
            p = self._phase if self._phase <= 1.0 else 2.0 - self._phase
            x = int((w - seg_w) * ease_in_out_cubic(p))
            self.itemconfigure(self._fill_id, image=self._seg[1], state="normal")
            self.coords(self._fill_id, x, 0)
        elif self._shown > 0:
            fw = max(h, int(round(w * self._shown / 100.0)))
            self._fill = ImageTk.PhotoImage(_pill_rgba(fw, h, C.TEAL), master=self)
            self.itemconfigure(self._fill_id, image=self._fill, state="normal")
            self.coords(self._fill_id, 0, 0)
        else:
            self.itemconfigure(self._fill_id, state="hidden")


class Stepper(ttk.Frame):
    """Yatay adim gostergesi: tamamlanan adim tik, siradaki adim halka, kalanlar gri."""

    def __init__(self, parent: tk.Misc, kit: Kit, labels: list[str], surface: str = "page") -> None:
        super().__init__(parent, style=f"{surface}.TFrame")
        self.kit = kit
        self.surface = surface
        px = kit.px
        self._circles: list[ttk.Label] = []
        self._texts: list[ttk.Label] = []
        self._lines: list[tk.Frame] = []
        self._line_colors: list[str] = []
        self._states: list[str | None] = []
        for i, text in enumerate(labels):
            if i:
                line = tk.Frame(self, bg=C.BORDER_STRONG, width=px(26), height=max(2, px(2)), bd=0, highlightthickness=0)
                line.pack(side=tk.LEFT, padx=px(10))
                self._lines.append(line)
                self._line_colors.append(C.BORDER_STRONG)
            c = ttk.Label(self, style=kit.label_style("body", surface))
            c.pack(side=tk.LEFT)
            t = kit.label(self, text, "caption", surface)
            t.pack(side=tk.LEFT, padx=(px(8), 0))
            self._circles.append(c)
            self._texts.append(t)
            self._states.append(None)
        self.set(0, 0, animate=False)

    def set(self, done: int, current: int | None, animate: bool = True) -> None:
        for i in range(len(self._circles)):
            st = "done" if i < done else ("current" if i == current else "todo")
            prev = self._states[i]
            if st == prev:
                continue
            self._states[i] = st
            kind = {"done": "body2", "current": "value", "todo": "caption"}[st]
            self._texts[i].configure(style=self.kit.label_style(kind, self.surface))
            self._animate_circle(i, prev, st, animate and prev is not None)
        for i, line in enumerate(self._lines):
            target = C.TEAL if i < done else C.BORDER_STRONG
            start = self._line_colors[i]
            if target == start:
                continue
            self._line_colors[i] = target
            if animate:
                self.kit.anim.run(f"stl{id(self)}{i}", 260, lambda t, ln=line, a=start, b=target: ln.configure(bg=mix(a, b, t)))
            else:
                line.configure(bg=target)

    def _animate_circle(self, i: int, prev: str | None, st: str, animate: bool) -> None:
        label = self._circles[i]
        if not animate:
            label.configure(image=self._circle(i + 1, st, st, 4))
            return

        def step(t: float) -> None:
            label.configure(image=self._circle(i + 1, prev or st, st, min(4, int(round(t * 4)))))

        self.kit.anim.run(f"stc{id(self)}{i}", 260, step)

    def _circle(self, number: int, a: str, b: str, q: int) -> ImageTk.PhotoImage:
        kit = self.kit
        d = kit.px(26)

        def visual(state: str) -> tuple[str, str, str, str]:
            if state == "done":
                return C.TEAL, C.TEAL, "check", "#FFFFFF"
            if state == "current":
                return C.SURFACE, C.TEAL, "num", C.PRIMARY
            return C.FILL_HOVER, C.FILL_HOVER, "num", C.TEXT_3

        def make() -> Image.Image:
            t = q / 4.0
            fa, ra, ca, ga = visual(a)
            fb, rb, cb, gb = visual(b)
            fill, ring = mix(fa, fb, t), mix(ra, rb, t)
            content = cb if t >= 0.5 else ca
            fg = mix(ga, gb, t) if ca == cb else (gb if t >= 0.5 else ga)
            ss = 4
            s = d * ss
            im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            dr = ImageDraw.Draw(im)
            dr.ellipse((0, 0, s - 1, s - 1), fill=ring)
            bw = kit.px(2) * ss
            dr.ellipse((bw, bw, s - bw - 1, s - bw - 1), fill=fill)
            if content == "check":
                glyph = kit.icon_pil("check", int(d * 0.55) * ss, fg)
                im.alpha_composite(glyph, ((s - glyph.width) // 2, (s - glyph.height) // 2))
            else:
                font = kit._pil_font(WIN_FONTS / "seguisb.ttf", int(d * 0.48) * ss)
                dr.text((s / 2, s / 2), str(number), font=font, fill=fg, anchor="mm")
            return im.resize((d, d), Image.Resampling.LANCZOS)

        return kit._photo(("step", number, a, b, q, d), make)


class ToastManager:
    """Sag altta beliren, kendiliginden kaybolan bildirimler (yeni olan en altta)."""

    def __init__(self, kit: Kit) -> None:
        self.kit = kit
        self.items: list[ttk.Frame] = []

    def show(self, text: str, kind: str = "info", duration: int | None = None) -> None:
        kit = self.kit
        px = kit.px
        root = kit.root
        icon_name, icon_color = TOAST_KINDS.get(kind, TOAST_KINDS["info"])
        m = px(14)
        f = ttk.Frame(root, style="Toast.TFrame", padding=(m, px(11), px(8), px(11)))
        f.columnconfigure(1, weight=1)
        ttk.Label(f, image=kit.icon(icon_name, px(18), icon_color), style=kit.label_style("body", "toast")).grid(row=0, column=0, sticky="n", padx=(0, px(10)), pady=(px(1), 0))
        msg = kit.label(f, text, "body", "toast", wraplength=px(360), justify="left")
        msg.grid(row=0, column=1, sticky="w")
        close = kit.icon_button(f, "close", lambda: self.dismiss(f), surface="toast", variant="toast")
        close.grid(row=0, column=2, sticky="ne", padx=(px(8), 0))
        for w in (f, msg):
            w.bind("<Button-1>", lambda _e: self.dismiss(f))
        f._ky = None  # type: ignore[attr-defined]
        self.items.insert(0, f)
        if len(self.items) > 4:
            for old in self.items[4:]:
                self.dismiss(old)
        f.update_idletasks()
        self._layout(new=f)
        if duration is None:
            duration = 6500 if kind in ("error", "warning") else 4200
        f.after(duration, lambda: self.dismiss(f))

    def _target(self, index: int) -> int:
        y = -self.kit.px(58)
        for f in self.items[:index]:
            y -= f.winfo_reqheight() + self.kit.px(10)
        return y

    def _layout(self, new: ttk.Frame | None = None) -> None:
        x = -self.kit.px(24)
        for i, f in enumerate(self.items):
            target = self._target(i)
            start = f._ky  # type: ignore[attr-defined]
            if start is None:
                start = target + self.kit.px(20)
            f._ky = target  # type: ignore[attr-defined]
            f.place(relx=1.0, rely=1.0, x=x, y=start, anchor="se")
            f.lift()
            self.kit.anim.run(
                f"toast{id(f)}",
                240,
                lambda t, w=f, a=start, b=target: w.place_configure(y=int(round(a + (b - a) * t))),
            )

    def dismiss(self, f: ttk.Frame) -> None:
        if f not in self.items:
            return
        self.items.remove(f)
        start = f._ky or 0  # type: ignore[attr-defined]

        def gone() -> None:
            try:
                f.destroy()
            except tk.TclError:
                pass

        self.kit.anim.run(
            f"toast{id(f)}",
            160,
            lambda t: f.place_configure(y=int(round(start + self.kit.px(24) * t))),
            on_done=gone,
        )
        self._layout()


class Tooltip:
    def __init__(self, widget: tk.Widget, text: str, kit: Kit, side: str = "bottom", delay: int = 450) -> None:
        self.widget = widget
        self.text = text
        self.kit = kit
        self.side = side
        self.delay = delay
        self._job: str | None = None
        self._tip: tk.Toplevel | None = None
        widget.bind("<Enter>", self._schedule, add="+")
        widget.bind("<Leave>", self._hide, add="+")
        widget.bind("<ButtonPress>", self._hide, add="+")

    def _schedule(self, _e: object = None) -> None:
        self._cancel()
        self._job = self.widget.after(self.delay, self._show)

    def _cancel(self) -> None:
        if self._job:
            try:
                self.widget.after_cancel(self._job)
            except tk.TclError:
                pass
            self._job = None

    def _show(self) -> None:
        self._job = None
        if self._tip is not None:
            return
        try:
            if not self.widget.winfo_viewable():
                return
            px = self.kit.px
            if self.side == "right":
                x = self.widget.winfo_rootx() + self.widget.winfo_width() + px(8)
                y = self.widget.winfo_rooty() + px(4)
            else:
                x = self.widget.winfo_rootx() + px(4)
                y = self.widget.winfo_rooty() + self.widget.winfo_height() + px(6)
            tip = tk.Toplevel(self.widget)
            tip.wm_overrideredirect(True)
            tip.configure(bg=C.TOAST_BG)
            tk.Label(
                tip,
                text=self.text,
                bg=C.TOAST_BG,
                fg=C.TOAST_TEXT,
                font=self.kit.fonts["small"],
                padx=px(9),
                pady=px(5),
                justify="left",
                wraplength=px(320),
            ).pack()
            tip.wm_geometry(f"+{x}+{y}")
            self._tip = tip
        except tk.TclError:
            self._tip = None

    def _hide(self, _e: object = None) -> None:
        self._cancel()
        if self._tip is not None:
            try:
                self._tip.destroy()
            except tk.TclError:
                pass
            self._tip = None


class Sidebar(tk.Frame):
    """Lacivert yan menu: marka, gruplu sayfa ogeleri ve kayan secim gostergesi."""

    def __init__(self, parent: tk.Misc, kit: Kit, logo: ImageTk.PhotoImage | None, title: str, subtitle: str, on_select: Callable[[str], None]) -> None:
        super().__init__(parent, bg=C.NAVY, width=kit.px(236), bd=0, highlightthickness=0)
        self.pack_propagate(False)
        self.kit = kit
        self.on_select = on_select
        px = kit.px
        brand = tk.Frame(self, bg=C.NAVY)
        brand.pack(fill=tk.X, padx=px(18), pady=(px(22), px(18)))
        if logo is not None:
            tk.Label(brand, image=logo, bg=C.NAVY, bd=0).pack(side=tk.LEFT)
        txt = tk.Frame(brand, bg=C.NAVY)
        txt.pack(side=tk.LEFT, padx=(px(10), 0))
        kit.label(txt, title, "brand", "nav").pack(anchor="w")
        kit.label(txt, subtitle, "caption", "nav").pack(anchor="w")
        self.nav = tk.Frame(self, bg=C.NAVY)
        self.nav.pack(fill=tk.X)
        self.footer = tk.Frame(self, bg=C.NAVY)
        self.footer.pack(side=tk.BOTTOM, fill=tk.X, padx=px(20), pady=(0, px(18)))
        self.indicator = tk.Frame(self.nav, bg=C.TEAL_BRIGHT, width=max(3, px(3)), bd=0, highlightthickness=0)
        self.items: dict[str, ttk.Button] = {}
        self.selected: str | None = None
        self._ind_y: int | None = None
        self.nav.bind("<Configure>", lambda _e: self._place_indicator(animate=False), add="+")

    def add_group(self, text: str) -> None:
        self.kit.label(self.nav, text, "caps", "nav").pack(anchor="w", padx=self.kit.px(24), pady=(self.kit.px(12), self.kit.px(6)))

    def add_item(self, key: str, text: str, icon: str, shortcut: str | None = None) -> ttk.Button:
        b = self.kit.button(self.nav, text, lambda k=key: self.on_select(k), variant="nav", icon=icon, surface="nav")
        b.pack(fill=tk.X, padx=self.kit.px(12), pady=self.kit.px(1))
        if shortcut:
            Tooltip(b, shortcut, self.kit, side="right", delay=700)
        self.items[key] = b
        return b

    def select(self, key: str, animate: bool = True) -> None:
        for k, b in self.items.items():
            b.state(["selected"] if k == key else ["!selected"])
        self.selected = key
        self._place_indicator(animate)

    def _place_indicator(self, animate: bool) -> None:
        b = self.items.get(self.selected or "")
        if b is None:
            return
        try:
            self.nav.update_idletasks()
            bh = b.winfo_height()
            if bh <= 1:
                return
            h = max(self.kit.px(14), int(bh * 0.46))
            target = b.winfo_y() + (bh - h) // 2
            x = b.winfo_x() + self.kit.px(5)
        except tk.TclError:
            return
        start = self._ind_y
        self._ind_y = target
        self.indicator.place(x=x, y=target if start is None or not animate else start, height=h)
        self.indicator.lift()
        if animate and start is not None and start != target:
            self.kit.anim.run(
                "nav-ind",
                220,
                lambda t: self.indicator.place_configure(y=int(round(start + (target - start) * t))),
                easing=ease_in_out_cubic,
            )

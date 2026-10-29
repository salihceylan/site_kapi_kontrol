"""Goruntu on-isleme: CLAHE kontrast, golge/parlaklik dengeleme, Otsu (yetersizse adaptif) esik.
Profiller (gunduz | gece | oto) ayarlar.json 'on_isleme' bolumunden gelir; kodda sabit esik yoktur."""
from __future__ import annotations

import cv2
import numpy as np


def otsu_ayrim(gri: np.ndarray, esik: float) -> float:
    """Otsu esiginde sinif-arasi varyansin toplam varyansa orani (0-1). Dusuk = iki modlu degil."""
    hist = np.bincount(gri.ravel(), minlength=256).astype(np.float64)
    toplam = hist.sum()
    if toplam <= 0:
        return 0.0
    p = hist / toplam
    i = np.arange(256, dtype=np.float64)
    w0 = np.cumsum(p)
    mu = np.cumsum(p * i)
    mut = mu[-1]
    var_t = float(np.sum(p * (i - mut) ** 2))
    if var_t <= 1e-9:
        return 0.0
    t = int(min(max(esik, 0), 255))
    w = w0[t]
    if w <= 1e-9 or w >= 1 - 1e-9:
        return 0.0
    return float(((mut * w - mu[t]) ** 2 / (w * (1 - w))) / var_t)


class Onisleyici:
    def __init__(self, ayar: dict):
        self.ayar = ayar or {}
        self.etkin = bool(self.ayar.get("etkin", True))

    # --- profil ------------------------------------------------------------------------
    def profil_coz(self, istenen: str | None, goruntu=None) -> str:
        """'gunduz'/'gece' dogrudan; 'oto' (ya da bos) => goruntunun ortalama parlakligindan."""
        p = (istenen or self.ayar.get("profil") or "oto").lower()
        if p in ("gunduz", "gece"):
            return p
        if goruntu is None:
            return "gunduz"
        gri = goruntu if goruntu.ndim == 2 else cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
        kucuk = gri[::4, ::4]
        return "gece" if float(kucuk.mean()) < float(self.ayar.get("gece_parlaklik_esik", 70)) else "gunduz"

    def _p(self, profil: str) -> dict:
        pr = self.ayar.get("profiller", {})
        return pr.get(profil) or pr.get("gunduz") or {}

    # --- adimlar -----------------------------------------------------------------------
    @staticmethod
    def _gri(g: np.ndarray) -> np.ndarray:
        return g if g.ndim == 2 else cv2.cvtColor(g, cv2.COLOR_BGR2GRAY)

    def golge_dengele(self, gri: np.ndarray, oran: float) -> np.ndarray:
        """Arka plan tahmini (kapama) ile bolme: gol'ge/isik gradyanini duzlestirir. Koyu karakter/acik zemin varsayar."""
        k = int(max(3, min(gri.shape[:2]) * float(oran))) | 1
        bg = cv2.morphologyEx(gri, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
        bg = cv2.GaussianBlur(bg, (k | 1, k | 1), 0)
        return cv2.divide(gri, np.maximum(bg, 1), scale=255)

    @staticmethod
    def gamma(gri: np.ndarray, g: float) -> np.ndarray:
        if abs(g - 1.0) < 1e-3:
            return gri
        tablo = (np.linspace(0, 1, 256) ** (1.0 / max(g, 0.05)) * 255).clip(0, 255).astype(np.uint8)
        return cv2.LUT(gri, tablo)

    def iyilestir(self, goruntu: np.ndarray, profil: str, golge: bool | None = None) -> np.ndarray:
        """Gri: yuzdelik kirpma (IR parlama) -> golge dengeleme -> gamma -> CLAHE."""
        pr = self._p(profil)
        gri = self._gri(goruntu)
        lo, hi = pr.get("yuzdelik_kirp", [0.0, 100.0])
        if lo > 0 or hi < 100:
            a, b = np.percentile(gri, (lo, hi))
            if b - a >= 8:
                gri = np.clip((gri.astype(np.float32) - a) * (255.0 / (b - a)), 0, 255).astype(np.uint8)
        if (pr.get("golge_denge", True) if golge is None else golge):
            gri = self.golge_dengele(gri, pr.get("golge_cekirdek_oran", 0.9))
        gri = self.gamma(gri, float(pr.get("gamma", 1.0)))
        kare = int(pr.get("clahe_kare", 8))
        clahe = cv2.createCLAHE(clipLimit=float(pr.get("clahe_clip", 2.0)), tileGridSize=(kare, kare))
        return clahe.apply(gri)

    def kare_hazirla(self, kare: np.ndarray, profil: str) -> np.ndarray:
        """Tespit oncesi: ayarda 'hep' ya da ('gece' ve profil gece) ise CLAHE (golge dengelemesiz, kenarlar korunur)."""
        mod = self.ayar.get("tespit_oncesi", "gece")
        if not self.etkin or mod == "yok" or (mod == "gece" and profil != "gece"):
            return kare
        return self.iyilestir(kare, profil, golge=False)

    def ikili(self, govde: np.ndarray, profil: str) -> np.ndarray:
        """Plaka govdesi (gri) -> ikili (karakter BEYAZ). Otsu ayrimi yetersizse adaptif esik."""
        pr = self._p(profil)
        gri = cv2.GaussianBlur(self.iyilestir(govde, profil), (3, 3), 0)
        t, ikili = cv2.threshold(gri, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        if otsu_ayrim(gri, t) < float(self.ayar.get("otsu_min_ayrim", 0.55)):
            blok = int(pr.get("adaptif_blok", 31)) | 1
            blok = max(3, min(blok, (min(gri.shape[:2]) // 2) * 2 - 1 if min(gri.shape[:2]) > 6 else 3))
            ikili = cv2.adaptiveThreshold(gri, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV,
                                          blok, float(pr.get("adaptif_c", 8)))
        if np.count_nonzero(ikili) > ikili.size * 0.5:  # karakter her zaman azinlik
            ikili = 255 - ikili
        return ikili

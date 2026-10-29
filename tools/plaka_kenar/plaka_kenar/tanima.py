"""Karakter segmentasyonu + TAKILABILIR karakter tanima arayuzu.

Tanima motorlari: OnnxTanima (egitilmis CNN), SablonTanima (sahada toplanan ornekler).
Dogrulanmis bir motor YOKSA "KALIBRASYON MODU": sonuclar dogrulanmis=False isaretlenir,
karar motoru kapiyi ASLA acmaz (sahte basari yok).
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

from .ayarlar import yol_coz


@dataclass
class Karakter:
    goruntu: np.ndarray  # BxB uint8, beyaz karakter / siyah zemin
    kutu: tuple


@dataclass
class TanimaSonucu:
    metin: str
    guvenler: list = field(default_factory=list)
    dogrulanmis: bool = False
    kaynak: str = ""
    alternatifler: list = field(default_factory=list)  # pozisyon basina {karakter: olasilik} (konsensus icin; bos olabilir)

    @property
    def guven(self) -> float:
        return float(min(self.guvenler)) if self.guvenler else 0.0


class Segmentleyici:
    """Perspektifi duzeltilmis gri plaka -> sirali karakter goruntuleri (egitimle AYNI normalizasyon)."""

    def __init__(self, p: dict, boyut: int = 28, onisleyici=None):
        self.p = p
        self.boyut = int(boyut)
        self.on = onisleyici  # None: eski davranis (3x3 bulanik + Otsu); verilirse CLAHE/golge/adaptif esik

    def normalize(self, ikili: np.ndarray, kutu: tuple) -> np.ndarray:
        x, y, w, h = kutu
        parca = ikili[y:y + h, x:x + w]
        kenar = int(max(w, h) * 1.2)
        tuval = np.zeros((kenar, kenar), np.uint8)
        tuval[(kenar - h) // 2:(kenar - h) // 2 + h, (kenar - w) // 2:(kenar - w) // 2 + w] = parca
        return cv2.resize(tuval, (self.boyut, self.boyut), interpolation=cv2.INTER_AREA)

    def bol(self, plaka: np.ndarray, profil: str | None = None) -> list:
        p = self.p
        H, W = plaka.shape[:2]
        sol = int(W * p["sol_kirp_oran"])
        kenar = int(H * p["kenar_kirp_oran"])
        govde = plaka[kenar:H - kenar, sol:W]
        if self.on is not None and self.on.etkin:
            ikili = self.on.ikili(govde, self.on.profil_coz(profil, govde))
        else:
            govde = cv2.GaussianBlur(govde, (3, 3), 0)
            _, ikili = cv2.threshold(govde, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
            if np.count_nonzero(ikili) > ikili.size * 0.5:  # karakter her zaman azinlik
                ikili = 255 - ikili
        n, _, ist, _ = cv2.connectedComponentsWithStats(ikili, connectivity=8)
        gh = govde.shape[0]
        kutular = []
        for i in range(1, n):
            x, y, w, h, alan = ist[i]
            if not p["yukseklik_min_oran"] * gh <= h <= p["yukseklik_max_oran"] * gh:
                continue
            if w > p["genislik_max_oran"] * W or w < 2 or alan < 0.12 * w * h:
                continue
            kutular.append((int(x), int(y), int(w), int(h)))
        kutular.sort(key=lambda k: k[0])
        if not p["min_karakter"] <= len(kutular) <= p["max_karakter"]:
            return []
        return [Karakter(self.normalize(ikili, k), (k[0] + sol, k[1] + kenar, k[2], k[3])) for k in kutular]


class Tanima(ABC):
    ad = "tanima"
    dogrulanmis = False
    aciklama = ""

    @abstractmethod
    def tani(self, karakterler: list) -> TanimaSonucu: ...


def _vektor(img: np.ndarray) -> np.ndarray:
    v = img.astype(np.float32).ravel() / 255.0
    v -= v.mean()
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-6 else v


class SablonTanima(Tanima):
    """sablon_dizini/<sinif>/*.png (BxB). Normalize korelasyonla en yakin sinif."""
    ad = "sablon"

    def __init__(self, p: dict, taban: Path | None = None):
        self.siniflar = p["siniflar"]
        self.boyut = int(p["karakter_boyut"])
        dizin = yol_coz(p["sablon_dizini"], taban)
        vek, etiket, sayac = [], [], {}
        if dizin.is_dir():
            for sinif in self.siniflar:
                for f in sorted((dizin / sinif).glob("*.png")) if (dizin / sinif).is_dir() else []:
                    img = cv2.imdecode(np.fromfile(str(f), np.uint8), cv2.IMREAD_GRAYSCALE)
                    if img is None:
                        continue
                    img = cv2.resize(img, (self.boyut, self.boyut), interpolation=cv2.INTER_AREA)
                    vek.append(_vektor(img))
                    etiket.append(sinif)
                    sayac[sinif] = sayac.get(sinif, 0) + 1
        self.M = np.stack(vek) if vek else np.zeros((0, self.boyut ** 2), np.float32)
        self.etiket = np.array(etiket)
        eksik = [s for s in self.siniflar if sayac.get(s, 0) < int(p["sablon_min_ornek"])]
        self.tam_kapsam = not eksik and bool(vek)
        self.dogrulanmis = bool(p.get("sablon_onayli")) and self.tam_kapsam
        self.aciklama = (
            "sablon dogrulanmis" if self.dogrulanmis else
            "sablon dogrulanmadi (sablon_onayli=false)" if self.tam_kapsam else
            f"sablon kapsami eksik ({len(eksik)}/{len(self.siniflar)} sinifta yetersiz ornek)")

    def tani(self, karakterler: list) -> TanimaSonucu:
        if not len(self.M) or not karakterler:
            return TanimaSonucu("", [], False, self.ad)
        metin, guv = [], []
        for k in karakterler:
            skor = self.M @ _vektor(k.goruntu)
            i = int(np.argmax(skor))
            metin.append(str(self.etiket[i]))
            guv.append(float(max(0.0, skor[i])))
        return TanimaSonucu("".join(metin), guv, self.dogrulanmis, self.ad)


class OnnxTanima(Tanima):
    """Egitilmis karakter CNN'i. Girdi (N,1,B,B) float32 [0,1]; cikti (N,sinif) logit/olasilik."""
    ad = "onnx"

    def __init__(self, model: Path, p: dict):
        import onnxruntime as ort  # gec yukleme: modelsiz kurulumda gerekmez
        self.siniflar = p["siniflar"]
        self.boyut = int(p["karakter_boyut"])
        self.alternatif_k = int(p.get("alternatif_k", 3))
        self.oturum =ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
        girdi = self.oturum.get_inputs()[0]
        self.girdi_adi = girdi.name
        self.nhwc = len(girdi.shape) == 4 and girdi.shape[-1] == 1
        cikti = self.oturum.get_outputs()[0].shape
        if isinstance(cikti[-1], int) and cikti[-1] != len(self.siniflar):
            raise ValueError(f"Model {cikti[-1]} sinif veriyor, ayarda {len(self.siniflar)} var")
        # model dosyasi var = dogrulanmis; yeni model saha denemesinde model_onayli=false ile kalibrasyonda kalir
        self.dogrulanmis = bool(p.get("model_onayli", True))
        self.aciklama = f"onnx model: {model.name}" + ("" if self.dogrulanmis else " (model_onayli=false)")

    def tani(self, karakterler: list) -> TanimaSonucu:
        if not karakterler:
            return TanimaSonucu("", [], False, self.ad)
        x = np.stack([k.goruntu for k in karakterler]).astype(np.float32) / 255.0
        x = x[..., None] if self.nhwc else x[:, None, :, :]
        cikis = self.oturum.run(None, {self.girdi_adi: x})[0]
        e = np.exp(cikis - cikis.max(axis=1, keepdims=True))
        olasilik = e / e.sum(axis=1, keepdims=True)
        idx = olasilik.argmax(axis=1)
        k = max(1, int(self.alternatif_k))
        alt = []
        for r in range(olasilik.shape[0]):
            sirali = np.argsort(-olasilik[r])[:k]
            alt.append({self.siniflar[int(j)]: float(olasilik[r, j]) for j in sirali if olasilik[r, j] >= 0.02})
        return TanimaSonucu("".join(self.siniflar[i] for i in idx),
                            [float(olasilik[r, i]) for r, i in enumerate(idx)], self.dogrulanmis, self.ad, alt)


class KalibrasyonSarmalayici(Tanima):
    """Ic motoru sarar, sonucu HER ZAMAN dogrulanmamis isaretler."""
    ad = "kalibrasyon"

    def __init__(self, ic: Tanima, neden: str):
        self.ic, self.aciklama = ic, f"KALIBRASYON MODU: {neden}"

    def tani(self, karakterler: list) -> TanimaSonucu:
        s = self.ic.tani(karakterler)
        s.dogrulanmis = False
        s.kaynak = f"kalibrasyon/{s.kaynak}"
        return s


def olustur(ayar: dict, taban: Path | None = None) -> Tanima:
    p = ayar["tanima"]
    tur, neden = p["tur"], []
    if tur in ("otomatik", "onnx"):
        model = yol_coz(p["model_yolu"], taban)
        if model.is_file():
            try:
                o = OnnxTanima(model, p)
                if o.dogrulanmis:
                    return o
                return KalibrasyonSarmalayici(o, o.aciklama)
            except Exception as e:  # noqa: BLE001 - bozuk model => guvenli dusus
                neden.append(f"model yuklenemedi ({type(e).__name__}: {e})")
        else:
            neden.append(f"model dosyasi yok ({p['model_yolu']})")
    if tur in ("otomatik", "sablon"):
        s = SablonTanima(p, taban)
        if s.dogrulanmis:
            return s
        neden.append(s.aciklama)
        return KalibrasyonSarmalayici(s, "; ".join(neden))
    return KalibrasyonSarmalayici(SablonTanima({**p, "sablon_dizini": "__yok__"}, taban), "; ".join(neden))

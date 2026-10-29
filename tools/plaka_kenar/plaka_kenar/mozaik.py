"""Canli izleme mozaigi icin saf yerlesim hesaplari (tkinter/cv2 gerektirmez; birim testlenir).
N kamera -> 1/2/4/6/9 karoluk izgara (9'dan fazlasi kareye yakin izgara)."""
from __future__ import annotations

import math

# (en fazla kamera, (satir, sutun)) - otomatik yerlesim kademeleri
KADEMELER = ((1, (1, 1)), (2, (1, 2)), (4, (2, 2)), (6, (2, 3)), (9, (3, 3)))


def yerlesim(n: int) -> tuple:
    """N kamera icin (satir, sutun). 0 kamera -> (0, 0)."""
    if n <= 0:
        return (0, 0)
    for en_fazla, izgara in KADEMELER:
        if n <= en_fazla:
            return izgara
    sutun = math.ceil(math.sqrt(n))
    return (math.ceil(n / sutun), sutun)


def karo_kutulari(n: int, genislik: int, yukseklik: int, bosluk: int = 6) -> list:
    """N karonun [(x, y, w, h)] dikdortgenleri (soldan saga, yukaridan asagi); bos hucreler listeye girmez."""
    satir, sutun = yerlesim(n)
    if satir == 0 or genislik <= 0 or yukseklik <= 0:
        return []
    w = max(1, (genislik - bosluk * (sutun - 1)) // sutun)
    h = max(1, (yukseklik - bosluk * (satir - 1)) // satir)
    return [((i % sutun) * (w + bosluk), (i // sutun) * (h + bosluk), w, h) for i in range(n)]


def karo_bul(kutular: list, x: float, y: float):
    """(x, y) noktasinin dustugu karonun indeksi, yoksa None."""
    for i, (kx, ky, kw, kh) in enumerate(kutular):
        if kx <= x < kx + kw and ky <= y < ky + kh:
            return i
    return None


def sigdir(kare_w: int, kare_h: int, kutu_w: int, kutu_h: int) -> tuple:
    """Kareyi kutuya en-boy korunarak sigdirir: (ofset_x, ofset_y, w, h, olcek)."""
    if kare_w <= 0 or kare_h <= 0 or kutu_w <= 0 or kutu_h <= 0:
        return (0, 0, max(1, kutu_w), max(1, kutu_h), 1.0)
    olcek = min(kutu_w / kare_w, kutu_h / kare_h)
    w, h = max(1, int(kare_w * olcek)), max(1, int(kare_h * olcek))
    return ((kutu_w - w) // 2, (kutu_h - h) // 2, w, h, olcek)

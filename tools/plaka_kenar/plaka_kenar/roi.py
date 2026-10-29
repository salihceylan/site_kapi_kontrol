"""Kamera basina ROI (ilgi bolgesi): [x, y, w, h] kare boyutuna ORAN (0-1). Tam kare = [0, 0, 1, 1]."""
from __future__ import annotations

TAM = [0.0, 0.0, 1.0, 1.0]


def normalize(roi, min_oran: float = 0.05):
    """Gecerli ROI'yi [x, y, w, h] (kare icine kirpilmis) dondurur; None/bozuk/tam kare => None."""
    try:
        x, y, w, h = (float(v) for v in roi)
    except (TypeError, ValueError):
        return None
    x, y = min(max(x, 0.0), 1.0), min(max(y, 0.0), 1.0)
    w, h = min(w, 1.0 - x), min(h, 1.0 - y)
    if w < min_oran or h < min_oran:
        return None
    if x <= 0 and y <= 0 and w >= 1.0 and h >= 1.0:
        return None
    return [round(x, 4), round(y, 4), round(w, 4), round(h, 4)]


def kirp(kare, roi, min_oran: float = 0.05):
    """(kirpik, x0, y0): ROI'ye gore kare parcasi ve piksel kaymasi. Gecersiz/tam ROI => kare, 0, 0."""
    n = normalize(roi, min_oran)
    if n is None:
        return kare, 0, 0
    h, w = kare.shape[:2]
    x0, y0 = int(n[0] * w), int(n[1] * h)
    x1, y1 = max(x0 + 1, int(round((n[0] + n[2]) * w))), max(y0 + 1, int(round((n[1] + n[3]) * h)))
    return kare[y0:y1, x0:x1], x0, y0


def surukleden(x0: float, y0: float, x1: float, y1: float, genislik: float, yukseklik: float, min_oran: float = 0.05):
    """Goruntu uzerindeki fare surukleme noktalari (piksel) -> [x, y, w, h] oran; cok kucukse None."""
    if genislik <= 0 or yukseklik <= 0:
        return None
    a, b = sorted((x0, x1)), sorted((y0, y1))
    return normalize([a[0] / genislik, b[0] / yukseklik, (a[1] - a[0]) / genislik, (b[1] - b[0]) / yukseklik], min_oran)

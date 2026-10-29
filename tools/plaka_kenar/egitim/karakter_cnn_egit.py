"""Karakter CNN egitim ISKELETI (plan A4: sahada toplanan etiketli kareler -> ONNX). Uretimde YALNIZ .onnx gider.

Ayri ortamda calistirin (kenar uygulamasi torch icermez):   pip install torch opencv-python numpy
    python egitim/karakter_cnn_egit.py --veri egitim/veri --cikti modeller/karakter.onnx

Veri duzeni:  <veri>/<sinif>/*.png   (sinif = '0'..'9','A'..'Z' [Q,W,X yok]; 28x28 gri, BEYAZ karakter / SIYAH zemin)
Ornekler kenar uygulamasinin kendi Segmentleyici.normalize() cikisiyla ayni on-isleme ile uretilmelidir
(karar.kalibrasyon_kare_kaydet=true ile kaydedilen plaka kirpiklarindan segmentleyiciyle bolunup elle etiketlenir).
Model sinif sirasi ayarlar.json tanima.siniflar ile BIREBIR ayni olmalidir (varsayilan: plaka_kenar.ayarlar.SINIFLAR).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from plaka_kenar.ayarlar import SINIFLAR  # noqa: E402


def veri_yukle(kok: Path, siniflar: str, boyut: int):
    x, y = [], []
    for i, s in enumerate(siniflar):
        for f in sorted((kok / s).glob("*.png")) if (kok / s).is_dir() else []:
            g = cv2.imdecode(np.fromfile(str(f), np.uint8), cv2.IMREAD_GRAYSCALE)
            if g is not None:
                x.append(cv2.resize(g, (boyut, boyut), interpolation=cv2.INTER_AREA))
                y.append(i)
    if not x:
        raise SystemExit(f"Egitim verisi yok: {kok}")
    return np.stack(x).astype(np.float32)[:, None] / 255.0, np.array(y, np.int64)


def artir(x):
    """Kucuk kayma/donme/olcek + gurultu (torch tensor, N,1,B,B)."""
    import torch
    import torch.nn.functional as F
    n = x.shape[0]
    aci = (torch.rand(n) - 0.5) * 0.35
    olcek = 1 + (torch.rand(n) - 0.5) * 0.2
    kay = (torch.rand(n, 2) - 0.5) * 0.2
    teta = torch.zeros(n, 2, 3)
    teta[:, 0, 0], teta[:, 0, 1] = torch.cos(aci) / olcek, -torch.sin(aci) / olcek
    teta[:, 1, 0], teta[:, 1, 1] = torch.sin(aci) / olcek, torch.cos(aci) / olcek
    teta[:, :, 2] = kay
    return (F.grid_sample(x, F.affine_grid(teta, x.shape, align_corners=False), align_corners=False)
            + 0.03 * torch.randn_like(x)).clamp(0, 1)


def model_kur(k: int, boyut: int):
    import torch.nn as nn
    c = boyut // 4
    return nn.Sequential(
        nn.Conv2d(1, 16, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
        nn.Conv2d(16, 32, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
        nn.Flatten(), nn.Linear(32 * c * c, 96), nn.ReLU(), nn.Dropout(0.2), nn.Linear(96, k))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--veri", default="egitim/veri")
    ap.add_argument("--cikti", default="modeller/karakter.onnx")
    ap.add_argument("--siniflar", default=SINIFLAR)
    ap.add_argument("--boyut", type=int, default=28)
    ap.add_argument("--epoch", type=int, default=40)
    ap.add_argument("--dogrulama_orani", type=float, default=0.15)
    a = ap.parse_args()
    import torch
    x, y = veri_yukle(Path(a.veri), a.siniflar, a.boyut)
    sira = np.random.default_rng(0).permutation(len(x))
    nv = max(1, int(len(x) * a.dogrulama_orani))
    xv, yv = torch.tensor(x[sira[:nv]]), torch.tensor(y[sira[:nv]])
    xt, yt = torch.tensor(x[sira[nv:]]), torch.tensor(y[sira[nv:]])
    m = model_kur(len(a.siniflar), a.boyut)
    opt = torch.optim.Adam(m.parameters(), 1e-3)
    for e in range(a.epoch):
        m.train()
        for b in torch.randperm(len(xt)).split(64):
            opt.zero_grad()
            torch.nn.functional.cross_entropy(m(artir(xt[b])), yt[b]).backward()
            opt.step()
        m.eval()
        with torch.no_grad():
            dogru = (m(xv).argmax(1) == yv).float().mean().item()
        print(f"epoch {e + 1}/{a.epoch}  dogrulama dogrulugu {dogru:.3f}")
    Path(a.cikti).parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(m, torch.zeros(1, 1, a.boyut, a.boyut), a.cikti, input_names=["girdi"], output_names=["logit"],
                      dynamic_axes={"girdi": {0: "n"}, "logit": {0: "n"}}, opset_version=17)
    print(f"Yazildi: {a.cikti}  (sinif sirasi: {a.siniflar}). Yeni modeli once ayarlarda "
          "tanima.model_onayli=false ile deneyin (okumalar dogrulanmamis kalir, kapi acilmaz); saha basarisi kabul edilince true yapin.")


if __name__ == "__main__":
    main()

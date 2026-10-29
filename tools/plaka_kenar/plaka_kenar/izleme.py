"""Canli izleme sekmesi (musteri demosu): kamera goruntusu, tespit kutusu + okunan plaka, karar rozeti,
FPS / islem suresi / guven gostergesi, fare ile ROI secimi. Koyu tema; PIL ImageTk ile goruntu.
Bu sekme KARE ISLEMEZ: servisin son karesini ve boru hattinin son analiz ozetini gosterir (kapiyi tetiklemez)."""
from __future__ import annotations

import threading
import time
import tkinter as tk
from tkinter import ttk

import cv2

from . import ayarlar, roi as roimod, yakalama

try:  # pillow yoksa sekme uyari gosterir, uygulamanin geri kalani calisir
    from PIL import Image, ImageTk
except ImportError:  # pragma: no cover
    Image = ImageTk = None

# ui_kit paletinin (NAVY / PRIMARY / SUCCESS / DANGER) koyu tema karsiliklari
K_BG, K_PANEL, K_KENAR = "#0E151C", "#16202A", "#243241"
K_METIN, K_METIN2 = "#E8EEF3", "#93A4B4"
K_ACCENT, K_YESIL, K_KIRMIZI, K_GRI, K_SARI = "#1FB6BE", "#1E9E5A", "#D13B3B", "#5B6B7A", "#E0A526"

ROZETLER = {  # karar kodu -> (etiket, renk)
    "acildi": ("AÇILDI", K_YESIL), "red": ("RED", K_KIRMIZI), "kara_liste": ("RED", K_KIRMIZI),
    "acma_basarisiz": ("RED", K_KIRMIZI), "tanimsiz": ("TANIMSIZ", K_GRI), "dogrulanmamis": ("TANIMSIZ", K_GRI)}
BEKLEME = ("BEKLİYOR", K_PANEL)


def rozet_bilgi(karar: str | None) -> tuple:
    return ROZETLER.get(karar or "", BEKLEME)


def guven_rengi(guven: float, min_guven: float, esik: float) -> str:
    return K_YESIL if guven >= esik else (K_SARI if guven >= min_guven else K_KIRMIZI)


class CanliSekme(tk.Frame):
    def __init__(self, ust, uyg):
        super().__init__(ust, bg=K_BG)
        self.uyg = uyg
        self.rozet: dict = {}  # kamera -> (karar, plaka, zaman)
        self._on_kare = None  # servis calismiyorsa onizleme karesi
        self._foto = None
        self._ofs, self._olcek, self._boyut = (0, 0), 1.0, (1, 1)
        self._surukle = None
        self._roi_modu = False
        self._acik = True
        self.kam_v = tk.StringVar()
        self._ust_cubuk()
        govde = tk.Frame(self, bg=K_BG)
        govde.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        self.tuval = tk.Canvas(govde, bg="#000000", highlightthickness=1, highlightbackground=K_KENAR)
        self.tuval.pack(side="left", fill="both", expand=True)
        self.tuval.bind("<ButtonPress-1>", self._bas)
        self.tuval.bind("<B1-Motion>", self._surukle_fn)
        self.tuval.bind("<ButtonRelease-1>", self._birak)
        self._yan_panel(govde)
        self.after(300, self._tik)

    # --- yerlesim ------------------------------------------------------------------------
    def _ust_cubuk(self) -> None:
        c = tk.Frame(self, bg=K_BG)
        c.pack(fill="x", padx=10, pady=8)
        tk.Label(c, text="Kamera", bg=K_BG, fg=K_METIN2).pack(side="left")
        self.kam_kutu = ttk.Combobox(c, textvariable=self.kam_v, state="readonly", width=24)
        self.kam_kutu.pack(side="left", padx=(6, 12))
        self.kam_kutu.bind("<<ComboboxSelected>>", lambda _e: self._on_kare_sifirla())
        for ad, cmd in (("Önizleme al", self._onizleme), ("ROI seç", self._roi_ac), ("ROI temizle", self._roi_temizle),
                        ("ROI kaydet", self._roi_kaydet)):
            tk.Button(c, text=ad, command=cmd, bg=K_PANEL, fg=K_METIN, activebackground=K_KENAR, activeforeground=K_METIN,
                      relief="flat", padx=12, pady=4, bd=0).pack(side="left", padx=(0, 8))
        self.ipucu = tk.Label(c, text="", bg=K_BG, fg=K_SARI)
        self.ipucu.pack(side="left", padx=8)
        self.yenile_kameralar()

    def _yan_panel(self, ust) -> None:
        y = tk.Frame(ust, bg=K_PANEL, width=270, highlightthickness=1, highlightbackground=K_KENAR)
        y.pack(side="right", fill="y", padx=(10, 0))
        y.pack_propagate(False)
        self.rozet_l = tk.Label(y, text=BEKLEME[0], bg=BEKLEME[1], fg=K_METIN, font=("Segoe UI Semibold", 20), pady=14)
        self.rozet_l.pack(fill="x", padx=14, pady=(14, 8))
        self.plaka_l = tk.Label(y, text="—", bg=K_PANEL, fg=K_METIN, font=("Consolas", 22, "bold"))
        self.plaka_l.pack(pady=(4, 0))
        self.alt_l = tk.Label(y, text="", bg=K_PANEL, fg=K_METIN2, font=("Segoe UI", 9))
        self.alt_l.pack()
        tk.Label(y, text="Güven", bg=K_PANEL, fg=K_METIN2).pack(anchor="w", padx=14, pady=(16, 2))
        self.guven_c = tk.Canvas(y, height=16, bg=K_BG, highlightthickness=0)
        self.guven_c.pack(fill="x", padx=14)
        self.guven_l = tk.Label(y, text="0.00", bg=K_PANEL, fg=K_METIN, font=("Segoe UI Semibold", 11))
        self.guven_l.pack(anchor="e", padx=14)
        self.metrik = {}
        for anahtar, etiket in (("fps", "FPS"), ("sure", "İşlem süresi"), ("profil", "Profil"), ("kons", "Konsensus")):
            satir = tk.Frame(y, bg=K_PANEL)
            satir.pack(fill="x", padx=14, pady=3)
            tk.Label(satir, text=etiket, bg=K_PANEL, fg=K_METIN2).pack(side="left")
            self.metrik[anahtar] = tk.Label(satir, text="—", bg=K_PANEL, fg=K_METIN, font=("Segoe UI Semibold", 10))
            self.metrik[anahtar].pack(side="right")

    # --- kamera / ROI ---------------------------------------------------------------------
    def yenile_kameralar(self) -> None:
        adlar = [k["id"] for k in self.uyg.ayar["kameralar"]]
        self.kam_kutu.configure(values=adlar)
        if adlar and self.kam_v.get() not in adlar:
            self.kam_v.set(adlar[0])

    def _kamera(self) -> dict | None:
        for k in self.uyg.ayar["kameralar"]:
            if k["id"] == self.kam_v.get():
                return k
        return None

    def _on_kare_sifirla(self) -> None:
        self._on_kare = None

    def _onizleme(self) -> None:
        k = self._kamera()
        if not k:
            return
        self.ipucu.configure(text="Kare alınıyor...")

        def is_() -> None:
            kare, hata = yakalama.tek_kare(k["url"], self.uyg.ayar["yakalama"])
            self.after(0, lambda: self._onizleme_bitti(kare, hata))
        threading.Thread(target=is_, daemon=True).start()

    def _onizleme_bitti(self, kare, hata: str) -> None:
        self._on_kare = kare
        self.ipucu.configure(text="" if kare is not None else f"Kare alınamadı: {hata}")

    def _roi_ac(self) -> None:
        self._roi_modu = True
        self.ipucu.configure(text="Fareyle plaka bölgesini sürükleyin")

    def _roi_temizle(self) -> None:
        k = self._kamera()
        if k:
            k.pop("roi", None)
            self.ipucu.configure(text="ROI temizlendi (tam kare)")

    def _roi_kaydet(self) -> None:
        self.uyg._formu_ayara_yaz()
        yol = ayarlar.kaydet(self.uyg.ayar, self.uyg.ayar_yolu)
        self.ipucu.configure(text=f"Kaydedildi: {yol.name}")

    def _bas(self, e) -> None:
        if self._roi_modu:
            self._surukle = [e.x, e.y, e.x, e.y]

    def _surukle_fn(self, e) -> None:
        if self._surukle:
            self._surukle[2:] = [e.x, e.y]

    def _birak(self, e) -> None:
        if not self._surukle:
            return
        x0, y0, _, _ = self._surukle
        self._surukle = None
        self._roi_modu = False
        gen, yuk = self._boyut
        r = roimod.surukleden((x0 - self._ofs[0]) / self._olcek, (y0 - self._ofs[1]) / self._olcek,
                              (e.x - self._ofs[0]) / self._olcek, (e.y - self._ofs[1]) / self._olcek, gen, yuk,
                              float(self.uyg.ayar["izleme"]["min_roi"]))
        k = self._kamera()
        if r is None or not k:
            self.ipucu.configure(text="Bölge çok küçük; tekrar deneyin")
            return
        k["roi"] = r  # servis ayni ayar sozlugunu paylasir: aninda gecerli; kalici icin 'ROI kaydet'
        self.ipucu.configure(text=f"ROI {r} — kalıcı için 'ROI kaydet'")

    # --- olaylar ------------------------------------------------------------------------------
    def olay(self, o: dict) -> None:
        """Uygulama olay kuyrugundan gelen karar olayi (kapi karari)."""
        self.rozet[o["kamera_id"]] = (o["karar"], o.get("plaka", ""), time.time())

    # --- cizim --------------------------------------------------------------------------------
    def _kare_bilgi(self):
        k = self._kamera()
        if not k:
            return None, None, k
        s = self.uyg.servis
        if self.uyg.calisiyor and s is not None:
            kt = s.son_kare.get(k["id"])
            if kt is not None:
                return kt[0], s.boru.son.get(k["id"]), k
        return self._on_kare, None, k

    def _tik(self) -> None:
        if not self._acik:
            return
        try:
            if self.winfo_ismapped():
                self._ciz()
        except tk.TclError:
            return
        self.after(int(1000 / max(1, float(self.uyg.ayar["izleme"]["fps"]))), self._tik)

    def _ciz(self) -> None:
        kare, bilgi, kam = self._kare_bilgi()
        t = self.tuval
        t.delete("all")
        cw, ch = max(2, t.winfo_width()), max(2, t.winfo_height())
        if Image is None:
            t.create_text(cw // 2, ch // 2, text="Görüntü için Pillow gerekli: pip install pillow", fill=K_SARI)
            return
        if kare is None:
            t.create_text(cw // 2, ch // 2, fill=K_METIN2, justify="center", font=("Segoe UI", 12),
                          text="Canlı görüntü için Genel sekmesinde Başlat'a basın\nveya 'Önizleme al' ile tek kare çekin")
            self._paneli_guncelle(None, None, kam)
            return
        yuk, gen = kare.shape[:2]
        self._boyut = (gen, yuk)
        olcek = min(cw / gen, ch / yuk)
        w, h = max(1, int(gen * olcek)), max(1, int(yuk * olcek))
        goster = cv2.resize(kare if kare.ndim == 3 else cv2.cvtColor(kare, cv2.COLOR_GRAY2BGR), (w, h), interpolation=cv2.INTER_AREA)
        self._foto = ImageTk.PhotoImage(Image.fromarray(cv2.cvtColor(goster, cv2.COLOR_BGR2RGB)))
        ox, oy = (cw - w) // 2, (ch - h) // 2
        self._ofs, self._olcek = (ox, oy), olcek
        t.create_image(ox, oy, anchor="nw", image=self._foto)
        roi = roimod.normalize(kam.get("roi")) if kam else None
        if roi:
            t.create_rectangle(ox + roi[0] * w, oy + roi[1] * h, ox + (roi[0] + roi[2]) * w, oy + (roi[1] + roi[3]) * h,
                               outline=K_SARI, dash=(6, 4), width=2)
        if self._surukle:
            a, b, c, d = self._surukle
            t.create_rectangle(a, b, c, d, outline=K_ACCENT, width=2, dash=(4, 3))
        if bilgi and bilgi.get("kutu") and time.time() - bilgi["zaman"] < 2.5:
            x, y, kw, kh = bilgi["kutu"]
            plaka = bilgi.get("konsensus") or bilgi.get("anlik") or ""
            x1, y1 = ox + x * olcek, oy + y * olcek
            t.create_rectangle(x1, y1, x1 + kw * olcek, y1 + kh * olcek, outline=K_YESIL, width=3)
            if plaka:
                t.create_rectangle(x1, y1 - 24, x1 + 14 + 11 * len(plaka), y1, fill=K_YESIL, outline=K_YESIL)
                t.create_text(x1 + 7, y1 - 12, text=plaka, anchor="w", fill="#FFFFFF", font=("Consolas", 12, "bold"))
        self._paneli_guncelle(bilgi, kare, kam)

    def _paneli_guncelle(self, bilgi, kare, kam) -> None:
        kid = kam["id"] if kam else ""
        karar, plaka_karar, zaman = self.rozet.get(kid, (None, "", 0.0))
        if time.time() - zaman > float(self.uyg.ayar["izleme"]["rozet_sn"]):
            karar = None
        etiket, renk = rozet_bilgi(karar)
        self.rozet_l.configure(text=etiket, bg=renk)
        b = bilgi or {}
        plaka = (plaka_karar if karar else "") or b.get("konsensus") or b.get("anlik") or "—"
        self.plaka_l.configure(text=plaka)
        self.alt_l.configure(text=(f"anlık: {b['anlik']}" if b.get("anlik") and b.get("konsensus") else ""))
        guven = float(b.get("guven", 0.0))
        self.guven_c.update_idletasks()
        gw = max(1, self.guven_c.winfo_width())
        self.guven_c.delete("all")
        self.guven_c.create_rectangle(0, 0, gw * min(1.0, guven), 16, fill=guven_rengi(
            guven, float(self.uyg.ayar["plaka"]["min_guven"]), float(self.uyg.ayar["konsensus"]["guven_esik"])), width=0)
        self.guven_l.configure(text=f"{guven:.2f}")
        self.metrik["fps"].configure(text=f"{b['fps']:.1f}" if b else "—")
        self.metrik["sure"].configure(text=f"{b['sure_ms']:.0f} ms" if b else "—")
        self.metrik["profil"].configure(text=b.get("profil", "—") if b else "—")
        self.metrik["kons"].configure(text="açık" if self.uyg.ayar["konsensus"]["etkin"] else "kapalı")

    def kapat(self) -> None:
        self._acik = False

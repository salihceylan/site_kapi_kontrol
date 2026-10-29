"""Canli izleme sekmesi: EKLENEN TUM kameralar ayni anda MOZAIK izgarada (1/2/4/6/9 karo otomatik).
Her karo: kucultulmus akici goruntu (isleme hizindan bagimsiz, ayri goruntu akisi), kamera adi + yon etiketi,
son okunan plaka + karar rozeti, goruntu kesilirse 'GORUNTU YOK'. Karoya tiklayinca o kamera buyur (tek kamera modu:
tespit kutusu, guven gostergesi, fare ile ROI secimi); 'Mozaik' dugmesi geri doner. Koyu tema; PIL ImageTk ile goruntu.
Bu sekme KARE ISLEMEZ: servisin goruntu yayinini ve boru hattinin son analiz ozetini gosterir (kapiyi tetiklemez).
Servis calismiyorken (ya da kamera 'tetik' modundaysa) sekme gorunurken yalniz-goruntu onizleme akisi acar, gorunmezken kapatir."""
from __future__ import annotations

import time
import tkinter as tk
from tkinter import ttk

import cv2

from . import ayarlar, gosterim, mozaik, roi as roimod, yakalama

try:  # pillow yoksa sekme uyari gosterir, uygulamanin geri kalani calisir
    from PIL import Image, ImageTk
except ImportError:  # pragma: no cover
    Image = ImageTk = None

# ui_kit paletinin (NAVY / PRIMARY / SUCCESS / DANGER) koyu tema karsiliklari
K_BG, K_PANEL, K_KENAR = "#0E151C", "#16202A", "#243241"
K_METIN, K_METIN2 = "#E8EEF3", "#93A4B4"
K_ACCENT, K_YESIL, K_KIRMIZI, K_GRI, K_SARI = "#1FB6BE", "#1E9E5A", "#D13B3B", "#5B6B7A", "#E0A526"
K_KARO = "#05090D"

TON_RENK = {"yesil": K_YESIL, "kirmizi": K_KIRMIZI, "gri": K_GRI}
# karar kodu -> (etiket, renk). Kapi durumu AYRI rozettir (gosterim.kapi_rozeti): "açıldı" yalnız cihaz bildirirse yazılır (P1-15).
ROZETLER = {kod: (etiket, TON_RENK[ton]) for kod, (etiket, ton) in gosterim.KARAR_ROZET.items()}
BEKLEME = ("BEKLİYOR", K_PANEL)
YON_ETIKET = {"giris": ("GİRİŞ", K_YESIL), "cikis": ("ÇIKIŞ", K_SARI)}
DURUM_METNI = {"koptu": "bağlantı koptu — yeniden bağlanıyor", "bagli": "bağlandı, kare bekleniyor", "bekliyor": "bağlanıyor…",
               "": "bağlanıyor…"}


def rozet_bilgi(karar: str | None) -> tuple:
    return ROZETLER.get(karar or "", BEKLEME)


def guven_rengi(guven: float, min_guven: float, esik: float) -> str:
    return K_YESIL if guven >= esik else (K_SARI if guven >= min_guven else K_KIRMIZI)


class CanliSekme(tk.Frame):
    def __init__(self, ust, uyg):
        super().__init__(ust, bg=K_BG)
        self.uyg = uyg
        self.secili: str | None = None  # None = mozaik; kamera kodu = tek kamera modu
        self.rozet: dict = {}  # kamera -> (karar, plaka, zaman) son okuma
        self.ek: dict = {}  # kamera -> (kimlik satiri, kapi_komut) son okuma (v3: "Daire A - 5 · Ali Y." + "Kapı tetiklendi ✓")
        self._onizleme: dict = {}  # kamera -> yalniz-goruntu AkisKaynagi (servis o kamerayi akitmiyorsa)
        self._on_goruntu: dict = {}  # kamera -> (kucultulmus kare, zaman)
        self._on_durum: dict = {}
        self._foto: dict = {}  # kamera -> (anahtar, PhotoImage, (ox, oy, w, h, olcek))
        self._kutular: list = []  # mozaik karo dikdortgenleri
        self._karo_idleri: list = []
        self._ofs, self._olcek, self._boyut = (0, 0), 1.0, (1, 1)
        self._surukle = None
        self._roi_modu = False
        self._acik = True
        self._ust_cubuk()
        govde = tk.Frame(self, bg=K_BG)
        govde.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        self.tuval = tk.Canvas(govde, bg="#000000", highlightthickness=1, highlightbackground=K_KENAR)
        self.tuval.pack(side="left", fill="both", expand=True)
        self.tuval.bind("<ButtonPress-1>", self._bas)
        self.tuval.bind("<B1-Motion>", self._surukle_fn)
        self.tuval.bind("<ButtonRelease-1>", self._birak)
        self._govde = govde
        self._yan_panel(govde)
        self.yan.pack_forget()  # yalniz tek kamera modunda gorunur
        self.after(300, self._tik)

    # --- yerlesim ------------------------------------------------------------------------
    def _ust_cubuk(self) -> None:
        c = tk.Frame(self, bg=K_BG)
        c.pack(fill="x", padx=10, pady=8)
        self.geri_dugme = tk.Button(c, text="◀ Mozaik", command=self.mozaige_don, bg=K_ACCENT, fg="#FFFFFF", activebackground=K_ACCENT,
                                    relief="flat", padx=12, pady=4, bd=0)
        self.baslik_l = tk.Label(c, text="", bg=K_BG, fg=K_METIN, font=("Segoe UI Semibold", 11))
        self.baslik_l.pack(side="left", padx=(0, 12))
        self.roi_kap = tk.Frame(c, bg=K_BG)
        for ad, cmd in (("ROI seç", self._roi_ac), ("ROI temizle", self._roi_temizle), ("ROI kaydet", self._roi_kaydet)):
            tk.Button(self.roi_kap, text=ad, command=cmd, bg=K_PANEL, fg=K_METIN, activebackground=K_KENAR, activeforeground=K_METIN,
                      relief="flat", padx=12, pady=4, bd=0).pack(side="left", padx=(0, 8))
        self.ipucu = tk.Label(c, text="", bg=K_BG, fg=K_SARI)
        self.ipucu.pack(side="left", padx=8)
        self._ust_guncelle()

    def _ust_guncelle(self) -> None:
        if self.secili is None:
            self.geri_dugme.pack_forget()
            self.roi_kap.pack_forget()
            n = len(self.etkin_kameralar())
            self.baslik_l.configure(text=f"Canlı mozaik — {n} kamera" if n else "Canlı mozaik")
            if not self.ipucu.cget("text").startswith(("ROI", "Kaydedildi", "Bölge")):
                self.ipucu.configure(text="Büyütmek için bir karoya tıklayın" if n else "")
        else:
            self.geri_dugme.pack(side="left", padx=(0, 10), before=self.baslik_l)
            self.roi_kap.pack(side="left", before=self.ipucu)
            self.baslik_l.configure(text=self.secili)

    def _yan_panel(self, ust) -> None:
        y = self.yan = tk.Frame(ust, bg=K_PANEL, width=270, highlightthickness=1, highlightbackground=K_KENAR)
        y.pack(side="right", fill="y", padx=(10, 0))
        y.pack_propagate(False)
        self.rozet_l = tk.Label(y, text=BEKLEME[0], bg=BEKLEME[1], fg=K_METIN, font=("Segoe UI Semibold", 20), pady=14)
        self.rozet_l.pack(fill="x", padx=14, pady=(14, 8))
        self.plaka_l = tk.Label(y, text="—", bg=K_PANEL, fg=K_METIN, font=("Consolas", 22, "bold"))
        self.plaka_l.pack(pady=(4, 0))
        self.alt_l = tk.Label(y, text="", bg=K_PANEL, fg=K_METIN2, font=("Segoe UI", 9))
        self.alt_l.pack()
        self.kimlik_l = tk.Label(y, text="", bg=K_PANEL, fg=K_METIN, font=("Segoe UI Semibold", 10), wraplength=240)
        self.kimlik_l.pack(pady=(4, 0))
        self.kapi_l = tk.Label(y, text="", bg=K_PANEL, fg="#FFFFFF", font=("Segoe UI Semibold", 9), padx=8, pady=2)
        self.kapi_l.pack(pady=(4, 0))
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

    # --- kamera listesi / mod ------------------------------------------------------------------
    def etkin_kameralar(self) -> list:
        return [k for k in self.uyg.ayar["kameralar"] if k.get("etkin", True) and k.get("id")]

    def yenile_kameralar(self) -> None:
        if self.secili is not None and self.secili not in [k["id"] for k in self.etkin_kameralar()]:
            self.secili = None
            self.yan.pack_forget()
        self._ust_guncelle()

    def _kamera(self) -> dict | None:
        return next((k for k in self.uyg.ayar["kameralar"] if k["id"] == self.secili), None)

    def tek_ac(self, kid: str) -> None:
        self.secili = kid
        self._surukle, self._roi_modu = None, False
        self.ipucu.configure(text="")
        self.yan.pack(side="right", fill="y", padx=(10, 0))
        self._ust_guncelle()

    def mozaige_don(self) -> None:
        self.secili = None
        self._surukle, self._roi_modu = None, False
        self.ipucu.configure(text="")
        self.yan.pack_forget()
        self._ust_guncelle()

    # --- goruntu kaynaklari ------------------------------------------------------------------------
    def _servis_akisi(self, kid: str):
        s = self.uyg.servis
        return s.akis(kid) if (self.uyg.calisiyor and s is not None) else None

    def _kare_al(self, kid: str):
        """(kucultulmus kare, zaman) ya da None: servis akitiyorsa onun yayini, degilse onizleme akisi."""
        if self._servis_akisi(kid) is not None:
            return self.uyg.servis.goruntu.get(kid)
        return self._on_goruntu.get(kid)

    def _durum_al(self, kid: str) -> str:
        if self._servis_akisi(kid) is not None:
            return self.uyg.servis.kam_durum.get(kid, {}).get("durum", "")
        return self._on_durum.get(kid, "")

    def _on_goruntu_cb(self, kid: str, kare, t: float) -> None:
        self._on_goruntu[kid] = (kare, t)

    def _on_durum_cb(self, kid: str, durum: str) -> None:
        self._on_durum[kid] = durum

    def _akislari_yonet(self, gorunur: bool) -> None:
        """Gorunmeyen sekmede goruntu uretimi kapanir (yalniz grab); gorunurken yalniz izlenen kameralar karo/buyuk boyda yayin yapar.
        Servisin akitmadigi kameralar icin yalniz-goruntu onizleme akisi acilir/kapatilir."""
        iz = self.uyg.ayar["izleme"]
        izlenen = {k["id"]: k for k in self.etkin_kameralar() if self.secili in (None, k["id"])} if gorunur else {}
        for kid, k in izlenen.items():
            a = self._servis_akisi(kid)
            if a is not None:
                a.goruntu_acik = True
                a.goruntu_yukseklik = int(iz["buyuk_yukseklik"] if kid == self.secili else iz["karo_yukseklik"])
        if self.uyg.servis is not None and self.uyg.calisiyor:
            for a in self.uyg.servis._akislar:
                if a.kam["id"] not in izlenen:
                    a.goruntu_acik = False
        gerekli = {kid: k for kid, k in izlenen.items() if self._servis_akisi(kid) is None and k.get("url")}
        for kid, a in list(self._onizleme.items()):
            k = gerekli.get(kid)
            if k is None or a.kam is not k:  # kapandi / duzenlendi (yeni sozluk) / servis devraldi
                a.dur.set()
                del self._onizleme[kid]
                self._on_goruntu.pop(kid, None)
                self._on_durum.pop(kid, None)
        for kid, k in gerekli.items():
            if kid not in self._onizleme:
                a = yakalama.AkisKaynagi(k, self.uyg.ayar["yakalama"], None, self._on_durum_cb, self._on_goruntu_cb, iz)
                self._onizleme[kid] = a
                a.start()
            self._onizleme[kid].goruntu_yukseklik = int(iz["buyuk_yukseklik"] if kid == self.secili else iz["karo_yukseklik"])

    # --- ROI ---------------------------------------------------------------------------------------
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
        if self.secili is None:
            i = mozaik.karo_bul(self._kutular, e.x, e.y)
            kam = self.etkin_kameralar()
            if i is not None and i < len(kam):
                self.tek_ac(kam[i]["id"])
        elif self._roi_modu:
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
        self.ek[o["kamera_id"]] = (gosterim.kimlik_satiri(o), o.get("kapi_komut", ""))

    # --- cizim --------------------------------------------------------------------------------
    def _tik(self) -> None:
        if not self._acik:
            return
        try:
            gorunur = self.winfo_ismapped()
            self._akislari_yonet(gorunur)
            if gorunur:
                self._ciz()
        except tk.TclError:
            return
        self.after(int(1000 / max(1, float(self.uyg.ayar["izleme"]["fps"]))), self._tik)

    def _foto_hazirla(self, kid: str, kt: tuple, kw: int, kh: int):
        """Kareyi (kw x kh) kutuya sigdirilmis PhotoImage'a cevirir; ayni kare/boyut icin onbellekten verir."""
        kare, zaman = kt
        anahtar = (zaman, kw, kh)
        c = self._foto.get(kid)
        if c is not None and c[0] == anahtar:
            return c[1], c[2]
        fh, fw = kare.shape[:2]
        ox, oy, w, h, olcek = mozaik.sigdir(fw, fh, kw, kh)
        goster = kare if kare.ndim == 3 else cv2.cvtColor(kare, cv2.COLOR_GRAY2BGR)
        if (w, h) != (fw, fh):
            goster = cv2.resize(goster, (w, h), interpolation=cv2.INTER_AREA if w < fw else cv2.INTER_LINEAR)
        foto = ImageTk.PhotoImage(Image.fromarray(cv2.cvtColor(goster, cv2.COLOR_BGR2RGB)))
        self._foto[kid] = (anahtar, foto, (ox, oy, w, h, olcek))
        return foto, (ox, oy, w, h, olcek)

    def _ciz(self) -> None:
        t = self.tuval
        t.delete("all")
        cw, ch = max(2, t.winfo_width()), max(2, t.winfo_height())
        self._ust_guncelle_hafif()
        if Image is None:
            t.create_text(cw // 2, ch // 2, text="Görüntü için Pillow gerekli: pip install pillow", fill=K_SARI)
            return
        kameralar = self.etkin_kameralar()
        if not kameralar:
            t.create_text(cw // 2, ch // 2, fill=K_METIN2, justify="center", font=("Segoe UI", 12),
                          text="Henüz kamera yok.\nKameralar sekmesinden 'Ağda kamera ara' ya da 'El ile ekle' ile ekleyin.")
            return
        if self.secili is not None and self.secili not in [k["id"] for k in kameralar]:
            self.mozaige_don()
        if self.secili is None:
            self._kutular = mozaik.karo_kutulari(len(kameralar), cw, ch)
            for k, (x, y, w, h) in zip(kameralar, self._kutular):
                self._karo_ciz(k, x, y, w, h)
        else:
            self._tek_ciz(self._kamera(), cw, ch)

    def _ust_guncelle_hafif(self) -> None:
        if self.secili is None:
            n = len(self.etkin_kameralar())
            ad = f"Canlı mozaik — {n} kamera" if n else "Canlı mozaik"
            if self.baslik_l.cget("text") != ad:
                self._ust_guncelle()

    def _etiketler(self, kid: str, kam: dict, x: float, y: float, w: float, h: float, buyuk: bool = False) -> None:
        """Karo ustu serit: kamera adi + yon etiketi; alt serit: son okunan plaka + karar rozeti."""
        t = self.tuval
        ust_y = 22
        t.create_rectangle(x, y, x + w, y + ust_y, fill=K_BG, outline="")
        yon = YON_ETIKET.get(kam.get("yon", ""))
        ad = str(kam.get("ad") or kid)
        t.create_text(x + 8, y + ust_y / 2, text=ad, anchor="w", fill=K_METIN, font=("Segoe UI Semibold", 10))
        if yon:
            gw = 62
            t.create_rectangle(x + w - gw - 4, y + 3, x + w - 4, y + ust_y - 3, fill=yon[1], outline="")
            t.create_text(x + w - gw / 2 - 4, y + ust_y / 2, text=yon[0], fill="#0B1218", font=("Segoe UI Semibold", 8))
        if h < 110:
            return
        karar, plaka, zaman = self.rozet.get(kid, (None, "", 0.0))
        taze = karar is not None and time.time() - zaman <= float(self.uyg.ayar["izleme"]["rozet_sn"])
        etiket, renk = rozet_bilgi(karar) if taze else (("ESKİ", K_GRI) if karar else ("", K_GRI))
        kimlik, kapi_komut = self.ek.get(kid, ("", "")) if taze else ("", "")
        kapi_r = gosterim.kapi_rozeti(kapi_komut)
        ek_satir = bool(kimlik or kapi_r)  # v3: plakanin ustunde kimlik ("Daire A - 5 · Ali Y.") + kapi durumu ("Kapı tetiklendi ✓")
        alt = 26 + (20 if ek_satir else 0)
        t.create_rectangle(x, y + h - alt, x + w, y + h, fill=K_BG, outline="")
        if ek_satir:
            yy, rw = y + h - alt + 10, 140
            sigar = max(6, int((w - (rw if kapi_r else 0) - 20) / 6))
            if kimlik:
                t.create_text(x + 8, yy, text=kimlik[:sigar], anchor="w", fill=K_METIN2, font=("Segoe UI", 9))
            if kapi_r:
                t.create_rectangle(x + w - rw - 4, yy - 8, x + w - 4, yy + 8, fill=TON_RENK[kapi_r[1]], outline="")
                t.create_text(x + w - rw / 2 - 4, yy, text=kapi_r[0], fill="#FFFFFF", font=("Segoe UI Semibold", 8))
        t.create_text(x + 8, y + h - 13, text=plaka or "—", anchor="w", fill=K_METIN if taze else K_METIN2,
                      font=("Consolas", 12, "bold"))
        if etiket:
            bw = 84
            t.create_rectangle(x + w - bw - 4, y + h - 23, x + w - 4, y + h - 3, fill=renk, outline="")
            t.create_text(x + w - bw / 2 - 4, y + h - 13, text=etiket, fill="#FFFFFF", font=("Segoe UI Semibold", 9))

    def _goruntu_yok(self, kid: str, x: float, y: float, w: float, h: float) -> None:
        t = self.tuval
        t.create_text(x + w / 2, y + h / 2 - 8, text="GÖRÜNTÜ YOK", fill=K_SARI, font=("Segoe UI Semibold", 13))
        t.create_text(x + w / 2, y + h / 2 + 14, text=DURUM_METNI.get(self._durum_al(kid), self._durum_al(kid)),
                      fill=K_METIN2, font=("Segoe UI", 9), width=max(40, w - 16), justify="center")

    def _kutu_ciz(self, kid: str, ox: float, oy: float, fw: int, olcek: float, ince: bool) -> None:
        """Boru hattinin son tespit kutusu (orijinal cozunurluk -> gosterilen goruntuye orantili)."""
        s = self.uyg.servis
        b = s.boru.son.get(kid) if (s is not None and self.uyg.calisiyor) else None
        if not b or not b.get("kutu") or time.time() - b["zaman"] >= 2.5 or not b.get("kare"):
            return
        o = fw / b["kare"][0]
        x, y, kw, kh = b["kutu"]
        x1, y1 = ox + x * o, oy + y * o
        self.tuval.create_rectangle(x1, y1, x1 + kw * o, y1 + kh * o, outline=K_YESIL, width=2 if ince else 3)
        plaka = b.get("konsensus") or b.get("anlik") or ""
        if plaka and not ince:
            self.tuval.create_rectangle(x1, y1 - 24, x1 + 14 + 11 * len(plaka), y1, fill=K_YESIL, outline=K_YESIL)
            self.tuval.create_text(x1 + 7, y1 - 12, text=plaka, anchor="w", fill="#FFFFFF", font=("Consolas", 12, "bold"))

    def _karo_ciz(self, kam: dict, x: int, y: int, w: int, h: int) -> None:
        """Mozaik karosu: basit cizim (yalniz ince tespit kutusu) - CPU icin."""
        t, kid = self.tuval, kam["id"]
        t.create_rectangle(x, y, x + w, y + h, fill=K_KARO, outline=K_KENAR)
        kt = self._kare_al(kid)
        if kt is not None and time.time() - kt[1] <= float(self.uyg.ayar["izleme"]["goruntu_yok_sn"]):
            foto, (ox, oy, fw, fh, olcek) = self._foto_hazirla(kid, kt, w, h)
            t.create_image(x + ox, y + oy, anchor="nw", image=foto)
            self._kutu_ciz(kid, x + ox, y + oy, fw, olcek, ince=True)
        else:
            self._goruntu_yok(kid, x, y, w, h)
        self._etiketler(kid, kam, x, y, w, h)

    def _tek_ciz(self, kam: dict, cw: int, ch: int) -> None:
        t, kid = self.tuval, kam["id"]
        t.create_rectangle(0, 0, cw, ch, fill=K_KARO, outline="")
        kt = self._kare_al(kid)
        bilgi = None
        s = self.uyg.servis
        if s is not None and self.uyg.calisiyor:
            bilgi = s.boru.son.get(kid)
        if kt is None or time.time() - kt[1] > float(self.uyg.ayar["izleme"]["goruntu_yok_sn"]):
            self._goruntu_yok(kid, 0, 0, cw, ch)
            self._paneli_guncelle(None, kam)
            return
        foto, (ox, oy, w, h, olcek) = self._foto_hazirla(kid, kt, cw, ch)
        fh, fw = kt[0].shape[:2]
        self._boyut, self._ofs, self._olcek = (fw, fh), (ox, oy), olcek
        t.create_image(ox, oy, anchor="nw", image=foto)
        roi = roimod.normalize(kam.get("roi"))
        if roi:
            t.create_rectangle(ox + roi[0] * w, oy + roi[1] * h, ox + (roi[0] + roi[2]) * w, oy + (roi[1] + roi[3]) * h,
                               outline=K_SARI, dash=(6, 4), width=2)
        if self._surukle:
            a, b, c, d = self._surukle
            t.create_rectangle(a, b, c, d, outline=K_ACCENT, width=2, dash=(4, 3))
        self._kutu_ciz(kid, ox, oy, w, olcek, ince=False)
        self._etiketler(kid, kam, 0, 0, cw, ch, buyuk=True)
        self._paneli_guncelle(bilgi, kam)

    def _paneli_guncelle(self, bilgi, kam) -> None:
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
        kimlik, kapi_komut = self.ek.get(kid, ("", "")) if karar else ("", "")
        kapi_r = gosterim.kapi_rozeti(kapi_komut)
        self.kimlik_l.configure(text=kimlik)
        if kapi_r:
            self.kapi_l.configure(text=kapi_r[0], bg=TON_RENK[kapi_r[1]])
        else:
            self.kapi_l.configure(text="", bg=K_PANEL)
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
        for a in self._onizleme.values():
            a.dur.set()
        self._onizleme.clear()

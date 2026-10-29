"""Tkinter ayar penceresi + canli olay seridi.
Gorunum deseni company_qr_tool/ui_kit.py paletinden uyarlandi (PIL/animasyon bagimliligi OLMADAN, yalniz ttk)."""
from __future__ import annotations

import queue
import re
import threading
import tkinter as tk
from datetime import datetime
from tkinter import messagebox, ttk

from . import ayarlar
from .servis import Servis

# company_qr_tool/ui_kit.py C sinifindan secilen renkler
BG, SURFACE, BORDER = "#F3F6F8", "#FFFFFF", "#E1E7EC"
TEXT, TEXT_2 = "#17212B", "#475563"
NAVY, PRIMARY, PRIMARY_HOVER = "#283848", "#07787F", "#066A70"
SUCCESS_SOFT, WARNING_SOFT, DANGER_SOFT = "#DCF5E4", "#FDF0D5", "#FCE8E8"
WARNING, DANGER, SUCCESS = "#96500A", "#C42B2B", "#12703A"

KARAR_ETIKET = {"acildi": ("Açıldı", SUCCESS_SOFT), "red": ("Red", DANGER_SOFT),
                "tanimsiz": ("Tanımsız", WARNING_SOFT), "dogrulanmamis": ("Doğrulanmamış", BORDER),
                "acma_basarisiz": ("Açılamadı", DANGER_SOFT)}


def maske(url: str) -> str:
    return re.sub(r"//[^/@]*@", "//***@", url or "")


def stil_uygula(kok: tk.Tk) -> None:
    kok.configure(bg=BG)
    s = ttk.Style(kok)
    s.theme_use("clam")
    s.configure(".", background=BG, foreground=TEXT, font=("Segoe UI", 10))
    s.configure("TFrame", background=BG)
    s.configure("Kart.TFrame", background=SURFACE)
    s.configure("TLabel", background=BG, foreground=TEXT)
    s.configure("Soluk.TLabel", foreground=TEXT_2)
    s.configure("Baslik.TLabel", background=NAVY, foreground="white", font=("Segoe UI Semibold", 13), padding=(16, 10))
    s.configure("TButton", padding=(12, 6), background=SURFACE, bordercolor=BORDER)
    s.configure("Birincil.TButton", background=PRIMARY, foreground="white", bordercolor=PRIMARY)
    s.map("Birincil.TButton", background=[("active", PRIMARY_HOVER)])
    s.configure("TNotebook", background=BG, bordercolor=BORDER)
    s.configure("TNotebook.Tab", padding=(14, 7))
    s.configure("Treeview", background=SURFACE, fieldbackground=SURFACE, rowheight=26, bordercolor=BORDER)
    s.configure("Treeview.Heading", font=("Segoe UI Semibold", 10), background=BG)


class SatirDialog(tk.Toplevel):
    """alanlar: [(anahtar, etiket, tur)] ; tur: str | int | float | bool | sifre | [secenekler]"""

    def __init__(self, ust, baslik: str, alanlar: list, deger: dict | None = None):
        super().__init__(ust)
        self.title(baslik)
        self.configure(bg=BG, padx=16, pady=14)
        self.transient(ust)
        self.grab_set()
        self.alanlar, self.deger, self.sonuc, self.vars = alanlar, dict(deger or {}), None, {}
        for i, (anahtar, etiket, tur) in enumerate(alanlar):
            ttk.Label(self, text=etiket).grid(row=i, column=0, sticky="w", pady=3, padx=(0, 10))
            v = self.vars[anahtar] = tk.BooleanVar() if tur == "bool" else tk.StringVar()
            mevcut = self.deger.get(anahtar, "")
            v.set(bool(mevcut) if tur == "bool" else ("" if mevcut is None else str(mevcut)))
            if tur == "bool":
                w = ttk.Checkbutton(self, variable=v)
            elif isinstance(tur, list):
                w = ttk.Combobox(self, textvariable=v, values=tur, state="readonly", width=38)
            else:
                w = ttk.Entry(self, textvariable=v, width=40, show="*" if tur == "sifre" else "")
            w.grid(row=i, column=1, sticky="ew", pady=3)
        alt = ttk.Frame(self)
        alt.grid(row=len(alanlar), column=0, columnspan=2, sticky="e", pady=(12, 0))
        ttk.Button(alt, text="İptal", command=self.destroy).pack(side="right", padx=(8, 0))
        ttk.Button(alt, text="Tamam", style="Birincil.TButton", command=self._tamam).pack(side="right")
        self.wait_window()

    def _tamam(self) -> None:
        sonuc = dict(self.deger)
        try:
            for anahtar, _, tur in self.alanlar:
                ham = self.vars[anahtar].get()
                sonuc[anahtar] = (bool(ham) if tur == "bool" else int(ham) if tur == "int" else
                                  float(ham) if tur == "float" else ham.strip())
        except ValueError:
            messagebox.showerror("Hatalı değer", "Sayısal alanlara sayı girin.", parent=self)
            return
        self.sonuc = sonuc
        self.destroy()


KAMERA_ALANLAR = [("id", "Kamera kodu", "str"), ("ad", "Ad", "str"), ("url", "RTSP adresi (kimlik dahil)", "sifre"),
                  ("mod", "Mod", ["akis", "tetik"]), ("fps", "Kare/sn (akış)", "float"),
                  ("kapi_id", "Bağlı kapı kodu", "str"), ("yon", "Yön (boş = kapıdan)", ["", "giris", "cikis"]),
                  ("etkin", "Etkin", "bool")]
KAPI_ALANLAR = [("id", "Kapı kodu", "str"), ("ad", "Ad", "str"), ("yon_modu", "Yön modu", ["giris", "cikis", "cift"]),
                ("skp_uid", "SmartKeyPass cihaz UID", "str"), ("skp_ip", "Cihaz IP (boş = otomatik bul)", "str"),
                ("skp_token", "Yerel kontrol anahtarı", "sifre"), ("komut", "Komut", ["open", "pulse"])]


class Uygulama(tk.Tk):
    def __init__(self, ayar_yolu=None):
        super().__init__()
        self.title("AHBU Plaka Kenar Uygulaması")
        self.geometry("1040x720")
        stil_uygula(self)
        self.ayar_yolu = ayar_yolu
        self.ayar = ayarlar.yukle(ayar_yolu)
        self.servis: Servis | None = None
        self.kuyruk: queue.Queue = queue.Queue()
        self.calisiyor = False
        ttk.Label(self, text="AHBU Plaka Kenar Uygulaması", style="Baslik.TLabel").pack(fill="x")
        self.afis = tk.Label(self, anchor="w", padx=16, pady=6, font=("Segoe UI Semibold", 10))
        self.afis.pack(fill="x")
        self.defter = ttk.Notebook(self)
        self.defter.pack(fill="both", expand=True, padx=12, pady=(4, 0))
        self._genel_sekme()
        self._kamera_sekme()
        self._olay_sekme()
        self.durum_cubugu = ttk.Label(self, style="Soluk.TLabel", padding=(16, 6))
        self.durum_cubugu.pack(fill="x")
        self._servis_kur()
        self.protocol("WM_DELETE_WINDOW", self._kapat)
        self.after(200, self._olay_cek)
        self.after(2000, self._durum_yenile)

    # --- sekmeler -------------------------------------------------------------------
    def _genel_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=16)
        self.defter.add(f, text="Genel")
        s, k = self.ayar["sunucu"], self.ayar["karar"]
        self.v = {
            "etkin": tk.BooleanVar(value=s["etkin"]), "adres": tk.StringVar(value=s["adres"]),
            "site_kodu": tk.StringVar(value=s["site_kodu"]), "cihaz_anahtari": tk.StringVar(value=s["cihaz_anahtari"]),
            "misafir": tk.StringVar(value=k["misafir_kurali"]), "tkare": tk.BooleanVar(value=k["tanimsiz_kare_sakla"]),
            "tgun": tk.StringVar(value=str(k["tanimsiz_kare_gun"]))}
        satirlar = [("Sunucuya bağlan", ttk.Checkbutton(f, variable=self.v["etkin"])),
                    ("Sunucu adresi", ttk.Entry(f, textvariable=self.v["adres"], width=48)),
                    ("Site kodu", ttk.Entry(f, textvariable=self.v["site_kodu"], width=28)),
                    ("Cihaz anahtarı", ttk.Entry(f, textvariable=self.v["cihaz_anahtari"], width=48, show="*")),
                    ("Misafir kuralı", ttk.Combobox(f, textvariable=self.v["misafir"], state="readonly", width=28,
                                                    values=["tum_yerler_bos", "en_az_bir_yer_bos"])),
                    ("Tanımsız araç karesini sakla", ttk.Checkbutton(f, variable=self.v["tkare"])),
                    ("Saklama süresi (gün)", ttk.Entry(f, textvariable=self.v["tgun"], width=8))]
        for i, (e, w) in enumerate(satirlar):
            ttk.Label(f, text=e).grid(row=i, column=0, sticky="w", pady=5, padx=(0, 14))
            w.grid(row=i, column=1, sticky="w", pady=5)
        d = ttk.Frame(f)
        d.grid(row=len(satirlar), column=0, columnspan=2, sticky="w", pady=14)
        ttk.Button(d, text="Kaydet", style="Birincil.TButton", command=self._kaydet).pack(side="left")
        ttk.Button(d, text="Sına", command=self._sina).pack(side="left", padx=8)
        self.baslat_dugme = ttk.Button(d, text="Başlat", command=self._baslat_durdur)
        self.baslat_dugme.pack(side="left")
        self.sina_kutu = tk.Text(f, height=12, width=100, bg=SURFACE, relief="solid", bd=1, font=("Consolas", 10))
        self.sina_kutu.grid(row=len(satirlar) + 1, column=0, columnspan=2, sticky="nsew")
        self.sina_kutu.tag_configure("ok", foreground=SUCCESS)
        self.sina_kutu.tag_configure("hata", foreground=DANGER)

    def _tablo(self, ust, kolonlar: list, yukseklik: int):
        t = ttk.Treeview(ust, columns=[c[0] for c in kolonlar], show="headings", height=yukseklik)
        for ad, baslik, gen in kolonlar:
            t.heading(ad, text=baslik)
            t.column(ad, width=gen, anchor="w")
        return t

    def _kamera_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=12)
        self.defter.add(f, text="Kameralar ve Kapılar")
        ttk.Label(f, text="Kameralar (sınırsız satır)", style="Soluk.TLabel").pack(anchor="w")
        self.kam_t = self._tablo(f, [("id", "Kod", 90), ("ad", "Ad", 140), ("url", "Adres", 300), ("mod", "Mod", 60),
                                     ("fps", "Kare/sn", 60), ("kapi_id", "Kapı", 90), ("yon", "Yön", 70),
                                     ("etkin", "Etkin", 60)], 8)
        self.kam_t.pack(fill="x")
        self._dugmeler(f, [("Ekle", lambda: self._satir("kameralar", KAMERA_ALANLAR)),
                           ("Düzenle", lambda: self._satir("kameralar", KAMERA_ALANLAR, True)),
                           ("Sil", lambda: self._sil("kameralar", self.kam_t)), ("Tetikle (tek kare)", self._tetikle)])
        ttk.Label(f, text="Kapılar (geçiş noktaları)", style="Soluk.TLabel").pack(anchor="w", pady=(14, 0))
        self.kapi_t = self._tablo(f, [("id", "Kod", 90), ("ad", "Ad", 160), ("yon_modu", "Yön modu", 90),
                                      ("skp_uid", "SmartKeyPass UID", 150), ("skp_ip", "IP", 130)], 6)
        self.kapi_t.pack(fill="x")
        self._dugmeler(f, [("Ekle", lambda: self._satir("kapilar", KAPI_ALANLAR)),
                           ("Düzenle", lambda: self._satir("kapilar", KAPI_ALANLAR, True)),
                           ("Sil", lambda: self._sil("kapilar", self.kapi_t))])
        self._tablolari_doldur()

    def _olay_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=12)
        self.defter.add(f, text="Canlı Olaylar")
        self.olay_t = self._tablo(f, [("z", "Zaman", 80), ("kam", "Kamera", 90), ("yon", "Yön", 60), ("plaka", "Plaka", 120),
                                      ("karar", "Karar", 110), ("neden", "Neden", 170), ("guven", "Güven", 60)], 22)
        for kod, (_, renk) in KARAR_ETIKET.items():
            self.olay_t.tag_configure(kod, background=renk)
        self.olay_t.pack(fill="both", expand=True)

    def _dugmeler(self, ust, liste) -> None:
        d = ttk.Frame(ust)
        d.pack(anchor="w", pady=6)
        for ad, cmd in liste:
            ttk.Button(d, text=ad, command=cmd).pack(side="left", padx=(0, 8))

    # --- veri islemleri --------------------------------------------------------------
    def _tablolari_doldur(self) -> None:
        for t, anahtar, kolonlar in ((self.kam_t, "kameralar", self.kam_t["columns"]),
                                     (self.kapi_t, "kapilar", self.kapi_t["columns"])):
            t.delete(*t.get_children())
            for i, s in enumerate(self.ayar[anahtar]):
                deger = [maske(str(s.get(c, ""))) if c == "url" else s.get(c, "") for c in kolonlar]
                t.insert("", "end", iid=str(i), values=deger)

    def _satir(self, anahtar: str, alanlar: list, duzenle: bool = False) -> None:
        tablo = self.kam_t if anahtar == "kameralar" else self.kapi_t
        mevcut = None
        if duzenle:
            sec = tablo.selection()
            if not sec:
                return
            mevcut = self.ayar[anahtar][int(sec[0])]
        d = SatirDialog(self, "Satır", alanlar, mevcut or ({"mod": "akis", "fps": 3, "etkin": True} if anahtar == "kameralar"
                                                          else {"yon_modu": "cift", "komut": "open"}))
        if d.sonuc is None or not d.sonuc.get("id"):
            return
        if duzenle:
            self.ayar[anahtar][int(sec[0])] = d.sonuc
        else:
            self.ayar[anahtar].append(d.sonuc)
        self._tablolari_doldur()

    def _sil(self, anahtar: str, tablo) -> None:
        sec = tablo.selection()
        if sec and messagebox.askyesno("Sil", "Seçili satır silinsin mi?", parent=self):
            del self.ayar[anahtar][int(sec[0])]
            self._tablolari_doldur()

    def _formu_ayara_yaz(self) -> None:
        s, k, v = self.ayar["sunucu"], self.ayar["karar"], self.v
        s.update(etkin=v["etkin"].get(), adres=v["adres"].get().strip(), site_kodu=v["site_kodu"].get().strip(),
                 cihaz_anahtari=v["cihaz_anahtari"].get().strip())
        k["misafir_kurali"] = v["misafir"].get()
        k["tanimsiz_kare_sakla"] = v["tkare"].get()
        try:
            k["tanimsiz_kare_gun"] = max(1, int(v["tgun"].get()))
        except ValueError:
            pass

    def _kaydet(self) -> None:
        self._formu_ayara_yaz()
        uyari = ayarlar.dogrula(self.ayar)
        yol = ayarlar.kaydet(self.ayar, self.ayar_yolu)
        if self.calisiyor:
            self._baslat_durdur()
        self._servis_kur()
        messagebox.showinfo("Kaydedildi", f"{yol}\n" + ("\n".join(uyari) if uyari else "Uyarı yok."), parent=self)

    def _servis_kur(self) -> None:
        if self.servis:
            self.servis.durdur()
        self.servis = Servis(self.ayar)
        self.servis.dinleyiciler.append(self.kuyruk.put)
        kal = self.servis.boru.kalibrasyon_modu
        self.afis.configure(
            text=(f"KALİBRASYON MODU — kapı AÇILMAZ. {self.servis.boru.tanima.aciklama}" if kal
                  else f"Tanıma motoru doğrulanmış: {self.servis.boru.tanima.aciklama}"),
            bg=WARNING_SOFT if kal else SUCCESS_SOFT, fg=WARNING if kal else SUCCESS)

    def _baslat_durdur(self) -> None:
        if self.calisiyor:
            self.servis.durdur()
            self.calisiyor = False
            self.baslat_dugme.configure(text="Başlat")
        else:
            self._formu_ayara_yaz()
            self.servis.baslat()
            self.calisiyor = True
            self.baslat_dugme.configure(text="Durdur")

    def _sina(self) -> None:
        self._formu_ayara_yaz()
        self.sina_kutu.delete("1.0", "end")
        self.sina_kutu.insert("end", "Sınanıyor...\n")

        def is_() -> None:
            try:
                sonuc = self.servis.sina()  # servis ayni ayar sozlugunu paylasir
            except Exception as e:  # noqa: BLE001
                sonuc = [("Sına", False, f"{type(e).__name__}: {e}")]
            self.after(0, lambda: self._sina_yaz(sonuc))
        threading.Thread(target=is_, daemon=True).start()

    def _sina_yaz(self, sonuc: list) -> None:
        self.sina_kutu.delete("1.0", "end")
        for ad, ok, mesaj in sonuc:
            self.sina_kutu.insert("end", f"{'TAMAM' if ok else 'SORUN'}  {ad}: {mesaj}\n", "ok" if ok else "hata")

    def _tetikle(self) -> None:
        sec = self.kam_t.selection()
        if not sec:
            return
        kid = self.ayar["kameralar"][int(sec[0])]["id"]
        threading.Thread(target=lambda: self.servis.tetikle(kid), daemon=True).start()

    # --- canli seritler ------------------------------------------------------------------
    def _olay_cek(self) -> None:
        try:
            while True:
                o = self.kuyruk.get_nowait()
                etiket = KARAR_ETIKET.get(o["karar"], (o["karar"], ""))[0]
                zaman = datetime.fromisoformat(o["zaman"]).astimezone().strftime("%H:%M:%S")
                self.olay_t.insert("", 0, tags=(o["karar"],), values=(
                    zaman, o["kamera_id"], o["yon"], o["plaka"], etiket, o["neden"], f"{o['guven']:.2f}"))
                for eski in self.olay_t.get_children()[int(self.ayar["arayuz"]["olay_seridi_satir"]):]:
                    self.olay_t.delete(eski)
        except queue.Empty:
            pass
        self.after(200, self._olay_cek)

    def _durum_yenile(self) -> None:
        if self.servis:
            d = self.servis.durum()
            bagli = sum(1 for k in d["kameralar"] if k.get("durum") == "bagli")
            self.durum_cubugu.configure(text=(
                f"Kamera bağlı {bagli}/{len(d['kameralar'])}  ·  Kuyrukta {d['kuyruk']['bekleyen']} olay  ·  "
                f"İzin listesi {d['izin']['arac']} araç  ·  {self.servis.son_hata or 'sunucu: sorun yok'}"))
        self.after(2000, self._durum_yenile)

    def _kapat(self) -> None:
        if self.servis:
            self.servis.durdur()
        self.destroy()


def calistir(ayar_yolu=None) -> None:
    Uygulama(ayar_yolu).mainloop()

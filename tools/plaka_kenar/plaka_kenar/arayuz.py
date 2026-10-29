"""Tkinter ayar penceresi + canli olay seridi.
Sekmeler: Kameralar (HICBIR sunucu/site/anahtar alani olmadan tam calisir) | Canli Izleme (mozaik) | Canli Olaylar |
Yerel ayarlar | Sunucu baglantisi (isteğe bagli). Sunucu alanlari bossa hicbir yerde zorunlu uyari cikmaz.
Gorunum deseni company_qr_tool/ui_kit.py paletinden uyarlandi (PIL/animasyon bagimliligi OLMADAN, yalniz ttk)."""
from __future__ import annotations

import queue
import re
import threading
import tkinter as tk
from datetime import datetime
from tkinter import messagebox, ttk

from . import ayarlar, gosterim, izleme, kesif, yakalama
from .servis import Servis

# company_qr_tool/ui_kit.py C sinifindan secilen renkler
BG, SURFACE, BORDER = "#F3F6F8", "#FFFFFF", "#E1E7EC"
TEXT, TEXT_2 = "#17212B", "#475563"
NAVY, PRIMARY, PRIMARY_HOVER = "#283848", "#07787F", "#066A70"
SUCCESS_SOFT, WARNING_SOFT, DANGER_SOFT = "#DCF5E4", "#FDF0D5", "#FCE8E8"
WARNING, DANGER, SUCCESS = "#96500A", "#C42B2B", "#12703A"

# Karar etiketleri gosterim.KARAR_METIN'dedir ("açıldı" yazılmaz: komut kabul edildi != kapı fiziksel açıldı, P1-15).
KARAR_ETIKET = {"acildi": (gosterim.KARAR_METIN["acildi"], SUCCESS_SOFT), "red": (gosterim.KARAR_METIN["red"], DANGER_SOFT),
                "tanimsiz": (gosterim.KARAR_METIN["tanimsiz"], WARNING_SOFT), "dogrulanmamis": (gosterim.KARAR_METIN["dogrulanmamis"], BORDER),
                "acma_basarisiz": (gosterim.KARAR_METIN["acma_basarisiz"], DANGER_SOFT), "kara_liste": (gosterim.KARAR_METIN["kara_liste"], DANGER_SOFT)}
YON_GOSTER = {"giris": "Giriş", "cikis": "Çıkış", "": "—"}
YONLENDIRME = ("Başlamak için:  1) 'Ağda kamera ara' ya da 'El ile ekle'   →   2) 'Sına'   →   3) Yön ver (giriş / çıkış)   →   "
               "4) 'Canlı İzleme' sekmesinde tüm kameraları izle.\nSunucu bağlantısı gerekmez; her şey bu bilgisayarda yerel çalışır.")


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
                  ("yon", "Yön (giriş / çıkış)", ["giris", "cikis"]),
                  ("mod", "Mod", ["akis", "tetik"]), ("fps", "Okuma kare/sn (akış)", "float"),
                  ("kapi_id", "Bağlı kapı kodu (isteğe bağlı)", "str"), ("profil", "Görüntü profili", ["oto", "gunduz", "gece"]),
                  ("etkin", "Etkin", "bool"),
                  ("sunucu_id", "Sunucudaki kamera kimliği (yalnız sunucu bağlantısı için, isteğe bağlı)", "str")]
KAPI_ALANLAR = [("id", "Kapı kodu", "str"), ("ad", "Ad", "str"), ("yon_modu", "Yön modu", ["giris", "cikis", "cift"]),
                ("skp_uid", "SmartKeyPass cihaz UID", "str"), ("skp_ip", "Cihaz IP (boş = otomatik bul)", "str"),
                ("skp_token", "Yerel kontrol anahtarı", "sifre"), ("komut", "Komut", ["open", "pulse"]),
                ("sunucu_id", "Sunucudaki kapı kimliği (isteğe bağlı)", "str")]


class KameraBulDialog(tk.Toplevel):
    """Kamera ekleme: (1) IP / tam RTSP adresini ELLE yaz ya da 'Ağda kamera ara' (ONVIF + alt ağ taraması) ile bul ->
    RTSP şablon önerileri (ya da ONVIF GetStreamUri) -> Sına (tek kare) -> kamera satırı olarak ekle (yön: giriş / çıkış).
    Pencere ekledikten sonra açık kalır: çift yönlü kapı için ikinci kamerayı hemen ekleyin."""

    def __init__(self, uyg, ara: bool = False):
        super().__init__(uyg)
        self.uyg, self.cihazlar, self._acik, self._mesgul = uyg, [], True, False
        self.title("Kamera ekle — ağda ara ya da IP ile elle ekle")
        self.configure(bg=BG, padx=14, pady=12)
        self.geometry("860x660")
        self.transient(uyg)
        self.protocol("WM_DELETE_WINDOW", self._kapat)
        self.ip_v, self.kul, self.par, self.url_v = tk.StringVar(), tk.StringVar(), tk.StringVar(), tk.StringVar()
        ttk.Label(self, text="1) Kameranın IP adresi (örn. 192.168.1.64) ya da tam RTSP adresi", style="Soluk.TLabel").pack(anchor="w")
        s1 = ttk.Frame(self)
        s1.pack(fill="x", pady=(4, 0))
        self.ip_kutu = ttk.Entry(s1, textvariable=self.ip_v, width=34)
        self.ip_kutu.pack(side="left")
        ttk.Label(s1, text="Kullanıcı").pack(side="left", padx=(12, 4))
        ttk.Entry(s1, textvariable=self.kul, width=12).pack(side="left")
        ttk.Label(s1, text="Parola").pack(side="left", padx=(10, 4))
        ttk.Entry(s1, textvariable=self.par, width=12, show="*").pack(side="left")
        ttk.Button(s1, text="RTSP önerilerini göster", style="Birincil.TButton", command=self._onerileri_goster).pack(side="left", padx=(12, 0))
        s2 = ttk.Frame(self)
        s2.pack(fill="x", pady=(14, 0))
        self.ara_dugme = ttk.Button(s2, text="Ağda kamera ara", command=self._ara)
        self.ara_dugme.pack(side="left")
        self.durum = ttk.Label(s2, text="Ağdaki kameralar ONVIF + alt ağ taramasıyla aranır; bulunamazsa IP'yi yukarıya yazın.",
                               style="Soluk.TLabel", wraplength=640)
        self.durum.pack(side="left", padx=12)
        self.tablo = ttk.Treeview(self, columns=("ip", "tur", "ad", "konum"), show="headings", height=7)
        for k, b, g in (("ip", "IP", 120), ("tur", "Tür", 230), ("ad", "Ad / model", 200), ("konum", "Konum / açık portlar", 240)):
            self.tablo.heading(k, text=b)
            self.tablo.column(k, width=g, anchor="w")
        self.tablo.pack(fill="x", pady=8)
        self.tablo.bind("<<TreeviewSelect>>", self._sec)
        ttk.Button(self, text="Seçili cihaz için ONVIF'ten RTSP adresini bul (kullanıcı/parola gerekir)", command=self._uri_bul).pack(anchor="w")
        ttk.Label(self, text="2) RTSP adresi (öneri seçin ya da düzeltin)", style="Soluk.TLabel").pack(anchor="w", pady=(12, 2))
        self.url_kutu = ttk.Combobox(self, textvariable=self.url_v, width=100)
        self.url_kutu.pack(fill="x")
        s3 = ttk.Frame(self)
        s3.pack(fill="x", pady=(8, 0))
        self.sina_dugme = ttk.Button(s3, text="Sına (tek kare al)", command=self._sina)
        self.sina_dugme.pack(side="left")
        self.hepsi_dugme = ttk.Button(s3, text="Tüm önerileri sına", command=self._hepsini_sina)
        self.hepsi_dugme.pack(side="left", padx=8)
        self.sonuc = ttk.Label(self, text="", style="Soluk.TLabel", wraplength=800, justify="left")
        self.sonuc.pack(anchor="w", pady=8)
        alt = ttk.Frame(self)
        alt.pack(fill="x", pady=(8, 0), side="bottom")
        ttk.Button(alt, text="Kapat", command=self._kapat).pack(side="right")
        ttk.Button(alt, text="Kamera olarak ekle", style="Birincil.TButton", command=self._ekle).pack(side="right", padx=8)
        self.oneri_ad: dict = {}
        self.ip_kutu.focus_set()
        if ara:
            self.after(150, self._ara)

    def _kapat(self) -> None:
        self._acik = False
        self.destroy()

    def _ana(self, f) -> None:
        """Ana iş parçacığında çalıştır (pencere kapandıysa sessizce atla)."""
        if self._acik:
            try:
                self.after(0, f)
            except (RuntimeError, tk.TclError):
                pass

    def _ayar(self) -> dict:
        return kesif.kesif_ayari(self.uyg.ayar.get("kesif"))

    # --- 1) IP / öneriler ----------------------------------------------------------------
    def _oneri_yaz(self, oneriler: list) -> None:
        self.oneri_ad = {a: ad for ad, a in oneriler}
        self.url_kutu.configure(values=[a for _, a in oneriler])
        if oneriler:
            self.url_v.set(oneriler[0][1])

    def _onerileri_goster(self, port: int | None = None) -> None:
        r = kesif.rtsp_coz(self.ip_v.get(), self.kul.get().strip(), self.par.get(), port or int(self._ayar()["rtsp_port"]))
        if r["hata"]:
            self.sonuc.configure(text=r["hata"])
            return
        self._oneri_yaz(r["oneriler"])
        self.sonuc.configure(text="Girilen RTSP adresi kullanılacak. 'Sına' ile doğrulayın." if r["tam"] else
                             f"{len(r['oneriler'])} yaygın RTSP yolu önerildi. 'Tüm önerileri sına' çalışanı kendisi bulur; "
                             "kullanıcı/parola gerekiyorsa önce onları yazıp tekrar 'RTSP önerilerini göster'e basın.")

    # --- ağda ara -------------------------------------------------------------------------------
    def _ara(self) -> None:
        if self._mesgul:
            return
        self.ara_dugme.state(["disabled"])
        self.durum.configure(text="Aranıyor… (ONVIF + alt ağ taraması)")
        ay = self.uyg.ayar["kesif"]

        def ilerleme(b: int, t: int) -> None:
            self._ana(lambda: self.durum.configure(text=f"Aranıyor… alt ağ taraması %{min(100, b * 100 // max(1, t))}"))

        def is_() -> None:
            try:
                sonuc = kesif.ara(ay, ilerleme=ilerleme)
            except Exception as e:  # noqa: BLE001 - ağ/arayüz hatası keşfi düşürmesin
                sonuc = {"cihazlar": [], "onvif_adet": 0, "tarama_adet": 0, "arayuzler": [], "hatalar": [type(e).__name__]}
            self._ana(lambda: self._bitti(sonuc))
        threading.Thread(target=is_, daemon=True).start()

    def _bitti(self, sonuc: dict) -> None:
        self.ara_dugme.state(["!disabled"])
        self.cihazlar = sonuc["cihazlar"]
        self.tablo.delete(*self.tablo.get_children())
        for i, d in enumerate(self.cihazlar):
            self.tablo.insert("", "end", iid=str(i), values=(d["ip"], d["tur"], d["ad"] or d["model"], d["konum"]))
        self.durum.configure(text=kesif.ozet_mesaj(sonuc) + (f"  [{'; '.join(sonuc['hatalar'])}]" if sonuc["hatalar"] else ""))
        if self.cihazlar:
            self.tablo.selection_set("0")
        else:
            self.ip_kutu.focus_set()

    def _secili(self):
        sec = self.tablo.selection()
        return self.cihazlar[int(sec[0])] if sec else None

    def _sec(self, _e=None) -> None:
        d = self._secili()
        if d:
            self.ip_v.set(d["ip"])
            self._onerileri_goster(d.get("rtsp_port"))

    def _uri_bul(self) -> None:
        d = self._secili()
        if d is None:
            r = kesif.rtsp_coz(self.ip_v.get())
            if r["hata"] or not r["ip"]:
                self.sonuc.configure(text="Önce listeden bir cihaz seçin ya da IP adresini yazın.")
                return
            d = {"ip": r["ip"], "xaddrs": [], "portlar": []}
        self.sonuc.configure(text="ONVIF'ten RTSP adresi isteniyor…")
        ay, kul, par = self._ayar(), self.kul.get().strip(), self.par.get()

        def is_() -> None:
            uri, hata = kesif.stream_uri(d, kul, par, float(ay["zaman_asimi_sn"]), ay["onvif_portlar"])
            self._ana(lambda: self._uri_bitti(d, uri, hata, kul, par))
        threading.Thread(target=is_, daemon=True).start()

    def _uri_bitti(self, d: dict, uri, hata: str, kul: str, par: str) -> None:
        oneri = kesif.rtsp_oneriler(d["ip"], kul, par, int(d.get("rtsp_port") or self._ayar()["rtsp_port"]))
        self._oneri_yaz(([("ONVIF adresi", uri)] if uri else []) + oneri)
        self.sonuc.configure(text=(
            "ONVIF adresi bulundu. 'Sına' ile doğrulayın." if uri else
            f"ONVIF GetStreamUri alınamadı ({hata}). Şablon önerileri listelendi; 'Tüm önerileri sına' ile deneyin."))

    # --- 2) sına -----------------------------------------------------------------------------------
    def _mesgul_yap(self, mesgul: bool) -> None:
        self._mesgul = mesgul
        for d in (self.sina_dugme, self.hepsi_dugme):
            d.state(["disabled"] if mesgul else ["!disabled"])

    def _sina(self) -> None:
        url = self.url_v.get().strip()
        if not url or self._mesgul:
            self.sonuc.configure(text="Önce RTSP adresini yazın ya da önerilerden seçin.")
            return
        self._mesgul_yap(True)
        self.sonuc.configure(text="Kamera deneniyor…")
        y = self.uyg.ayar["yakalama"]

        def is_() -> None:
            kare, hata = yakalama.tek_kare(url, y)
            self._ana(lambda: self._sina_bitti(kare, hata))
        threading.Thread(target=is_, daemon=True).start()

    def _sina_bitti(self, kare, hata: str) -> None:
        self._mesgul_yap(False)
        self.sonuc.configure(text=(f"TAMAM: kare alındı ({kare.shape[1]}x{kare.shape[0]}). 'Kamera olarak ekle'ye basabilirsiniz." if kare is not None else
                                   f"SORUN: kare alınamadı ({hata}). Kullanıcı/parola, port ve yolu denetleyin; 'Tüm önerileri sına' deneyin."))

    def _hepsini_sina(self) -> None:
        adresler = list(self.url_kutu.cget("values"))
        if not adresler or self._mesgul:
            self.sonuc.configure(text="Önce IP yazıp 'RTSP önerilerini göster'e basın.")
            return
        self._mesgul_yap(True)
        y = self.uyg.ayar["yakalama"]

        def is_() -> None:
            for i, url in enumerate(adresler, 1):
                if not self._acik:
                    return
                ad = self.oneri_ad.get(url, url)
                self._ana(lambda i=i, ad=ad: self.sonuc.configure(text=f"Deneniyor {i}/{len(adresler)}: {ad}"))
                kare, _ = yakalama.tek_kare(url, y)
                if kare is not None:
                    self._ana(lambda url=url, ad=ad, k=kare: self._bulundu(url, ad, k))
                    return
            self._ana(lambda: (self._mesgul_yap(False), self.sonuc.configure(
                text="SORUN: önerilerin hiçbiri açılmadı. Kullanıcı/parola doğru mu? Kamerada RTSP açık mı? Kamera arayüzündeki RTSP adresini tam yazın.")))
        threading.Thread(target=is_, daemon=True).start()

    def _bulundu(self, url: str, ad: str, kare) -> None:
        self._mesgul_yap(False)
        self.url_v.set(url)
        self.sonuc.configure(text=f"TAMAM: çalışan adres bulundu ({ad}, {kare.shape[1]}x{kare.shape[0]}). 'Kamera olarak ekle'ye basabilirsiniz.")

    # --- ekle ---------------------------------------------------------------------------------------
    def _ekle(self) -> None:
        url, d = self.url_v.get().strip(), self._secili()
        if not url:
            self.sonuc.configure(text="Önce RTSP adresini yazın ya da önerilerden seçin.")
            return
        ayar = self.uyg.ayar
        var = {k["id"] for k in ayar["kameralar"]}
        n = 1
        while f"kamera{n}" in var:
            n += 1
        kapilar = ayar["kapilar"]
        kapi = kapilar[0]["id"] if len(kapilar) == 1 else ""
        ip = kesif.rtsp_coz(self.ip_v.get())["ip"] or (d["ip"] if d else "")
        ad = (d["ad"] or d["model"] or d["ip"]) if d else (ip or f"kamera{n}")
        s = SatirDialog(self, "Yeni kamera — yönünü seçin (giriş / çıkış)", KAMERA_ALANLAR,
                        {"id": f"kamera{n}", "ad": ad, "url": url, "yon": ayarlar.siradaki_yon(ayar, kapi), "mod": "akis", "fps": 3,
                         "kapi_id": kapi, "etkin": True, "profil": "oto"})
        if s.sonuc and s.sonuc.get("id"):
            ayar["kameralar"].append(s.sonuc)
            self.uyg._tablolari_doldur()
            self.sonuc.configure(text=f"{s.sonuc['id']} eklendi ({YON_GOSTER.get(s.sonuc.get('yon', ''), '—')}). "
                                      "Çift yönlü kapı için ikinci kamerayı (diğer yön) de ekleyin; sonra 'Kaydet'e basın.")


class Uygulama(tk.Tk):
    def __init__(self, ayar_yolu=None):
        super().__init__()
        self.title("AHBU Plaka Kenar Uygulaması")
        self.geometry("1100x760")
        stil_uygula(self)
        self.ayar_yolu = ayar_yolu
        self.ayar = ayarlar.yukle(ayar_yolu)
        self._satir_kimlik: dict = {}  # tablo satir sirasi -> ayar satir kodu (secili satiri guvenle bulmak icin)
        self._kamera_surum_gorulen = 0
        self.servis: Servis | None = None
        self.kuyruk: queue.Queue = queue.Queue()
        self.calisiyor = False
        ttk.Label(self, text="AHBU Plaka Kenar Uygulaması", style="Baslik.TLabel").pack(fill="x")
        self.afis = tk.Label(self, anchor="w", padx=16, pady=6, font=("Segoe UI Semibold", 10))
        self.afis.pack(fill="x")
        self._arac_cubugu()
        self.defter = ttk.Notebook(self)
        self.defter.pack(fill="both", expand=True, padx=12, pady=(4, 0))
        self._degiskenler()
        self._kamera_sekme()
        self.canli = izleme.CanliSekme(self.defter, self)
        self.defter.add(self.canli, text="Canlı İzleme")
        self._olay_sekme()
        self._yerel_sekme()
        self._sunucu_sekme()
        self.durum_cubugu = ttk.Label(self, style="Soluk.TLabel", padding=(16, 6))
        self.durum_cubugu.pack(fill="x")
        self._tablolari_doldur()
        self._servis_kur()
        self.protocol("WM_DELETE_WINDOW", self._kapat)
        self.after(200, self._olay_cek)
        self.after(2000, self._durum_yenile)

    # --- sekmeler -------------------------------------------------------------------
    def _arac_cubugu(self) -> None:
        d = ttk.Frame(self)
        d.pack(fill="x", padx=12, pady=(8, 0))
        ttk.Button(d, text="Kaydet", style="Birincil.TButton", command=self._kaydet).pack(side="left")
        ttk.Button(d, text="Tümünü sına", command=lambda: self._sina(None)).pack(side="left", padx=8)
        self.baslat_dugme = ttk.Button(d, text="Başlat", command=self._baslat_durdur)
        self.baslat_dugme.pack(side="left")
        ttk.Label(d, text="Başlat: plaka okuma + yerel karar çalışır (sunucu bağlantısı gerekmez).", style="Soluk.TLabel").pack(side="left", padx=12)

    def _degiskenler(self) -> None:
        s, k = self.ayar["sunucu"], self.ayar["karar"]
        self.v = {
            "etkin": tk.BooleanVar(value=s["etkin"]), "adres": tk.StringVar(value=s["adres"]),
            "site_kodu": tk.StringVar(value=s["site_kodu"]), "cihaz_anahtari": tk.StringVar(value=s["cihaz_anahtari"]),
            "misafir": tk.StringVar(value=k["misafir_kurali"]), "tkare": tk.BooleanVar(value=k["tanimsiz_kare_sakla"]),
            "tgun": tk.StringVar(value=str(k["tanimsiz_kare_gun"]))}

    def _yerel_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=16)
        self.defter.add(f, text="Yerel ayarlar")
        satirlar = [("Misafir kuralı", ttk.Combobox(f, textvariable=self.v["misafir"], state="readonly", width=28,
                                                    values=["tum_yerler_bos", "en_az_bir_yer_bos"])),
                    ("Tanımsız araç karesini sakla", ttk.Checkbutton(f, variable=self.v["tkare"])),
                    ("Saklama süresi (gün)", ttk.Entry(f, textvariable=self.v["tgun"], width=8))]
        for i, (e, w) in enumerate(satirlar):
            ttk.Label(f, text=e).grid(row=i, column=0, sticky="w", pady=5, padx=(0, 14))
            w.grid(row=i, column=1, sticky="w", pady=5)
        ttk.Label(f, text="Sunucu bağlıysa misafir kuralını sitenin ayarı belirler; bu değer yalnız ilk senkrona kadar geçerlidir.",
                  style="Soluk.TLabel", wraplength=640).grid(row=len(satirlar), column=0, columnspan=2, sticky="w", pady=(10, 0))

    def _sunucu_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=16)
        self.defter.add(f, text="Sunucu bağlantısı (isteğe bağlı)")
        ttk.Label(f, text=("Bu sekme İSTEĞE BAĞLIDIR. Boş bırakırsanız kameralar, plaka okuma, canlı izleme ve yerel karar sunucusuz çalışır; "
                           "olaylar sunucuya gönderilmez. Site izin listesini (sakin / misafir / kara liste) kullanmak isterseniz doldurun."),
                  style="Soluk.TLabel", wraplength=700, justify="left").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 12))
        satirlar = [("Sunucuya bağlan", ttk.Checkbutton(f, variable=self.v["etkin"])),
                    ("Sunucu adresi", ttk.Entry(f, textvariable=self.v["adres"], width=48)),
                    ("Site adı (isteğe bağlı)", ttk.Entry(f, textvariable=self.v["site_kodu"], width=28)),
                    ("Kenar PC anahtarı", ttk.Entry(f, textvariable=self.v["cihaz_anahtari"], width=48, show="*"))]
        for i, (e, w) in enumerate(satirlar, 1):
            ttk.Label(f, text=e).grid(row=i, column=0, sticky="w", pady=5, padx=(0, 14))
            w.grid(row=i, column=1, sticky="w", pady=5)
        ttk.Label(f, text="Değişikliklerin geçerli olması için üstteki 'Kaydet'e basın.", style="Soluk.TLabel").grid(
            row=len(satirlar) + 1, column=0, columnspan=2, sticky="w", pady=(10, 0))

    def _tablo(self, ust, kolonlar: list, yukseklik: int):
        t = ttk.Treeview(ust, columns=[c[0] for c in kolonlar], show="headings", height=yukseklik)
        for ad, baslik, gen in kolonlar:
            t.heading(ad, text=baslik)
            t.column(ad, width=gen, anchor="w")
        t.tag_configure("uyari", background=WARNING_SOFT)
        return t

    def _kamera_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=12)
        self.defter.add(f, text="Kameralar")
        self.yonlendirme_kap = ttk.Frame(f)
        self.yonlendirme_kap.pack(fill="x")
        self.yonlendirme = tk.Label(self.yonlendirme_kap, text=YONLENDIRME, bg=SUCCESS_SOFT, fg=SUCCESS, anchor="w", justify="left",
                                    padx=14, pady=10, font=("Segoe UI", 10), wraplength=1000)
        ttk.Label(f, text="Kameralar (sınırsız satır) — çift yönlü kapıda biri giriş, biri çıkış kamerası olmalı", style="Soluk.TLabel").pack(anchor="w")
        ttk.Label(f, text="“Sunucu” etiketli kameralar yönetici uygulamasından eklenir; burada silinemez / düzenlenemez (uygulamadan değiştirin).",
                  style="Soluk.TLabel").pack(anchor="w")
        self.kam_t = self._tablo(f, [("id", "Kod", 70), ("kaynak", "Kaynak", 60), ("ad", "Ad", 120), ("url", "Adres", 240), ("yon", "Yön", 55),
                                     ("mod", "Mod", 50), ("fps", "Kare/sn", 55), ("kapi_id", "Kapı", 80), ("etkin", "Etkin", 50),
                                     ("uyari", "Uyarı", 260)], 7)
        self.kam_t.pack(fill="x")
        self._dugmeler(f, [("Ağda kamera ara", lambda: KameraBulDialog(self, ara=True)),
                           ("El ile ekle", lambda: KameraBulDialog(self)),
                           ("Düzenle", lambda: self._satir("kameralar", KAMERA_ALANLAR, True)),
                           ("Sil", lambda: self._sil("kameralar", self.kam_t)),
                           ("Seçiliyi sına", self._secili_sina), ("Tetikle (tek kare)", self._tetikle)])
        self.sina_kutu = tk.Text(f, height=6, bg=SURFACE, relief="solid", bd=1, font=("Consolas", 10))
        self.sina_kutu.pack(fill="x")
        self.sina_kutu.tag_configure("ok", foreground=SUCCESS)
        self.sina_kutu.tag_configure("hata", foreground=DANGER)
        ttk.Label(f, text="Kapılar (isteğe bağlı — yalnız kapıyı SmartKeyPass ile açmak için)", style="Soluk.TLabel").pack(anchor="w", pady=(12, 0))
        self.kapi_t = self._tablo(f, [("id", "Kod", 90), ("ad", "Ad", 160), ("yon_modu", "Yön modu", 90),
                                      ("skp_uid", "SmartKeyPass UID", 150), ("skp_ip", "IP", 120), ("uyari", "Uyarı", 240)], 4)
        self.kapi_t.pack(fill="x")
        self._dugmeler(f, [("Ekle", lambda: self._satir("kapilar", KAPI_ALANLAR)),
                           ("Düzenle", lambda: self._satir("kapilar", KAPI_ALANLAR, True)),
                           ("Sil", lambda: self._sil("kapilar", self.kapi_t))])

    def _olay_sekme(self) -> None:
        f = ttk.Frame(self.defter, padding=12)
        self.defter.add(f, text="Canlı Olaylar")
        self.olay_t = self._tablo(f, [("z", "Zaman", 70), ("kam", "Kamera", 80), ("yon", "Yön", 50), ("plaka", "Plaka", 100),
                                      ("karar", "Karar", 95), ("kimlik", "Daire · kişi", 190), ("kapi", "Kapı durumu", 140),
                                      ("neden", "Neden", 150), ("guven", "Güven", 50)], 22)
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
        uy = ayarlar.yon_uyarilari(self.ayar)
        for t, anahtar, kolonlar, uyarilar in ((self.kam_t, "kameralar", self.kam_t["columns"], uy["kameralar"]),
                                               (self.kapi_t, "kapilar", self.kapi_t["columns"], uy["kapilar"])):
            t.delete(*t.get_children())
            satirlar = list(self.ayar[anahtar])  # tek anlik kopya: sunucu kamera birlestirmesi listeyi arka planda degistirebilir
            self._satir_kimlik[anahtar] = [s.get("id", "") for s in satirlar]
            for i, s in enumerate(satirlar):
                uyari = uyarilar.get(s.get("id", ""), "")
                deger = []
                for c in kolonlar:
                    if c == "uyari":
                        deger.append(("⚠ " + uyari) if uyari else "")
                    elif c == "url":
                        deger.append(maske(str(s.get(c, ""))))
                    elif c == "yon":
                        deger.append(YON_GOSTER.get(s.get(c, ""), s.get(c, "")))
                    elif c == "kaynak":
                        deger.append("Sunucu" if gosterim.sunucu_kaynakli(s) else "Yerel")
                    else:
                        deger.append(s.get(c, ""))
                t.insert("", "end", iid=str(i), values=deger, tags=("uyari",) if uyari else ())
        if self.ayar["kameralar"]:
            self.yonlendirme.pack_forget()
        elif not self.yonlendirme.winfo_ismapped():
            self.yonlendirme.pack(fill="x", pady=(0, 10))
        if hasattr(self, "canli"):
            self.canli.yenile_kameralar()

    def _secili_satir(self, anahtar: str, tablo):
        """Tabloda seçili satırın ayar sözlüğü (kimlikle bulunur: sunucu kamera birleştirmesi listeyi arka planda değiştirse de doğru satır)."""
        sec = tablo.selection()
        kodlar = self._satir_kimlik.get(anahtar, [])
        if not sec or int(sec[0]) >= len(kodlar):
            return None
        return next((s for s in self.ayar[anahtar] if s.get("id", "") == kodlar[int(sec[0])]), None)

    def _sunucu_satiri_uyar(self) -> None:
        messagebox.showinfo("Sunucu kamerası", "Bu kamera yönetici uygulamasından eklendi; burada düzenlenemez / silinemez.\n"
                            "Değiştirmek için uygulamadaki “Kamera ve Plaka” ekranını kullanın. (Yön / bölge ayarı için "
                            "yerel bir kamera satırı ekleyebilirsiniz.)", parent=self)

    def _satir(self, anahtar: str, alanlar: list, duzenle: bool = False) -> None:
        tablo = self.kam_t if anahtar == "kameralar" else self.kapi_t
        mevcut, asil = None, None
        if duzenle:
            asil = self._secili_satir(anahtar, tablo)
            if asil is None:
                return
            if anahtar == "kameralar" and gosterim.sunucu_kaynakli(asil):
                self._sunucu_satiri_uyar()
                return
            mevcut = dict(asil)
            if anahtar == "kameralar" and mevcut.get("yon", "") not in ("giris", "cikis"):
                mevcut["yon"] = ayarlar.siradaki_yon(self.ayar, mevcut.get("kapi_id", ""))  # eski satır: yön seçtirilir
        d = SatirDialog(self, "Satır", alanlar, mevcut or ({"mod": "akis", "fps": 3, "etkin": True, "profil": "oto",
                                                            "yon": ayarlar.siradaki_yon(self.ayar)} if anahtar == "kameralar"
                                                           else {"yon_modu": "cift", "komut": "open"}))
        if d.sonuc is None or not d.sonuc.get("id"):
            return
        if duzenle:
            liste = self.ayar[anahtar]
            for i, s in enumerate(liste):
                if s is asil:
                    liste[i] = d.sonuc
                    break
        else:
            self.ayar[anahtar].append(d.sonuc)
        self._tablolari_doldur()

    def _sil(self, anahtar: str, tablo) -> None:
        asil = self._secili_satir(anahtar, tablo)
        if asil is None:
            return
        if anahtar == "kameralar" and gosterim.sunucu_kaynakli(asil):
            self._sunucu_satiri_uyar()
            return
        if messagebox.askyesno("Sil", "Seçili satır silinsin mi?", parent=self):
            self.ayar[anahtar] = [s for s in self.ayar[anahtar] if s is not asil]
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
        self.servis = Servis(self.ayar, ayar_yolu=self.ayar_yolu or ayarlar.varsayilan_yol())
        self._kamera_surum_gorulen = 0
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

    def _secili_sina(self) -> None:
        kam = self._secili_satir("kameralar", self.kam_t)
        if kam is None:
            messagebox.showinfo("Sına", "Önce tablodan bir kamera seçin.", parent=self)
            return
        self._sina(kam["id"])

    def _sina(self, kamera_id: str | None = None) -> None:
        self._formu_ayara_yaz()
        self.defter.select(0)  # sonuc kutusu Kameralar sekmesinde
        self.sina_kutu.delete("1.0", "end")
        self.sina_kutu.insert("end", "Sınanıyor...\n")

        def is_() -> None:
            try:
                sonuc = self.servis.sina(kamera_id)  # servis ayni ayar sozlugunu paylasir
            except Exception as e:  # noqa: BLE001
                sonuc = [("Sına", False, f"{type(e).__name__}: {e}")]
            self.after(0, lambda: self._sina_yaz(sonuc))
        threading.Thread(target=is_, daemon=True).start()

    def _sina_yaz(self, sonuc: list) -> None:
        self.sina_kutu.delete("1.0", "end")
        for ad, ok, mesaj in sonuc:
            self.sina_kutu.insert("end", f"{'TAMAM' if ok else 'SORUN'}  {ad}: {mesaj}\n", "ok" if ok else "hata")

    def _tetikle(self) -> None:
        kam = self._secili_satir("kameralar", self.kam_t)
        if kam is None:
            return
        kid = kam["id"]
        threading.Thread(target=lambda: self.servis.tetikle(kid), daemon=True).start()

    # --- canli seritler ------------------------------------------------------------------
    def _olay_cek(self) -> None:
        try:
            while True:
                o = self.kuyruk.get_nowait()
                self.canli.olay(o)
                zaman = datetime.fromisoformat(o["zaman"]).astimezone().strftime("%H:%M:%S")
                self.olay_t.insert("", 0, tags=(o["karar"],), values=gosterim.olay_satiri(o, zaman))
                for eski in self.olay_t.get_children()[int(self.ayar["arayuz"]["olay_seridi_satir"]):]:
                    self.olay_t.delete(eski)
        except queue.Empty:
            pass
        self.after(200, self._olay_cek)

    def _durum_yenile(self) -> None:
        if self.servis:
            if self.servis.kamera_surum != self._kamera_surum_gorulen:  # sunucudan kamera tanimi geldi / degisti: tablolari tazele
                self._kamera_surum_gorulen = self.servis.kamera_surum
                self._tablolari_doldur()
            d = self.servis.durum()
            bagli = sum(1 for k in d["kameralar"] if k.get("durum") == "bagli")
            sunucu = (self.servis.son_hata or "sunucu: sorun yok") if ayarlar.sunucu_hazir(self.ayar) else "sunucu: kapalı (isteğe bağlı)"
            self.durum_cubugu.configure(text=(
                f"Kamera bağlı {bagli}/{len(d['kameralar'])}  ·  Kuyrukta {d['kuyruk']['bekleyen']} olay  ·  "
                f"İzin listesi {d['izin']['arac']} araç  ·  {sunucu}"))
        self.after(2000, self._durum_yenile)

    def _kapat(self) -> None:
        self.canli.kapat()
        if self.servis:
            self.servis.durdur()
        self.destroy()


def calistir(ayar_yolu=None) -> None:
    Uygulama(ayar_yolu).mainloop()

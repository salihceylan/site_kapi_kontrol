"""Uzaktan komutlar (sozlesme v3): yonetici uygulamadan "Agda kamera ara" / "Kamerayi sina" der, sunucu komutu kuyruga koyar,
kenar `GET commands` ya da kalp atisi yanitiyla alir, YERELDE calistirir ve sonucu `POST commands/{id}/result` ile bildirir.

- discover: mevcut kesif (ONVIF WS-Discovery + yerel alt ag TCP taramasi) -> {devices, summary, onvif_count, scan_count, interfaces, errors}
- probe:    RTSP'ye baglan, bir kare al -> {ok, width, height, reason, message, rtsp_url?}. rtsp_url bos ise ONVIF GetStreamUri ile cozulur;
            cozulen adres KIMLIKSIZ dondurulur. Parola sonucta / gunlukte ASLA yer almaz.
Komutlar AYRI is parcaciginda calisir (arka dongu bloklanmasin); ayni komut kimligi iki kez islenmez; ayni anda en cok 1 kesif."""
from __future__ import annotations

import logging
import re
import threading
import time
from collections import OrderedDict
from urllib import parse

from . import kesif, yakalama
from .sunucu import SunucuHatasi

log = logging.getLogger("plaka_kenar.komut")

MAX_CIHAZ = 300  # tek sonucta bildirilen en cok cihaz (istek boyutu guvenligi; sunucu govde siniri 128 KB)
MAX_MESAJ = 200
_HATA_ACIKLAMA = {  # yakalama.tek_kare hata kodu -> yonetici metni
    "baglanti_acilamadi": "RTSP bağlantısı açılamadı (adres, port, kullanıcı / parola ya da kamerada RTSP kapalı olabilir)",
    "kare_okunamadi": "Bağlantı kuruldu ama kare okunamadı (yol / profil yanlış olabilir)",
}


def kisalt(metin, en_cok: int = MAX_MESAJ) -> str:
    return " ".join(str(metin or "").split())[:en_cok]


def temizle(metin, *sirlar: str) -> str:
    """Mesajda parola / kullanici adi gecmesin (ag hatasi metinleri URL tasiyabilir)."""
    t = kisalt(metin)
    for s in sirlar:
        if s and len(s) >= 2:
            t = t.replace(s, "***")
            t = t.replace(parse.quote(s, safe=""), "***")
    return re.sub(r"//[^/@\s]*@", "//***@", t)


def kimliksiz(url: str) -> str:
    """rtsp://kul:par@host:554/yol -> rtsp://host:554/yol"""
    p = parse.urlsplit(url)
    host = p.hostname or ""
    if ":" in host:
        host = f"[{host}]"
    netloc = host + (f":{p.port}" if p.port else "")
    return parse.urlunsplit((p.scheme, netloc, p.path, p.query, p.fragment))


def kesif_sonucu(s: dict) -> dict:
    """kesif.ara() cikisi -> sozlesmedeki discover sonucu."""
    cihazlar = []
    for d in (s.get("cihazlar") or [])[:MAX_CIHAZ]:
        cihazlar.append({
            "ip": kisalt(d.get("ip"), 45),
            "ports": [int(p) for p in d.get("portlar", []) if isinstance(p, int) and 0 < p < 65536][:32],
            "name": kisalt(d.get("ad"), 80), "model": kisalt(d.get("model"), 80),
            "source": d.get("kaynak") if d.get("kaynak") in ("onvif", "onvif+tarama", "tarama") else "tarama",
            "label": kisalt(d.get("tur"), 80), "rtsp_port": int(d.get("rtsp_port") or 554)})
    return {"devices": cihazlar, "summary": kisalt(kesif.ozet_mesaj(s), 400), "onvif_count": int(s.get("onvif_adet", 0)),
            "scan_count": int(s.get("tarama_adet", 0)), "interfaces": [kisalt(i, 45) for i in (s.get("arayuzler") or [])][:16],
            "errors": [kisalt(h, 80) for h in (s.get("hatalar") or [])][:8]}


class KomutIsleyici:
    """`ayar`: canli ayar sozlugu (kesif / yakalama bolumleri). `sunucu`: komut_sonucu(id, govde) saglayan istemci.
    `calistir(f)`: isi baslatir (varsayilan: daemon thread; testler ayni thread'de calistirir)."""

    def __init__(self, ayar: dict, sunucu, kesif_fn=None, kare_fn=None, stream_uri_fn=None, calistir=None,
                 deneme: int | None = None, bekle_sn: float | None = None):
        self.ayar, self.sunucu = ayar, sunucu
        self.kesif_fn = kesif_fn or kesif.ara
        self.kare_fn = kare_fn or yakalama.tek_kare
        self.stream_uri_fn = stream_uri_fn or kesif.stream_uri
        self.calistir = calistir or (lambda f: threading.Thread(target=f, daemon=True, name="komut").start())
        s = ayar.get("sunucu", {})
        self.deneme = max(1, int(s.get("komut_sonuc_deneme", 3) if deneme is None else deneme))
        self.bekle_sn = float(s.get("komut_sonuc_bekle_sn", 2.0) if bekle_sn is None else bekle_sn)
        self._islenen: OrderedDict = OrderedDict()
        self._kilit = threading.Lock()
        self._kesif_kilidi = threading.Lock()

    # --- giris -----------------------------------------------------------------------
    def ver(self, komutlar) -> int:
        """Sunucudan gelen komut listesini isler (yeni olanlari baslatir). Doner: baslatilan komut sayisi."""
        n = 0
        for k in komutlar or []:
            if not isinstance(k, dict):
                continue
            kid = k.get("id")
            try:
                kid = int(kid)
            except (TypeError, ValueError):
                continue
            with self._kilit:
                if kid in self._islenen:
                    continue
                self._islenen[kid] = time.time()
                while len(self._islenen) > 500:
                    self._islenen.popitem(last=False)
            self.calistir(lambda k=k, kid=kid: self._yurut(kid, k))
            n += 1
        return n

    # --- calistirma --------------------------------------------------------------------
    def _yurut(self, kid: int, komut: dict) -> None:
        try:
            govde = self.isle(komut)
        except Exception as e:  # noqa: BLE001 - komut hatasi isleyiciyi dusurmesin; sunucuya 'failed' bildirilir
            log.warning("komut %s hata: %s", kid, type(e).__name__)
            govde = {"status": "failed", "message": f"Kenar uygulamada hata: {type(e).__name__}"}
        self.bildir(kid, govde)

    def isle(self, komut: dict) -> dict:
        """Komutu calistirir ve sonuc govdesini ({status, message?, result?}) dondurur; ag / sunucu cagrisi YOK."""
        tur, yuk = komut.get("kind"), komut.get("payload") if isinstance(komut.get("payload"), dict) else {}
        if tur == "discover":
            return self.kesif_calistir()
        if tur == "probe":
            return {"status": "done", "result": self.sina(yuk)}
        return {"status": "failed", "message": f"Desteklenmeyen komut türü: {kisalt(tur, 30)}"}

    def kesif_calistir(self) -> dict:
        with self._kesif_kilidi:  # ayni anda en cok 1 kesif (ag taramasi agirdir)
            sonuc = self.kesif_fn(self.ayar.get("kesif"))
        return {"status": "done", "result": kesif_sonucu(sonuc)}

    def sina(self, yuk: dict) -> dict:
        kul, par = str(yuk.get("username") or ""), str(yuk.get("password") or "")
        url = str(yuk.get("rtsp_url") or "").strip()
        cozulen = None
        if not url:
            host = str(yuk.get("host") or "").strip()
            if not host:
                return {"ok": False, "reason": "adres_yok", "message": "Kamera adresi (IP) yok."}
            k = kesif.kesif_ayari(self.ayar.get("kesif"))
            uri, hata = self.stream_uri_fn({"ip": host, "xaddrs": [], "portlar": []}, kul, par, float(k["zaman_asimi_sn"]), k["onvif_portlar"])
            if not uri:
                return {"ok": False, "reason": "onvif_cozulemedi",
                        "message": temizle(f"ONVIF ile RTSP adresi çözülemedi ({hata}). RTSP yolunu elle yazın.", kul, par)}
            cozulen = kimliksiz(uri)
            tam = kesif.rtsp_adresi_ekle(uri, kul, par)
        else:
            tam = kesif.rtsp_adresi_ekle(url, kul, par)
        try:
            kare, hata = self.kare_fn(tam, self.ayar["yakalama"])
        except Exception as e:  # noqa: BLE001 - cv2 / ag istisnasi sinamayi dusurmesin
            kare, hata = None, f"{type(e).__name__}"
        if kare is None:
            kod = temizle(hata, kul, par)
            sonuc = {"ok": False, "reason": re.sub(r"[^a-z0-9_]", "_", kod.lower())[:40] or "bilinmeyen",
                     "message": _HATA_ACIKLAMA.get(kod, f"Kare alınamadı ({kod})")}
        else:
            sonuc = {"ok": True, "width": int(kare.shape[1]), "height": int(kare.shape[0]),
                     "message": f"RTSP sınandı {int(kare.shape[1])}x{int(kare.shape[0])}"}
        if cozulen:
            sonuc["rtsp_url"] = cozulen
        return sonuc

    def bildir(self, kid: int, govde: dict) -> bool:
        """POST commands/{id}/result; gecici hatada (ag, 5xx, 401/403) birkac kez dener. Kalici 4xx (404 / 409: komut artik gecersiz) birakilir."""
        for deneme in range(1, self.deneme + 1):
            try:
                self.sunucu.komut_sonucu(kid, govde)
                return True
            except SunucuHatasi as e:
                if e.kalici:
                    log.warning("komut %s sonucu reddedildi: %s", kid, e)
                    return False
                log.warning("komut %s sonucu gonderilemedi (%s/%s): %s", kid, deneme, self.deneme, e)
                if deneme < self.deneme and self.bekle_sn > 0:
                    time.sleep(self.bekle_sn)
        return False

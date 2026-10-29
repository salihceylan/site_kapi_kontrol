"""Sunucu istemcisi (plan A1 uclari: kayit, delta senkron, olay POST, kalp atisi).
Yollar/basliklar ayarlar.json'dadir; her uc ayri ayri kapatilabilir (sunucu hazir degilse)."""
from __future__ import annotations

import socket
from dataclasses import dataclass


class SunucuHatasi(Exception):
    def __init__(self, mesaj: str, kalici: bool = False):
        super().__init__(mesaj)
        self.kalici = kalici  # 4xx (408/429 haric): tekrar denemek anlamsiz


@dataclass
class Yanit:
    kod: int
    govde: dict


class SunucuIstemcisi:
    def __init__(self, s: dict, oturum=None):
        self.s = s
        self._oturum = oturum

    @property
    def oturum(self):
        if self._oturum is None:
            import requests  # gec yukleme
            self._oturum = requests.Session()
        return self._oturum

    def uc_etkin(self, ad: str) -> bool:
        return bool(self.s.get("etkin")) and bool(self.s["uclar"].get(ad, {}).get("etkin"))

    def _url(self, ad: str) -> str:
        yol = self.s["uclar"][ad]["yol"].replace("{site_kodu}", self.s["site_kodu"])
        return self.s["adres"].rstrip("/") + yol

    def _basliklar(self) -> dict:
        return {self.s["site_baslik"]: self.s["site_kodu"], self.s["anahtar_baslik"]: self.s["cihaz_anahtari"],
                "Content-Type": "application/json"}

    def _cagir(self, yontem: str, ad: str, **kw) -> Yanit:
        if not self.uc_etkin(ad):
            raise SunucuHatasi(f"'{ad}' ucu kapali", kalici=True)
        try:
            r = self.oturum.request(yontem, self._url(ad), headers=self._basliklar(),
                                    timeout=float(self.s["zaman_asimi_sn"]),
                                    verify=bool(self.s["tls_dogrula"]), **kw)
        except Exception as e:  # noqa: BLE001 - ag hatalari gecici
            raise SunucuHatasi(f"{type(e).__name__}") from e
        try:
            govde = r.json() if r.content else {}
        except ValueError:
            govde = {}
        if r.status_code >= 400:
            raise SunucuHatasi(f"HTTP {r.status_code}", kalici=r.status_code < 500 and r.status_code not in (408, 429))
        return Yanit(r.status_code, govde if isinstance(govde, dict) else {})

    def kayit(self, govde: dict) -> Yanit:
        return self._cagir("POST", "kayit", json={"schema_version": self.s["schema_version"], **govde})

    def senkron(self, imlec: str) -> Yanit:
        return self._cagir("GET", "senkron", params={"imlec": imlec, "schema_version": self.s["schema_version"]})

    def olaylar(self, liste: list) -> Yanit:
        return self._cagir("POST", "olay", json={"schema_version": self.s["schema_version"], "olaylar": liste})

    def kalp_atisi(self, govde: dict) -> Yanit:
        return self._cagir("POST", "kalp_atisi", json={"schema_version": self.s["schema_version"], **govde})

    def sina(self) -> tuple:
        """(basarili, mesaj): adres cozulur + TCP baglanti denenir (kimlik dogrulamasiz, yan etkisiz)."""
        from urllib.parse import urlparse
        if not self.s.get("adres"):
            return False, "Sunucu adresi bos"
        u = urlparse(self.s["adres"])
        host, port = u.hostname, u.port or (443 if u.scheme == "https" else 80)
        try:
            with socket.create_connection((host, port), timeout=float(self.s["zaman_asimi_sn"])):
                pass
        except OSError as e:
            return False, f"{host}:{port} erisilemedi ({type(e).__name__})"
        return True, f"{host}:{port} erisilebilir"

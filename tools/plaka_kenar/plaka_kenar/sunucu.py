"""Sunucu istemcisi: A1 sozlesmesi (docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md, /edge/plate/v1).
Kimlik: Authorization: Bearer <id>.<gizli>. Uclar: POST claim, GET sync, POST events (TEK olay), POST heartbeat.
Yollar ayarlar.json'dadir ve her uc ayri ayri kapatilabilir. Her istek/yanit `schema_version` tasir."""
from __future__ import annotations

import socket
from dataclasses import dataclass


class SunucuHatasi(Exception):
    def __init__(self, mesaj: str, kalici: bool = False, kod: int = 0):
        super().__init__(mesaj)
        self.kalici = kalici  # sozlesme: 4xx (401/403/408/429 haric) KALICI hatadir, ayni istegi tekrar deneme
        self.kod = kod


def kalici_mi(kod: int) -> bool:
    """401/403 anahtar ya da modul sorunudur (yonetici duzeltince gecer): gecici sayilir. 408/429/5xx gecici."""
    return 400 <= kod < 500 and kod not in (401, 403, 408, 429)


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
        return self.s["adres"].rstrip("/") + self.s["uclar"][ad]["yol"]

    def _basliklar(self) -> dict:
        return {"Authorization": f"Bearer {str(self.s['cihaz_anahtari']).strip()}", "Content-Type": "application/json"}

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
        govde = govde if isinstance(govde, dict) else {}
        if r.status_code >= 400:
            raise SunucuHatasi(f"HTTP {r.status_code} {govde.get('code', '')}".strip(), kalici=kalici_mi(r.status_code), kod=r.status_code)
        return Yanit(r.status_code, govde)

    def kayit(self, uygulama_surumu: str) -> Yanit:
        """POST claim: anahtari dogrular, surum bilgisini kaydeder; yanit `intervals` ve `supported_schema_versions` tasir."""
        return self._cagir("POST", "kayit", json={"schema_version": self.s["schema_version"], "app_version": uygulama_surumu})

    def senkron(self, updated_since: str = "", revler: dict | None = None) -> Yanit:
        """GET sync: ilk senkronda yalniz schema_version; sonrakinde onceki yanittaki server_time (updated_since) ve bolum rev'leri."""
        params: dict = {"schema_version": self.s["schema_version"]}
        if updated_since:
            params["updated_since"] = updated_since
        for ad in ("vehicles", "permits", "blacklist"):
            if (revler or {}).get(ad):
                params[f"{ad}_rev"] = revler[ad]
        return self._cagir("GET", "senkron", params=params)

    def olay(self, govde: dict) -> Yanit:
        """POST events: TEK olay; event_id ile idempotent (ikinci gonderim duplicate:true)."""
        return self._cagir("POST", "olay", json=govde)

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

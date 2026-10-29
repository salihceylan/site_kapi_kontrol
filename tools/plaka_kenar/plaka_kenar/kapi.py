"""Kapi acma surucusu. Soyut `KapiSurucu` + SmartKeyPass YEREL kontrol v2 (docs/YEREL_KONTROL_V2.md).

Emniyet cizgisi: yazilim YALNIZ "open"/"pulse" gonderir; "kapat" komutu YOKTUR (bariyer kendi
sensorleriyle kapanir). Token ve imza/challenge ASLA gunluge yazilmaz.
"""
from __future__ import annotations

import hashlib
import hmac
import ipaddress
import json
import logging
import socket
import time
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass

log = logging.getLogger("plaka_kenar.kapi")


@dataclass
class KapiSonucu:
    basarili: bool
    neden: str = ""


class KapiSurucu(ABC):
    @abstractmethod
    def ac(self, kapi: dict) -> KapiSonucu: ...


def imza(token: str, eylem: str, uid: str, ch: str) -> str:
    """sig = hex(HMAC-SHA256(key=token, msg=eylem|UID_BUYUK|ch)) - cihazla birebir."""
    msg = f"{eylem}|{uid.upper()}|{ch}".encode("utf-8")
    return hmac.new(token.encode("utf-8"), msg, hashlib.sha256).hexdigest()


def ozel_ag_mi(ip: str) -> bool:
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return a.is_private or a.is_link_local


class SmartKeyPassYerel(KapiSurucu):
    def __init__(self, p: dict, soket_fabrikasi=None):
        self.p = p
        self._yeni_soket = soket_fabrikasi or (lambda: socket.socket(socket.AF_INET, socket.SOCK_DGRAM))

    def _istek(self, mesaj: dict, adres: tuple, genel: bool = False):
        """Tek UDP istek/yanit. genel=True: yayin gonder, device_uid eslesen ilk yaniti al."""
        s = self._yeni_soket()
        try:
            s.settimeout(float(self.p["zaman_asimi_sn"]))
            if genel:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(json.dumps(mesaj).encode("utf-8"), adres)
            son = time.monotonic() + float(self.p["zaman_asimi_sn"])
            while time.monotonic() < son:
                veri, kaynak = s.recvfrom(1024)
                try:
                    yanit = json.loads(veri.decode("utf-8"))
                except ValueError:
                    continue
                if mesaj.get("nonce") and yanit.get("nonce") not in (None, mesaj["nonce"]):
                    continue
                if mesaj.get("target_uid") not in (None, "", "*") and \
                        str(yanit.get("device_uid", "")).upper() != str(mesaj["target_uid"]).upper():
                    continue
                return yanit, kaynak[0]
        except (socket.timeout, OSError):
            return None, None
        finally:
            s.close()
        return None, None

    def _kesif(self, uid: str, ip: str):
        mesaj = {"action": "discover", "target_uid": uid.upper(), "nonce": uuid.uuid4().hex[:16]}
        if ip:
            return self._istek(mesaj, (ip, int(self.p["port"])))
        return self._istek(mesaj, (self.p["yayin_adresi"], int(self.p["port"])), genel=True)

    def ac(self, kapi: dict) -> KapiSonucu:
        eylem = kapi.get("komut", "open")
        if eylem not in self.p["izinli_komutlar"] or eylem not in ("open", "pulse"):
            return KapiSonucu(False, "komut_izinli_degil")  # 'close' vb. asla gonderilmez
        uid, token = (kapi.get("skp_uid") or "").strip(), kapi.get("skp_token") or ""
        if not uid or not token:
            return KapiSonucu(False, "skp_uid_veya_token_yok")
        yanit, ip = self._kesif(uid, (kapi.get("skp_ip") or "").strip())
        if yanit is None:
            return KapiSonucu(False, "cihaz_yanit_vermedi")
        if not ozel_ag_mi(ip):
            return KapiSonucu(False, "hedef_ozel_ag_degil")
        if yanit.get("local_control_available") is False:
            return KapiSonucu(False, "cihazda_yerel_kontrol_yok")
        ch = str(yanit.get("ch", ""))
        adres = (ip, int(yanit.get("port") or self.p["port"]))
        deneme = 0
        while True:
            mesaj = {"action": eylem, "target_uid": uid.upper(), "device_uid": uid.upper(), "ch": ch,
                     "sig": imza(token, eylem, uid, ch), "nonce": uuid.uuid4().hex[:16]}
            y, _ = self._istek(mesaj, adres)
            if y is None:
                return KapiSonucu(False, "acma_yaniti_yok")
            if y.get("ok"):
                return KapiSonucu(True, "tekrar_paket" if y.get("duplicate") else "")
            hata = str(y.get("error", "bilinmeyen"))
            if hata == "challenge" and y.get("ch") and deneme < int(self.p["yeniden_deneme"]):
                ch, deneme = str(y["ch"]), deneme + 1  # TEK yeniden deneme, guncel ch ile
                continue
            return KapiSonucu(False, hata)  # unauthorized / role_mesgul: kesin ret, tekrar yok


def olustur(ayar: dict) -> KapiSurucu:
    return SmartKeyPassYerel(ayar["skp"])

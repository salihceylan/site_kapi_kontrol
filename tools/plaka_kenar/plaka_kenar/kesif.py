"""Agda kamera kesfi: ONVIF WS-Discovery (UDP multicast 239.255.255.250:3702) + ONVIF GetStreamUri.
Yalniz stdlib (socket, uuid, urllib, xml.etree). Aga gelen XML guvenilmez veridir: DOCTYPE/ENTITY reddedilir, boyut sinirlidir."""
from __future__ import annotations

import base64
import hashlib
import os
import socket
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from urllib import error, parse, request
from xml.sax.saxutils import escape

COKLU_YAYIN = ("239.255.255.250", 3702)
MAX_XML = 256 * 1024
YANIT_YOK = "ONVIF yanıtı yok — kamera ONVIF kapalı olabilir, elle ekleyin"

# Yaygin RTSP yollari (ONVIF basarisiz olursa oneri listesi; kullanici secer/duzeltir)
RTSP_SABLONLARI = [
    ("Hikvision / HiLook ana akis", "/Streaming/Channels/101"),
    ("Hikvision / HiLook alt akis", "/Streaming/Channels/102"),
    ("Dahua / Amcrest ana akis", "/cam/realmonitor?channel=1&subtype=0"),
    ("Dahua / Amcrest alt akis", "/cam/realmonitor?channel=1&subtype=1"),
    ("Reolink ana akis", "/h264Preview_01_main"),
    ("Axis", "/axis-media/media.amp"),
    ("Uniview", "/media/video1"),
    ("Genel (stream1)", "/stream1"),
    ("Genel (live/ch0)", "/live/ch0"),
    ("Genel (ONVIF profil 1)", "/onvif1"),
    ("Genel (kok)", "/"),
]


def probe_xml(mesaj_id: str | None = None) -> bytes:
    """WS-Discovery Probe (NetworkVideoTransmitter)."""
    mid = mesaj_id or f"uuid:{uuid.uuid4()}"
    return (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
        'xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" '
        'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" '
        'xmlns:dn="http://www.onvif.org/ver10/network/wsdl">'
        f'<e:Header><w:MessageID>{escape(mid)}</w:MessageID>'
        '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
        '<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action></e:Header>'
        '<e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body></e:Envelope>'
    ).encode("utf-8")


def _guvenli_xml(veri: bytes):
    """Guvenilmez XML -> kok eleman ya da None (DOCTYPE/ENTITY, buyuk boyut, bozuk XML reddedilir)."""
    if not veri or len(veri) > MAX_XML:
        return None
    ust = veri.upper()
    if b"<!DOCTYPE" in ust or b"<!ENTITY" in ust:
        return None
    try:
        return ET.fromstring(veri)
    except ET.ParseError:
        return None


def _yerel(etiket: str) -> str:
    return etiket.rsplit("}", 1)[-1]


def _bul(kok, ad: str) -> list:
    return [e for e in kok.iter() if _yerel(e.tag) == ad]


def _scope_degeri(scopes: list, anahtar: str) -> str:
    on = f"onvif://www.onvif.org/{anahtar}/"
    for s in scopes:
        if s.lower().startswith(on.lower()):
            return parse.unquote(s[len(on):])
    return ""


def ayristir(veri: bytes, gonderen_ip: str = "") -> dict | None:
    """ProbeMatches datagrami -> {ip, xaddrs, scopes, ad, model, konum, uuid} ya da None (ilgisiz/bozuk yanit)."""
    kok = _guvenli_xml(veri)
    if kok is None or not _bul(kok, "ProbeMatch"):
        return None
    xaddrs = [x for e in _bul(kok, "XAddrs") for x in (e.text or "").split() if x.lower().startswith("http")]
    scopes = [s for e in _bul(kok, "Scopes") for s in (e.text or "").split()]
    ip = gonderen_ip
    for x in xaddrs:
        h = parse.urlsplit(x).hostname
        if h and not ip:
            ip = h
    if not ip:
        return None
    adres = [(e.text or "").strip() for e in _bul(kok, "Address") if (e.text or "").strip()]
    return {"ip": ip, "xaddrs": xaddrs, "scopes": scopes,
            "ad": _scope_degeri(scopes, "name"), "model": _scope_degeri(scopes, "hardware"),
            "konum": _scope_degeri(scopes, "location"), "uuid": adres[0] if adres else ""}


def yerel_ipler() -> list:
    """Cok kartli bilgisayarda her arayuzden aramak icin yerel IPv4 adresleri (loopback haric)."""
    ipler = []
    try:
        for bilgi in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = bilgi[4][0]
            if not ip.startswith("127.") and ip not in ipler:
                ipler.append(ip)
    except OSError:
        pass
    return ipler


def kesfet(sure_sn: float = 3.5, ipler: list | None = None) -> list:
    """Multicast Probe gonderir, `sure_sn` dinler. Doner: IP'ye gore tekil cihaz sozlukleri (bos liste = yanit yok)."""
    bulunan: dict = {}
    soketler = []
    for ip in (ipler if ipler is not None else yerel_ipler()) or [""]:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
            if ip:
                s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
            s.bind((ip, 0))
            s.settimeout(0.2)
            soketler.append(s)
        except OSError:
            continue
    try:
        bitis = time.monotonic() + float(sure_sn)
        sonraki_probe = 0.0
        while time.monotonic() < bitis:
            if time.monotonic() >= sonraki_probe:  # UDP kayiplara karsi 1 sn arayla tekrar
                for s in soketler:
                    try:
                        s.sendto(probe_xml(), COKLU_YAYIN)
                    except OSError:
                        pass
                sonraki_probe = time.monotonic() + 1.0
            for s in soketler:
                try:
                    veri, adr = s.recvfrom(65535)
                except (socket.timeout, OSError):
                    continue
                d = ayristir(veri, adr[0])
                if d:
                    bulunan.setdefault(d["ip"], d)
    finally:
        for s in soketler:
            s.close()
    return sorted(bulunan.values(), key=lambda d: tuple(int(p) if p.isdigit() else 0 for p in d["ip"].split(".")))


# --- ONVIF SOAP (GetStreamUri) ---------------------------------------------------------------
def _guvenlik_basligi(kullanici: str, parola: str, metin: bool = False) -> str:
    if not kullanici:
        return ""
    olusturma = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    ns = ('xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" '
          'xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"')
    pw = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#"
    if metin:
        sifre = f'<wsse:Password Type="{pw}PasswordText">{escape(parola)}</wsse:Password>'
        return f'<s:Header><wsse:Security {ns}><wsse:UsernameToken><wsse:Username>{escape(kullanici)}</wsse:Username>{sifre}</wsse:UsernameToken></wsse:Security></s:Header>'
    nonce = os.urandom(16)
    ozet = base64.b64encode(hashlib.sha1(nonce + olusturma.encode() + parola.encode()).digest()).decode()
    return (f'<s:Header><wsse:Security {ns}><wsse:UsernameToken><wsse:Username>{escape(kullanici)}</wsse:Username>'
            f'<wsse:Password Type="{pw}PasswordDigest">{ozet}</wsse:Password>'
            f'<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">'
            f'{base64.b64encode(nonce).decode()}</wsse:Nonce><wsu:Created>{olusturma}</wsu:Created></wsse:UsernameToken></wsse:Security></s:Header>')


def soap_govdesi(govde: str, kullanici: str = "", parola: str = "", metin: bool = False) -> bytes:
    return ('<?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
            f'{_guvenlik_basligi(kullanici, parola, metin)}<s:Body>{govde}</s:Body></s:Envelope>').encode("utf-8")


def _soap(url: str, govde: str, kullanici: str, parola: str, zaman_asimi: float):
    """Once PasswordDigest, 400/401'de PasswordText dener. Kok eleman ya da (None, hata) icin istisna firlatir."""
    son = None
    for metin in ((False, True) if kullanici else (False,)):
        istek = request.Request(url, data=soap_govdesi(govde, kullanici, parola, metin),
                                headers={"Content-Type": "application/soap+xml; charset=utf-8"}, method="POST")
        try:
            with request.urlopen(istek, timeout=zaman_asimi) as y:  # noqa: S310 - url yalniz http(s), kesif IP'sine kurulur
                kok = _guvenli_xml(y.read(MAX_XML + 1))
                if kok is None:
                    raise ValueError("ONVIF yaniti okunamadi")
                return kok
        except error.HTTPError as e:
            son = e
            if e.code not in (400, 401, 403):
                break
    raise son if son else ValueError("ONVIF istegi basarisiz")


def _servis_adresi(xaddr: str, ip: str) -> str:
    """Kameranin bildirdigi adrese degil, YANIT VEREN IP'ye baglan (yanlis/zararli XAddrs baska ana makineye yonlendiremesin)."""
    p = parse.urlsplit(xaddr)
    port = f":{p.port}" if p.port else ""
    return parse.urlunsplit((p.scheme if p.scheme in ("http", "https") else "http", f"{ip}{port}", p.path or "/onvif/device_service", "", ""))


def rtsp_adresi_ekle(uri: str, kullanici: str, parola: str) -> str:
    p = parse.urlsplit(uri)
    if not kullanici or p.username:
        return uri
    kimlik = parse.quote(kullanici, safe="") + (":" + parse.quote(parola, safe="") if parola else "")
    return parse.urlunsplit((p.scheme, f"{kimlik}@{p.hostname}" + (f":{p.port}" if p.port else ""), p.path, p.query, p.fragment))


def stream_uri(cihaz: dict, kullanici: str = "", parola: str = "", zaman_asimi: float = 4.0):
    """(rtsp_adresi | None, hata_metni). GetCapabilities -> GetProfiles -> GetStreamUri; adres kimlikle birlikte dondurulur."""
    ip = cihaz["ip"]
    adaylar = [_servis_adresi(x, ip) for x in cihaz.get("xaddrs", [])] or []
    for port in (80, 8000):
        a = f"http://{ip}:{port}/onvif/device_service"
        if a not in adaylar:
            adaylar.append(a)
    son_hata = "baglanti kurulamadi"
    for dev in adaylar:
        try:
            media = dev
            try:
                kok = _soap(dev, '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl">'
                                 '<tds:Category>Media</tds:Category></tds:GetCapabilities>', kullanici, parola, zaman_asimi)
                for m in _bul(kok, "Media"):
                    for x in _bul(m, "XAddr"):
                        if (x.text or "").strip().lower().startswith("http"):
                            media = _servis_adresi(x.text.strip(), ip)
                            break
            except (error.URLError, OSError, ValueError):
                pass  # bazi kameralar GetCapabilities'i kapatir; ayni adreste medya dene
            kok = _soap(media, '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>', kullanici, parola, zaman_asimi)
            tokenlar = [e.get("token") for e in _bul(kok, "Profiles") if e.get("token")]
            if not tokenlar:
                son_hata = "profil bulunamadi"
                continue
            govde = ('<trt:GetStreamUri xmlns:trt="http://www.onvif.org/ver10/media/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">'
                     '<trt:StreamSetup><tt:Stream>RTP-Unicast</tt:Stream><tt:Transport><tt:Protocol>RTSP</tt:Protocol></tt:Transport>'
                     f'</trt:StreamSetup><trt:ProfileToken>{escape(tokenlar[0])}</trt:ProfileToken></trt:GetStreamUri>')
            kok = _soap(media, govde, kullanici, parola, zaman_asimi)
            uri = next(((e.text or "").strip() for e in _bul(kok, "Uri") if (e.text or "").strip().lower().startswith("rtsp")), "")
            if uri:
                return rtsp_adresi_ekle(uri, kullanici, parola), ""
            son_hata = "RTSP adresi dönmedi"
        except error.HTTPError as e:
            son_hata = "kimlik doğrulanamadı (kullanıcı/parola?)" if e.code in (400, 401, 403) else f"HTTP {e.code}"
        except (error.URLError, OSError, ValueError, ET.ParseError) as e:
            son_hata = f"{type(e).__name__}: {e}"
    return None, son_hata


def rtsp_oneriler(ip: str, kullanici: str = "", parola: str = "", port: int = 554) -> list:
    """Yaygin RTSP sablonlarindan [(etiket, adres)] (kullanici secer/duzeltir)."""
    kimlik = ""
    if kullanici:
        kimlik = parse.quote(kullanici, safe="") + (":" + parse.quote(parola, safe="") if parola else "") + "@"
    return [(ad, f"rtsp://{kimlik}{ip}:{port}{yol}") for ad, yol in RTSP_SABLONLARI]

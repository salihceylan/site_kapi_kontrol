"""Agda kamera kesfi: ONVIF WS-Discovery (UDP multicast 239.255.255.250:3702) + YEREL ALT AG TCP TARAMASI (birlikte)
+ ONVIF GetStreamUri. Windows guvenlik duvari multicast'i kesse bile tarama sonuclari listelenir.
Yalniz stdlib (socket, uuid, urllib, xml.etree). Aga gelen XML guvenilmez veridir: DOCTYPE/ENTITY reddedilir, boyut sinirlidir.
Tarama portlari / zaman asimi / is parcacigi `ayarlar.json` > kesif bolumundendir (kodda sabit yok)."""
from __future__ import annotations

import base64
import errno
import hashlib
import ipaddress
import os
import re
import socket
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from urllib import error, parse, request
from xml.sax.saxutils import escape

from . import ayarlar

COKLU_YAYIN = ("239.255.255.250", 3702)  # WS-Discovery protokol sabitidir (ayar degil)
MAX_XML = 256 * 1024
YANIT_YOK = "ONVIF yanıtı yok — kamera ONVIF kapalı olabilir, elle ekleyin"
_REDDEDILDI = {errno.ECONNREFUSED, 10061}  # WSAECONNREFUSED: ana makine canli, port kapali

# Yaygin RTSP yollari (ONVIF basarisiz olursa oneri listesi; kullanici secer/duzeltir)
RTSP_SABLONLARI = [
    ("Hikvision / HiLook ana akis", "/Streaming/Channels/101"),
    ("Hikvision / HiLook alt akis", "/Streaming/Channels/102"),
    ("Dahua / Amcrest ana akis", "/cam/realmonitor?channel=1&subtype=0"),
    ("Dahua / Amcrest alt akis", "/cam/realmonitor?channel=1&subtype=1"),
    ("Reolink ana akis", "/h264Preview_01_main"),
    ("Axis", "/axis-media/media.amp"),
    ("Uniview", "/media/video1"),
    ("TP-Link Tapo / genel (stream1)", "/stream1"),
    ("Genel (live/ch0)", "/live/ch0"),
    ("Genel (ONVIF profil 1)", "/onvif1"),
    ("TP-Link Tapo alt akis", "/stream2"),
    ("Hikvision eski / Ezviz", "/h264/ch1/main/av_stream"),
    ("Foscam", "/videoMain"),
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
    ipler: list = []

    def ekle(ip) -> None:
        if ip and not ip.startswith(("127.", "0.")) and ip not in ipler:
            ipler.append(ip)

    host = socket.gethostname()
    try:  # ana makine adina kayitli arayuzler
        for bilgi in socket.getaddrinfo(host, None, socket.AF_INET):
            ekle(bilgi[4][0])
    except OSError:
        pass
    try:
        for ip in socket.gethostbyname_ex(host)[2]:
            ekle(ip)
    except OSError:
        pass
    try:  # varsayilan cikis arayuzu (UDP connect paket gondermez; DNS'e kayitli olmayan Wi-Fi/Ethernet'i yakalar)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 9))
            ekle(s.getsockname()[0])
    except OSError:
        pass
    return ipler


def kesfet(sure_sn: float = 3.5, ipler: list | None = None, soket_fabrikasi=None) -> list:
    """Multicast Probe gonderir (HER arayuzden ayri soketle), `sure_sn` dinler. Doner: IP'ye gore tekil cihaz sozlukleri
    (bos liste = yanit yok; guvenlik duvari multicast'i kesiyor olabilir - bu yuzden `ara()` ayrica alt ag taramasi yapar)."""
    bulunan: dict = {}
    soketler = []
    yeni = soket_fabrikasi or (lambda: socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP))
    for ip in (ipler if ipler is not None else yerel_ipler()) or [""]:
        try:
            s = yeni()
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


# --- Yerel alt ag TCP taramasi -----------------------------------------------------------------
def kesif_ayari(ayar: dict | None = None) -> dict:
    """Verilen `kesif` bolumunu VARSAYILAN ile birlestirir (eksik anahtarlar geri-dusus degerini alir)."""
    return ayarlar.derin_birlestir(ayarlar.VARSAYILAN["kesif"], ayar or {})


def alt_ag_adresleri(ip: str, uzunluk: int = 24, haric: set | frozenset = frozenset()) -> list:
    """`ip`'nin bulundugu IPv4 alt agindaki ana makine adresleri (kendi adresleri haric). Uzunluk guvenlik icin 22-30 arasina sikistirilir."""
    try:
        ag = ipaddress.ip_network(f"{ip}/{max(22, min(30, int(uzunluk)))}", strict=False)
    except ValueError:
        return []
    return [str(h) for h in ag.hosts() if str(h) not in haric]


def tcp_dene(ip: str, port: int, zaman_asimi: float, soket_fabrikasi=None) -> str:
    """'acik' | 'reddedildi' (ana makine canli, port kapali) | 'zaman_asimi'."""
    s = (soket_fabrikasi or (lambda: socket.socket(socket.AF_INET, socket.SOCK_STREAM)))()
    try:
        s.settimeout(float(zaman_asimi))
        kod = s.connect_ex((ip, int(port)))
    except OSError:
        return "zaman_asimi"
    finally:
        try:
            s.close()
        except OSError:
            pass
    return "acik" if kod == 0 else ("reddedildi" if kod in _REDDEDILDI else "zaman_asimi")


def alt_ag_tara(ipler: list, ayar: dict | None = None, soket_fabrikasi=None, ilerleme=None) -> dict:
    """PC'nin her IPv4 adresinin alt aginda (varsayilan /24) threadli TCP connect taramasi.
    Doner {ip: [acik_portlar]} (yalniz en az bir portu acik olanlar). `ilerleme(biten, toplam)` verilirse cagrilir."""
    c = kesif_ayari(ayar)["tarama"]
    portlar = [int(p) for p in c["portlar"]]
    kendi, goruldu, hedefler = set(ipler), set(), []
    haric = [ipaddress.ip_network(a, strict=False) for a in c["haric_aglar"]]
    for ip in ipler:
        if any(ipaddress.ip_address(ip) in a for a in haric):  # VPN / sanal arayuz aglari taranmaz
            continue
        for h in alt_ag_adresleri(ip, c["alt_ag_uzunlugu"], kendi):
            if h not in goruldu:
                goruldu.add(h)
                hedefler.append(h)
    acik: dict = {}
    kilit = threading.Lock()
    biten = [0]
    isler = [(h, p) for h in hedefler for p in portlar]
    toplam = len(isler) * int(c["tur"])

    def is_(h: str, p: int) -> tuple:
        return h, p, tcp_dene(h, p, c["zaman_asimi_sn"], soket_fabrikasi)

    with ThreadPoolExecutor(max_workers=max(1, int(c["is_parcacigi"]))) as havuz:
        for _tur in range(max(1, int(c["tur"]))):  # ilk SYN ARP cozumunde kaybolabilir: yanit vermeyenler bir tur daha denenir
            sonraki = []
            for f in as_completed([havuz.submit(is_, h, p) for h, p in isler]):
                h, p, durum = f.result()
                biten[0] += 1
                if durum == "acik":
                    with kilit:
                        acik.setdefault(h, set()).add(p)
                elif durum == "zaman_asimi":
                    sonraki.append((h, p))
                if ilerleme and biten[0] % 50 == 0:
                    ilerleme(biten[0], toplam)
            isler = sonraki
            if not isler:
                break
    return {h: sorted(p) for h, p in acik.items()}


def _ip_anahtar(ip: str) -> tuple:
    return tuple(int(p) if p.isdigit() else 0 for p in ip.split("."))


def siniflandir(portlar: list, ayar: dict | None = None) -> tuple:
    """(oncelik, etiket): RTSP portu acik -> 1, ONVIF/kamera portu -> 2, yalniz web -> 3."""
    c = kesif_ayari(ayar)["tarama"]
    if set(portlar) & set(c["rtsp_portlari"]):
        return 1, "Olası kamera — RTSP açık"
    if set(portlar) & set(c["kamera_portlari"]):
        return 2, "Olası kamera — kamera/ONVIF portu açık"
    return 3, "Ağ cihazı — yalnız web arayüzü (kamera olabilir)"


def onvif_tekil(hedefler: list, sure_sn: float, soket_fabrikasi=None) -> list:
    """Multicast yerine DOGRUDAN (unicast) WS-Discovery Probe: `hedefler` = IP listesi. Multicast filtrelense bile
    bazi kameralar bu sorguya yanit verir. Doner: ayristir() sozlukleri."""
    if not hedefler:
        return []
    yeni = soket_fabrikasi or (lambda: socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP))
    try:
        s = yeni()
        s.settimeout(0.2)
    except OSError:
        return []
    bulunan: dict = {}
    try:
        for h in hedefler:
            try:
                s.sendto(probe_xml(), (h, COKLU_YAYIN[1]))
            except OSError:
                pass
        bitis = time.monotonic() + float(sure_sn)
        while time.monotonic() < bitis:
            try:
                veri, adr = s.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            d = ayristir(veri, adr[0])
            if d:
                bulunan.setdefault(d["ip"], d)
    finally:
        s.close()
    return list(bulunan.values())


def birlestir(onvif: list, tarama: dict, ayar: dict | None = None) -> list:
    """ONVIF yanitlari + tarama sonuclari -> IP'ye gore tekil cihaz listesi (ONVIF dogrulananlar, sonra RTSP acik olanlar...)."""
    kes = kesif_ayari(ayar)
    rtsp_portlari = set(kes["tarama"]["rtsp_portlari"])
    cihazlar: dict = {}
    for d in onvif:
        cihazlar[d["ip"]] = {**d, "portlar": sorted(tarama.get(d["ip"], [])), "kaynak": "onvif"}
    for ip, portlar in tarama.items():
        if ip in cihazlar:
            cihazlar[ip]["kaynak"] = "onvif+tarama"
        else:
            cihazlar[ip] = {"ip": ip, "xaddrs": [], "scopes": [], "ad": "", "model": "", "konum": "", "uuid": "",
                            "portlar": sorted(portlar), "kaynak": "tarama"}
    for d in cihazlar.values():
        oncelik, etiket = siniflandir(d["portlar"], ayar)
        if d["kaynak"].startswith("onvif"):
            oncelik, etiket = 0, "ONVIF kamera"
        d["oncelik"], d["tur"] = oncelik, etiket
        d["rtsp_port"] = next((p for p in d["portlar"] if p in rtsp_portlari), int(kes["rtsp_port"]))
        d["konum"] = d["konum"] or ("açık portlar: " + ", ".join(str(p) for p in d["portlar"]) if d["portlar"] else "")
    return sorted(cihazlar.values(), key=lambda d: (d["oncelik"], _ip_anahtar(d["ip"])))


def ara(ayar: dict | None = None, ipler: list | None = None, tcp_fabrikasi=None, udp_fabrikasi=None, ilerleme=None) -> dict:
    """'Agda kamera ara': ONVIF WS-Discovery (her arayuzden) VE yerel alt ag taramasi BIRLIKTE.
    Doner {cihazlar, onvif_adet, tarama_adet, arayuzler, hatalar}; ONVIF 0 donse bile tarama sonuclari cihazlar icindedir."""
    kes = kesif_ayari(ayar)
    ipler = list(ipler) if ipler is not None else yerel_ipler()
    onvif: list = []
    hatalar: list = []

    def onvif_is() -> None:
        try:
            onvif.extend(kesfet(float(kes["sure_sn"]), ipler, udp_fabrikasi))
        except Exception as e:  # noqa: BLE001 - ONVIF hatasi taramayi dusurmesin
            hatalar.append(f"ONVIF: {type(e).__name__}")

    t = threading.Thread(target=onvif_is, daemon=True)
    t.start()
    tarama: dict = {}
    if kes["tarama"]["etkin"] and ipler:
        try:
            tarama = alt_ag_tara(ipler, kes, tcp_fabrikasi, ilerleme)
        except Exception as e:  # noqa: BLE001
            hatalar.append(f"Tarama: {type(e).__name__}")
    t.join()
    bilinen = {d["ip"] for d in onvif}
    ek = onvif_tekil([ip for ip in tarama if ip not in bilinen], min(1.5, float(kes["sure_sn"])), udp_fabrikasi) if tarama else []
    onvif.extend(ek)
    cihazlar = birlestir(onvif, tarama, kes)
    return {"cihazlar": cihazlar, "onvif_adet": len(onvif), "tarama_adet": len(tarama), "arayuzler": ipler, "hatalar": hatalar}


def ozet_mesaj(s: dict) -> str:
    """Arama sonucu icin durust durum metni."""
    n, ov, tr = len(s["cihazlar"]), s["onvif_adet"], s["tarama_adet"]
    if not s["arayuzler"]:
        return "Bu bilgisayarda IPv4 ağ bağlantısı bulunamadı — kablo/Wi-Fi bağlantısını denetleyin ya da 'El ile ekle' ile IP yazın."
    if n == 0:
        return ("Ağda kamera bulunamadı: ONVIF yanıtı yok ve " + ", ".join(s["arayuzler"]) + " ağlarının taramasında kamera portu açık cihaz çıkmadı. "
                "Windows güvenlik duvarı ya da farklı alt ağ olabilir — 'El ile ekle' ile kameranın IP adresini yazın.")
    if ov == 0:
        return (f"{n} olası kamera listelendi (alt ağ taraması). ONVIF yanıtı gelmedi — güvenlik duvarı multicast'i kesiyor olabilir; "
                "RTSP adresini seçili cihaz için kullanıcı/parola ile bulun ya da şablonlardan deneyin.")
    return f"{n} cihaz bulundu (ONVIF: {ov}, tarama: {tr}). Birini seçin."


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


def stream_uri(cihaz: dict, kullanici: str = "", parola: str = "", zaman_asimi: float = 4.0, onvif_portlar: list | None = None):
    """(rtsp_adresi | None, hata_metni). GetCapabilities -> GetProfiles -> GetStreamUri; adres kimlikle birlikte dondurulur.
    `onvif_portlar` (ayar: kesif.onvif_portlar): kamera XAddrs vermediyse denenen servis portlari; taramada acik cikanlar once denenir."""
    ip = cihaz["ip"]
    adaylar = [_servis_adresi(x, ip) for x in cihaz.get("xaddrs", [])] or []
    portlar = [int(p) for p in (onvif_portlar if onvif_portlar is not None else kesif_ayari()["onvif_portlar"])]
    acik = set(cihaz.get("portlar", []))
    for port in sorted(portlar, key=lambda p: p not in acik):
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


_IPV4_BICIM = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
_AD_BICIM = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")


def rtsp_coz(girdi: str, kullanici: str = "", parola: str = "", port: int = 554) -> dict:
    """'El ile ekle' girdisini ayristirir: IP (192.168.1.64), IP:port, ana makine adi, yol ekli (192.168.1.64/stream1) ya da TAM RTSP adresi.
    Doner {hata, ip, tam, oneriler:[(etiket, rtsp_adresi)]}; `tam` True ise tek oneri girilen adrestir, degilse yaygin RTSP sablonlari."""
    bos = {"hata": "", "ip": "", "tam": False, "oneriler": []}
    g = (girdi or "").strip()
    if not g:
        return {**bos, "hata": "Kameranın IP adresini (192.168.1.64) ya da tam RTSP adresini yazın."}
    if g.lower().startswith(("rtsp://", "rtsps://")):
        p = parse.urlsplit(g)
        try:
            p.port
        except ValueError:
            return {**bos, "hata": "RTSP adresindeki port geçersiz."}
        if not p.hostname:
            return {**bos, "hata": "RTSP adresinde IP/ana makine yok."}
        return {**bos, "ip": p.hostname, "tam": True, "oneriler": [("Girilen RTSP adresi", rtsp_adresi_ekle(g, kullanici, parola))]}
    g = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*://", "", g)  # http://192.168.1.64/ yazilmissa semayi at
    p = parse.urlsplit("//" + g)
    try:
        prt = p.port
    except ValueError:
        return {**bos, "hata": "Port geçersiz."}
    host = p.hostname or ""
    if _IPV4_BICIM.match(host):
        try:
            ipaddress.IPv4Address(host)
        except ValueError:
            return {**bos, "hata": f"Geçersiz IP adresi: {host}"}
    elif not _AD_BICIM.match(host):
        return {**bos, "hata": "IP adresi ya da ana makine adı geçersiz."}
    yol = p.path + (("?" + p.query) if p.query else "")
    if yol not in ("", "/"):  # yol verilmis -> tam adres
        url = f"rtsp://{host}:{prt or port}{yol}"
        return {**bos, "ip": host, "tam": True, "oneriler": [("Girilen adres", rtsp_adresi_ekle(url, kullanici, parola))]}
    return {**bos, "ip": host, "oneriler": rtsp_oneriler(host, kullanici, parola, prt or port)}

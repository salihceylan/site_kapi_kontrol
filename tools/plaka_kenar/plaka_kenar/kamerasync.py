"""Sunucudan inen kamera tanimlarini (GET sync > config.cameras) yerel `ayarlar.json > kameralar` ile birlestirir (sozlesme v3).
SAF fonksiyonlar: ag, dosya, thread yok (servis cagirir, kaydeder, akislari yeniler).

Kurallar:
- Sunucu kaynakli satirlar `kaynak: "sunucu"` ile ISARETLIDIR (id "s<camera_id>"). Sunucudan artik gelmeyen sunucu-kaynakli satir SILINIR.
- Yerelde elle eklenen (isaretsiz) satirlar KORUNUR. Ayni `sunucu_id`'li yerel satir varsa YEREL kazanir (sunucu satiri eklenmez).
- Sunucu satiri yalniz sunucunun yonettigi alanlari ezer (ad, url, sunucu_id, kapi_id, yon, etkin, marka); yerelde ayarlanan roi / fps / profil / mod korunur.
- Satir sozlugu degismediyse AYNI nesne kalir (calisan akis ayni sozlugu okur); yalniz url / etkin degisince akis yeniden baslatilir.
- `kapi_id`: yerelde `sunucu_id`'si sunucudaki kapi kimligiyle eslesen kapi satirinin kodu; eslesen yoksa "" (kamera goruntu / sinama icin calisir, kapi acamaz).
Parola yalniz `url` icinde (kimlik dahil RTSP adresi) tutulur ve ASLA gunluge yazilmaz."""
from __future__ import annotations

from . import kesif

KAYNAK = "sunucu"
SUNUCU_ALANLARI = ("ad", "url", "sunucu_id", "kapi_id", "yon", "etkin", "marka", "kaynak")


def sunucu_kamera_id(kamera_id) -> str:
    return f"s{int(kamera_id)}"


def _pozitif(v):
    try:
        n = int(v)
    except (TypeError, ValueError):
        return None
    return n if n > 0 else None


def _yon(direction) -> str:
    return direction if direction in ("giris", "cikis") else ""  # 'auto' / bilinmeyen: yon kapi modundan ya da "iceride" durumundan


def kapi_eslemesi(kapilar: list) -> dict:
    """{sunucudaki kapi kimligi (str): yerel kapi kodu}."""
    return {str(k["sunucu_id"]): k["id"] for k in kapilar if k.get("id") and _pozitif(k.get("sunucu_id")) is not None}


def sunucu_satiri(k: dict, esleme: dict) -> dict | None:
    """Sunucu kamera tanimi -> yerel kamera satiri alanlari; gecersizse None (rtsp_url zorunlu, yalniz rtsp/rtsps)."""
    cid = _pozitif(k.get("camera_id"))
    url = str(k.get("rtsp_url") or "").strip()
    if cid is None or not url.lower().startswith(("rtsp://", "rtsps://")):
        return None
    gate = _pozitif(k.get("gate_id"))
    return {"id": sunucu_kamera_id(cid), "ad": str(k.get("name") or f"Kamera {cid}")[:60],
            "url": kesif.rtsp_adresi_ekle(url, str(k.get("username") or ""), str(k.get("password") or "")),
            "sunucu_id": cid, "kapi_id": esleme.get(str(gate), "") if gate is not None else "",
            "yon": _yon(k.get("direction")), "etkin": True, "marka": str(k.get("brand") or ""), "kaynak": KAYNAK,
            "_kapi_yok": gate is not None and str(gate) not in esleme}


def birlestir(ayar: dict, sunucu_kameralari: list) -> dict:
    """`ayar["kameralar"]` listesini yerinde GUNCELLER (yeni liste atamasi) ve farki dondurur:
    {degisti, eklenen[id], silinen[id], guncellenen[id], yeniden_baslat[id], kapisiz[id]}. `sunucu_kameralari` None ise (sunucu cevap vermedi)
    hicbir sey yapilmaz."""
    fark = {"degisti": False, "eklenen": [], "silinen": [], "guncellenen": [], "yeniden_baslat": [], "kapisiz": []}
    if sunucu_kameralari is None:
        return fark
    kameralar = ayar.setdefault("kameralar", [])
    esleme = kapi_eslemesi(ayar.get("kapilar", []))
    yerel = [k for k in kameralar if k.get("kaynak") != KAYNAK]
    yerel_sunucu_idleri = {str(_pozitif(k.get("sunucu_id"))) for k in yerel if _pozitif(k.get("sunucu_id")) is not None}
    eski = {k["id"]: k for k in kameralar if k.get("kaynak") == KAYNAK and k.get("id")}
    yeni_liste: list = []
    gorulen: set = set()
    for ham in sunucu_kameralari:
        satir = sunucu_satiri(ham, esleme) if isinstance(ham, dict) else None
        if satir is None or str(satir["sunucu_id"]) in yerel_sunucu_idleri or satir["id"] in gorulen:
            continue  # gecersiz / yerel kazanir / tekrar
        gorulen.add(satir["id"])
        kapi_yok = satir.pop("_kapi_yok")
        if kapi_yok:
            fark["kapisiz"].append(satir["id"])
        mevcut = eski.get(satir["id"])
        if mevcut is None:
            satir.update(mod="akis", fps=3, profil="oto")
            yeni_liste.append(satir)
            fark["eklenen"].append(satir["id"])
            fark["yeniden_baslat"].append(satir["id"])
            continue
        degisen = [a for a in SUNUCU_ALANLARI if mevcut.get(a) != satir[a]]
        if degisen:
            mevcut.update({a: satir[a] for a in degisen})  # ayni nesne: calisan akis canli alanlari (ad, yon, kapi_id) hemen okur
            fark["guncellenen"].append(satir["id"])
            if "url" in degisen or "etkin" in degisen:
                fark["yeniden_baslat"].append(satir["id"])
        yeni_liste.append(mevcut)
    for kid in eski:
        if kid not in gorulen:
            fark["silinen"].append(kid)
            fark["yeniden_baslat"].append(kid)
    fark["degisti"] = bool(fark["eklenen"] or fark["silinen"] or fark["guncellenen"])
    if fark["degisti"]:
        ayar["kameralar"] = yerel + yeni_liste  # tek atama: arayuz / servis okuyucular tutarli listeyi gorur
    return fark

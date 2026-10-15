"""Faz kontrol listesi sayfasini uretir: sablon.html + <liste>.json -> <liste>.html. Kullanim: python uret.py [liste ...]"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# ad -> (baslik, ust etiket, vurgu, vurgu acik, vurgu koyu, vurgu acik koyu)
LISTELER = {
    "platform": ("Platform Faz Kontrol Listesi", "AHBU Site Yönetim Platformu · Faz listesi",
                 "#1d4fb0", "#dbe6fb", "#7fa9f2", "#1b2e52"),
}
GELISTIRME = {"hazir", "yapiliyor", "planli", "yakinda"}

sablon = io.open(os.path.join(HERE, "sablon.html"), encoding="utf-8").read()
for ad in sys.argv[1:] or list(LISTELER):
    title, eyebrow, acc, soft, acc_d, soft_d = LISTELER[ad]
    veri = json.load(io.open(os.path.join(HERE, ad + ".json"), encoding="utf-8"))
    ids = [m["id"] for b in veri["bolumler"] for m in b["maddeler"]]
    assert len(ids) == len(set(ids)), "yinelenen madde id"
    for b in veri["bolumler"]:
        assert b.get("durum") in GELISTIRME, "bolum durumu gecersiz: " + b["id"]
        for m in b["maddeler"]:
            assert m.get("gelistirme", "hazir") in GELISTIRME, "madde durumu gecersiz: " + m["id"]
            assert m["id"].split(".")[0] == b["id"], "madde bolum disinda: " + m["id"]
    veri["rol"] = ad
    data = json.dumps(veri, ensure_ascii=False).replace("</", "<\\/")
    html = (sablon.replace("__TITLE__", title).replace("__EYEBROW__", eyebrow).replace("__ACCENT__", acc)
            .replace("__ACCENT_SOFT__", soft).replace("__ACCENT_DARK__", acc_d)
            .replace("__ACCENT_SOFT_DARK__", soft_d).replace("__DATA__", data))
    io.open(os.path.join(HERE, ad + ".html"), "w", encoding="utf-8", newline="\n").write(html)
    print(ad, "bolum", len(veri["bolumler"]), "madde", len(ids), "->", ad + ".html", len(html), "bayt")

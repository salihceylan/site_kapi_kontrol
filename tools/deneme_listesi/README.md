# Faz kontrol listesi (claude.ai sayfası)

Site ve toplu yaşam yönetim platformunun fazlarını ve her fazın deneme maddelerini gösteren sayfa. Proje sahibi her maddeyi
"Çalışıyor / Çalışmıyor" ve "Böyle istiyorum / istemiyorum" ile işaretler, not yazar; işaretler sayfanın veritabanında
(`yanitlar` koleksiyonu) tutulur, Claude `ArtifactData` ile okur ve yanıtlar.

- **Sayfa:** https://claude.ai/artifact/WruF9VpJPLktkfM9zrVWCb (özel; yalnız sahibi açar)
- **Madde listesi:** `platform.json` (bölüm = faz: `F0`, `F1`, …; madde kimliği `F1.03`). Üretici: `python uret.py` → `platform.html`
  (`.gitignore`'da). Aynı URL'ye yeniden yayınlanır; kayıtlar kalır, bu yüzden madde kimliklerini DEĞİŞTİRMEYİN, yeni madde yeni kimlik alır.
- **Kayıt biçimi:** belge kimliği = madde kimliğinde nokta yerine alt çizgi (`F1.03` -> `F1_03`). Alanlar: `madde`, `durum`
  (`calisiyor` / `calismiyor` / boş), `istek` (`istiyorum` / `istemiyorum` / boş), `not`, `guncellendi`. Claude'un yanıtı:
  `claude_yanit`, `claude_tarih`, `claude_durum` (`duzeltildi` -> sayfada "Düzeltildi · yeniden deneyin"; yazarken `if_version` şart).
- **Geliştirme durumu:** madde `gelistirme` alanı `planli` → `yapiliyor` → `hazir` (denemeye hazır) ya da `yakinda` ("Yakında…", denenmez);
  bölümün `durum` alanı aynı değerleri taşır. Bir faz canlıya alındığında o fazın maddeleri ve bölümü `hazir` yapılır, değişen maddelere
  `yeni: true` konur (önceki turun işaretleri kaldırılır) ve sayfa yeniden yayınlanır.
- Şablon, `ev_otomasyon/tools/deneme_listesi` şablonundan türetilmiştir (faz durumu, "Yakında…" ve planlı madde desteği eklendi).

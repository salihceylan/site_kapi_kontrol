# Demo veri tohumu (`tools/demo_seed`)

"Cenk" sitesini (sites.name icinde "Cenk" gecen TEK site) 2023-01'den bugune YILLARDIR kullaniliyormus gibi tutarli SAHTE veriyle doldurur
(Finans grafikleri, yaslandirma, kasa/banka seyri, duyuru, is takibi, rezervasyon, karar defteri, belgeler...). Uygulama kodu (`lib/`, `server/src`)
DEGISMEZ; arac uygulamanin kendi servislerini ve tablo kisitlarini kullanir. Her eklenen satir `demo_seed_registry`'ye yazilir ve `cleanup.mjs` ile geri alinir.

> UYARI: Uretilen kisi, telefon, IBAN, firma, belge ve hesaplarin HEPSI sahtedir. E-postalar `@demo.invalid` (RFC 2606, teslim edilemez); telefonlar `+90 500 000 xx xx`;
> IBAN bicim olarak gecerli (mod-97) ama banka kodu (99990) gercek bir bankaya ait degil. Sifreler HICBIR yere commit edilmez (`out/` .gitignore'dadir).

## Dosyalar

| Dosya | Gorev |
|---|---|
| `seed.mjs` | Ana arac. `--site "Cenk"` (birden cok ya da hic eslesme: DURUR), `--creds-out <json>`, `--only people,finance`, `--force`, `--dry-run`, `--today`, `--close-through 2026-08` |
| `cleanup.mjs` | `--list`, `--batch <id> --yes`: kayitli satirlari siler (SUPERUSER gerekir), diskteki belge dosyalarini siler, degistirilen satirlari eski haline getirir |
| `make_pdf.py` | `--creds creds.json --out hesaplar.pdf` : A4 PDF (yonetim kadrosu + gorevliler + daire daire sakinler, daire amiri belirtilmis). `pip install reportlab` |
| `run_remote.sh` | Sunucuda: pg_dump yedegi -> yedekten gecici DB -> tohum + cleanup provasi -> `--prod` ile canli |
| `test/local_test.mjs` | Yerel uctan uca test (gecici PostgreSQL, fixture site, dogrulamalar, cleanup, PDF) |
| `lib/`, `steps/` | Yardimcilar ve modul adimlari (`people`, `metering`, `finance`, `budget`, `announcements`, `neighbor`, `documents`, `work`, `reservation`, `visitors`, `contracts`, `decisions`, `surveys`, `equipment`, `devices`, `annual_report`) |

## Calistirma

```bash
# 1) Sunucuya kopyala ve provayi calistir (yedek + gecici DB + cleanup provasi; canliya YAZMAZ)
scp -r tools/demo_seed <kullanici>@<sunucu>:~/demo_seed
ssh <sunucu> 'bash ~/demo_seed/run_remote.sh --site Cenk'

# 2) Prova temizse canliya yaz (yedek tekrar alinir)
ssh <sunucu> 'bash ~/demo_seed/run_remote.sh --prod --skip-rehearsal --creds-out ~/demo_seed/out/creds.json'

# 3) Kimlik dosyasini al, PDF uret, sunucudaki kopyayi sil
scp <sunucu>:~/demo_seed/out/creds.json out/ && python make_pdf.py --creds out/creds.json --out out/demo_hesaplar.pdf
ssh <sunucu> 'shred -u ~/demo_seed/out/creds.json'

# Geri alma (deneme bitince)
DATABASE_URL=postgres://... node cleanup.mjs --list
DATABASE_URL=postgres://... node cleanup.mjs --batch demo-YYYYMMDDHHMMSS --yes
```

Elle (herhangi bir PostgreSQL): `DATABASE_URL=postgres://kullanici:parola@host:5432/db node seed.mjs --site Cenk --creds-out out/creds.json`.
`server/` dizininde `npm ci` yapilmis olmali (arac `pg`, `bcryptjs` ve servis modullerini oradan yukler; `--server-dir` ile degistirilebilir). `server/.env` varsa
yuklenir (mevcut ortam degiskenlerini ezmez): `FINANCE_RECEIPT_SECRET` (makbuz), `JWT_SECRET` (kamera parolasi sifreleme), `DOCUMENTS_DIR` (belge deposu) buradan gelir.

## Neler uretir (10 daireli sitede, bugun 2026-10-22)

* **Kisiler**: her dairede 4-5 kisi (ayni soyad; ebeveynler, cocuklar, yasli yakin), tam 1 daire amiri (`APARTMENT_ADMIN`); yaklasik %70 malik / %30 kiraci (kiraci dairede dis oturan malik de kayitli);
  tasinma tarihleri farkli (yari daire 2019-2022'den beri, kalani 2023-2026), yeni tasinan malik dairelerde onceki malik pasif kayit. Her kisinin KENDI hesabi (kullanici adi `ad.soyad`, sifre 12 karakter
  karisabilen harfler yok, bcrypt = uygulamanin `hashPassword`'u). Yonetim kurulu (baskan, 2 uye, denetci; farkli dairelerden `BOARD_MEMBER`), 3 gorevli (`STAFF`: kapici, teknik, danisma), 0-2 arac/daire, rehber (12 telefon).
  Mevcut site yoneticisi KORUNUR, dokunulmaz.
* **Finans (en onemli)**: iki hesap (Kasa + sahte IBAN'li banka), 46 ay aylik aidat (m2'ye gore daire basina farkli; 2023 ~1.500, 2024 ~2.400, 2025 ~3.500, 2026 ~4.800 TL), ek borc taksitleri (asansor 2, dis cephe 4),
  tahsilat deseni (zamaninda odeyenler, surekli 30/60 gun gecikenler, 2 kronik gecikmeli daire, ceyreklik pesin odeyen), nakit/havale/cek, malik/kiraci hesabi, her tahsilat icin makbuz, ~575 gider (14 kategori, 13 tedarikci,
  rutin/beklenmedik, mevsimsel dogalgaz/elektrik/su, 11 beklenmedik ariza), kasa<->banka aktarimlari, 6 mutabakat (banka faizi/ucreti duzeltmeli), 2 bekleyen dekont bildirimi, 4 eslesmemis banka satiri, ay kapatma (2026-08'e kadar).
  Yillik gelir ~ gider (+-%10): tahsilat toplamina gore gider olceklenir (oranlar 2023 0,97 / 2024 1,03 / 2025 0,96 / 2026 0,95).
* **Isletme projesi**: 2023-2026 kesin (kalemler gerceklesenin %95-112'si), 2027 teblig (itiraz suresi acik). **Faaliyet raporu**: 2023-2025 + 2026 taslak (yonetici duzenleme metinleri). **Sayaclar**: daire basi su + kalorimetre, 47 aylik okuma, 2 daire anormal tuketim,
  ceyreklik su faturalandirma (deftere yazilir). **Duyurular**: ~47 (okundu kayitlari, 3 okunmamis guncel). **Komsu panosu**: 15 ilan. **Belgeler**: 21 gercek PDF (servis uzerinden, sha256/kota tutarli). **Is takibi**: 60 talep (fotograf eki yok).
  **Rezervasyon**: 3 alan, ~118 rezervasyon, 8 konsiyerj. **Ziyaretci/kargo**: ~155 kayit (bugun 4 bekleyen kargo). **Firma/sozlesme**: 8 firma, 11 sozlesme (2 yakinda biten). **Karar defteri**: ~53 numarali karar (uc aylik kurul + yillik genel kurul).
  **Anket**: 6 (4 kapali sonuclu, 2 acik; daire basina tek oy). **Ekipman**: 10 ekipman, 11 plan, ~160 bakim kaydi, gider baglantilari. **Odeme/Kamera**: sahte kapali saglayici bilgisi, 3 kamera (Hikvision/Tiandy/ONVIF, yerel IP), ~104 plaka olayi.

## Modul eslemesi ve atlama

Her adim yalniz o site icin ACIK modulde calisir (`site_modules` + `catalog.js`); kapali modul ATLANIR ve rapora yazilir (modul ASLA acilmaz):
`finance`, `metering`, `budget`, `announcements` (cekirdek), `neighbor_board`, `documents`, `work_tracking`, `reservation`, `visitor_log`, `contracts`, `decision_book`, `survey`, `equipment`, `directory`, `annual_report`, `card_payments` + `plate_cameras` (devices).
KAPSAM DISI (dokunulmaz): kapilar, kayitli cihazlar, "Daireye Katil", kartli gecis, misafir gecisi, PIN, plaka tanima ve CCTV. `drive_storage` (Google Drive, OAuth gerekir) ve "yakinda" moduller (`online_payment`, `hgs_access`, `cctv_link`, `plate_recognition`) atlanir.

## Etiketleme ve geri alma

* `seed.mjs` baslarken **gecici** `AFTER INSERT` yakalama tetikleyicilerini (`zz_demo_seed_capture`) tum public tablolara kurar, oturumda `demo_seed.batch` ayari doluyken eklenen HER satiri
  (uygulama servislerinin ve tetikleyicilerin urettigi satirlar dahil) `demo_seed_registry(batch_id, table_name, row_id, op, before_image, created_at)` tablosuna yazar; bitince tetikleyicileri kaldirir.
* Mevcut satirlarda yapilan degisiklikler (dairelerin m2/kat/arsa payi/kategori/sorumlu taraf, `resident_user_code`) `op='update'` + `before_image` ile saklanir; cleanup eski haline getirir.
* `cleanup.mjs` tek transaction'da `SET LOCAL session_replication_role = replica` ile (yalniz eklemeli tablolar: `ledger_entries`, makbuzlar, `audit_log`, `board_decisions` vb.) YALNIZ kayitli satirlari siler,
  belge dosyalarini (`@file`) diskten kaldirir. Sequence degerleri geri alinmaz (zararsiz). Koruma: sitede demo batch ya da finans/defter/guncel sakin kaydi varsa tohum DURUR (`--force` ile asilir).

## E-posta gonderilmez

Hesap acilis e-postasi yok (hesaplar dogrudan yazilir), kullanici bildirim tercihlerinde e-posta ve push kapali, duyurular `send_email=false` ve alici `email_status='none'`, borc hatirlatma ve push kuyrugu bos,
sozlesme hatirlatma zamanlayicisi icin onceden "gonderildi" satirlari yazilir (yoneticiye sahte sozlesme e-postasi gitmesin). Yerel testte tum kuyruk tablolarinin bos oldugu dogrulanir.

## Bilinen sinirlar ve riskler

* Sayac tablosu daire zorunlu kildigindan "ortak elektrik sayaci" modellenemedi; yalniz su ve kalorimetre var. Isi (kalorimetre) okumalari faturalanmaz.
* Zaman damgalari: servislerin yazdigi `created_at`/`audit_log` ve makbuz `issued_at` degerleri **gercek calisma zamani**dir (append-only tablolar guncellenemez); is tarihleri (`entry_date`, `period`, `paid_on`) gecmise yayilir.
* Dekont bildirimi ve banka satirlari dogrudan SQL ile yazilir (servis dosya/PDF ayristirma ister); `file_required=false`, dosya yok.
* Belge deposu: dosyalar `DOCUMENTS_DIR`'e (ya da `~/kapi-documents`) tohumu calistiran OS kullanicisi olarak yazilir; PM2 kullanicisi ayniysa uygulama okur, degilse izinleri ayarlayin.
* `--force` mevcut gercek sakin/finans kaydi olan sitede kullanilirsa daire basina "tam 1 amir" kurali bozulabilir. Onerilmez.
* Aidat 'm2' dagitimiyla (brut alan) yazilir; yillik zam yeni yillik tanimla yapilir. Gecikme tazminati ve borc hatirlatma KAPALI birakilir (hukuk onayi bayragi).
* Yerel testte cleanup, `session_replication_role` nedeniyle FK eylemlerini calistirmaz: her satir acikca kayitli oldugundan sorun olmaz; baska bir surecin tohumlanan satirlara sonradan bagladigi kayitlar cleanup'ta yetim kalabilir.

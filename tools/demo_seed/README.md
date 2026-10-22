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
| `cleanup.mjs` | `--list`, `--batch <id> --yes`: kayitli satirlari siler (SUPERUSER gerekir), diskteki belge dosyalarini siler, degistirilen satirlari eski haline getirir; yeniden yapilandirma batch'i varken tohum batch'ini reddeder (`--force`) |
| `make_pdf.py` | `--creds creds.json --out hesaplar.pdf` : A4 PDF (yonetim kadrosu + gorevliler + daire daire sakinler; yeniden yapilandirilmis JSON'da Malik / Daire admini (sari satir) / aile uyeleri). `pip install reportlab` |
| `run_remote.sh` | Sunucuda: pg_dump yedegi -> yedekten gecici DB -> tohum + cleanup provasi -> `--prod` ile canli |
| `restructure_families.mjs` | Tohumlanmis sitenin dairelerini YENI DAIRE YONETIMI modeline gore duzenler (asagidaki bolum): `--prev-creds`, `--creds-out`, `--dry-run`, `--seed`, `--force`, `--ensure-composition` (her haneye en az 1 cocuk + 1 yasli ekler) |
| `run_remote_restructure.sh` | Sunucuda: yedek -> gecici DB provasi (yeniden yapilandirma + cleanup, icerik ozeti karsilastirmasi) -> `--prod` ile canli; `--force`, `--extra "<bayraklar>"` / `EXTRA_ARGS` ile `restructure_families.mjs`'e ek bayrak iletir |
| `test/local_restructure_test.mjs` | Yeniden yapilandirma icin yerel uctan uca test (seed + 2 bozulma + dry-run + uygulama + dogrulamalar + PDF + iki cleanup) |
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

## Aile yeniden yapilandirma (`restructure_families.mjs`)

Tohumlanmis demo sitesini uygulamanin YENI daire yonetimi modeline (migration 074, `docs/PLATFORM_DAIRE_YONETIMI.md` ve `PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md`) uydurur. Uygulama kodu (`lib/`, `server/src`) DEGISMEZ; kapi komutlari, MQTT, BLE, firmware ve kapi servislerine dokunulmaz.

**Kararlar (her dairede):**

* **Tek daire admini = dairede oturan kisi**: kiraci oturuyorsa kiraci, malik oturuyorsa malik (`apartment_memberships.role = 'APARTMENT_ADMIN'`; admin baska kisideyse `membership_service.applyApartmentPrimaryAdmin` ile tasinir, `apartments.resident_user_code` gostergesi dahil).
* **Aile**: ayni dairedeki es / cocuk / yasli ebeveyn `family_member` olarak yeniden baglanir (`sponsor_person_id` = admin, `is_minor` = yas < 18). Rol ve yas, tohumun ad havuzlarindan (yetiskin / cocuk / yasli) cikarilir; ayni soyad korunur. Yaslar tutarli atanir (cocuk 3-17 = reşit degil, 18-26 genc yetiskin; yasli ebeveyn >= 62). Aile boyutu (oturanlar) 3-5; en az 3 dairede yasli ebeveyn (`--min-elder-houses`); reşit olmayan cocugu olmayan hanelere cogunlukla, boyutu <=4 olanlara %30 olasilikla (`--extra-child-chance`) 3-15 yas cocuk eklenir. 13+ yas ve yetiskin yeni uyelerin hesabi vardir (12 karakter rastgele sifre, bcrypt, `@demo.invalid`).
* **Malik**: her dairede tek guncel malik. Kiraci oturan dairede mevcut dis malik korunur; malik kaydi YOKSA ayri bir malik kisisi + hesabi eklenir (oturmaz, `RESIDENT` site uyeligi var, daire uyeligi = kapi yetkisi YOK). Malik oturan dairede malik = admin.
* **Kiraci oturuyorsa yonetim kiraciya devredilmis**: `apartment_admin_delegations` (`source='tenant_delegated'`, `state='active'`, `note` "Demo: ..."; acik kayit zaten varsa dokunulmaz).
* **Silinmez / kesilmez**: mevcut kisi ve hesaplar, sifreleri ve yetiskin uyelerin kapi erisimi (uyelikler) AYNEN kalir; yalniz yeniden siniflandirilir, eksikler eklenir. E-posta / davet / bildirim / talep satiri yazilmaz.

```bash
# Sunucuda (yedek + prova + canli); eski hesaplarin parolalari creds_prod.json'dan gelir
scp -r tools/demo_seed <kullanici>@<sunucu>:~/demo_seed
scp G:\site\demo_hesaplar\creds_prod.json <kullanici>@<sunucu>:~/demo_seed/out/creds_prod.json
ssh <sunucu> 'bash ~/demo_seed/run_remote_restructure.sh --prev-creds ~/demo_seed/out/creds_prod.json'            # yalniz yedek + prova
ssh <sunucu> 'bash ~/demo_seed/run_remote_restructure.sh --prev-creds ~/demo_seed/out/creds_prod.json --prod --skip-rehearsal --creds-out ~/demo_seed/out/creds_restructured.json'
scp <sunucu>:~/demo_seed/out/creds_restructured.json out/ && python make_pdf.py --creds out/creds_restructured.json --out out/demo_hesaplar.pdf
ssh <sunucu> 'shred -u ~/demo_seed/out/creds_restructured.json ~/demo_seed/out/creds_prod.json'

# Elle: once --dry-run (plani yazdirir, hicbir sey yazmaz)
DATABASE_URL=postgres://... node restructure_families.mjs --site Cenk --prev-creds out/creds_prod.json --dry-run
DATABASE_URL=postgres://... node restructure_families.mjs --site Cenk --prev-creds out/creds_prod.json --creds-out out/creds_restructured.json

# Geri alma (SEED batch'inden ONCE): eklenenleri siler, degisenleri eski haline getirir
DATABASE_URL=postgres://... node cleanup.mjs --list
DATABASE_URL=postgres://... node cleanup.mjs --batch demo-restructure-YYYYMMDDHHMMSS --yes
```

* **Korumalar**: sitede demo tohum kaydi yoksa, daha once yeniden yapilandirma batch'i varsa (cleanup yapilmadan tekrar calismaz), demo tohum disi kisi varsa, oturan ana kisinin hesabi / aktif daire uyeligi yoksa ya da `--prev-creds` dosyasinda sifresi olmayan eski hesap varsa HICBIR sey yazilmadan durur (cikis 4 / 6; `--force` ve `--allow-missing-passwords` ile asilir). Tum degisiklik TEK transaction'dadir: hata olursa tamami geri alinir.
* **Geri alma kaydi**: yeni satirlar `demo_seed_registry`'ye `insert`, degisen mevcut satirlar (`apartment_residencies`, `apartment_memberships`, `apartments`) `update` + `before_image` ile yazilir (batch `demo-restructure-<zaman>`). `cleanup.mjs` ayni batch'i geri alinca kisi / bag tablolari yeniden yapilandirma ONCESI haline AYNEN doner. Yeniden yapilandirma batch'i geri alinmadan tohum batch'i geri alinmaya calisilirsa `cleanup.mjs` durur (cikis 5; `--force` ile asilir) - sira: ONCE `demo-restructure-...`, SONRA `demo-...`.
* **Cikti**: `--creds-out` JSON'u (sifreler duz metin: commit etmeyin) tum daire hesaplarini `familyRole` (`landlord` / `head` / `spouse` / `child` / `elder`), `apartmentRole`, `isAmir`, `age`, `isMinor`, `hasAccount`, `isNew` ve kullanici adi / sifreyle icerir; ayrica `households` (daire basina malik / admin / devir) ve `roleChanges` (mevcut hesaplarin onceki / yeni rolu). Rapor: `out/restructure-report-<batch>.json` (sifresiz). `make_pdf.py` bu dosyadan her dairede Malik, Daire admini (sari satir), aile uyeleri ve kullanici adi / sifre tablolarini uretir.
* **Test**: `node tools/demo_seed/test/local_restructure_test.mjs --port <gecici PG>` (seed + admin kaymasi + malik yok bozulmasi + dry-run + uygulama + dogrulamalar + PDF + iki cleanup).
* **Bilinen sinirlar**: yaslar veritabaninda tutulmaz (yalniz `is_minor` ve kimlik JSON'unda `age`); denetim kaydi (`audit_log`) yazilmaz; hesapsiz kucuk cocuklarin e-postasi / telefonu yoktur (12 yas alti).

### Her ailede cocuk ve yasli (`--ensure-composition`)

Ilk yeniden yapilandirma turu aile boyutunu 3-5 ile sinirladigindan bazi haneler cocuksuz ya da yaslisiz kalabilir. `--ensure-composition` ikinci turdur: **HER hane (daire)** en az 1 cocuk (`is_minor = true`, 2-17 yas) ve en az 1 yasli (62-84 yas, hesapli yetiskin ebeveyn / buyukanne-buyukbaba) icerir; eksik haneye yeni `family_member` EKLER. Hane boyutu ust siniri bu modda **7**'dir (uygulamanin aile limiti 12'nin cok altinda).

* **Ne yapar / yapmaz**: mevcut kisi, hesap, sifre, daire uyeligi (kapi yetkisi), admin, malik ve devir kayitlari DEGISMEZ, hicbir sey silinmez; mevcut uyelerin sinifi planin zaten kullandigi sekilde cikarilir (es / cocuk / yasli; cocuk = DB'de `is_minor`, yasli = yasli ad havuzu ya da onceki kimlik dosyasinda yas >= 60). Zaten cocugu ve yaslisi olan haneye TEKRAR eklenmez (idempotent: ikinci calistirmada "eklenecek uye yok", yeni batch acilmaz). Bir hane boyutu 7'yi asacaksa HICBIR sey yazilmadan durur (cikis 6).
* **Yeni uyeler**: ayni soyad, ad cesitli (yasli kadin / erkek); yasli 62-84, cocuk 2-17 (ana kisiden en az ~20 yas kucuk). Yasli ve 13+ cocuk HESAPLI (12 karakter rastgele sifre, bcrypt, kullanici adi `ad.soyad`, cakisinca sayi eki, `@demo.invalid`, hesapli uyeye `FAMILY_MEMBER` daire uyeligi - ilk turdaki yeni uyelerle ayni); 13 alti cocuk hesapsiz. Telefon yapay (`0 500 000 xx xx`). `sponsor_person_id` = daire admini. E-posta / davet / bildirim / talep satiri YAZILMAZ.
* **Onkosul**: sitede onceki bir `demo-restructure-...` batch'i olmali (yoksa durur, cikis 4) ve `--prev-creds` = o turun `--creds-out` dosyasi (mevcut hesaplarin sifreleri ve yaslari oradan gelir). Onceki restructure batch'i kayitli oldugundan **`--force` ZORUNLUDUR** (`--force` olmadan arac yazmadan durur, cikis 4; ayrica `--ensure-composition`'siz varsayilan mod batch varken ayni sekilde durur). Bu modda `--force` yalniz EKLER, baska korumayi gevsetmez.
* **Geri alma**: yeni satirlar yeni bir `demo-restructure-<zaman>` batch'ine (yalniz `insert`) yazilir; `cleanup.mjs --batch <o batch> --yes` yalniz onlari siler. Sira: ONCE bu (ikinci) batch, SONRA ilk restructure batch'i, SONRA tohum batch'i.
* **Cikti**: `--creds-out` JSON'u `--prev-creds`'teki tum hesaplari (gorevli / kurul / daire) AYNEN korur, yeni hesaplar `isNew: true`, `familyRole` `child` / `elder` ve `age` ile eklenir; `make_pdf.py` her dairenin tablosuna **Yas** sutunu ve rol etiketini (`Çocuk (9 yaş) - hesapsız`, `Yaşlı ebeveyn (74 yaş)`) yazar, hane basliginda reşit olmayan cocuk / yasli sayisini gosterir.

```bash
# Elle: once --dry-run (plani + hangi hanede ne eksik oldugunu yazdirir, hicbir sey yazmaz)
DATABASE_URL=postgres://... node restructure_families.mjs --site Cenk --ensure-composition --force --prev-creds out/creds_restructured.json --dry-run
DATABASE_URL=postgres://... node restructure_families.mjs --site Cenk --ensure-composition --force --prev-creds out/creds_restructured.json --creds-out out/creds_composition.json

# Sunucuda (yedek + gecici DB provasi + cleanup provasi + canli); ilk turun creds_restructured.json'u sunucuya geri kopyalanir
scp out/creds_restructured.json <kullanici>@<sunucu>:~/demo_seed/out/creds_restructured.json
ssh <sunucu> 'bash ~/demo_seed/run_remote_restructure.sh --prev-creds ~/demo_seed/out/creds_restructured.json --force --extra "--ensure-composition"'          # yalniz yedek + prova
ssh <sunucu> 'bash ~/demo_seed/run_remote_restructure.sh --prev-creds ~/demo_seed/out/creds_restructured.json --force --extra "--ensure-composition" --prod --skip-rehearsal --creds-out ~/demo_seed/out/creds_composition.json'
scp <sunucu>:~/demo_seed/out/creds_composition.json out/ && python make_pdf.py --creds out/creds_composition.json --out out/demo_hesaplar.pdf
ssh <sunucu> 'shred -u ~/demo_seed/out/creds_composition.json ~/demo_seed/out/creds_restructured.json'
```

Test: `node tools/demo_seed/test/local_restructure_test.mjs --port <gecici PG>` bu modu da kapsar (fixture + tohum + varsayilan restructure + `--ensure-composition --force`: her dairede cocuk + yasli, hane <= 7, tek admin / tek malik, mevcut satirlar degismedi, ikinci calistirma eklemez, e-posta kuyrugu 0, PDF, cleanup).

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

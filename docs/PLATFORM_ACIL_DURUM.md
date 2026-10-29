# Acil durum akisi (P2-24, karar K13) - cekirdek ozellik (modul DEGIL: her sitede ve her kullanicida acik, kapatilamaz)

Sakin, kurul uyesi, gorevli, yonetici ve bireysel kullanici "Acil durum" ekranindan: buyuk **112** dugmesi, **Yangin** ve **Asansor arizasi** icin AYRI hizli dugmeler; her senaryoda dogru numara, cagri merkezinin sorabilecekleri ve aramada soylenecek **site adresi**. Karar K13: acil numara 112; arama kanali yoksa **kuru mod**; yangin / asansor ayri hizli dugme.

Bu belge AKIS sayfasini anlatir. Kisi kartindaki / ana menudeki dokun-ara dugmeleri (P2-23, Dalga D) ayri is ve bu dalga onlara dokunmaz.

## Durustluk kurali (kuru mod)
- `tel:` adresini acmak telefon uygulamasini numara hazir olarak acar; **aramayi kullanici orada baslatir**. Bu yuzden hicbir yerde "arandi / araniyor / arama yapildi" denmez; basari mesaji yalnizca "Telefon uygulamasi acildi. Aramayi orada baslatin." der. Testler (`test/emergency_models_test.dart`, `test/screens/emergency_view_test.dart`) tum metinlerde bu soz dizilerinin olmadigini denetler.
- **Kanal yoksa** (masaustu, web, telefonsuz tablet, simulator: `TelCallChannel.mayBeAvailable` / `probe()`) ya da **arama baslatilamazsa** (`unavailable` / `failed`) ekran KURU MODA gecer: uyari seridi, 112 icin arama dugmesi yerine buyuk numara + "Numarayi kopyala"; senaryo kartlarinda da numara metin olarak ve kopyalanabilir; adres ve sorular zaten metindir; "Bilgileri kopyala" numara + soylenecekler + adres + sorulari tek metin yapar. Masaustu ve web'de kanal YOK sayilir (aramanin baslayip baslamadigi bilinemez).
- Kanal bu platformda olabiliyorsa (Android / iOS) seritte "Tekrar Dene" yoklamayi yeniler.
- 112 ve senaryo icerigi **sabittir**; ag olmadan da calisir. Yalnizca site adresi ve bakim firmasi sunucudan gelir: alinamazsa hata + "Tekrar Dene" gosterilir, **112 etkilenmez**. Yenileme basarisizsa son bilinen bilgi korunur ve bu soylenir.

## Senaryolar (`lib/models/emergency_models.dart`)
| Dugme | Numara(lar) | Aramada ilk soylenen | Yonlendirme |
| --- | --- | --- | --- |
| 112 (buyuk dugme, genel) | 112 | "Acil bir durum var." | Cagri bitene kadar hatta kalin |
| Yangin | 112 | "Yangin var." | Binayi terk edin, asansor kullanmayin, geri donmeyin; guvenli yerden 112 |
| Asansor arizasi | Site asansor bakim firmasi (varsa) + 112 | "Asansor arizasi var." | Mahsur kalan: sakin kalin, kapiyi zorlamayin, alarm / interkom; tehlike varsa 112 |

Her senaryo: "Aramada soyleyin" blogu (ilk cumle + site adi + adres, secilip kopyalanabilir; adres kayitli degilse dururca soyler, uydurmaz) ve cagri merkezinin (asansorde bakim firmasinin) sorabilecekleri (5 madde: ne oldu / nerede, adres, blok-kat-daire, kac kisi, ad ve telefon).

## Asansor bakim firmasi (site ayari)
- Tablo `site_emergency_info(site_code PK, elevator_firm_name, elevator_firm_phone, created_at, updated_at)` (migration **107**, `server/src/modules/emergency_schema.js` ile ayni DDL, idempotent; site silinince CASCADE; kullanici FK'si YOK, kim degistirdi denetim kaydinda).
- Tanimliysa Asansor arizasi ekraninda firma karti: ad + telefon + "Bakim firmasini ara" + "Numarayi kopyala". 112 ayri kart ("Mahsur kalan kisi tehlikedeyse").
- Tanimli degilse: **yoneticiye** "Bakim firmasinin telefonu kayitli degil. Ekleyin ..." ipucu ve "Bakim firmasini ekle"; **digerlerine** (sakin, kurul, gorevli, sakin modundaki yonetici) "henuz eklenmemis, site yonetiminden isteyin; mahsur kalan tehlikedeyse 112" ipucu (duzenleme dugmesi yok).
- Yonetici ayni ekrandan ekler / duzenler / kaldirir (`emergency_firm_dialog.dart`): telefon kisa numara (444 1 234), sabit hat veya cep olabilir; ad yazilip telefon bos birakilirsa kaydedilmez (telefonsuz firma acil durumda isse yaramaz); ikisi de bos = kayit silinir.

## Uclar (`server/src/modules/emergency_routes.js`; modul kapisi YOK)
- `GET /app/emergency` -> `{ sites: [{ site_code, site_name, address, city, district, elevator_firm_name, elevator_firm_phone, can_edit }] }`. Kapsam sunucuda `module_service.MY_SITES_SQL` ile hesaplanir (istemcinin "benim sitelerim" listesiyle AYNI: yonetici, kurul, gorevli, sakin); istemciden site kodu alinmaz. **Baska sitenin adresi / firmasi asla donmez.** `can_edit` yalniz o sitenin yoneticisi icin true. Super kullanici ve sitesiz kullanici: bos liste. `Cache-Control: no-store`.
- `PUT /manager/sites/:siteCode/emergency` `{ elevator_firm_name, elevator_firm_phone }` -> iki alan YERINE yazilir (gonderilmeyen alan temizlenir; ikisi de hic gonderilmezse 400 `INVALID_BODY`, bos govdeyle kazara silme olmaz). Yetki: yonetici / super (kurul, gorevli, sakin 403 `FORBIDDEN_ROLE`; baska site 403 `FORBIDDEN_SITE`); sira: yetki -> site -> govde. Telefon: rakam, bosluk ve `+ ( ) - .`, 3-15 hane; ad en cok 120 karakter, gorunmez karakterler atilir. Denetim kaydi `emergency.info_updated` (`details`: `set` / `cleared`; telefon numarasi yazilmaz).
- Hiz sinirlari: okuma 600/saat, yazma 60/saat (kullanici basina).

## Uygulama
- Menu: `SirketMenuItem.acilDurum` ("Acil durum"), grup **Ana sayfa** (Panel'in yaninda), Panel vitrininde kart. Gorunurluk: super kullanici disinda herkes; **modul verisi gelmese de gorunur** (acil durumda menu ag ya da modul durumuna bagli olmaz). Cekmecedeki site secimi (`preferredSiteCode`) ekrana tasinir; cok siteli kullanicida ekranin kendi "Hangi site icin?" secicisi vardir.
- Duzenleme yalniz yonetici modundaki site yoneticisinde (`allowEdit`) ve sitenin `can_edit` degeri true iken.
- Dosyalar: `lib/ui/views/emergency_view.dart` (ekran), `lib/ui/widgets/emergency_parts.dart` (parcalar), `lib/ui/dialogs/emergency_firm_dialog.dart`, `lib/services/emergency_api.dart` (uclar), `lib/services/emergency_dialer.dart` (arama kanali; testte sahtesi), `lib/models/emergency_models.dart` (model + icerik + kopyalanabilir metin).
- Yeniden kullanim: Dalga D'nin dokun-ara dugmeleri `EmergencyCallChannel` / `TelCallChannel`'i ve `kEmergencyNumber`'i kullanabilir (ayni durust sonuc: acildi / kullanilamiyor / basarisiz).

## Testler
`server/test/emergency.test.js` (sema <-> migration, girdi kurallari, kapsam, yetki, denetim, hata sizdirmama), `test/emergency_models_test.dart`, `test/emergency_dialer_test.dart`, `test/emergency_api_test.dart`, `test/screens/emergency_view_test.dart` (kuru mod, dogru site, firma ipucu / duzenleme, ag hatasi, tasma matrisi), `test/screens/emergency_home_page_test.dart` (menu gorunurlugu ve yetki).

## Sinirlar / sonraki adimlar
- Aramanin gercekten baslayip baslamadigi platformdan ogrenilemez; bu yuzden "arandi" durumu yoktur (bilincli).
- Son bilinen adres / firma bilgisi cihaza yazilmaz (yalniz bellekte); cevrimdisi acilista adresi sunucudan alamazsa kullanici adresi kendisi soyler. Kalici onbellek istenirse hesap silme / cikis temizligine baglanmalidir.
- Sonraki adim: Sozlesmeler modulunde (varsayilan kapali) `asansor` kategorili bir firma kayitliysa ekran bunu "bakim firmasi olarak ekle" diye onerebilir; bugun yalnizca bu ekrandaki ayar gecerlidir.

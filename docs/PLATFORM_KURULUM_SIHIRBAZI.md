# Site Kurulum Sihirbazı ve «Excel'den yükle» Kısayolları (P2-15 + P2-16)

Karşılaştırma güçlendirme programı, Dalga E (`docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md`). **Yalnız istemci**: sunucu uçlarına, migration'a ya da sunucu gövdelerine dokunulmadı; eski istemci etkilenmez.

## Ne yapar

Yeni kurulan (ya da başvurusu onaylanan) sitenin yöneticisini altı adımda kurulumdan geçirir. Sihirbaz **mevcut ekranları yeniden yazmaz**: her adım var olan formu / ekranı aynen açar ve dönünce durumu sunucudan yeniden okur.

| # | Adım | Durum nereden gelir | Eylemler (hepsi MEVCUT akış) |
|---|---|---|---|
| 1 | Site bilgileri | site var ve adı dolu | süper kullanıcı: «Site bilgilerini düzenle» (`SiteDialog` + `updateSite`) |
| 2 | Bloklar (Katlar ...) | sitede en az 1 blok | süper kullanıcı: blok ve daire sayılarını düzenle (aynı form) |
| 3 | Daireler (Ofisler ...) | sitede en az 1 daire | «Excel'den yükle» (`BulkImportView`, «Hepsi bir arada»), «Daireler listesini aç» (Kişiler ekranı, Daireler sekmesi) |
| 4 | Kişiler | en az 1 aktif kişi (`listPeople`) | «Excel'den yükle» (aynı sihirbaz), «Kişileri tek tek ekle» (Kişiler ekranı) |
| 5 | Modüller | yalnız onay ister (temel modüller zaten açık) | «Modülleri seç / talep et» (`ModulesView`; süper kullanıcıda doğrudan açma) |
| 6 | Finans açılışı | en az 1 aktif aidat / ek borç tanımı | «Aidat tanımı ekle» (`FinanceDefinitionFormDialog`), «Devir bakiyesi yükle» (`FinanceOpeningDialog`), «Finans ekranını aç» (`FinanceView`, Tanımlar sekmesi) |

Metinler sitenin yönetim türü terimleriyle yazılır (`ManagementTerms`: Blok -> Kat, Daire -> Ofis, Aidat -> Ortak gider).

**Site yöneticisi 1-3. adımlarda düzenleme göremez**: `PATCH /manager/sites/:id` yalnız süper kullanıcıya açıktır (403 «Site kaydini yalnizca super user guncelleyebilir.»); bu adımlar yönetici için salt gösterimdir ve nedenini açıklayan not taşır. Sihirbaz bu sunucu kuralını gevşetmez; site oluşturma da sihirbazda DEĞİLDİR (AGENTS.md kural 14: yönetici site kurmak için başvurur, süper kullanıcı onaylar; sihirbaz site ZATEN VAR iken başlar).

## Adım geçişi

- «Devam» yalnız **tamamlanmış** adımda etkindir; **durumu okunamayan** adımda (hata) ve yalnız onay isteyen **Modüller** adımında da etkindir (kullanıcı kilitlenmez).
- «Atla» yalnız tamamlanmamış adımda vardır; atlanan adım özette «Atlandı» kalır, sonradan tamamlanınca atlananlardan çıkar.
- «Geri» önceki adıma döner; son adımdan sonra **özet** açılır (altı adımın durumu, tamamlanmayana dönüş, «Kurulumu bitir»).
- Hata dürüsttür: bir parça yüklenemediyse o adım «Durum alınamadı» + «Tekrar Dene» olur; sayı uydurulmaz, adım kendiliğinden tamam sayılmaz.

## Yarım kalan kurulum devam eder

İlerleme cihazda `SharedPreferences`ta saklanır (`SiteSetupProgressStore`, anahtar `site_setup_wizard_v1_<kullanıcı>`; kullanıcı başına, içinde site başına bir kayıt, en çok 20 site). İçerik: kalınan adım, tamamlanan / atlanan adımlar, `started` / `finished` / `dismissed`. Kişisel veri yok (site adı ve adım adları); hesap silinince `LocalDataWiper` zaten tüm anahtarları siler. Depolama yazılamazsa sihirbaz yine çalışır, yalnız hatırlanmaz.

- Kapatılıp yeniden açılınca **kalınan adımdan** sürer. Sihirbaz bir site için hiç açılmadıysa (kayıt site kurulunca / başvuru onaylanınca açıldıysa) sıradaki yapılacak adımdan başlar.
- Sunucu verisinden **gözlenen** tamamlanma ilerlemeye işlenir (başka cihazda eklenen kişi sayılır) ve **geri alınmaz**.
- Bitirilmiş ya da her adımı tamam olan kurulum yeniden açılınca özet gösterilir.

## Girişler

- **Panel** (yönetici / süper kullanıcı görünümü): cihazda kaydı olan ve bitmemiş / kapatılmamış kurulum için «Site kurulumunuz yarım kaldı» kartı (`SiteSetupResumeCard`; ağ isteği yapmaz, «3 / 6 adım tamam» kayıttan okunur). Kayıt yoksa HİÇBİR ŞEY çizilmez: kartın kimseye «site kur» diye davet etmesi AGENTS.md kural 16'ya aykırıdır. «Şimdilik gizle» kapatır.
- **Site Yönetimi**: seçili onaylı sitenin özet kartında «Kurulum Sihirbazı» düğmesi (`sites_setup_wizard`).
- **Başvuru onayı** (P2-16): onaylanan başvurudan sonraki ilk girişte hatırlatma kaydı açılır (Panel kartı «Site kurulumunu tamamlayın») ve «Site başvurunuz onaylandı» iletisi «Kuruluma başla» eylemi taşır.
- Sihirbazda kayıt değiştiyse (`SiteSetupOutcome.changed`) ana sayfa site listelerini ve modül erişimini yeniden okur (AGENTS.md kural 7).

## «Excel'den yükle» kısayolları (P2-16)

Kişiler ekranındaki listelerde, üstteki «Toplu Yükle» eyleminden bağımsız, listeye özel kısayol düğmesi (yalnız yazma yetkisi olanda; kurul üyesi göremez). Mevcut `BulkImportView`ı listeye uygun tür önseçili açar:

| Liste | Anahtar | Önseçili tür |
|---|---|---|
| Kişiler | `persons_list_excel_import` | Hepsi bir arada |
| Daireler | `apartments_list_excel_import` | Hepsi bir arada |
| Araçlar | `vehicles_list_excel_import` | Araçlar |

Boş ve süzgeçsiz Kişiler listesinde aynı eylem boş durum kartının içindedir (`people_empty_bulk_import`, yönlendirici metinle); iki aynı düğme yan yana durmasın diye o durumda üstteki gizlenir. Sihirbazın Kişiler ve Daireler adımları da aynı sihirbazı açar.

## Kod haritası

`lib/models/site_setup_progress.dart` (adımlar + ilerleme), `lib/services/site_setup_progress_store.dart` (saklama), `lib/ui/views/site_setup_controller.dart` (durum makinesi + sunucu özeti), `lib/ui/views/site_setup_wizard_view.dart` (sayfa), `lib/ui/widgets/site_setup_parts.dart` / `site_setup_steps.dart` (adım göstergesi + adım gövdeleri), `lib/ui/helpers/site_setup_actions.dart` + `setup_screen_route.dart` (mevcut ekranları açan eylemler), `lib/ui/widgets/site_setup_resume_card.dart` (Panel kartı), `lib/ui/widgets/bulk_entry_buttons.dart` (`BulkListImportButton`). Mevcut ekranlara yalnız EKLEMELİ seçenekler girdi: `PeopleView.initialSiteCode / initialTab`, `ModulesView.initialSiteCode`, `PeopleApartmentsTab / PeopleVehiclesTab.onImportRequested`, `SitesView.onOpenSetupWizard`.

Testler: `test/site_setup_progress_test.dart`, `test/screens/site_setup_controller_test.dart`, `site_setup_wizard_test.dart`, `site_setup_home_page_test.dart`, `bulk_list_shortcut_test.dart`.

## Yakında…

İlerlemenin sunucuda saklanması (cihazlar arası «kaldığı yer»; bugün cihaz içi, tamamlanma ise sunucu verisinden zaten gözlenir), süper kullanıcı anlık site kurulumundan (`SetupSiteOutcome.created`) sonra sihirbaza yönlendirme (kurulan sitenin kodu formdan dönmüyor).

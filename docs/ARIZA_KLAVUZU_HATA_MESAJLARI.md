# Hata mesajı → kaynak (otomatik)

> Kullanıcıya/istemciye görünen metinleri üretildikleri `dosya:satır` ile eşler. `Ctrl+F` ile ekranda gördüğünüz mesajın bir parçasını arayın. Koddan otomatik üretilir: `node tools/klavuz/build.mjs`. Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).

## Sunucu mesajları (576)

Kaynak: `server/src` (`error:`, `message:`, `httpError(...)`, `new Error(...)`). Uygulama bu metinleri HTTP yanıt gövdesinde (`error` alanı) alır.

| Mesaj | Dosya:satır |
| --- | --- |
| "${bName}" blok adı birden fazla kez kullanılmış. Blok adları benzersiz olmalıdır. | [server/src/services/membership_rules.js:473](../server/src/services/membership_rules.js#L473) |
| "${site.name}" sitesi, ${createdBlocks.length} blok ve ${totalApartmentCount} daire ile başarıyla kuruldu! | [server/src/services/membership_service.js:930](../server/src/services/membership_service.js#L930) |
| "${siteName}" sitesi ${apt.block_name \|\| ''} ${apt.unit_label} için katılım başvurunuz başarıyla oluşturuldu. Site yöneticisinin onayı bekleniyor. | [server/src/services/membership_service.js:1120](../server/src/services/membership_service.js#L1120) |
| ${deviceUid} kodlu cihaz ve karekodu basariyla silindi. | [server/src/routes/company_routes.js:430](../server/src/routes/company_routes.js#L430) |
| ${field.body} alani true/false olmalidir. | [server/src/utils/site_rules.js:306](../server/src/utils/site_rules.js#L306) |
| ${fieldName} alanı true/false olmalıdır. | [server/src/services/membership_service.js:1780](../server/src/services/membership_service.js#L1780) |
| ${label} ${min} ile ${max} arasında bir tamsayı olmalıdır. | [server/src/services/membership_rules.js:427](../server/src/services/membership_rules.js#L427) |
| ${name} env degiskeni eksik. | [server/src/mailer.js:6](../server/src/mailer.js#L6) |
| ${pass.door_name} aciliyor. | [server/src/routes/guest_passes_routes.js:440](../server/src/routes/guest_passes_routes.js#L440) |
| ${req.full_name} sakini, "${req.block_name \|\| ''} ${req.unit_label}" dairesine ${assignedRole === 'APARTMENT_ADMIN' ? 'Daire Yöneticisi' : 'Aile Üyesi'} olarak başarıyla onaylandı. | [server/src/services/membership_service.js:1381](../server/src/services/membership_service.js#L1381) |
| ${result.revoked_count} aktif karekod basariyla iptal edildi. | [server/src/routes/manager_routes.js:1059](../server/src/routes/manager_routes.js#L1059) |
| ${targetUserCodes.length} sakin için kapı yetkisi ${actionText}. | [server/src/services/membership_service.js:2563](../server/src/services/membership_service.js#L2563) |
| Abonelik talebiniz onay bekliyor. | [server/src/middlewares/auth_middleware.js:85](../server/src/middlewares/auth_middleware.js#L85) |
| Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:742](../server/src/routes/auth_routes.js#L742) |
| Abonelik talebiniz reddedildi. | [server/src/middlewares/auth_middleware.js:88](../server/src/middlewares/auth_middleware.js#L88) |
| Abonelik talebiniz reddedildi. | [server/src/routes/auth_routes.js:745](../server/src/routes/auth_routes.js#L745) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:594](../server/src/routes/admin_routes.js#L594) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:747](../server/src/routes/admin_routes.js#L747) |
| Ad ve soyad alanları zorunludur. | [server/src/services/membership_service.js:226](../server/src/services/membership_service.js#L226) |
| Ad ve soyad en fazla ${NAME_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:229](../server/src/services/membership_service.js#L229) |
| Aile Reisi (Daire Yöneticisi) başarıyla değiştirildi. | [server/src/services/membership_service.js:2151](../server/src/services/membership_service.js#L2151) |
| Aktif bir doğrulama kodu bulunamadı. Lütfen yeni kod talep ediniz. | [server/src/services/membership_rules.js:67](../server/src/services/membership_rules.js#L67) |
| Bekleyen abonelik talebi bulunamadi. | [server/src/routes/admin_routes.js:627](../server/src/routes/admin_routes.js#L627) |
| Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz. | [server/src/services/membership_service.js:392](../server/src/services/membership_service.js#L392) |
| Bekleyen site talebi bulunamadi. | [server/src/routes/admin_routes.js:753](../server/src/routes/admin_routes.js#L753) |
| Belirtilen cihaz hesabınıza ait değil. | [server/src/services/membership_service.js:769](../server/src/services/membership_service.js#L769) |
| Bos olmayan bloklar varken blok sayisi azaltilamaz. | [server/src/services/site_service.js:1156](../server/src/services/site_service.js#L1156) |
| Boylam -180 ile 180 arasinda olmalidir. | [server/src/utils/site_rules.js:331](../server/src/utils/site_rules.js#L331) |
| Bu cihaz arizali olarak isaretlenmis. | [server/src/utils/site_rules.js:482](../server/src/utils/site_rules.js#L482) |
| Bu cihaz baska bir kullanici hesabi tarafindan sahiplenilmis. | [server/src/utils/site_rules.js:480](../server/src/utils/site_rules.js#L480) |
| Bu cihaz icin log gonderme yetkiniz yok. | [server/src/routes/door_log_routes.js:248](../server/src/routes/door_log_routes.js#L248) |
| Bu cihaz şirket envanterinde arızalı olarak işaretlenmiştir. Lütfen şirket yetkilisiyle iletişime geçiniz. | [server/src/services/membership_service.js:640](../server/src/services/membership_service.js#L640) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/routes/admin_routes.js:1215](../server/src/routes/admin_routes.js#L1215) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/utils/site_rules.js:477](../server/src/utils/site_rules.js#L477) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:612](../server/src/services/membership_service.js#L612) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:635](../server/src/services/membership_service.js#L635) |
| Bu cihazin unique id kayitli. | [server/src/utils/validators.js:396](../server/src/utils/validators.js#L396) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:695](../server/src/routes/manager_routes.js#L695) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:748](../server/src/routes/manager_routes.js#L748) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:778](../server/src/routes/manager_routes.js#L778) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1582](../server/src/services/membership_service.js#L1582) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1622](../server/src/services/membership_service.js#L1622) |
| Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz. | [server/src/services/membership_service.js:377](../server/src/services/membership_service.js#L377) |
| Bu e-posta adresi için çok fazla kod istendi. Lütfen daha sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:116](../server/src/services/membership_rules.js#L116) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:243](../server/src/services/membership_service.js#L243) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:406](../server/src/services/membership_service.js#L406) |
| Bu e-posta baska bir rol icin kayitli. | [server/src/routes/auth_routes.js:575](../server/src/routes/auth_routes.js#L575) |
| Bu e-posta ile onaylanmis bir hesap zaten var. Giris yapin. | [server/src/routes/auth_routes.js:580](../server/src/routes/auth_routes.js#L580) |
| Bu e-posta zaten kayitli. | [server/src/utils/validators.js:353](../server/src/utils/validators.js#L353) |
| Bu gecis linki iptal edilmis. | [server/src/utils/guest_pass_utils.js:122](../server/src/utils/guest_pass_utils.js#L122) |
| Bu gecis linkinin suresi dolmus. | [server/src/utils/guest_pass_utils.js:123](../server/src/utils/guest_pass_utils.js#L123) |
| Bu gecisi olusturan kullanicinin kapiya yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:314](../server/src/routes/guest_passes_routes.js#L314) |
| Bu gecisi olusturan kullanicinin yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:301](../server/src/routes/guest_passes_routes.js#L301) |
| Bu hedef icin OTA yayini yok. | [server/src/routes/firmware_routes.js:165](../server/src/routes/firmware_routes.js#L165) |
| Bu islem icin site yoneticisi yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:131](../server/src/middlewares/auth_middleware.js#L131) |
| Bu islem icin super user yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:102](../server/src/middlewares/auth_middleware.js#L102) |
| Bu işlem için yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1689](../server/src/services/site_service.js#L1689) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1733](../server/src/services/site_service.js#L1733) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1815](../server/src/services/site_service.js#L1815) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen cihaz ekranındaki güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:314](../server/src/routes/app_doors_routes.js#L314) |
| Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır. | [server/src/services/qr_access_service.js:42](../server/src/services/qr_access_service.js#L42) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2187](../server/src/services/membership_service.js#L2187) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2208](../server/src/services/membership_service.js#L2208) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:131](../server/src/routes/app_doors_routes.js#L131) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:172](../server/src/routes/app_doors_routes.js#L172) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:294](../server/src/routes/app_doors_routes.js#L294) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/guest_passes_routes.js:268](../server/src/routes/guest_passes_routes.js#L268) |
| Bu kapiya gecis yetkiniz bulunmuyor. | [server/src/routes/app_doors_routes.js:289](../server/src/routes/app_doors_routes.js#L289) |
| Bu kapiyi silme yetkiniz yok. | [server/src/routes/manager_routes.js:1020](../server/src/routes/manager_routes.js#L1020) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:813](../server/src/routes/manager_routes.js#L813) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:855](../server/src/routes/manager_routes.js#L855) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:898](../server/src/routes/manager_routes.js#L898) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:987](../server/src/routes/manager_routes.js#L987) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1047](../server/src/routes/manager_routes.js#L1047) |
| Bu karekod daha once kullanildi. Lutfen cihaz ekraninda yenilenen guncel karekodu okutun. | [server/src/routes/app_doors_routes.js:331](../server/src/routes/app_doors_routes.js#L331) |
| Bu kullanıcı zaten bu sitenin yöneticisidir. | [server/src/services/site_service.js:2039](../server/src/services/site_service.js#L2039) |
| Bu kullanıcı zaten daire yöneticisidir. | [server/src/services/membership_service.js:2105](../server/src/services/membership_service.js#L2105) |
| Bu kullanıcı zaten dairenin Aile Reisidir (Daire Yöneticisi). | [server/src/services/membership_service.js:2115](../server/src/services/membership_service.js#L2115) |
| Bu kullanici adi zaten kayitli. | [server/src/utils/validators.js:356](../server/src/utils/validators.js#L356) |
| Bu silme doğrulama kodu artık geçerli değil. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:1904](../server/src/services/site_service.js#L1904) |
| Bu silme talebini yalnızca ilgili sitenin yöneticisi onaylayabilir. | [server/src/services/site_service.js:1664](../server/src/services/site_service.js#L1664) |
| Bu silme talebini yalnızca Süper Kullanıcı onaylayabilir. | [server/src/services/site_service.js:1654](../server/src/services/site_service.js#L1654) |
| Bu site için bekleyen bir silme onayı bulunmamaktadır. | [server/src/services/site_service.js:1671](../server/src/services/site_service.js#L1671) |
| Bu site için bekleyen bir silme talebi bulunmuyor. | [server/src/services/site_service.js:1706](../server/src/services/site_service.js#L1706) |
| Bu site için talep edilmiş aktif bir silme doğrulama kodu bulunmuyor. | [server/src/services/site_service.js:1859](../server/src/services/site_service.js#L1859) |
| Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır. | [server/src/services/membership_service.js:1054](../server/src/services/membership_service.js#L1054) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/routes/membership_routes.js:138](../server/src/routes/membership_routes.js#L138) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/services/membership_service.js:1014](../server/src/services/membership_service.js#L1014) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1280](../server/src/routes/manager_routes.js#L1280) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1306](../server/src/routes/manager_routes.js#L1306) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1334](../server/src/routes/manager_routes.js#L1334) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1361](../server/src/routes/manager_routes.js#L1361) |
| Bu sitede karekod ile giris yonetim tarafindan gecici olarak durdurulmustur. | [server/src/services/door_access_policy.js:88](../server/src/services/door_access_policy.js#L88) |
| Bu sitede karekod ile kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:81](../server/src/services/door_access_policy.js#L81) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/routes/guest_passes_routes.js:256](../server/src/routes/guest_passes_routes.js#L256) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/services/door_access_policy.js:98](../server/src/services/door_access_policy.js#L98) |
| Bu sitede misafir/kurye gecis kodu olusturma kapalidir. | [server/src/routes/guest_passes_routes.js:67](../server/src/routes/guest_passes_routes.js#L67) |
| Bu sitede yerel ag uzerinden kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:108](../server/src/services/door_access_policy.js#L108) |
| Bu sitenin cihazlarini gorme yetkiniz yok. | [server/src/routes/manager_routes.js:1079](../server/src/routes/manager_routes.js#L1079) |
| Bu sitenin katılım taleplerini görme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1210](../server/src/services/membership_service.js#L1210) |
| Bu sitenin loglarini gorme yetkiniz yok. | [server/src/routes/door_log_routes.js:136](../server/src/routes/door_log_routes.js#L136) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2594](../server/src/services/membership_service.js#L2594) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2615](../server/src/services/membership_service.js#L2615) |
| Bu siteye kapi ekleme yetkiniz yok. | [server/src/routes/manager_routes.js:941](../server/src/routes/manager_routes.js#L941) |
| Bu siteyi silme yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1517](../server/src/services/site_service.js#L1517) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:226](../server/src/routes/manager_routes.js#L226) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:394](../server/src/routes/manager_routes.js#L394) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:526](../server/src/routes/manager_routes.js#L526) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:548](../server/src/routes/manager_routes.js#L548) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:573](../server/src/routes/manager_routes.js#L573) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1123](../server/src/routes/manager_routes.js#L1123) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:366](../server/src/routes/auth_routes.js#L366) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:384](../server/src/routes/auth_routes.js#L384) |
| Bu şifre sıfırlama bağlantısının süresi dolmuş (30 dakika). Lütfen mobil uygulamadan yeni bir bağlantı talep ediniz. | [server/src/routes/auth_routes.js:393](../server/src/routes/auth_routes.js#L393) |
| Bu talebi onaylama yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1316](../server/src/services/membership_service.js#L1316) |
| Bu talebi reddetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1425](../server/src/services/membership_service.js#L1425) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1322](../server/src/services/membership_service.js#L1322) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1431](../server/src/services/membership_service.js#L1431) |
| Bu tek kullanimlik gecis linki daha once kullanilmis. | [server/src/utils/guest_pass_utils.js:124](../server/src/utils/guest_pass_utils.js#L124) |
| Cihaz (${device.device_uid}) başarıyla şirket envanterine kaydedildi. | [server/src/routes/admin_routes.js:1477](../server/src/routes/admin_routes.js#L1477) |
| Cihaz (${deviceRow.device_uid}) başarıyla hesabınıza bağlandı! Artık bu cihaz ile site ve kapı kurulumu yapabilirsiniz. | [server/src/services/membership_service.js:653](../server/src/services/membership_service.js#L653) |
| Cihaz (${normalizedUid}) zaten şirket veritabanında kayıtlı. | [server/src/services/device_service.js:903](../server/src/services/device_service.js#L903) |
| Cihaz (${updated.device_uid}) sahipliği sıfırlandı ve şirket stokuna geri döndürüldü. | [server/src/routes/admin_routes.js:1542](../server/src/routes/admin_routes.js#L1542) |
| Cihaz atamasi olan kapilar varken kapi sayisi azaltilamaz. | [server/src/services/site_service.js:1138](../server/src/services/site_service.js#L1138) |
| Cihaz basariyla degistirildi. Kapi yetkileri ve ayarlari aynen korundu. | [server/src/routes/manager_routes.js:912](../server/src/routes/manager_routes.js#L912) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:971](../server/src/services/device_service.js#L971) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:1010](../server/src/services/device_service.js#L1010) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1256](../server/src/routes/admin_routes.js#L1256) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1401](../server/src/routes/admin_routes.js#L1401) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1419](../server/src/routes/admin_routes.js#L1419) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1134](../server/src/routes/manager_routes.js#L1134) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1145](../server/src/routes/manager_routes.js#L1145) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1172](../server/src/routes/manager_routes.js#L1172) |
| Cihaz dogrulamasi gecici olarak yapilamadi. | [server/src/routes/firmware_routes.js:127](../server/src/routes/firmware_routes.js#L127) |
| Cihaz donanimi bu firmware hedefiyle uyusmuyor. | [server/src/routes/firmware_routes.js:144](../server/src/routes/firmware_routes.js#L144) |
| Cihaz ekranindaki guncel karekod henuz alinamadi. Birkac saniye sonra tekrar deneyin. | [server/src/routes/app_doors_routes.js:322](../server/src/routes/app_doors_routes.js#L322) |
| Cihaz kaydedildi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1484](../server/src/routes/admin_routes.js#L1484) |
| Cihaz online gorunmuyor. | [server/src/routes/app_doors_routes.js:68](../server/src/routes/app_doors_routes.js#L68) |
| Cihaz QR kodu veya seri numarası boş olamaz. | [server/src/services/membership_rules.js:300](../server/src/services/membership_rules.js#L300) |
| Cihaz QR kodu veya seri numarası çok uzun. | [server/src/services/membership_rules.js:303](../server/src/services/membership_rules.js#L303) |
| Cihaz sahiplenmek için önce e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:547](../server/src/services/membership_service.js#L547) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1426](../server/src/routes/admin_routes.js#L1426) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:1183](../server/src/routes/manager_routes.js#L1183) |
| Cihaz silinemedi. | [server/src/routes/admin_routes.js:1430](../server/src/routes/admin_routes.js#L1430) |
| Cihaz silinemedi. | [server/src/routes/company_routes.js:436](../server/src/routes/company_routes.js#L436) |
| Cihaz silme islemini yalnizca super user yapabilir. | [server/src/routes/manager_routes.js:1161](../server/src/routes/manager_routes.js#L1161) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1212](../server/src/routes/admin_routes.js#L1212) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1275](../server/src/routes/admin_routes.js#L1275) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:607](../server/src/routes/manager_routes.js#L607) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:611](../server/src/routes/manager_routes.js#L611) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:641](../server/src/routes/manager_routes.js#L641) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:646](../server/src/routes/manager_routes.js#L646) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:651](../server/src/routes/manager_routes.js#L651) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/utils/site_rules.js:476](../server/src/utils/site_rules.js#L476) |
| Cihaz sunucuya kaydedilemedi. | [server/src/routes/company_routes.js:368](../server/src/routes/company_routes.js#L368) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/admin_routes.js:1269](../server/src/routes/admin_routes.js#L1269) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:601](../server/src/routes/manager_routes.js#L601) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:635](../server/src/routes/manager_routes.js#L635) |
| Cihaz ve karekod basariyla sunucuya kaydedildi. | [server/src/routes/company_routes.js:363](../server/src/routes/company_routes.js#L363) |
| Cihaz veritabanina kaydedilemedi; islemi tekrar deneyin. | [server/src/routes/company_routes.js:313](../server/src/routes/company_routes.js#L313) |
| Cihaz veritabanindan silinemedi; islemi tekrar deneyin. | [server/src/routes/company_routes.js:395](../server/src/routes/company_routes.js#L395) |
| Cihaz veya bagli oldugu site bulunamadi. | [server/src/routes/door_log_routes.js:245](../server/src/routes/door_log_routes.js#L245) |
| Cok fazla cihaz sahiplenme denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:261](../server/src/middlewares/rate_limiters.js#L261) |
| Cok fazla davet gonderildi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:270](../server/src/middlewares/rate_limiters.js#L270) |
| Cok fazla dogrulama denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:229](../server/src/middlewares/rate_limiters.js#L229) |
| Cok fazla giris denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:171](../server/src/middlewares/rate_limiters.js#L171) |
| Cok fazla hassas islem denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:279](../server/src/middlewares/rate_limiters.js#L279) |
| Cok fazla hatali mevcut parola denemesi. Biraz sonra tekrar deneyin. | [server/src/routes/auth_routes.js:835](../server/src/routes/auth_routes.js#L835) |
| Cok fazla hatali mevcut parola denemesi. Biraz sonra tekrar deneyin. | [server/src/routes/auth_routes.js:852](../server/src/routes/auth_routes.js#L852) |
| Cok fazla istek. Biraz sonra tekrar deneyin. | [server/src/routes/company_routes.js:28](../server/src/routes/company_routes.js#L28) |
| Cok fazla kayit denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:220](../server/src/middlewares/rate_limiters.js#L220) |
| Cok fazla kod isteme denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:238](../server/src/middlewares/rate_limiters.js#L238) |
| Cok fazla parametre. | [server/src/middlewares/error_handler.js:32](../server/src/middlewares/error_handler.js#L32) |
| Cok fazla sifre sifirlama denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:252](../server/src/middlewares/rate_limiters.js#L252) |
| Cok fazla sifre sifirlama istegi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:247](../server/src/middlewares/rate_limiters.js#L247) |
| Cok fazla site kurulum denemesi. Biraz sonra tekrar deneyin. | [server/src/routes/membership_routes.js:39](../server/src/routes/membership_routes.js#L39) |
| Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz. | [server/src/services/membership_rules.js:69](../server/src/services/membership_rules.js#L69) |
| Çok fazla hatalı doğrulama denemesi yapıldı. Kod iptal edildi; lütfen daha sonra yeni bir kod isteyiniz. | [server/src/services/site_service.js:1885](../server/src/services/site_service.js#L1885) |
| Çok fazla hatalı giriş denemesi. Hesap geçici olarak kilitlendi; lütfen 15 dakika sonra tekrar deneyin. | [server/src/routes/auth_routes.js:656](../server/src/routes/auth_routes.js#L656) |
| Daire bilgileri e-posta ile gonderilemedi. | [server/src/routes/admin_routes.js:1183](../server/src/routes/admin_routes.js#L1183) |
| Daire bulunamadı. | [server/src/services/membership_service.js:1572](../server/src/services/membership_service.js#L1572) |
| Daire bulunamadı. | [server/src/services/membership_service.js:2006](../server/src/services/membership_service.js#L2006) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1135](../server/src/routes/admin_routes.js#L1135) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1157](../server/src/routes/admin_routes.js#L1157) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1175](../server/src/routes/admin_routes.js#L1175) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:692](../server/src/routes/manager_routes.js#L692) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:726](../server/src/routes/manager_routes.js#L726) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:745](../server/src/routes/manager_routes.js#L745) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:759](../server/src/routes/manager_routes.js#L759) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:775](../server/src/routes/manager_routes.js#L775) |
| Daire kullanicisi e-postasi uretilirken cakisma oldu. | [server/src/utils/validators.js:373](../server/src/utils/validators.js#L373) |
| Daire kullanicisi hesabi uretilemedi. | [server/src/utils/validators.js:382](../server/src/utils/validators.js#L382) |
| Daire kullanicisi hesabi uretilirken kullanici adi cakismasi oldu. | [server/src/utils/validators.js:376](../server/src/utils/validators.js#L376) |
| Daire sakini sifirlanamadi. | [server/src/routes/admin_routes.js:1159](../server/src/routes/admin_routes.js#L1159) |
| Daire sakini sifirlandi. | [server/src/routes/admin_routes.js:1154](../server/src/routes/admin_routes.js#L1154) |
| Daire sakini sifirlandi. | [server/src/routes/manager_routes.js:756](../server/src/routes/manager_routes.js#L756) |
| Daire sakininin şifresi başarıyla güncellendi. | [server/src/services/membership_service.js:2071](../server/src/services/membership_service.js#L2071) |
| Daire yöneticisi kendi durumunu pasife alamaz. | [server/src/services/membership_service.js:1796](../server/src/services/membership_service.js#L1796) |
| Daire yöneticisi kendi kendisini daireden çıkaramaz. | [server/src/services/membership_service.js:1718](../server/src/services/membership_service.js#L1718) |
| Desteklenmeyen karakter kumesi. | [server/src/middlewares/error_handler.js:30](../server/src/middlewares/error_handler.js#L30) |
| Desteklenmeyen kodlama. | [server/src/middlewares/error_handler.js:29](../server/src/middlewares/error_handler.js#L29) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:292](../server/src/routes/company_routes.js#L292) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:381](../server/src/routes/company_routes.js#L381) |
| device_uid zorunlu. | [server/src/routes/door_log_routes.js:229](../server/src/routes/door_log_routes.js#L229) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:289](../server/src/routes/company_routes.js#L289) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:377](../server/src/routes/company_routes.js#L377) |
| Dogrulama kodu tekrar e-posta adresinize gonderildi. | [server/src/routes/auth_routes.js:597](../server/src/routes/auth_routes.js#L597) |
| Doğrulama isteği şu an işlenemiyor. Lütfen biraz sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:76](../server/src/services/membership_rules.js#L76) |
| Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır. | [server/src/services/membership_service.js:327](../server/src/services/membership_service.js#L327) |
| E-posta adresi gereklidir. | [server/src/routes/auth_routes.js:92](../server/src/routes/auth_routes.js#L92) |
| E-posta adresi gereklidir. | [server/src/services/membership_service.js:479](../server/src/services/membership_service.js#L479) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/admin_routes.js:362](../server/src/routes/admin_routes.js#L362) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/auth_routes.js:820](../server/src/routes/auth_routes.js#L820) |
| E-posta adresiniz başarıyla doğrulandı. Hesabınız aktif! | [server/src/services/membership_service.js:462](../server/src/services/membership_service.js#L462) |
| E-posta adresiniz dogrulanmadi. | [server/src/middlewares/auth_middleware.js:82](../server/src/middlewares/auth_middleware.js#L82) |
| E-posta adresiniz dogrulanmadi. | [server/src/routes/auth_routes.js:739](../server/src/routes/auth_routes.js#L739) |
| E-posta ve doğrulama kodu zorunludur. | [server/src/services/membership_service.js:321](../server/src/services/membership_service.js#L321) |
| E-posta zaten dogrulanmis. Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:584](../server/src/routes/auth_routes.js#L584) |
| email ve password zorunlu. | [server/src/routes/auth_routes.js:671](../server/src/routes/auth_routes.js#L671) |
| email_verified alani true/false olmali. | [server/src/routes/admin_routes.js:318](../server/src/routes/admin_routes.js#L318) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/routes/admin_routes.js:972](../server/src/routes/admin_routes.js#L972) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/utils/site_rules.js:415](../server/src/utils/site_rules.js#L415) |
| En fazla ${SITE_LIMITS.maxBlocks} blok tanımlanabilir. | [server/src/services/membership_rules.js:463](../server/src/services/membership_rules.js#L463) |
| En fazla ${SITE_LIMITS.maxDoors} kapı tanımlanabilir. | [server/src/services/membership_rules.js:494](../server/src/services/membership_rules.js#L494) |
| Enlem -90 ile 90 arasinda olmalidir. | [server/src/utils/site_rules.js:325](../server/src/utils/site_rules.js#L325) |
| Etiketli cihazlar okunamadi. | [server/src/routes/company_routes.js:274](../server/src/routes/company_routes.js#L274) |
| feature_* alanlari true/false olmali. | [server/src/routes/admin_routes.js:960](../server/src/routes/admin_routes.js#L960) |
| Firmware dosyasi bulunamadi. | [server/src/routes/firmware_routes.js:240](../server/src/routes/firmware_routes.js#L240) |
| Firmware manifest okunamadi. | [server/src/routes/firmware_routes.js:221](../server/src/routes/firmware_routes.js#L221) |
| full_name en az 3 karakter olmali. | [server/src/routes/admin_routes.js:312](../server/src/routes/admin_routes.js#L312) |
| Gecerli bir kapi secin. | [server/src/utils/guest_pass_utils.js:43](../server/src/utils/guest_pass_utils.js#L43) |
| Gecersiz approval_status degeri. | [server/src/routes/admin_routes.js:647](../server/src/routes/admin_routes.js#L647) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:936](../server/src/routes/manager_routes.js#L936) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:974](../server/src/routes/manager_routes.js#L974) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1340](../server/src/routes/admin_routes.js#L1340) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1413](../server/src/routes/admin_routes.js#L1413) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1499](../server/src/routes/admin_routes.js#L1499) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1532](../server/src/routes/admin_routes.js#L1532) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:886](../server/src/routes/manager_routes.js#L886) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1101](../server/src/routes/manager_routes.js#L1101) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1166](../server/src/routes/manager_routes.js#L1166) |
| Gecersiz cihaz unique id. | [server/src/routes/admin_routes.js:1243](../server/src/routes/admin_routes.js#L1243) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1092](../server/src/routes/admin_routes.js#L1092) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1145](../server/src/routes/admin_routes.js#L1145) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1167](../server/src/routes/admin_routes.js#L1167) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:679](../server/src/routes/manager_routes.js#L679) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:739](../server/src/routes/manager_routes.js#L739) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:769](../server/src/routes/manager_routes.js#L769) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:246](../server/src/routes/company_routes.js#L246) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:250](../server/src/routes/company_routes.js#L250) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:325](../server/src/routes/company_routes.js#L325) |
| Gecersiz firmware dosyasi. | [server/src/routes/firmware_routes.js:230](../server/src/routes/firmware_routes.js#L230) |
| Gecersiz firmware hedefi. | [server/src/routes/firmware_routes.js:114](../server/src/routes/firmware_routes.js#L114) |
| Gecersiz firmware yolu. | [server/src/routes/firmware_routes.js:237](../server/src/routes/firmware_routes.js#L237) |
| Gecersiz gecis id. | [server/src/routes/guest_passes_routes.js:184](../server/src/routes/guest_passes_routes.js#L184) |
| Gecersiz gecis kodu. | [server/src/routes/guest_passes_routes.js:212](../server/src/routes/guest_passes_routes.js#L212) |
| Gecersiz gecis suresi. | [server/src/utils/guest_pass_utils.js:62](../server/src/utils/guest_pass_utils.js#L62) |
| Gecersiz gecis turu. | [server/src/utils/guest_pass_utils.js:53](../server/src/utils/guest_pass_utils.js#L53) |
| Gecersiz istek akisi. | [server/src/middlewares/error_handler.js:31](../server/src/middlewares/error_handler.js#L31) |
| Gecersiz istek boyutu. | [server/src/middlewares/error_handler.js:28](../server/src/middlewares/error_handler.js#L28) |
| Gecersiz istek govdesi. | [server/src/middlewares/error_handler.js:26](../server/src/middlewares/error_handler.js#L26) |
| Gecersiz JSON govdesi. | [server/src/middlewares/error_handler.js:25](../server/src/middlewares/error_handler.js#L25) |
| Gecersiz kapi acma kanali. | [server/src/services/door_access_policy.js:48](../server/src/services/door_access_policy.js#L48) |
| Gecersiz kapi ID. | [server/src/routes/admin_routes.js:1191](../server/src/routes/admin_routes.js#L1191) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:802](../server/src/routes/manager_routes.js#L802) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:846](../server/src/routes/manager_routes.js#L846) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:875](../server/src/routes/manager_routes.js#L875) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:965](../server/src/routes/manager_routes.js#L965) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1011](../server/src/routes/manager_routes.js#L1011) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1038](../server/src/routes/manager_routes.js#L1038) |
| Gecersiz kapi id. | [server/src/routes/app_doors_routes.js:39](../server/src/routes/app_doors_routes.js#L39) |
| Gecersiz karekod verisi. | [server/src/routes/app_doors_routes.js:260](../server/src/routes/app_doors_routes.js#L260) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:294](../server/src/routes/admin_routes.js#L294) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:401](../server/src/routes/admin_routes.js#L401) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:431](../server/src/routes/admin_routes.js#L431) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:591](../server/src/routes/admin_routes.js#L591) |
| Gecersiz kullanim limiti. | [server/src/utils/guest_pass_utils.js:74](../server/src/utils/guest_pass_utils.js#L74) |
| Gecersiz parametreler. | [server/src/services/qr_access_service.js:23](../server/src/services/qr_access_service.js#L23) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:155](../server/src/routes/admin_routes.js#L155) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:315](../server/src/routes/admin_routes.js#L315) |
| Gecersiz rol. | [server/src/routes/auth_routes.js:674](../server/src/routes/auth_routes.js#L674) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:744](../server/src/routes/admin_routes.js#L744) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:810](../server/src/routes/admin_routes.js#L810) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:943](../server/src/routes/admin_routes.js#L943) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:994](../server/src/routes/admin_routes.js#L994) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1012](../server/src/routes/admin_routes.js#L1012) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1027](../server/src/routes/admin_routes.js#L1027) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1042](../server/src/routes/admin_routes.js#L1042) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1057](../server/src/routes/admin_routes.js#L1057) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1072](../server/src/routes/admin_routes.js#L1072) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:221](../server/src/routes/manager_routes.js#L221) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:356](../server/src/routes/manager_routes.js#L356) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:476](../server/src/routes/manager_routes.js#L476) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:491](../server/src/routes/manager_routes.js#L491) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:506](../server/src/routes/manager_routes.js#L506) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:521](../server/src/routes/manager_routes.js#L521) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:543](../server/src/routes/manager_routes.js#L543) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:568](../server/src/routes/manager_routes.js#L568) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:926](../server/src/routes/manager_routes.js#L926) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:1074](../server/src/routes/manager_routes.js#L1074) |
| Gecersiz token. | [server/src/middlewares/auth_middleware.js:32](../server/src/middlewares/auth_middleware.js#L32) |
| Gecersiz veya suresi dolmus token. | [server/src/middlewares/auth_middleware.js:24](../server/src/middlewares/auth_middleware.js#L24) |
| Gecis baglantisi bulunamadi veya silinmis. | [server/src/routes/guest_passes_routes.js:249](../server/src/routes/guest_passes_routes.js#L249) |
| Gecis baglantisi su an baska bir istekle kullaniliyor. Lutfen tekrar deneyin. | [server/src/routes/guest_passes_routes.js:368](../server/src/routes/guest_passes_routes.js#L368) |
| Gecis bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:199](../server/src/routes/guest_passes_routes.js#L199) |
| Gecis iptal edildi. | [server/src/routes/guest_passes_routes.js:202](../server/src/routes/guest_passes_routes.js#L202) |
| Geçerli bir Cihaz Unique ID (UID) giriniz (12 haneli onaltılık, örn. D4C771A172E0). | [server/src/services/device_service.js:888](../server/src/services/device_service.js#L888) |
| Geçerli bir daire seçiniz. | [server/src/services/membership_service.js:971](../server/src/services/membership_service.js#L971) |
| Geçerli bir e-posta adresi gereklidir. | [server/src/services/site_service.js:1996](../server/src/services/site_service.js#L1996) |
| Geçerli bir e-posta adresi giriniz. | [server/src/routes/auth_routes.js:324](../server/src/routes/auth_routes.js#L324) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:232](../server/src/services/membership_service.js#L232) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:324](../server/src/services/membership_service.js#L324) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:482](../server/src/services/membership_service.js#L482) |
| Geçersiz blok kimliği. | [server/src/services/membership_service.js:2495](../server/src/services/membership_service.js#L2495) |
| Geçersiz blok seçimi. | [server/src/services/membership_service.js:976](../server/src/services/membership_service.js#L976) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:948](../server/src/services/device_service.js#L948) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:994](../server/src/services/device_service.js#L994) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:1562](../server/src/services/membership_service.js#L1562) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:1972](../server/src/services/membership_service.js#L1972) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:2488](../server/src/services/membership_service.js#L2488) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:318](../server/src/routes/membership_routes.js#L318) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:338](../server/src/routes/membership_routes.js#L338) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:366](../server/src/routes/membership_routes.js#L366) |
| Geçersiz kapı kimliği. | [server/src/services/membership_service.js:2165](../server/src/services/membership_service.js#L2165) |
| Geçersiz katılım tokeni. | [server/src/services/membership_service.js:962](../server/src/services/membership_service.js#L962) |
| Geçersiz kullanıcı kimliği. | [server/src/services/membership_service.js:1700](../server/src/services/membership_service.js#L1700) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:1470](../server/src/services/membership_service.js#L1470) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:2399](../server/src/services/membership_service.js#L2399) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1329](../server/src/routes/manager_routes.js#L1329) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1356](../server/src/routes/manager_routes.js#L1356) |
| Geçersiz parametreler. | [server/src/services/site_service.js:2173](../server/src/services/site_service.js#L2173) |
| Geçersiz site ID. | [server/src/routes/manager_routes.js:1205](../server/src/routes/manager_routes.js#L1205) |
| Geçersiz site ID. | [server/src/routes/membership_routes.js:393](../server/src/routes/membership_routes.js#L393) |
| Geçersiz site katılım kodu. | [server/src/routes/membership_routes.js:141](../server/src/routes/membership_routes.js#L141) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:1195](../server/src/services/membership_service.js#L1195) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:2573](../server/src/services/membership_service.js#L2573) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1275](../server/src/routes/manager_routes.js#L1275) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1298](../server/src/routes/manager_routes.js#L1298) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1509](../server/src/services/site_service.js#L1509) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1635](../server/src/services/site_service.js#L1635) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1682](../server/src/services/site_service.js#L1682) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1740](../server/src/services/site_service.js#L1740) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1822](../server/src/services/site_service.js#L1822) |
| Geçersiz şifre sıfırlama bağlantısı. Lütfen e-postanızdaki bağlantıyı kontrol ediniz. | [server/src/routes/auth_routes.js:360](../server/src/routes/auth_routes.js#L360) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1227](../server/src/routes/manager_routes.js#L1227) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1248](../server/src/routes/manager_routes.js#L1248) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1279](../server/src/services/membership_service.js#L1279) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1398](../server/src/services/membership_service.js#L1398) |
| Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır. | [server/src/services/membership_service.js:371](../server/src/services/membership_service.js#L371) |
| Girdiğiniz silme doğrulama kodu hatalı. | [server/src/services/site_service.js:1889](../server/src/services/site_service.js#L1889) |
| Giris bilgileri hatali. | [server/src/routes/auth_routes.js:729](../server/src/routes/auth_routes.js#L729) |
| Giris islemi basarisiz. | [server/src/routes/auth_routes.js:759](../server/src/routes/auth_routes.js#L759) |
| Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapilabilir. | [server/src/utils/site_rules.js:392](../server/src/utils/site_rules.js#L392) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:351](../server/src/routes/admin_routes.js#L351) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:849](../server/src/routes/admin_routes.js#L849) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/auth_routes.js:815](../server/src/routes/auth_routes.js#L815) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/manager_routes.js:389](../server/src/routes/manager_routes.js#L389) |
| Güncellenecek alan bulunamadı. | [server/src/services/door_service.js:675](../server/src/services/door_service.js#L675) |
| Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez. Kullanıcılar kendi şifrelerini hesaplarına giriş yaparak profil bölümünden değiştirmelidir. | [server/src/routes/admin_routes.js:370](../server/src/routes/admin_routes.js#L370) |
| hardware_type esp32_c3 veya esp32_wroom olmali. | [server/src/routes/admin_routes.js:1370](../server/src/routes/admin_routes.js#L1370) |
| Hesap aktif degil. | [server/src/middlewares/auth_middleware.js:79](../server/src/middlewares/auth_middleware.js#L79) |
| Hesap aktif degil. | [server/src/routes/auth_routes.js:748](../server/src/routes/auth_routes.js#L748) |
| Islem basarisiz. | [server/src/utils/guest_pass_utils.js:242](../server/src/utils/guest_pass_utils.js#L242) |
| Istek govdesi cok buyuk. | [server/src/middlewares/error_handler.js:24](../server/src/middlewares/error_handler.js#L24) |
| Istek govdesi cok buyuk. | [server/src/routes/door_log_routes.js:223](../server/src/routes/door_log_routes.js#L223) |
| Istek yarida kesildi. | [server/src/middlewares/error_handler.js:27](../server/src/middlewares/error_handler.js#L27) |
| İptal edilecek bekleyen davet bulunamadı. | [server/src/services/site_service.js:2311](../server/src/services/site_service.js#L2311) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:406](../server/src/routes/admin_routes.js#L406) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:1102](../server/src/routes/admin_routes.js#L1102) |
| is_active alani true/false olmali. | [server/src/routes/manager_routes.js:978](../server/src/routes/manager_routes.js#L978) |
| is_defective alani true/false olmali. | [server/src/routes/admin_routes.js:1503](../server/src/routes/admin_routes.js#L1503) |
| İşlem sırasında bir hata oluştu. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:406](../server/src/routes/auth_routes.js#L406) |
| Kapı adı boş olamaz. | [server/src/services/door_service.js:650](../server/src/services/door_service.js#L650) |
| Kapı adı zorunludur. | [server/src/services/door_service.js:576](../server/src/services/door_service.js#L576) |
| Kapı bulunamadı. | [server/src/services/membership_service.js:2177](../server/src/services/membership_service.js#L2177) |
| Kapı yetkisi varsayılan ayarlara döndürüldü. | [server/src/services/membership_service.js:2416](../server/src/services/membership_service.js#L2416) |
| Kapi adi zorunludur. | [server/src/routes/manager_routes.js:932](../server/src/routes/manager_routes.js#L932) |
| Kapi basariyla acildi. | [server/src/routes/app_doors_routes.js:402](../server/src/routes/app_doors_routes.js#L402) |
| Kapi bulunamadi veya erisim yetkiniz yok. | [server/src/services/qr_access_service.js:30](../server/src/services/qr_access_service.js#L30) |
| Kapi bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:60](../server/src/routes/guest_passes_routes.js#L60) |
| Kapi bulunamadi. | [server/src/routes/admin_routes.js:1209](../server/src/routes/admin_routes.js#L1209) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:128](../server/src/routes/app_doors_routes.js#L128) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:169](../server/src/routes/app_doors_routes.js#L169) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:426](../server/src/routes/app_doors_routes.js#L426) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:810](../server/src/routes/manager_routes.js#L810) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:852](../server/src/routes/manager_routes.js#L852) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:895](../server/src/routes/manager_routes.js#L895) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:984](../server/src/routes/manager_routes.js#L984) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1017](../server/src/routes/manager_routes.js#L1017) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1044](../server/src/routes/manager_routes.js#L1044) |
| Kapi bulunamadi. | [server/src/services/door_access_policy.js:55](../server/src/services/door_access_policy.js#L55) |
| Kapi bulunamadi. | [server/src/utils/site_rules.js:475](../server/src/utils/site_rules.js#L475) |
| Kapi cihazi su anda bagli degil. | [server/src/routes/guest_passes_routes.js:446](../server/src/routes/guest_passes_routes.js#L446) |
| Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:186](../server/src/middlewares/rate_limiters.js#L186) |
| Kapi loglari alinamadi. | [server/src/routes/door_log_routes.js:101](../server/src/routes/door_log_routes.js#L101) |
| Kapi loglari alinamadi. | [server/src/routes/door_log_routes.js:197](../server/src/routes/door_log_routes.js#L197) |
| Karekod dosyasi bulunamadi. | [server/src/routes/company_routes.js:253](../server/src/routes/company_routes.js#L253) |
| Karekod ile eslesen aktif bir kapi bulunamadi. | [server/src/routes/app_doors_routes.js:278](../server/src/routes/app_doors_routes.js#L278) |
| Karekod talebi çok sık yapıldı. Lütfen birkaç saniye bekleyip tekrar deneyiniz. | [server/src/middlewares/rate_limiters.js:192](../server/src/middlewares/rate_limiters.js#L192) |
| Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:336](../server/src/routes/app_doors_routes.js#L336) |
| Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:357](../server/src/routes/app_doors_routes.js#L357) |
| Katılım başvurusu reddedildi. | [server/src/services/membership_service.js:1454](../server/src/services/membership_service.js#L1454) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1300](../server/src/services/membership_service.js#L1300) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1409](../server/src/services/membership_service.js#L1409) |
| Kayit olusturuldu. E-posta adresinize gonderilen 6 haneli kodu girin. | [server/src/routes/auth_routes.js:625](../server/src/routes/auth_routes.js#L625) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:355](../server/src/routes/admin_routes.js#L355) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:409](../server/src/routes/admin_routes.js#L409) |
| Kendi hesabinizi silemezsiniz. | [server/src/routes/admin_routes.js:439](../server/src/routes/admin_routes.js#L439) |
| Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin. | [server/src/routes/admin_routes.js:326](../server/src/routes/admin_routes.js#L326) |
| Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur. | [server/src/utils/site_rules.js:462](../server/src/utils/site_rules.js#L462) |
| Konum yaricapi ${GEOFENCE_RADIUS_MIN} ile ${GEOFENCE_RADIUS_MAX} metre arasinda olmalidir. | [server/src/utils/site_rules.js:342](../server/src/utils/site_rules.js#L342) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_rules.js:352](../server/src/services/membership_rules.js#L352) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1740](../server/src/services/membership_service.js#L1740) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1826](../server/src/services/membership_service.js#L1826) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1925](../server/src/services/membership_service.js#L1925) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:2107](../server/src/services/membership_service.js#L2107) |
| Kullanıcı bu daireye ait değil. | [server/src/services/membership_service.js:2018](../server/src/services/membership_service.js#L2018) |
| Kullanıcı bu sitenin yöneticisi değil. | [server/src/utils/site_rules.js:172](../server/src/utils/site_rules.js#L172) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:543](../server/src/services/membership_service.js#L543) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:2425](../server/src/services/membership_service.js#L2425) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:745](../server/src/services/membership_service.js#L745) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:997](../server/src/services/membership_service.js#L997) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:2034](../server/src/services/membership_service.js#L2034) |
| Kullanıcı kodu (userCode) zorunludur. | [server/src/routes/membership_routes.js:342](../server/src/routes/membership_routes.js#L342) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:526](../server/src/services/membership_service.js#L526) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:716](../server/src/services/membership_service.js#L716) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:967](../server/src/services/membership_service.js#L967) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:1139](../server/src/services/membership_service.js#L1139) |
| Kullanıcı site yöneticiliğinden çıkarıldı. | [server/src/services/site_service.js:2288](../server/src/services/site_service.js#L2288) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/admin_routes.js:1181](../server/src/routes/admin_routes.js#L1181) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/manager_routes.js:788](../server/src/routes/manager_routes.js#L788) |
| Kullanici bulunamadi. | [server/src/middlewares/auth_middleware.js:61](../server/src/middlewares/auth_middleware.js#L61) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:385](../server/src/routes/admin_routes.js#L385) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:415](../server/src/routes/admin_routes.js#L415) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:495](../server/src/routes/admin_routes.js#L495) |
| Kullanici bulunamadi. | [server/src/routes/auth_routes.js:874](../server/src/routes/auth_routes.js#L874) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1376](../server/src/routes/admin_routes.js#L1376) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1453](../server/src/routes/admin_routes.js#L1453) |
| Kullanici ID sayisal olmali. | [server/src/routes/admin_routes.js:1355](../server/src/routes/admin_routes.js#L1355) |
| Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin. | [server/src/utils/validators.js:361](../server/src/utils/validators.js#L361) |
| Kullanici rolu ile secilen rol uyusmuyor. | [server/src/routes/auth_routes.js:736](../server/src/routes/auth_routes.js#L736) |
| Kullanici silinemedi. | [server/src/routes/admin_routes.js:517](../server/src/routes/admin_routes.js#L517) |
| Log senkronizasyonu basarisiz. | [server/src/routes/door_log_routes.js:267](../server/src/routes/door_log_routes.js#L267) |
| logs bir dizi olmali. | [server/src/routes/door_log_routes.js:232](../server/src/routes/door_log_routes.js#L232) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/routes/manager_routes.js:889](../server/src/routes/manager_routes.js#L889) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/utils/site_rules.js:485](../server/src/utils/site_rules.js#L485) |
| Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz. | [server/src/services/site_service.js:1841](../server/src/services/site_service.js#L1841) |
| Lütfen 6 haneli silme doğrulama kodunu giriniz. | [server/src/routes/admin_routes.js:1077](../server/src/routes/admin_routes.js#L1077) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/admin_routes.js:1178](../server/src/routes/admin_routes.js#L1178) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/manager_routes.js:785](../server/src/routes/manager_routes.js#L785) |
| Mevcut parola hatali. | [server/src/routes/auth_routes.js:859](../server/src/routes/auth_routes.js#L859) |
| Mevcut şifre hatalı. | [server/src/services/membership_service.js:2042](../server/src/services/membership_service.js#L2042) |
| Mevcut şifre zorunludur. | [server/src/services/membership_service.js:1997](../server/src/services/membership_service.js#L1997) |
| Mevcut yonetici kodu veya yeni yonetici bilgilerinden yalnizca biri gonderilmeli. | [server/src/routes/admin_routes.js:698](../server/src/routes/admin_routes.js#L698) |
| MQTT ACL senkronu zaman asimina ugradi (${timeoutMs} ms). | [server/src/mqtt_acl_sync.js:208](../server/src/mqtt_acl_sync.js#L208) |
| MQTT baglantisi hazir degil. | [server/src/routes/admin_routes.js:1330](../server/src/routes/admin_routes.js#L1330) |
| MQTT baglantisi hazir degil. | [server/src/routes/app_doors_routes.js:64](../server/src/routes/app_doors_routes.js#L64) |
| MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1286](../server/src/routes/admin_routes.js#L1286) |
| MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:663](../server/src/routes/manager_routes.js#L663) |
| MQTT cihaz kimligi uretilemedi. | [server/src/routes/admin_routes.js:1290](../server/src/routes/admin_routes.js#L1290) |
| MQTT_SYNC_COMMAND tanimli degil. | [server/src/mqtt_acl_sync.js:169](../server/src/mqtt_acl_sync.js#L169) |
| MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS gecersiz karakter iceriyor. | [server/src/mqtt_acl_sync.js:182](../server/src/mqtt_acl_sync.js#L182) |
| OTA komutu gonderilemedi. | [server/src/routes/admin_routes.js:1332](../server/src/routes/admin_routes.js#L1332) |
| Oturum gecersiz. Lutfen tekrar giris yapin. | [server/src/middlewares/auth_middleware.js:73](../server/src/middlewares/auth_middleware.js#L73) |
| Parolayi degistirmek icin mevcut parolanizi girmelisiniz. | [server/src/routes/auth_routes.js:826](../server/src/routes/auth_routes.js#L826) |
| qr_entry_active alani true/false olmalidir. | [server/src/utils/site_rules.js:313](../server/src/utils/site_rules.js#L313) |
| qr_image_base64 gecerli bir PNG (en fazla 2 MB) olmalidir. | [server/src/routes/company_routes.js:299](../server/src/routes/company_routes.js#L299) |
| qr_rotation_seconds sayisal olmalidir. | [server/src/utils/site_rules.js:353](../server/src/utils/site_rules.js#L353) |
| require_geofence alani true/false olmalidir. | [server/src/utils/site_rules.js:319](../server/src/utils/site_rules.js#L319) |
| Route bulunamadi. | [server/src/middlewares/error_handler.js:100](../server/src/middlewares/error_handler.js#L100) |
| Sakin daireden başarıyla silindi. | [server/src/services/membership_service.js:1951](../server/src/services/membership_service.js#L1951) |
| Sakini kalıcı olarak silme yetkisi yalnızca site yöneticilerine aittir. | [server/src/services/membership_service.js:1903](../server/src/services/membership_service.js#L1903) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:691](../server/src/routes/admin_routes.js#L691) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:832](../server/src/routes/admin_routes.js#L832) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:315](../server/src/routes/manager_routes.js#L315) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:376](../server/src/routes/manager_routes.js#L376) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:944](../server/src/routes/manager_routes.js#L944) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:990](../server/src/routes/manager_routes.js#L990) |
| Secilen yeni cihaz bulunamadi. | [server/src/routes/manager_routes.js:916](../server/src/routes/manager_routes.js#L916) |
| Seçilen alanda aktif sakin bulunamadı. | [server/src/services/membership_service.js:2507](../server/src/services/membership_service.js#L2507) |
| Seçilen daire belirtilen bloğa ait değil. | [server/src/services/membership_service.js:1036](../server/src/services/membership_service.js#L1036) |
| Seçilen daire bulunamadı veya bu siteye ait değil. | [server/src/services/membership_service.js:1032](../server/src/services/membership_service.js#L1032) |
| Sıfırlama anahtarı (token) eksik. | [server/src/routes/auth_routes.js:418](../server/src/routes/auth_routes.js#L418) |
| Sifre 4 haneli sayisal olmali. | [server/src/services/apartment_service.js:178](../server/src/services/apartment_service.js#L178) |
| Sifre en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir. | [server/src/routes/auth_routes.js:805](../server/src/routes/auth_routes.js#L805) |
| Silme doğrulama kodu e-posta adresinize (${maskedEmail}) gönderildi. | [server/src/services/site_service.js:1796](../server/src/services/site_service.js#L1796) |
| Silme doğrulama kodunun 10 dakikalık süresi dolmuş. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:1865](../server/src/services/site_service.js#L1865) |
| Site adı en fazla ${SETUP_NAME_MAX} karakter olabilir. | [server/src/services/membership_rules.js:454](../server/src/services/membership_rules.js#L454) |
| Site adı zorunludur. | [server/src/services/membership_rules.js:451](../server/src/services/membership_rules.js#L451) |
| Site adi en az 2 karakter olmali. | [server/src/routes/admin_routes.js:835](../server/src/routes/admin_routes.js#L835) |
| Site bulunamadı. | [server/src/services/membership_service.js:2584](../server/src/services/membership_service.js#L2584) |
| Site bulunamadı. | [server/src/services/site_service.js:1451](../server/src/services/site_service.js#L1451) |
| Site bulunamadı. | [server/src/services/site_service.js:1468](../server/src/services/site_service.js#L1468) |
| Site bulunamadı. | [server/src/services/site_service.js:1528](../server/src/services/site_service.js#L1528) |
| Site bulunamadı. | [server/src/services/site_service.js:1646](../server/src/services/site_service.js#L1646) |
| Site bulunamadı. | [server/src/services/site_service.js:1699](../server/src/services/site_service.js#L1699) |
| Site bulunamadı. | [server/src/services/site_service.js:1750](../server/src/services/site_service.js#L1750) |
| Site bulunamadı. | [server/src/services/site_service.js:1852](../server/src/services/site_service.js#L1852) |
| Site bulunamadı. | [server/src/services/site_service.js:2003](../server/src/services/site_service.js#L2003) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:855](../server/src/routes/admin_routes.js#L855) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:966](../server/src/routes/admin_routes.js#L966) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1000](../server/src/routes/admin_routes.js#L1000) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:236](../server/src/routes/manager_routes.js#L236) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:399](../server/src/routes/manager_routes.js#L399) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:531](../server/src/routes/manager_routes.js#L531) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:558](../server/src/routes/manager_routes.js#L558) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:587](../server/src/routes/manager_routes.js#L587) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1379](../server/src/routes/admin_routes.js#L1379) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1456](../server/src/routes/admin_routes.js#L1456) |
| Site ID bulunamadi. | [server/src/routes/manager_routes.js:1119](../server/src/routes/manager_routes.js#L1119) |
| Site ID sayisal olmali. | [server/src/routes/admin_routes.js:1358](../server/src/routes/admin_routes.js#L1358) |
| Site katilim QR kodu basariyla yenilendi. Eski QR kodlar iptal edildi. | [server/src/routes/manager_routes.js:583](../server/src/routes/manager_routes.js#L583) |
| Site kaydini yalnizca super user guncelleyebilir. | [server/src/routes/manager_routes.js:351](../server/src/routes/manager_routes.js#L351) |
| Site kaydini yalnizca super user olusturabilir. | [server/src/routes/manager_routes.js:290](../server/src/routes/manager_routes.js#L290) |
| Site kodu olusturulurken cakisma oldu. | [server/src/utils/validators.js:379](../server/src/utils/validators.js#L379) |
| Site kurmak için önce bir cihaz sahiplenmelisiniz. | [server/src/services/membership_service.js:772](../server/src/services/membership_service.js#L772) |
| Site silme talebi başarıyla iptal edildi / reddedildi. | [server/src/services/site_service.js:1724](../server/src/services/site_service.js#L1724) |
| Site silme talebi oluşturuldu. Site yöneticisinin onayı gerekmektedir. | [server/src/services/site_service.js:1587](../server/src/services/site_service.js#L1587) |
| Site silme talebi oluşturuldu. Süper kullanıcının onayı gerekmektedir. | [server/src/services/site_service.js:1625](../server/src/services/site_service.js#L1625) |
| Site silme talebi zaten oluşturulmuş; Site Yöneticisinin onayı bekleniyor. | [server/src/services/site_service.js:1566](../server/src/services/site_service.js#L1566) |
| Site silme talebi zaten oluşturulmuş; Süper Kullanıcının onayı bekleniyor. | [server/src/services/site_service.js:1604](../server/src/services/site_service.js#L1604) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:816](../server/src/routes/manager_routes.js#L816) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:1126](../server/src/routes/manager_routes.js#L1126) |
| Site talebi baska bir islemle zaten sonuclandirildi. | [server/src/routes/admin_routes.js:797](../server/src/routes/admin_routes.js#L797) |
| Site ve bağlı tüm kayıtlar başarıyla silindi. | [server/src/services/site_service.js:1500](../server/src/services/site_service.js#L1500) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/helpers.js:587](../server/src/utils/helpers.js#L587) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/validators.js:201](../server/src/utils/validators.js#L201) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:715](../server/src/routes/admin_routes.js#L715) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:870](../server/src/routes/admin_routes.js#L870) |
| Site yoneticisi kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:536](../server/src/routes/auth_routes.js#L536) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:638](../server/src/routes/auth_routes.js#L638) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:645](../server/src/routes/auth_routes.js#L645) |
| Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz. | [server/src/utils/site_rules.js:181](../server/src/utils/site_rules.js#L181) |
| Sitenin kurucu yöneticisi (Site Sahibi) yalnızca Süper Kullanıcı tarafından çıkarılabilir. | [server/src/utils/site_rules.js:189](../server/src/utils/site_rules.js#L189) |
| Siteye katılım başvurusu yapabilmek için e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:1001](../server/src/services/membership_service.js#L1001) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:94](../server/src/mailer.js#L94) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:138](../server/src/mailer.js#L138) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:170](../server/src/mailer.js#L170) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:204](../server/src/mailer.js#L204) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:249](../server/src/mailer.js#L249) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:320](../server/src/mailer.js#L320) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:380](../server/src/mailer.js#L380) |
| Süper kullanıcı hesabına kayıtlı bir e-posta adresi bulunamadı. | [server/src/services/site_service.js:1762](../server/src/services/site_service.js#L1762) |
| Şifre en az 4 karakter uzunluğunda olmalıdır. | [server/src/services/membership_service.js:1988](../server/src/services/membership_service.js#L1988) |
| Şifre en az 6 karakter olmalıdır. | [server/src/services/membership_service.js:235](../server/src/services/membership_service.js#L235) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:238](../server/src/services/membership_service.js#L238) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:1991](../server/src/services/membership_service.js#L1991) |
| Şifre güncellenemedi. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:486](../server/src/routes/auth_routes.js#L486) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:427](../server/src/routes/auth_routes.js#L427) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:442](../server/src/routes/auth_routes.js#L442) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:468](../server/src/routes/auth_routes.js#L468) |
| Şifre sıfırlama bağlantısının süresi dolmuş. Lütfen yeni bir talepte bulunun. | [server/src/routes/auth_routes.js:448](../server/src/routes/auth_routes.js#L448) |
| Şifreniz başarıyla güncellendi. Yeni şifrenizle giriş yapabilirsiniz. | [server/src/routes/auth_routes.js:481](../server/src/routes/auth_routes.js#L481) |
| Tek istekte en fazla ${MAX_DEVICE_LOG_BATCH} kayit gonderilebilir. | [server/src/routes/door_log_routes.js:237](../server/src/routes/door_log_routes.js#L237) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:438](../server/src/services/qr_access_service.js#L438) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:466](../server/src/services/qr_access_service.js#L466) |
| Token parametresi zorunludur. | [server/src/routes/app_doors_routes.js:527](../server/src/routes/app_doors_routes.js#L527) |
| Token zorunludur. | [server/src/services/qr_access_service.js:433](../server/src/services/qr_access_service.js#L433) |
| Toplam daire sayısı en fazla ${SITE_LIMITS.maxApartments} olabilir. | [server/src/services/membership_rules.js:487](../server/src/services/membership_rules.js#L487) |
| Toplu yetkilendirme için blok, daire veya kullanıcı listesi belirtilmelidir. | [server/src/services/membership_service.js:2500](../server/src/services/membership_service.js#L2500) |
| Üye daireden başarıyla çıkarıldı. | [server/src/services/membership_service.js:1765](../server/src/services/membership_service.js#L1765) |
| Veritabanı sağlık bilgisi alınamadı. | [server/src/services/maintenance_service.js:206](../server/src/services/maintenance_service.js#L206) |
| Veritabanı temizliği başarısız oldu. | [server/src/services/maintenance_service.js:92](../server/src/services/maintenance_service.js#L92) |
| Veritabani saglik bilgisi alinamadi. | [server/src/routes/admin_routes.js:1558](../server/src/routes/admin_routes.js#L1558) |
| Veritabani temizligi sirasinda hata olustu. | [server/src/routes/admin_routes.js:1573](../server/src/routes/admin_routes.js#L1573) |
| Yeni kod istemek için lütfen ${seconds} saniye bekleyiniz. | [server/src/services/membership_rules.js:113](../server/src/services/membership_rules.js#L113) |
| Yeni kullanici kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:493](../server/src/routes/auth_routes.js#L493) |
| Yeni şifreniz en az 6 karakter olmalıdır. | [server/src/routes/auth_routes.js:421](../server/src/routes/auth_routes.js#L421) |
| Yeni şifreniz en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir. | [server/src/routes/auth_routes.js:424](../server/src/routes/auth_routes.js#L424) |
| Yetkisiz erisim. | [server/src/middlewares/auth_middleware.js:15](../server/src/middlewares/auth_middleware.js#L15) |
| Yetkisiz erisim. | [server/src/middlewares/company_auth.js:43](../server/src/middlewares/company_auth.js#L43) |
| Yetkisiz erisim. | [server/src/routes/admin_routes.js:436](../server/src/routes/admin_routes.js#L436) |
| Yetkisiz erisim. | [server/src/routes/auth_routes.js:774](../server/src/routes/auth_routes.js#L774) |
| Yetkisiz erisim. | [server/src/routes/manager_routes.js:295](../server/src/routes/manager_routes.js#L295) |
| Yönetici daveti iptal edildi. | [server/src/services/site_service.js:2318](../server/src/services/site_service.js#L2318) |
| Zaten bu dairenin aktif bir sakinisisiniz (${existingMemberRes.rows[0].role}). | [server/src/services/membership_service.js:1045](../server/src/services/membership_service.js#L1045) |

## Uygulama (Flutter) mesajları (106)

Kaynak: `lib` (`ApiException(...)`, `_errorMessage =`, `lib/services` içindeki `return '...'`).

| Mesaj | Dosya:satır |
| --- | --- |
| ${e.message} Kod 30 dakika geçerlidir; yeni kod için "Kodu Tekrar Gönder"e dokunun. | [lib/services/auth_service.dart:285](../lib/services/auth_service.dart#L285) |
| $distance m uzaktasınız, izin verilen mesafe $allowed m. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:1680](../lib/services/auth_api.dart#L1680) |
| $label verisi beklenen formatta degil. | [lib/services/auth_api.dart:1817](../lib/services/auth_api.dart#L1817) |
| $label verisi islenemedi. | [lib/services/auth_api.dart:1815](../lib/services/auth_api.dart#L1815) |
| $trimmed Lütfen ${formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/auth_api.dart:1626](../lib/services/auth_api.dart#L1626) |
| Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin. | [lib/services/voice_door_service.dart:501](../lib/services/voice_door_service.dart#L501) |
| Anlık konum alınamadı. Lütfen GPS'i kontrol edip tekrar deneyin. | [lib/services/geofence_service.dart:134](../lib/services/geofence_service.dart#L134) |
| Bağlantı hatası: $e | [lib/ui/widgets/door_logs_accordion.dart:113](../lib/ui/widgets/door_logs_accordion.dart#L113) |
| Bluetooth islemi basarisiz oldu. | [lib/services/ble_wifi_provision_service.dart:521](../lib/services/ble_wifi_provision_service.dart#L521) |
| Bu cihaz arızalı olarak işaretlenmiş. | [lib/services/auth_api.dart:1726](../lib/services/auth_api.dart#L1726) |
| Bu cihaz başka bir hesaba ait. | [lib/services/auth_api.dart:1724](../lib/services/auth_api.dart#L1724) |
| Bu cihaz bu kapıya atanamaz. | [lib/services/auth_api.dart:1722](../lib/services/auth_api.dart#L1722) |
| Bu isimde bir kapı bulunamadı. Lütfen kapının adını veya numarasını söyleyin. | [lib/services/voice_door_service.dart:496](../lib/services/voice_door_service.dart#L496) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:1158](../lib/services/auth_service.dart#L1158) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:1179](../lib/services/auth_service.dart#L1179) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:2023](../lib/services/auth_service.dart#L2023) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:619](../lib/services/auth_service.dart#L619) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:653](../lib/services/auth_service.dart#L653) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:683](../lib/services/auth_service.dart#L683) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:704](../lib/services/auth_service.dart#L704) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:789](../lib/services/auth_service.dart#L789) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:823](../lib/services/auth_service.dart#L823) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:1390](../lib/services/auth_service.dart#L1390) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:1832](../lib/services/auth_service.dart#L1832) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:1856](../lib/services/auth_service.dart#L1856) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:2004](../lib/services/auth_service.dart#L2004) |
| Bu islem icin yetkiniz bulunmamaktadir. | [lib/services/auth_service.dart:860](../lib/services/auth_service.dart#L860) |
| Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin. | [lib/services/auth_api.dart:1667](../lib/services/auth_api.dart#L1667) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen kapı ekranındaki güncel karekodu okutun. | [lib/services/auth_api.dart:1700](../lib/services/auth_api.dart#L1700) |
| Bu kapıda QR ile giriş şu an devre dışı. | [lib/services/auth_api.dart:1692](../lib/services/auth_api.dart#L1692) |
| Bu kapıyı açma yetkiniz yok. | [lib/services/auth_api.dart:1716](../lib/services/auth_api.dart#L1716) |
| Bu karekod daha önce kullanıldı. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:1702](../lib/services/auth_api.dart#L1702) |
| Bu platform MQTT TCP baglantisini desteklemiyor. | [lib/services/mqtt_door_service_stub.dart:41](../lib/services/mqtt_door_service_stub.dart#L41) |
| Bu sitede misafir geçişi kapalı. | [lib/services/auth_api.dart:1694](../lib/services/auth_api.dart#L1694) |
| Bu sitede QR ile giriş kapalı. | [lib/services/auth_api.dart:1690](../lib/services/auth_api.dart#L1690) |
| Bu sitede uygulamadan uzaktan kapı açma kapalı. | [lib/services/auth_api.dart:1688](../lib/services/auth_api.dart#L1688) |
| Bu sitede yerel ağdan kapı açma kapalı. | [lib/services/auth_api.dart:1696](../lib/services/auth_api.dart#L1696) |
| Bu sitenin konum çemberi hatalı tanımlanmış. Lütfen site yöneticinize başvurun. | [lib/services/auth_api.dart:1684](../lib/services/auth_api.dart#L1684) |
| Cihaz bulunamadı. | [lib/services/auth_api.dart:1728](../lib/services/auth_api.dart#L1728) |
| Cihaz sahiplenme sırasında bir hata oluştu. | [lib/ui/widgets/claim_device_dialog.dart:83](../lib/ui/widgets/claim_device_dialog.dart#L83) |
| Cihaz şu an çevrimdışı. Cihazın internet bağlantısını kontrol edin. | [lib/services/auth_api.dart:1720](../lib/services/auth_api.dart#L1720) |
| Cihazlar yüklenirken bir sorun oluştu. | [lib/ui/views/individual_home_view.dart:173](../lib/ui/views/individual_home_view.dart#L173) |
| Çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:1660](../lib/services/auth_api.dart#L1660) |
| Doğrulama işlemi sırasında hata oluştu. | [lib/services/auth_service.dart:289](../lib/services/auth_service.dart#L289) |
| Geçersiz kapı bilgisi. | [lib/services/auth_api.dart:1712](../lib/services/auth_api.dart#L1712) |
| Giriş oturumu bulunamadı. | [lib/ui/widgets/door_logs_accordion.dart:76](../lib/ui/widgets/door_logs_accordion.dart#L76) |
| GPS doğruluğu yetersiz. Açık alana çıkıp tekrar deneyin. | [lib/services/auth_api.dart:1675](../lib/services/auth_api.dart#L1675) |
| GPS doğruluğu yetersiz$acc. Lütfen açık alana çıkıp tekrar deneyin. | [lib/services/geofence_service.dart:86](../lib/services/geofence_service.dart#L86) |
| GPS sinyali alınamadı (zaman aşımı). Açık alanda tekrar deneyin. | [lib/services/geofence_service.dart:126](../lib/services/geofence_service.dart#L126) |
| Hangi kapıyı açmamı istersiniz?$suffix Örneğin "1. kapıyı aç" veya kapının adını söyleyin. | [lib/services/voice_door_service.dart:494](../lib/services/voice_door_service.dart#L494) |
| Hata: $e | [lib/ui/widgets/device_connectivity_logs_accordion.dart:103](../lib/ui/widgets/device_connectivity_logs_accordion.dart#L103) |
| İşlem sırasında bir hata oluştu: $e | [lib/ui/dialogs/door_edit_dialog.dart:123](../lib/ui/dialogs/door_edit_dialog.dart#L123) |
| Kapı bulunamadı. | [lib/services/auth_api.dart:1714](../lib/services/auth_api.dart#L1714) |
| Kapı ekranındaki karekod henüz alınamadı. Birkaç saniye sonra tekrar deneyin. | [lib/services/auth_api.dart:1706](../lib/services/auth_api.dart#L1706) |
| Kapı konumunda değilsiniz. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:1682](../lib/services/auth_api.dart#L1682) |
| Kapıyı kapatma veya kilitleme komutu desteklenmiyor. Açmak için "kapıyı aç" deyin. | [lib/services/voice_door_service.dart:486](../lib/services/voice_door_service.dart#L486) |
| Karekodun süresi doldu. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:1704](../lib/services/auth_api.dart#L1704) |
| Kendi şifrenizi Profilim ekranından değiştirin. | [lib/services/auth_api.dart:1663](../lib/services/auth_api.dart#L1663) |
| Kod tekrar gönderilemedi. | [lib/services/auth_service.dart:302](../lib/services/auth_service.dart#L302) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/auth_api.dart:1673](../lib/services/auth_api.dart#L1673) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/geofence_service.dart:88](../lib/services/geofence_service.dart#L88) |
| Konum bilgisi geçersiz. GPS'i kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:1669](../lib/services/auth_api.dart#L1669) |
| Konum izni kalıcı olarak engellenmiş. Ayarlardan izin verin. | [lib/services/geofence_service.dart:119](../lib/services/geofence_service.dart#L119) |
| Konum izni verilmedi. Güvenlik için konum gereklidir. | [lib/services/geofence_service.dart:115](../lib/services/geofence_service.dart#L115) |
| Konum izni verilmedi. Güvenlik için konum gereklidir. | [lib/services/geofence_service.dart:132](../lib/services/geofence_service.dart#L132) |
| Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın. | [lib/services/geofence_service.dart:108](../lib/services/geofence_service.dart#L108) |
| Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın. | [lib/services/geofence_service.dart:129](../lib/services/geofence_service.dart#L129) |
| Lütfen blok ve daire seçiniz. | [lib/ui/dialogs/submit_join_request_dialog.dart:119](../lib/ui/dialogs/submit_join_request_dialog.dart#L119) |
| Lütfen geçerli bir cihaz QR kodu veya Seri No giriniz. | [lib/ui/widgets/claim_device_dialog.dart:54](../lib/ui/widgets/claim_device_dialog.dart#L54) |
| Lütfen yeni cihazın QR kodunu okutun veya seri numarasını girin. | [lib/ui/dialogs/replace_device_dialog.dart:105](../lib/ui/dialogs/replace_device_dialog.dart#L105) |
| Mevcut şifre için çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:1658](../lib/services/auth_api.dart#L1658) |
| Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:1656](../lib/services/auth_api.dart#L1656) |
| Okutulan karekod geçersiz. | [lib/services/auth_api.dart:1708](../lib/services/auth_api.dart#L1708) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:1883](../lib/services/auth_service.dart#L1883) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:1987](../lib/services/auth_service.dart#L1987) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/auth_api.dart:1671](../lib/services/auth_api.dart#L1671) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/geofence_service.dart:81](../lib/services/geofence_service.dart#L81) |
| Site kurulumu sırasında bir hata oluştu. | [lib/ui/dialogs/setup_site_dialog.dart:208](../lib/ui/dialogs/setup_site_dialog.dart#L208) |
| SSL baglantisi kurulurken hata olustu. | [lib/services/auth_api.dart:1800](../lib/services/auth_api.dart#L1800) |
| Sunucu baglantisinda istemci hatasi olustu. | [lib/services/auth_api.dart:1808](../lib/services/auth_api.dart#L1808) |
| Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:1790](../lib/services/auth_api.dart#L1790) |
| Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:1792](../lib/services/auth_api.dart#L1792) |
| Sunucunun cihaz bağlantısı şu an hazır değil. Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:1718](../lib/services/auth_api.dart#L1718) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:244](../lib/services/auth_service.dart#L244) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:506](../lib/services/auth_service.dart#L506) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:637](../lib/services/auth_service.dart#L637) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:673](../lib/services/auth_service.dart#L673) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:697](../lib/services/auth_service.dart#L697) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:714](../lib/services/auth_service.dart#L714) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:810](../lib/services/auth_service.dart#L810) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:840](../lib/services/auth_service.dart#L840) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:884](../lib/services/auth_service.dart#L884) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1172](../lib/services/auth_service.dart#L1172) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1193](../lib/services/auth_service.dart#L1193) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1404](../lib/services/auth_service.dart#L1404) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1846](../lib/services/auth_service.dart#L1846) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1870](../lib/services/auth_service.dart#L1870) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1929](../lib/services/auth_service.dart#L1929) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1997](../lib/services/auth_service.dart#L1997) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:265](../lib/services/auth_service.dart#L265) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:517](../lib/services/auth_service.dart#L517) |
| Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin. | [lib/services/auth_api.dart:1806](../lib/services/auth_api.dart#L1806) |
| Şifrenizi değiştirmek için mevcut şifrenizi girin. | [lib/services/auth_service.dart:1888](../lib/services/auth_service.dart#L1888) |
| Şifrenizi değiştirmek için mevcut şifrenizi girmelisiniz. | [lib/services/auth_api.dart:1654](../lib/services/auth_api.dart#L1654) |
| Tanımlı bir kapı bulunamadı. | [lib/services/voice_door_service.dart:498](../lib/services/voice_door_service.dart#L498) |
| Yetkilendirme servisi bulunamadı. | [lib/ui/widgets/dynamic_qr_pass_modal.dart:423](../lib/ui/widgets/dynamic_qr_pass_modal.dart#L423) |


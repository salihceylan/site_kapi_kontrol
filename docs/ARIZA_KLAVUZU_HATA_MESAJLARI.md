# Hata mesajı → kaynak (otomatik)

> Kullanıcıya/istemciye görünen metinleri üretildikleri `dosya:satır` ile eşler. `Ctrl+F` ile ekranda gördüğünüz mesajın bir parçasını arayın. Koddan otomatik üretilir: `node tools/klavuz/build.mjs`. Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).

## Sunucu mesajları (597)

Kaynak: `server/src` (`error:`, `message:`, `httpError(...)`, `new Error(...)`). Uygulama bu metinleri HTTP yanıt gövdesinde (`error` alanı) alır.

| Mesaj | Dosya:satır |
| --- | --- |
| "${bName}" blok adı birden fazla kez kullanılmış. Blok adları benzersiz olmalıdır. | [server/src/services/membership_rules.js:473](../server/src/services/membership_rules.js#L473) |
| "${site.name}" sitesi, ${createdBlocks.length} blok ve ${totalApartmentCount} daire ile başarıyla kuruldu! | [server/src/services/membership_service.js:944](../server/src/services/membership_service.js#L944) |
| "${siteName}" sitesi ${apt.block_name \|\| ''} ${apt.unit_label} için katılım başvurunuz başarıyla oluşturuldu. Site yöneticisinin onayı bekleniyor. | [server/src/services/membership_service.js:1135](../server/src/services/membership_service.js#L1135) |
| <Türkçe mesaj> | [server/src/modules/module_request_routes.js:9](../server/src/modules/module_request_routes.js#L9) |
| <Türkçe mesaj> | [server/src/modules/module_routes.js:14](../server/src/modules/module_routes.js#L14) |
| ${deviceUid} kodlu cihaz ve karekodu basariyla silindi. | [server/src/routes/company_routes.js:430](../server/src/routes/company_routes.js#L430) |
| ${field.body} alani true/false olmalidir. | [server/src/utils/site_rules.js:306](../server/src/utils/site_rules.js#L306) |
| ${fieldName} alanı true/false olmalıdır. | [server/src/services/membership_service.js:1811](../server/src/services/membership_service.js#L1811) |
| ${label} ${min} ile ${max} arasında bir tamsayı olmalıdır. | [server/src/services/membership_rules.js:427](../server/src/services/membership_rules.js#L427) |
| ${name} env degiskeni eksik. | [server/src/mailer.js:6](../server/src/mailer.js#L6) |
| ${pass.door_name} aciliyor. | [server/src/routes/guest_passes_routes.js:463](../server/src/routes/guest_passes_routes.js#L463) |
| ${req.full_name} sakini, "${req.block_name \|\| ''} ${req.unit_label}" dairesine ${assignedRole === 'APARTMENT_ADMIN' ? 'Daire Yöneticisi' : 'Aile Üyesi'} olarak başarıyla onaylandı. | [server/src/services/membership_service.js:1396](../server/src/services/membership_service.js#L1396) |
| ${result.revoked_count} aktif karekod basariyla iptal edildi. | [server/src/routes/manager_routes.js:1060](../server/src/routes/manager_routes.js#L1060) |
| ${targetUserCodes.length} sakin için kapı yetkisi ${actionText}. | [server/src/services/membership_service.js:2598](../server/src/services/membership_service.js#L2598) |
| Abonelik talebiniz onay bekliyor. | [server/src/middlewares/auth_middleware.js:85](../server/src/middlewares/auth_middleware.js#L85) |
| Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:742](../server/src/routes/auth_routes.js#L742) |
| Abonelik talebiniz reddedildi. | [server/src/middlewares/auth_middleware.js:88](../server/src/middlewares/auth_middleware.js#L88) |
| Abonelik talebiniz reddedildi. | [server/src/routes/auth_routes.js:745](../server/src/routes/auth_routes.js#L745) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:613](../server/src/routes/admin_routes.js#L613) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:773](../server/src/routes/admin_routes.js#L773) |
| Ad ve soyad alanları zorunludur. | [server/src/services/membership_service.js:228](../server/src/services/membership_service.js#L228) |
| Ad ve soyad en fazla ${NAME_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:231](../server/src/services/membership_service.js#L231) |
| Aile Reisi (Daire Yöneticisi) başarıyla değiştirildi. | [server/src/services/membership_service.js:2186](../server/src/services/membership_service.js#L2186) |
| Aktif bir doğrulama kodu bulunamadı. Lütfen yeni kod talep ediniz. | [server/src/services/membership_rules.js:67](../server/src/services/membership_rules.js#L67) |
| audit action zorunlu | [server/src/modules/audit_service.js:59](../server/src/modules/audit_service.js#L59) |
| Bekleyen abonelik talebi bulunamadi. | [server/src/routes/admin_routes.js:646](../server/src/routes/admin_routes.js#L646) |
| Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz. | [server/src/services/membership_service.js:394](../server/src/services/membership_service.js#L394) |
| Bekleyen site talebi bulunamadi. | [server/src/routes/admin_routes.js:779](../server/src/routes/admin_routes.js#L779) |
| Belirtilen cihaz hesabınıza ait değil. | [server/src/services/membership_service.js:780](../server/src/services/membership_service.js#L780) |
| Bos olmayan bloklar varken blok sayisi azaltilamaz. | [server/src/services/site_service.js:1173](../server/src/services/site_service.js#L1173) |
| Boylam -180 ile 180 arasinda olmalidir. | [server/src/utils/site_rules.js:331](../server/src/utils/site_rules.js#L331) |
| Bu cihaz arizali olarak isaretlenmis. | [server/src/utils/site_rules.js:482](../server/src/utils/site_rules.js#L482) |
| Bu cihaz baska bir kullanici hesabi tarafindan sahiplenilmis. | [server/src/utils/site_rules.js:480](../server/src/utils/site_rules.js#L480) |
| Bu cihaz icin log gonderme yetkiniz yok. | [server/src/routes/door_log_routes.js:248](../server/src/routes/door_log_routes.js#L248) |
| Bu cihaz şirket envanterinde arızalı olarak işaretlenmiştir. Lütfen şirket yetkilisiyle iletişime geçiniz. | [server/src/services/membership_service.js:642](../server/src/services/membership_service.js#L642) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/routes/admin_routes.js:1243](../server/src/routes/admin_routes.js#L1243) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/utils/site_rules.js:477](../server/src/utils/site_rules.js#L477) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:614](../server/src/services/membership_service.js#L614) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:637](../server/src/services/membership_service.js#L637) |
| Bu cihazin unique id kayitli. | [server/src/utils/validators.js:396](../server/src/utils/validators.js#L396) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:696](../server/src/routes/manager_routes.js#L696) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:749](../server/src/routes/manager_routes.js#L749) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:779](../server/src/routes/manager_routes.js#L779) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1597](../server/src/services/membership_service.js#L1597) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1637](../server/src/services/membership_service.js#L1637) |
| Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz. | [server/src/services/membership_service.js:379](../server/src/services/membership_service.js#L379) |
| Bu e-posta adresi için çok fazla kod istendi. Lütfen daha sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:116](../server/src/services/membership_rules.js#L116) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:245](../server/src/services/membership_service.js#L245) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:408](../server/src/services/membership_service.js#L408) |
| Bu e-posta baska bir rol icin kayitli. | [server/src/routes/auth_routes.js:575](../server/src/routes/auth_routes.js#L575) |
| Bu e-posta ile onaylanmis bir hesap zaten var. Giris yapin. | [server/src/routes/auth_routes.js:580](../server/src/routes/auth_routes.js#L580) |
| Bu e-posta zaten kayitli. | [server/src/utils/validators.js:353](../server/src/utils/validators.js#L353) |
| Bu gecis linki iptal edilmis. | [server/src/utils/guest_pass_utils.js:122](../server/src/utils/guest_pass_utils.js#L122) |
| Bu gecis linkinin suresi dolmus. | [server/src/utils/guest_pass_utils.js:123](../server/src/utils/guest_pass_utils.js#L123) |
| Bu gecisi olusturan kullanicinin kapiya yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:333](../server/src/routes/guest_passes_routes.js#L333) |
| Bu gecisi olusturan kullanicinin yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:320](../server/src/routes/guest_passes_routes.js#L320) |
| Bu hedef icin OTA yayini yok. | [server/src/routes/firmware_routes.js:165](../server/src/routes/firmware_routes.js#L165) |
| Bu islem icin site yoneticisi yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:131](../server/src/middlewares/auth_middleware.js#L131) |
| Bu islem icin super user yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:102](../server/src/middlewares/auth_middleware.js#L102) |
| Bu işlem için yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1706](../server/src/services/site_service.js#L1706) |
| Bu işlem için yetkiniz yok. | [server/src/modules/people_access.js:13](../server/src/modules/people_access.js#L13) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1750](../server/src/services/site_service.js#L1750) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1832](../server/src/services/site_service.js#L1832) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen cihaz ekranındaki güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:319](../server/src/routes/app_doors_routes.js#L319) |
| Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır. | [server/src/services/qr_access_service.js:43](../server/src/services/qr_access_service.js#L43) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2222](../server/src/services/membership_service.js#L2222) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2243](../server/src/services/membership_service.js#L2243) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:136](../server/src/routes/app_doors_routes.js#L136) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:177](../server/src/routes/app_doors_routes.js#L177) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:299](../server/src/routes/app_doors_routes.js#L299) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/guest_passes_routes.js:287](../server/src/routes/guest_passes_routes.js#L287) |
| Bu kapiya gecis yetkiniz bulunmuyor. | [server/src/routes/app_doors_routes.js:294](../server/src/routes/app_doors_routes.js#L294) |
| Bu kapiyi silme yetkiniz yok. | [server/src/routes/manager_routes.js:1021](../server/src/routes/manager_routes.js#L1021) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:814](../server/src/routes/manager_routes.js#L814) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:856](../server/src/routes/manager_routes.js#L856) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:899](../server/src/routes/manager_routes.js#L899) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:988](../server/src/routes/manager_routes.js#L988) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1048](../server/src/routes/manager_routes.js#L1048) |
| Bu karekod daha once kullanildi. Lutfen cihaz ekraninda yenilenen guncel karekodu okutun. | [server/src/routes/app_doors_routes.js:336](../server/src/routes/app_doors_routes.js#L336) |
| Bu kişide kurul veya görevli rolü yok. | [server/src/modules/module_routes.js:193](../server/src/modules/module_routes.js#L193) |
| Bu kullanıcı zaten bu sitenin yöneticisidir. | [server/src/services/site_service.js:2056](../server/src/services/site_service.js#L2056) |
| Bu kullanıcı zaten daire yöneticisidir. | [server/src/services/membership_service.js:2140](../server/src/services/membership_service.js#L2140) |
| Bu kullanıcı zaten dairenin Aile Reisidir (Daire Yöneticisi). | [server/src/services/membership_service.js:2150](../server/src/services/membership_service.js#L2150) |
| Bu kullanici adi zaten kayitli. | [server/src/utils/validators.js:356](../server/src/utils/validators.js#L356) |
| Bu silme doğrulama kodu artık geçerli değil. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:1921](../server/src/services/site_service.js#L1921) |
| Bu silme talebini yalnızca ilgili sitenin yöneticisi onaylayabilir. | [server/src/services/site_service.js:1681](../server/src/services/site_service.js#L1681) |
| Bu silme talebini yalnızca Süper Kullanıcı onaylayabilir. | [server/src/services/site_service.js:1671](../server/src/services/site_service.js#L1671) |
| Bu site için bekleyen bir silme onayı bulunmamaktadır. | [server/src/services/site_service.js:1688](../server/src/services/site_service.js#L1688) |
| Bu site için bekleyen bir silme talebi bulunmuyor. | [server/src/services/site_service.js:1723](../server/src/services/site_service.js#L1723) |
| Bu site için talep edilmiş aktif bir silme doğrulama kodu bulunmuyor. | [server/src/services/site_service.js:1876](../server/src/services/site_service.js#L1876) |
| Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır. | [server/src/services/membership_service.js:1069](../server/src/services/membership_service.js#L1069) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/routes/membership_routes.js:142](../server/src/routes/membership_routes.js#L142) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/services/membership_service.js:1029](../server/src/services/membership_service.js#L1029) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/modules/people_access.js:15](../server/src/modules/people_access.js#L15) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/modules/route_helpers.js:44](../server/src/modules/route_helpers.js#L44) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1281](../server/src/routes/manager_routes.js#L1281) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1307](../server/src/routes/manager_routes.js#L1307) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1335](../server/src/routes/manager_routes.js#L1335) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1362](../server/src/routes/manager_routes.js#L1362) |
| Bu sitede karekod ile giris yonetim tarafindan gecici olarak durdurulmustur. | [server/src/services/door_access_policy.js:111](../server/src/services/door_access_policy.js#L111) |
| Bu sitede karekod ile kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:104](../server/src/services/door_access_policy.js#L104) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/routes/guest_passes_routes.js:275](../server/src/routes/guest_passes_routes.js#L275) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/services/door_access_policy.js:121](../server/src/services/door_access_policy.js#L121) |
| Bu sitede misafir/kurye gecis kodu olusturma kapalidir. | [server/src/routes/guest_passes_routes.js:79](../server/src/routes/guest_passes_routes.js#L79) |
| Bu sitede yerel ag uzerinden kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:131](../server/src/services/door_access_policy.js#L131) |
| Bu sitenin cihazlarini gorme yetkiniz yok. | [server/src/routes/manager_routes.js:1080](../server/src/routes/manager_routes.js#L1080) |
| Bu sitenin katılım taleplerini görme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1225](../server/src/services/membership_service.js#L1225) |
| Bu sitenin loglarini gorme yetkiniz yok. | [server/src/routes/door_log_routes.js:136](../server/src/routes/door_log_routes.js#L136) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2629](../server/src/services/membership_service.js#L2629) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2650](../server/src/services/membership_service.js#L2650) |
| Bu siteye kapi ekleme yetkiniz yok. | [server/src/routes/manager_routes.js:942](../server/src/routes/manager_routes.js#L942) |
| Bu siteyi silme yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1534](../server/src/services/site_service.js#L1534) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:226](../server/src/routes/manager_routes.js#L226) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:394](../server/src/routes/manager_routes.js#L394) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:527](../server/src/routes/manager_routes.js#L527) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:549](../server/src/routes/manager_routes.js#L549) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:574](../server/src/routes/manager_routes.js#L574) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1124](../server/src/routes/manager_routes.js#L1124) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:366](../server/src/routes/auth_routes.js#L366) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:384](../server/src/routes/auth_routes.js#L384) |
| Bu şifre sıfırlama bağlantısının süresi dolmuş (30 dakika). Lütfen mobil uygulamadan yeni bir bağlantı talep ediniz. | [server/src/routes/auth_routes.js:393](../server/src/routes/auth_routes.js#L393) |
| Bu talebi onaylama yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1331](../server/src/services/membership_service.js#L1331) |
| Bu talebi reddetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1440](../server/src/services/membership_service.js#L1440) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1337](../server/src/services/membership_service.js#L1337) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1446](../server/src/services/membership_service.js#L1446) |
| Bu tek kullanimlik gecis linki daha once kullanilmis. | [server/src/utils/guest_pass_utils.js:124](../server/src/utils/guest_pass_utils.js#L124) |
| Cihaz (${device.device_uid}) başarıyla şirket envanterine kaydedildi. | [server/src/routes/admin_routes.js:1505](../server/src/routes/admin_routes.js#L1505) |
| Cihaz (${deviceRow.device_uid}) başarıyla hesabınıza bağlandı! Artık bu cihaz ile site ve kapı kurulumu yapabilirsiniz. | [server/src/services/membership_service.js:655](../server/src/services/membership_service.js#L655) |
| Cihaz (${normalizedUid}) zaten şirket veritabanında kayıtlı. | [server/src/services/device_service.js:903](../server/src/services/device_service.js#L903) |
| Cihaz (${updated.device_uid}) sahipliği sıfırlandı ve şirket stokuna geri döndürüldü. | [server/src/routes/admin_routes.js:1570](../server/src/routes/admin_routes.js#L1570) |
| Cihaz atamasi olan kapilar varken kapi sayisi azaltilamaz. | [server/src/services/site_service.js:1155](../server/src/services/site_service.js#L1155) |
| Cihaz basariyla degistirildi. Kapi yetkileri ve ayarlari aynen korundu. | [server/src/routes/manager_routes.js:913](../server/src/routes/manager_routes.js#L913) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:971](../server/src/services/device_service.js#L971) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:1010](../server/src/services/device_service.js#L1010) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1284](../server/src/routes/admin_routes.js#L1284) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1429](../server/src/routes/admin_routes.js#L1429) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1447](../server/src/routes/admin_routes.js#L1447) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1135](../server/src/routes/manager_routes.js#L1135) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1146](../server/src/routes/manager_routes.js#L1146) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1173](../server/src/routes/manager_routes.js#L1173) |
| Cihaz dogrulamasi gecici olarak yapilamadi. | [server/src/routes/firmware_routes.js:127](../server/src/routes/firmware_routes.js#L127) |
| Cihaz donanimi bu firmware hedefiyle uyusmuyor. | [server/src/routes/firmware_routes.js:144](../server/src/routes/firmware_routes.js#L144) |
| Cihaz ekranindaki guncel karekod henuz alinamadi. Birkac saniye sonra tekrar deneyin. | [server/src/routes/app_doors_routes.js:327](../server/src/routes/app_doors_routes.js#L327) |
| Cihaz kaydedildi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1512](../server/src/routes/admin_routes.js#L1512) |
| Cihaz online gorunmuyor. | [server/src/routes/app_doors_routes.js:69](../server/src/routes/app_doors_routes.js#L69) |
| Cihaz QR kodu veya seri numarası boş olamaz. | [server/src/services/membership_rules.js:300](../server/src/services/membership_rules.js#L300) |
| Cihaz QR kodu veya seri numarası çok uzun. | [server/src/services/membership_rules.js:303](../server/src/services/membership_rules.js#L303) |
| Cihaz sahiplenmek için önce e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:549](../server/src/services/membership_service.js#L549) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1454](../server/src/routes/admin_routes.js#L1454) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:1184](../server/src/routes/manager_routes.js#L1184) |
| Cihaz silinemedi. | [server/src/routes/admin_routes.js:1458](../server/src/routes/admin_routes.js#L1458) |
| Cihaz silinemedi. | [server/src/routes/company_routes.js:436](../server/src/routes/company_routes.js#L436) |
| Cihaz silme islemini yalnizca super user yapabilir. | [server/src/routes/manager_routes.js:1162](../server/src/routes/manager_routes.js#L1162) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1240](../server/src/routes/admin_routes.js#L1240) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1303](../server/src/routes/admin_routes.js#L1303) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:608](../server/src/routes/manager_routes.js#L608) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:612](../server/src/routes/manager_routes.js#L612) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:642](../server/src/routes/manager_routes.js#L642) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:647](../server/src/routes/manager_routes.js#L647) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:652](../server/src/routes/manager_routes.js#L652) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/utils/site_rules.js:476](../server/src/utils/site_rules.js#L476) |
| Cihaz sunucuya kaydedilemedi. | [server/src/routes/company_routes.js:368](../server/src/routes/company_routes.js#L368) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/admin_routes.js:1297](../server/src/routes/admin_routes.js#L1297) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:602](../server/src/routes/manager_routes.js#L602) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:636](../server/src/routes/manager_routes.js#L636) |
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
| Çok fazla hatalı doğrulama denemesi yapıldı. Kod iptal edildi; lütfen daha sonra yeni bir kod isteyiniz. | [server/src/services/site_service.js:1902](../server/src/services/site_service.js#L1902) |
| Çok fazla hatalı giriş denemesi. Hesap geçici olarak kilitlendi; lütfen 15 dakika sonra tekrar deneyin. | [server/src/routes/auth_routes.js:656](../server/src/routes/auth_routes.js#L656) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/people_routes.js:53](../server/src/modules/people_routes.js#L53) |
| Çok fazla kayıt işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/people_routes.js:43](../server/src/modules/people_routes.js#L43) |
| Çok fazla modül değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/module_routes.js:61](../server/src/modules/module_routes.js#L61) |
| Çok fazla modül talebi. Biraz sonra tekrar deneyin. | [server/src/modules/module_request_routes.js:35](../server/src/modules/module_request_routes.js#L35) |
| Çok fazla rol atama denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/module_routes.js:49](../server/src/modules/module_routes.js#L49) |
| Daire bilgileri e-posta ile gonderilemedi. | [server/src/routes/admin_routes.js:1211](../server/src/routes/admin_routes.js#L1211) |
| Daire bulunamadı. | [server/src/services/membership_service.js:1587](../server/src/services/membership_service.js#L1587) |
| Daire bulunamadı. | [server/src/services/membership_service.js:2041](../server/src/services/membership_service.js#L2041) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1163](../server/src/routes/admin_routes.js#L1163) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1185](../server/src/routes/admin_routes.js#L1185) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1203](../server/src/routes/admin_routes.js#L1203) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:693](../server/src/routes/manager_routes.js#L693) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:727](../server/src/routes/manager_routes.js#L727) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:746](../server/src/routes/manager_routes.js#L746) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:760](../server/src/routes/manager_routes.js#L760) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:776](../server/src/routes/manager_routes.js#L776) |
| Daire kullanicisi e-postasi uretilirken cakisma oldu. | [server/src/utils/validators.js:373](../server/src/utils/validators.js#L373) |
| Daire kullanicisi hesabi uretilemedi. | [server/src/utils/validators.js:382](../server/src/utils/validators.js#L382) |
| Daire kullanicisi hesabi uretilirken kullanici adi cakismasi oldu. | [server/src/utils/validators.js:376](../server/src/utils/validators.js#L376) |
| Daire sakini sifirlanamadi. | [server/src/routes/admin_routes.js:1187](../server/src/routes/admin_routes.js#L1187) |
| Daire sakini sifirlandi. | [server/src/routes/admin_routes.js:1182](../server/src/routes/admin_routes.js#L1182) |
| Daire sakini sifirlandi. | [server/src/routes/manager_routes.js:757](../server/src/routes/manager_routes.js#L757) |
| Daire sakininin şifresi başarıyla güncellendi. | [server/src/services/membership_service.js:2106](../server/src/services/membership_service.js#L2106) |
| Daire yöneticisi kendi durumunu pasife alamaz. | [server/src/services/membership_service.js:1827](../server/src/services/membership_service.js#L1827) |
| Daire yöneticisi kendi kendisini daireden çıkaramaz. | [server/src/services/membership_service.js:1745](../server/src/services/membership_service.js#L1745) |
| Desteklenmeyen karakter kumesi. | [server/src/middlewares/error_handler.js:30](../server/src/middlewares/error_handler.js#L30) |
| Desteklenmeyen kodlama. | [server/src/middlewares/error_handler.js:29](../server/src/middlewares/error_handler.js#L29) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:292](../server/src/routes/company_routes.js#L292) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:381](../server/src/routes/company_routes.js#L381) |
| device_uid zorunlu. | [server/src/routes/door_log_routes.js:229](../server/src/routes/door_log_routes.js#L229) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:289](../server/src/routes/company_routes.js#L289) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:377](../server/src/routes/company_routes.js#L377) |
| Dogrulama kodu tekrar e-posta adresinize gonderildi. | [server/src/routes/auth_routes.js:597](../server/src/routes/auth_routes.js#L597) |
| Doğrulama isteği şu an işlenemiyor. Lütfen biraz sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:76](../server/src/services/membership_rules.js#L76) |
| Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır. | [server/src/services/membership_service.js:329](../server/src/services/membership_service.js#L329) |
| E-posta adresi gereklidir. | [server/src/routes/auth_routes.js:92](../server/src/routes/auth_routes.js#L92) |
| E-posta adresi gereklidir. | [server/src/services/membership_service.js:481](../server/src/services/membership_service.js#L481) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/admin_routes.js:363](../server/src/routes/admin_routes.js#L363) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/auth_routes.js:820](../server/src/routes/auth_routes.js#L820) |
| E-posta adresiniz başarıyla doğrulandı. Hesabınız aktif! | [server/src/services/membership_service.js:464](../server/src/services/membership_service.js#L464) |
| E-posta adresiniz dogrulanmadi. | [server/src/middlewares/auth_middleware.js:82](../server/src/middlewares/auth_middleware.js#L82) |
| E-posta adresiniz dogrulanmadi. | [server/src/routes/auth_routes.js:739](../server/src/routes/auth_routes.js#L739) |
| E-posta ve doğrulama kodu zorunludur. | [server/src/services/membership_service.js:323](../server/src/services/membership_service.js#L323) |
| E-posta zaten dogrulanmis. Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:584](../server/src/routes/auth_routes.js#L584) |
| email ve password zorunlu. | [server/src/routes/auth_routes.js:671](../server/src/routes/auth_routes.js#L671) |
| email_verified alani true/false olmali. | [server/src/routes/admin_routes.js:319](../server/src/routes/admin_routes.js#L319) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/routes/admin_routes.js:1000](../server/src/routes/admin_routes.js#L1000) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/utils/site_rules.js:415](../server/src/utils/site_rules.js#L415) |
| En fazla ${SITE_LIMITS.maxBlocks} blok tanımlanabilir. | [server/src/services/membership_rules.js:463](../server/src/services/membership_rules.js#L463) |
| En fazla ${SITE_LIMITS.maxDoors} kapı tanımlanabilir. | [server/src/services/membership_rules.js:494](../server/src/services/membership_rules.js#L494) |
| Enlem -90 ile 90 arasinda olmalidir. | [server/src/utils/site_rules.js:325](../server/src/utils/site_rules.js#L325) |
| Etiketli cihazlar okunamadi. | [server/src/routes/company_routes.js:274](../server/src/routes/company_routes.js#L274) |
| feature_* alanlari true/false olmali. | [server/src/routes/admin_routes.js:988](../server/src/routes/admin_routes.js#L988) |
| Firmware dosyasi bulunamadi. | [server/src/routes/firmware_routes.js:240](../server/src/routes/firmware_routes.js#L240) |
| Firmware manifest okunamadi. | [server/src/routes/firmware_routes.js:221](../server/src/routes/firmware_routes.js#L221) |
| full_name en az 3 karakter olmali. | [server/src/routes/admin_routes.js:313](../server/src/routes/admin_routes.js#L313) |
| Gecerli bir kapi secin. | [server/src/utils/guest_pass_utils.js:43](../server/src/utils/guest_pass_utils.js#L43) |
| Gecersiz approval_status degeri. | [server/src/routes/admin_routes.js:666](../server/src/routes/admin_routes.js#L666) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:937](../server/src/routes/manager_routes.js#L937) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:975](../server/src/routes/manager_routes.js#L975) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1368](../server/src/routes/admin_routes.js#L1368) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1441](../server/src/routes/admin_routes.js#L1441) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1527](../server/src/routes/admin_routes.js#L1527) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1560](../server/src/routes/admin_routes.js#L1560) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:887](../server/src/routes/manager_routes.js#L887) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1102](../server/src/routes/manager_routes.js#L1102) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1167](../server/src/routes/manager_routes.js#L1167) |
| Gecersiz cihaz unique id. | [server/src/routes/admin_routes.js:1271](../server/src/routes/admin_routes.js#L1271) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1120](../server/src/routes/admin_routes.js#L1120) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1173](../server/src/routes/admin_routes.js#L1173) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1195](../server/src/routes/admin_routes.js#L1195) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:680](../server/src/routes/manager_routes.js#L680) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:740](../server/src/routes/manager_routes.js#L740) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:770](../server/src/routes/manager_routes.js#L770) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:246](../server/src/routes/company_routes.js#L246) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:250](../server/src/routes/company_routes.js#L250) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:325](../server/src/routes/company_routes.js#L325) |
| Gecersiz firmware dosyasi. | [server/src/routes/firmware_routes.js:230](../server/src/routes/firmware_routes.js#L230) |
| Gecersiz firmware hedefi. | [server/src/routes/firmware_routes.js:114](../server/src/routes/firmware_routes.js#L114) |
| Gecersiz firmware yolu. | [server/src/routes/firmware_routes.js:237](../server/src/routes/firmware_routes.js#L237) |
| Gecersiz gecis id. | [server/src/routes/guest_passes_routes.js:196](../server/src/routes/guest_passes_routes.js#L196) |
| Gecersiz gecis kodu. | [server/src/routes/guest_passes_routes.js:224](../server/src/routes/guest_passes_routes.js#L224) |
| Gecersiz gecis suresi. | [server/src/utils/guest_pass_utils.js:62](../server/src/utils/guest_pass_utils.js#L62) |
| Gecersiz gecis turu. | [server/src/utils/guest_pass_utils.js:53](../server/src/utils/guest_pass_utils.js#L53) |
| Gecersiz istek akisi. | [server/src/middlewares/error_handler.js:31](../server/src/middlewares/error_handler.js#L31) |
| Gecersiz istek boyutu. | [server/src/middlewares/error_handler.js:28](../server/src/middlewares/error_handler.js#L28) |
| Gecersiz istek govdesi. | [server/src/middlewares/error_handler.js:26](../server/src/middlewares/error_handler.js#L26) |
| Gecersiz JSON govdesi. | [server/src/middlewares/error_handler.js:25](../server/src/middlewares/error_handler.js#L25) |
| Gecersiz kapi acma kanali. | [server/src/services/door_access_policy.js:61](../server/src/services/door_access_policy.js#L61) |
| Gecersiz kapi ID. | [server/src/routes/admin_routes.js:1219](../server/src/routes/admin_routes.js#L1219) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:803](../server/src/routes/manager_routes.js#L803) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:847](../server/src/routes/manager_routes.js#L847) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:876](../server/src/routes/manager_routes.js#L876) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:966](../server/src/routes/manager_routes.js#L966) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1012](../server/src/routes/manager_routes.js#L1012) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1039](../server/src/routes/manager_routes.js#L1039) |
| Gecersiz kapi id. | [server/src/routes/app_doors_routes.js:40](../server/src/routes/app_doors_routes.js#L40) |
| Gecersiz karekod verisi. | [server/src/routes/app_doors_routes.js:265](../server/src/routes/app_doors_routes.js#L265) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:295](../server/src/routes/admin_routes.js#L295) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:402](../server/src/routes/admin_routes.js#L402) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:432](../server/src/routes/admin_routes.js#L432) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:610](../server/src/routes/admin_routes.js#L610) |
| Gecersiz kullanim limiti. | [server/src/utils/guest_pass_utils.js:74](../server/src/utils/guest_pass_utils.js#L74) |
| Gecersiz parametreler. | [server/src/services/qr_access_service.js:24](../server/src/services/qr_access_service.js#L24) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:156](../server/src/routes/admin_routes.js#L156) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:316](../server/src/routes/admin_routes.js#L316) |
| Gecersiz rol. | [server/src/routes/auth_routes.js:674](../server/src/routes/auth_routes.js#L674) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:770](../server/src/routes/admin_routes.js#L770) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:837](../server/src/routes/admin_routes.js#L837) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:971](../server/src/routes/admin_routes.js#L971) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1022](../server/src/routes/admin_routes.js#L1022) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1040](../server/src/routes/admin_routes.js#L1040) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1055](../server/src/routes/admin_routes.js#L1055) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1070](../server/src/routes/admin_routes.js#L1070) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1085](../server/src/routes/admin_routes.js#L1085) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1100](../server/src/routes/admin_routes.js#L1100) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:221](../server/src/routes/manager_routes.js#L221) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:356](../server/src/routes/manager_routes.js#L356) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:477](../server/src/routes/manager_routes.js#L477) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:492](../server/src/routes/manager_routes.js#L492) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:507](../server/src/routes/manager_routes.js#L507) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:522](../server/src/routes/manager_routes.js#L522) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:544](../server/src/routes/manager_routes.js#L544) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:569](../server/src/routes/manager_routes.js#L569) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:927](../server/src/routes/manager_routes.js#L927) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:1075](../server/src/routes/manager_routes.js#L1075) |
| Gecersiz token. | [server/src/middlewares/auth_middleware.js:32](../server/src/middlewares/auth_middleware.js#L32) |
| Gecersiz veya suresi dolmus token. | [server/src/middlewares/auth_middleware.js:24](../server/src/middlewares/auth_middleware.js#L24) |
| Gecis baglantisi bulunamadi veya silinmis. | [server/src/routes/guest_passes_routes.js:263](../server/src/routes/guest_passes_routes.js#L263) |
| Gecis baglantisi su an baska bir istekle kullaniliyor. Lutfen tekrar deneyin. | [server/src/routes/guest_passes_routes.js:391](../server/src/routes/guest_passes_routes.js#L391) |
| Gecis bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:211](../server/src/routes/guest_passes_routes.js#L211) |
| Gecis iptal edildi. | [server/src/routes/guest_passes_routes.js:214](../server/src/routes/guest_passes_routes.js#L214) |
| Geçerli bir Cihaz Unique ID (UID) giriniz (12 haneli onaltılık, örn. D4C771A172E0). | [server/src/services/device_service.js:888](../server/src/services/device_service.js#L888) |
| Geçerli bir daire seçiniz. | [server/src/services/membership_service.js:986](../server/src/services/membership_service.js#L986) |
| Geçerli bir e-posta adresi gereklidir. | [server/src/services/site_service.js:2013](../server/src/services/site_service.js#L2013) |
| Geçerli bir e-posta adresi giriniz. | [server/src/routes/auth_routes.js:324](../server/src/routes/auth_routes.js#L324) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:234](../server/src/services/membership_service.js#L234) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:326](../server/src/services/membership_service.js#L326) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:484](../server/src/services/membership_service.js#L484) |
| Geçersiz blok kimliği. | [server/src/services/membership_service.js:2530](../server/src/services/membership_service.js#L2530) |
| Geçersiz blok seçimi. | [server/src/services/membership_service.js:991](../server/src/services/membership_service.js#L991) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:948](../server/src/services/device_service.js#L948) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:994](../server/src/services/device_service.js#L994) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:1577](../server/src/services/membership_service.js#L1577) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:2007](../server/src/services/membership_service.js#L2007) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:2523](../server/src/services/membership_service.js#L2523) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:322](../server/src/routes/membership_routes.js#L322) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:342](../server/src/routes/membership_routes.js#L342) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:370](../server/src/routes/membership_routes.js#L370) |
| Geçersiz kapı kimliği. | [server/src/services/membership_service.js:2200](../server/src/services/membership_service.js#L2200) |
| Geçersiz katılım tokeni. | [server/src/services/membership_service.js:977](../server/src/services/membership_service.js#L977) |
| Geçersiz kullanıcı kimliği. | [server/src/services/membership_service.js:1727](../server/src/services/membership_service.js#L1727) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:1485](../server/src/services/membership_service.js#L1485) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:2434](../server/src/services/membership_service.js#L2434) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1330](../server/src/routes/manager_routes.js#L1330) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1357](../server/src/routes/manager_routes.js#L1357) |
| Geçersiz parametreler. | [server/src/services/site_service.js:2190](../server/src/services/site_service.js#L2190) |
| Geçersiz site ID. | [server/src/routes/manager_routes.js:1206](../server/src/routes/manager_routes.js#L1206) |
| Geçersiz site ID. | [server/src/routes/membership_routes.js:397](../server/src/routes/membership_routes.js#L397) |
| Geçersiz site katılım kodu. | [server/src/routes/membership_routes.js:145](../server/src/routes/membership_routes.js#L145) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:1210](../server/src/services/membership_service.js#L1210) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:2608](../server/src/services/membership_service.js#L2608) |
| Geçersiz site kodu. | [server/src/modules/people_access.js:79](../server/src/modules/people_access.js#L79) |
| Geçersiz site kodu. | [server/src/modules/route_helpers.js:38](../server/src/modules/route_helpers.js#L38) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1276](../server/src/routes/manager_routes.js#L1276) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1299](../server/src/routes/manager_routes.js#L1299) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1526](../server/src/services/site_service.js#L1526) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1652](../server/src/services/site_service.js#L1652) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1699](../server/src/services/site_service.js#L1699) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1757](../server/src/services/site_service.js#L1757) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1839](../server/src/services/site_service.js#L1839) |
| Geçersiz sorgu parametresi. | [server/src/modules/module_request_routes.js:125](../server/src/modules/module_request_routes.js#L125) |
| Geçersiz sorgu parametresi. | [server/src/modules/module_routes.js:229](../server/src/modules/module_routes.js#L229) |
| Geçersiz şifre sıfırlama bağlantısı. Lütfen e-postanızdaki bağlantıyı kontrol ediniz. | [server/src/routes/auth_routes.js:360](../server/src/routes/auth_routes.js#L360) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1228](../server/src/routes/manager_routes.js#L1228) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1249](../server/src/routes/manager_routes.js#L1249) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1294](../server/src/services/membership_service.js#L1294) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1413](../server/src/services/membership_service.js#L1413) |
| Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır. | [server/src/services/membership_service.js:373](../server/src/services/membership_service.js#L373) |
| Girdiğiniz silme doğrulama kodu hatalı. | [server/src/services/site_service.js:1906](../server/src/services/site_service.js#L1906) |
| Giris bilgileri hatali. | [server/src/routes/auth_routes.js:729](../server/src/routes/auth_routes.js#L729) |
| Giris islemi basarisiz. | [server/src/routes/auth_routes.js:759](../server/src/routes/auth_routes.js#L759) |
| Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapilabilir. | [server/src/utils/site_rules.js:392](../server/src/utils/site_rules.js#L392) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:352](../server/src/routes/admin_routes.js#L352) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:876](../server/src/routes/admin_routes.js#L876) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/auth_routes.js:815](../server/src/routes/auth_routes.js#L815) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/manager_routes.js:389](../server/src/routes/manager_routes.js#L389) |
| Güncellenecek alan bulunamadı. | [server/src/services/door_service.js:679](../server/src/services/door_service.js#L679) |
| Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez. Kullanıcılar kendi şifrelerini hesaplarına giriş yaparak profil bölümünden değiştirmelidir. | [server/src/routes/admin_routes.js:371](../server/src/routes/admin_routes.js#L371) |
| hardware_type esp32_c3 veya esp32_wroom olmali. | [server/src/routes/admin_routes.js:1398](../server/src/routes/admin_routes.js#L1398) |
| Hesap aktif degil. | [server/src/middlewares/auth_middleware.js:79](../server/src/middlewares/auth_middleware.js#L79) |
| Hesap aktif degil. | [server/src/routes/auth_routes.js:748](../server/src/routes/auth_routes.js#L748) |
| Islem basarisiz. | [server/src/utils/guest_pass_utils.js:242](../server/src/utils/guest_pass_utils.js#L242) |
| Istek govdesi cok buyuk. | [server/src/middlewares/error_handler.js:24](../server/src/middlewares/error_handler.js#L24) |
| Istek govdesi cok buyuk. | [server/src/routes/door_log_routes.js:223](../server/src/routes/door_log_routes.js#L223) |
| Istek yarida kesildi. | [server/src/middlewares/error_handler.js:27](../server/src/middlewares/error_handler.js#L27) |
| İptal edilecek bekleyen davet bulunamadı. | [server/src/services/site_service.js:2328](../server/src/services/site_service.js#L2328) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:407](../server/src/routes/admin_routes.js#L407) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:1130](../server/src/routes/admin_routes.js#L1130) |
| is_active alani true/false olmali. | [server/src/routes/manager_routes.js:979](../server/src/routes/manager_routes.js#L979) |
| is_defective alani true/false olmali. | [server/src/routes/admin_routes.js:1531](../server/src/routes/admin_routes.js#L1531) |
| İşlem sırasında bir hata oluştu. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:406](../server/src/routes/auth_routes.js#L406) |
| Kapı adı boş olamaz. | [server/src/services/door_service.js:654](../server/src/services/door_service.js#L654) |
| Kapı adı zorunludur. | [server/src/services/door_service.js:580](../server/src/services/door_service.js#L580) |
| Kapı bulunamadı. | [server/src/services/membership_service.js:2212](../server/src/services/membership_service.js#L2212) |
| Kapı yetkisi varsayılan ayarlara döndürüldü. | [server/src/services/membership_service.js:2451](../server/src/services/membership_service.js#L2451) |
| Kapi adi zorunludur. | [server/src/routes/manager_routes.js:933](../server/src/routes/manager_routes.js#L933) |
| Kapi basariyla acildi. | [server/src/routes/app_doors_routes.js:407](../server/src/routes/app_doors_routes.js#L407) |
| Kapi bulunamadi veya erisim yetkiniz yok. | [server/src/services/qr_access_service.js:31](../server/src/services/qr_access_service.js#L31) |
| Kapi bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:67](../server/src/routes/guest_passes_routes.js#L67) |
| Kapi bulunamadi. | [server/src/routes/admin_routes.js:1237](../server/src/routes/admin_routes.js#L1237) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:133](../server/src/routes/app_doors_routes.js#L133) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:174](../server/src/routes/app_doors_routes.js#L174) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:431](../server/src/routes/app_doors_routes.js#L431) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:811](../server/src/routes/manager_routes.js#L811) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:853](../server/src/routes/manager_routes.js#L853) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:896](../server/src/routes/manager_routes.js#L896) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:985](../server/src/routes/manager_routes.js#L985) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1018](../server/src/routes/manager_routes.js#L1018) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1045](../server/src/routes/manager_routes.js#L1045) |
| Kapi bulunamadi. | [server/src/services/door_access_policy.js:68](../server/src/services/door_access_policy.js#L68) |
| Kapi bulunamadi. | [server/src/utils/site_rules.js:475](../server/src/utils/site_rules.js#L475) |
| Kapi cihazi su anda bagli degil. | [server/src/routes/guest_passes_routes.js:469](../server/src/routes/guest_passes_routes.js#L469) |
| Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:186](../server/src/middlewares/rate_limiters.js#L186) |
| Kapi loglari alinamadi. | [server/src/routes/door_log_routes.js:101](../server/src/routes/door_log_routes.js#L101) |
| Kapi loglari alinamadi. | [server/src/routes/door_log_routes.js:197](../server/src/routes/door_log_routes.js#L197) |
| Karekod dosyasi bulunamadi. | [server/src/routes/company_routes.js:253](../server/src/routes/company_routes.js#L253) |
| Karekod ile eslesen aktif bir kapi bulunamadi. | [server/src/routes/app_doors_routes.js:283](../server/src/routes/app_doors_routes.js#L283) |
| Karekod talebi çok sık yapıldı. Lütfen birkaç saniye bekleyip tekrar deneyiniz. | [server/src/middlewares/rate_limiters.js:192](../server/src/middlewares/rate_limiters.js#L192) |
| Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:341](../server/src/routes/app_doors_routes.js#L341) |
| Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:362](../server/src/routes/app_doors_routes.js#L362) |
| Katılım başvurusu reddedildi. | [server/src/services/membership_service.js:1469](../server/src/services/membership_service.js#L1469) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1315](../server/src/services/membership_service.js#L1315) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1424](../server/src/services/membership_service.js#L1424) |
| Kayit olusturuldu. E-posta adresinize gonderilen 6 haneli kodu girin. | [server/src/routes/auth_routes.js:625](../server/src/routes/auth_routes.js#L625) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:356](../server/src/routes/admin_routes.js#L356) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:410](../server/src/routes/admin_routes.js#L410) |
| Kendi hesabinizi silemezsiniz. | [server/src/routes/admin_routes.js:440](../server/src/routes/admin_routes.js#L440) |
| Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin. | [server/src/routes/admin_routes.js:327](../server/src/routes/admin_routes.js#L327) |
| Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur. | [server/src/utils/site_rules.js:462](../server/src/utils/site_rules.js#L462) |
| Konum yaricapi ${GEOFENCE_RADIUS_MIN} ile ${GEOFENCE_RADIUS_MAX} metre arasinda olmalidir. | [server/src/utils/site_rules.js:342](../server/src/utils/site_rules.js#L342) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_rules.js:352](../server/src/services/membership_rules.js#L352) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1767](../server/src/services/membership_service.js#L1767) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1857](../server/src/services/membership_service.js#L1857) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1956](../server/src/services/membership_service.js#L1956) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:2142](../server/src/services/membership_service.js#L2142) |
| Kullanıcı bu daireye ait değil. | [server/src/services/membership_service.js:2053](../server/src/services/membership_service.js#L2053) |
| Kullanıcı bu sitenin yöneticisi değil. | [server/src/utils/site_rules.js:172](../server/src/utils/site_rules.js#L172) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:545](../server/src/services/membership_service.js#L545) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:2460](../server/src/services/membership_service.js#L2460) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:756](../server/src/services/membership_service.js#L756) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:1012](../server/src/services/membership_service.js#L1012) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:2069](../server/src/services/membership_service.js#L2069) |
| Kullanıcı kodu (userCode) zorunludur. | [server/src/routes/membership_routes.js:346](../server/src/routes/membership_routes.js#L346) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:528](../server/src/services/membership_service.js#L528) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:719](../server/src/services/membership_service.js#L719) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:982](../server/src/services/membership_service.js#L982) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:1154](../server/src/services/membership_service.js#L1154) |
| Kullanıcı site yöneticiliğinden çıkarıldı. | [server/src/services/site_service.js:2305](../server/src/services/site_service.js#L2305) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/admin_routes.js:1209](../server/src/routes/admin_routes.js#L1209) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/manager_routes.js:789](../server/src/routes/manager_routes.js#L789) |
| Kullanici bulunamadi. | [server/src/middlewares/auth_middleware.js:61](../server/src/middlewares/auth_middleware.js#L61) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:386](../server/src/routes/admin_routes.js#L386) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:416](../server/src/routes/admin_routes.js#L416) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:514](../server/src/routes/admin_routes.js#L514) |
| Kullanici bulunamadi. | [server/src/routes/auth_routes.js:874](../server/src/routes/auth_routes.js#L874) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1404](../server/src/routes/admin_routes.js#L1404) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1481](../server/src/routes/admin_routes.js#L1481) |
| Kullanici ID sayisal olmali. | [server/src/routes/admin_routes.js:1383](../server/src/routes/admin_routes.js#L1383) |
| Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin. | [server/src/utils/validators.js:361](../server/src/utils/validators.js#L361) |
| Kullanici rolu ile secilen rol uyusmuyor. | [server/src/routes/auth_routes.js:736](../server/src/routes/auth_routes.js#L736) |
| Kullanici silinemedi. | [server/src/routes/admin_routes.js:536](../server/src/routes/admin_routes.js#L536) |
| Log senkronizasyonu basarisiz. | [server/src/routes/door_log_routes.js:267](../server/src/routes/door_log_routes.js#L267) |
| logs bir dizi olmali. | [server/src/routes/door_log_routes.js:232](../server/src/routes/door_log_routes.js#L232) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/routes/manager_routes.js:890](../server/src/routes/manager_routes.js#L890) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/utils/site_rules.js:485](../server/src/utils/site_rules.js#L485) |
| Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz. | [server/src/services/site_service.js:1858](../server/src/services/site_service.js#L1858) |
| Lütfen 6 haneli silme doğrulama kodunu giriniz. | [server/src/routes/admin_routes.js:1105](../server/src/routes/admin_routes.js#L1105) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/admin_routes.js:1206](../server/src/routes/admin_routes.js#L1206) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/manager_routes.js:786](../server/src/routes/manager_routes.js#L786) |
| Mevcut parola hatali. | [server/src/routes/auth_routes.js:859](../server/src/routes/auth_routes.js#L859) |
| Mevcut şifre hatalı. | [server/src/services/membership_service.js:2077](../server/src/services/membership_service.js#L2077) |
| Mevcut şifre zorunludur. | [server/src/services/membership_service.js:2032](../server/src/services/membership_service.js#L2032) |
| Mevcut yonetici kodu veya yeni yonetici bilgilerinden yalnizca biri gonderilmeli. | [server/src/routes/admin_routes.js:717](../server/src/routes/admin_routes.js#L717) |
| Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz. | [server/src/modules/module_routes.js:36](../server/src/modules/module_routes.js#L36) |
| MQTT ACL senkronu zaman asimina ugradi (${timeoutMs} ms). | [server/src/mqtt_acl_sync.js:208](../server/src/mqtt_acl_sync.js#L208) |
| MQTT baglantisi hazir degil. | [server/src/routes/admin_routes.js:1358](../server/src/routes/admin_routes.js#L1358) |
| MQTT baglantisi hazir degil. | [server/src/routes/app_doors_routes.js:65](../server/src/routes/app_doors_routes.js#L65) |
| MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1314](../server/src/routes/admin_routes.js#L1314) |
| MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:664](../server/src/routes/manager_routes.js#L664) |
| MQTT cihaz kimligi uretilemedi. | [server/src/routes/admin_routes.js:1318](../server/src/routes/admin_routes.js#L1318) |
| MQTT_SYNC_COMMAND tanimli degil. | [server/src/mqtt_acl_sync.js:169](../server/src/mqtt_acl_sync.js#L169) |
| MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS gecersiz karakter iceriyor. | [server/src/mqtt_acl_sync.js:182](../server/src/mqtt_acl_sync.js#L182) |
| OTA komutu gonderilemedi. | [server/src/routes/admin_routes.js:1360](../server/src/routes/admin_routes.js#L1360) |
| Oturum gecersiz. Lutfen tekrar giris yapin. | [server/src/middlewares/auth_middleware.js:73](../server/src/middlewares/auth_middleware.js#L73) |
| Parolayi degistirmek icin mevcut parolanizi girmelisiniz. | [server/src/routes/auth_routes.js:826](../server/src/routes/auth_routes.js#L826) |
| qr_entry_active alani true/false olmalidir. | [server/src/utils/site_rules.js:313](../server/src/utils/site_rules.js#L313) |
| qr_image_base64 gecerli bir PNG (en fazla 2 MB) olmalidir. | [server/src/routes/company_routes.js:299](../server/src/routes/company_routes.js#L299) |
| qr_rotation_seconds sayisal olmalidir. | [server/src/utils/site_rules.js:353](../server/src/utils/site_rules.js#L353) |
| require_geofence alani true/false olmalidir. | [server/src/utils/site_rules.js:319](../server/src/utils/site_rules.js#L319) |
| Route bulunamadi. | [server/src/middlewares/error_handler.js:100](../server/src/middlewares/error_handler.js#L100) |
| Sakin daireden başarıyla silindi. | [server/src/services/membership_service.js:1986](../server/src/services/membership_service.js#L1986) |
| Sakini kalıcı olarak silme yetkisi yalnızca site yöneticilerine aittir. | [server/src/services/membership_service.js:1934](../server/src/services/membership_service.js#L1934) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:710](../server/src/routes/admin_routes.js#L710) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:859](../server/src/routes/admin_routes.js#L859) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:315](../server/src/routes/manager_routes.js#L315) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:376](../server/src/routes/manager_routes.js#L376) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:945](../server/src/routes/manager_routes.js#L945) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:991](../server/src/routes/manager_routes.js#L991) |
| Secilen yeni cihaz bulunamadi. | [server/src/routes/manager_routes.js:917](../server/src/routes/manager_routes.js#L917) |
| Seçilen alanda aktif sakin bulunamadı. | [server/src/services/membership_service.js:2542](../server/src/services/membership_service.js#L2542) |
| Seçilen daire belirtilen bloğa ait değil. | [server/src/services/membership_service.js:1051](../server/src/services/membership_service.js#L1051) |
| Seçilen daire bulunamadı veya bu siteye ait değil. | [server/src/services/membership_service.js:1047](../server/src/services/membership_service.js#L1047) |
| Sıfırlama anahtarı (token) eksik. | [server/src/routes/auth_routes.js:418](../server/src/routes/auth_routes.js#L418) |
| Sifre 4 haneli sayisal olmali. | [server/src/services/apartment_service.js:184](../server/src/services/apartment_service.js#L184) |
| Sifre en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir. | [server/src/routes/auth_routes.js:805](../server/src/routes/auth_routes.js#L805) |
| Silme doğrulama kodu e-posta adresinize (${maskedEmail}) gönderildi. | [server/src/services/site_service.js:1813](../server/src/services/site_service.js#L1813) |
| Silme doğrulama kodunun 10 dakikalık süresi dolmuş. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:1882](../server/src/services/site_service.js#L1882) |
| Site adı en fazla ${SETUP_NAME_MAX} karakter olabilir. | [server/src/services/membership_rules.js:454](../server/src/services/membership_rules.js#L454) |
| Site adı zorunludur. | [server/src/services/membership_rules.js:451](../server/src/services/membership_rules.js#L451) |
| Site adi en az 2 karakter olmali. | [server/src/routes/admin_routes.js:862](../server/src/routes/admin_routes.js#L862) |
| Site bulunamadı. | [server/src/modules/people_access.js:18](../server/src/modules/people_access.js#L18) |
| Site bulunamadı. | [server/src/modules/route_helpers.js:15](../server/src/modules/route_helpers.js#L15) |
| Site bulunamadı. | [server/src/services/membership_service.js:2619](../server/src/services/membership_service.js#L2619) |
| Site bulunamadı. | [server/src/services/site_service.js:1468](../server/src/services/site_service.js#L1468) |
| Site bulunamadı. | [server/src/services/site_service.js:1485](../server/src/services/site_service.js#L1485) |
| Site bulunamadı. | [server/src/services/site_service.js:1545](../server/src/services/site_service.js#L1545) |
| Site bulunamadı. | [server/src/services/site_service.js:1663](../server/src/services/site_service.js#L1663) |
| Site bulunamadı. | [server/src/services/site_service.js:1716](../server/src/services/site_service.js#L1716) |
| Site bulunamadı. | [server/src/services/site_service.js:1767](../server/src/services/site_service.js#L1767) |
| Site bulunamadı. | [server/src/services/site_service.js:1869](../server/src/services/site_service.js#L1869) |
| Site bulunamadı. | [server/src/services/site_service.js:2020](../server/src/services/site_service.js#L2020) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:882](../server/src/routes/admin_routes.js#L882) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:994](../server/src/routes/admin_routes.js#L994) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1028](../server/src/routes/admin_routes.js#L1028) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:236](../server/src/routes/manager_routes.js#L236) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:399](../server/src/routes/manager_routes.js#L399) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:532](../server/src/routes/manager_routes.js#L532) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:559](../server/src/routes/manager_routes.js#L559) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:588](../server/src/routes/manager_routes.js#L588) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1407](../server/src/routes/admin_routes.js#L1407) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1484](../server/src/routes/admin_routes.js#L1484) |
| Site ID bulunamadi. | [server/src/routes/manager_routes.js:1120](../server/src/routes/manager_routes.js#L1120) |
| Site ID sayisal olmali. | [server/src/routes/admin_routes.js:1386](../server/src/routes/admin_routes.js#L1386) |
| Site katilim QR kodu basariyla yenilendi. Eski QR kodlar iptal edildi. | [server/src/routes/manager_routes.js:584](../server/src/routes/manager_routes.js#L584) |
| Site kaydini yalnizca super user guncelleyebilir. | [server/src/routes/manager_routes.js:351](../server/src/routes/manager_routes.js#L351) |
| Site kaydini yalnizca super user olusturabilir. | [server/src/routes/manager_routes.js:290](../server/src/routes/manager_routes.js#L290) |
| Site kodu olusturulurken cakisma oldu. | [server/src/utils/validators.js:379](../server/src/utils/validators.js#L379) |
| Site kurmak için önce bir cihaz sahiplenmelisiniz. | [server/src/services/membership_service.js:783](../server/src/services/membership_service.js#L783) |
| Site silme talebi başarıyla iptal edildi / reddedildi. | [server/src/services/site_service.js:1741](../server/src/services/site_service.js#L1741) |
| Site silme talebi oluşturuldu. Site yöneticisinin onayı gerekmektedir. | [server/src/services/site_service.js:1604](../server/src/services/site_service.js#L1604) |
| Site silme talebi oluşturuldu. Süper kullanıcının onayı gerekmektedir. | [server/src/services/site_service.js:1642](../server/src/services/site_service.js#L1642) |
| Site silme talebi zaten oluşturulmuş; Site Yöneticisinin onayı bekleniyor. | [server/src/services/site_service.js:1583](../server/src/services/site_service.js#L1583) |
| Site silme talebi zaten oluşturulmuş; Süper Kullanıcının onayı bekleniyor. | [server/src/services/site_service.js:1621](../server/src/services/site_service.js#L1621) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:817](../server/src/routes/manager_routes.js#L817) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:1127](../server/src/routes/manager_routes.js#L1127) |
| Site talebi baska bir islemle zaten sonuclandirildi. | [server/src/routes/admin_routes.js:824](../server/src/routes/admin_routes.js#L824) |
| Site ve bağlı tüm kayıtlar başarıyla silindi. | [server/src/services/site_service.js:1517](../server/src/services/site_service.js#L1517) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/helpers.js:591](../server/src/utils/helpers.js#L591) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/validators.js:201](../server/src/utils/validators.js#L201) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:740](../server/src/routes/admin_routes.js#L740) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:897](../server/src/routes/admin_routes.js#L897) |
| Site yoneticisi kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:536](../server/src/routes/auth_routes.js#L536) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:638](../server/src/routes/auth_routes.js#L638) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:645](../server/src/routes/auth_routes.js#L645) |
| Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz. | [server/src/utils/site_rules.js:181](../server/src/utils/site_rules.js#L181) |
| Sitenin kurucu yöneticisi (Site Sahibi) yalnızca Süper Kullanıcı tarafından çıkarılabilir. | [server/src/utils/site_rules.js:189](../server/src/utils/site_rules.js#L189) |
| Siteye katılım başvurusu yapabilmek için e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:1016](../server/src/services/membership_service.js#L1016) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:94](../server/src/mailer.js#L94) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:138](../server/src/mailer.js#L138) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:170](../server/src/mailer.js#L170) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:204](../server/src/mailer.js#L204) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:249](../server/src/mailer.js#L249) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:320](../server/src/mailer.js#L320) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:380](../server/src/mailer.js#L380) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:448](../server/src/mailer.js#L448) |
| Süper kullanıcı hesabına kayıtlı bir e-posta adresi bulunamadı. | [server/src/services/site_service.js:1779](../server/src/services/site_service.js#L1779) |
| Şifre en az 4 karakter uzunluğunda olmalıdır. | [server/src/services/membership_service.js:2023](../server/src/services/membership_service.js#L2023) |
| Şifre en az 6 karakter olmalıdır. | [server/src/services/membership_service.js:237](../server/src/services/membership_service.js#L237) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:240](../server/src/services/membership_service.js#L240) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:2026](../server/src/services/membership_service.js#L2026) |
| Şifre güncellenemedi. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:486](../server/src/routes/auth_routes.js#L486) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:427](../server/src/routes/auth_routes.js#L427) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:442](../server/src/routes/auth_routes.js#L442) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:468](../server/src/routes/auth_routes.js#L468) |
| Şifre sıfırlama bağlantısının süresi dolmuş. Lütfen yeni bir talepte bulunun. | [server/src/routes/auth_routes.js:448](../server/src/routes/auth_routes.js#L448) |
| Şifreniz başarıyla güncellendi. Yeni şifrenizle giriş yapabilirsiniz. | [server/src/routes/auth_routes.js:481](../server/src/routes/auth_routes.js#L481) |
| Talep bulunamadı. | [server/src/modules/module_request_routes.js:39](../server/src/modules/module_request_routes.js#L39) |
| Tek istekte en fazla ${MAX_DEVICE_LOG_BATCH} kayit gonderilebilir. | [server/src/routes/door_log_routes.js:237](../server/src/routes/door_log_routes.js#L237) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:441](../server/src/services/qr_access_service.js#L441) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:469](../server/src/services/qr_access_service.js#L469) |
| Token parametresi zorunludur. | [server/src/routes/app_doors_routes.js:534](../server/src/routes/app_doors_routes.js#L534) |
| Token zorunludur. | [server/src/services/qr_access_service.js:436](../server/src/services/qr_access_service.js#L436) |
| Toplam daire sayısı en fazla ${SITE_LIMITS.maxApartments} olabilir. | [server/src/services/membership_rules.js:487](../server/src/services/membership_rules.js#L487) |
| Toplu yetkilendirme için blok, daire veya kullanıcı listesi belirtilmelidir. | [server/src/services/membership_service.js:2535](../server/src/services/membership_service.js#L2535) |
| Üye daireden başarıyla çıkarıldı. | [server/src/services/membership_service.js:1796](../server/src/services/membership_service.js#L1796) |
| Veritabanı sağlık bilgisi alınamadı. | [server/src/services/maintenance_service.js:206](../server/src/services/maintenance_service.js#L206) |
| Veritabanı temizliği başarısız oldu. | [server/src/services/maintenance_service.js:92](../server/src/services/maintenance_service.js#L92) |
| Veritabani saglik bilgisi alinamadi. | [server/src/routes/admin_routes.js:1586](../server/src/routes/admin_routes.js#L1586) |
| Veritabani temizligi sirasinda hata olustu. | [server/src/routes/admin_routes.js:1601](../server/src/routes/admin_routes.js#L1601) |
| Yeni kod istemek için lütfen ${seconds} saniye bekleyiniz. | [server/src/services/membership_rules.js:113](../server/src/services/membership_rules.js#L113) |
| Yeni kullanici kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:493](../server/src/routes/auth_routes.js#L493) |
| Yeni şifreniz en az 6 karakter olmalıdır. | [server/src/routes/auth_routes.js:421](../server/src/routes/auth_routes.js#L421) |
| Yeni şifreniz en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir. | [server/src/routes/auth_routes.js:424](../server/src/routes/auth_routes.js#L424) |
| Yetkisiz erisim. | [server/src/middlewares/auth_middleware.js:15](../server/src/middlewares/auth_middleware.js#L15) |
| Yetkisiz erisim. | [server/src/middlewares/company_auth.js:43](../server/src/middlewares/company_auth.js#L43) |
| Yetkisiz erisim. | [server/src/routes/admin_routes.js:437](../server/src/routes/admin_routes.js#L437) |
| Yetkisiz erisim. | [server/src/routes/auth_routes.js:774](../server/src/routes/auth_routes.js#L774) |
| Yetkisiz erisim. | [server/src/routes/manager_routes.js:295](../server/src/routes/manager_routes.js#L295) |
| Yönetici daveti iptal edildi. | [server/src/services/site_service.js:2335](../server/src/services/site_service.js#L2335) |
| Zaten bu dairenin aktif bir sakinisisiniz (${existingMemberRes.rows[0].role}). | [server/src/services/membership_service.js:1060](../server/src/services/membership_service.js#L1060) |

## Uygulama (Flutter) mesajları (137)

Kaynak: `lib` (`ApiException(...)`, `_errorMessage =`, `lib/services` içindeki `return '...'`).

| Mesaj | Dosya:satır |
| --- | --- |
| ${e.message} Kod 30 dakika geçerlidir; yeni kod için "Kodu Tekrar Gönder"e dokunun. | [lib/services/auth_service.dart:294](../lib/services/auth_service.dart#L294) |
| $distance m uzaktasınız, izin verilen mesafe $allowed m. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:2343](../lib/services/auth_api.dart#L2343) |
| $label verisi beklenen formatta degil. | [lib/services/auth_api.dart:2531](../lib/services/auth_api.dart#L2531) |
| $label verisi islenemedi. | [lib/services/auth_api.dart:2529](../lib/services/auth_api.dart#L2529) |
| $trimmed Lütfen ${formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/auth_api.dart:2246](../lib/services/auth_api.dart#L2246) |
| Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin. | [lib/services/voice_door_service.dart:508](../lib/services/voice_door_service.dart#L508) |
| Anlık konum alınamadı. Lütfen GPS'i kontrol edip tekrar deneyin. | [lib/services/geofence_service.dart:134](../lib/services/geofence_service.dart#L134) |
| Araç bulunamadı. | [lib/services/auth_api.dart:2278](../lib/services/auth_api.dart#L2278) |
| Bağlantı hatası: $e | [lib/ui/widgets/door_logs_accordion.dart:113](../lib/ui/widgets/door_logs_accordion.dart#L113) |
| Bluetooth islemi basarisiz oldu. | [lib/services/ble_wifi_provision_service.dart:521](../lib/services/ble_wifi_provision_service.dart#L521) |
| Bu cihaz arızalı olarak işaretlenmiş. | [lib/services/auth_api.dart:2389](../lib/services/auth_api.dart#L2389) |
| Bu cihaz başka bir hesaba ait. | [lib/services/auth_api.dart:2387](../lib/services/auth_api.dart#L2387) |
| Bu cihaz bu kapıya atanamaz. | [lib/services/auth_api.dart:2385](../lib/services/auth_api.dart#L2385) |
| Bu dairede bu ilişki için aktif bir kişi zaten var. | [lib/services/auth_api.dart:2434](../lib/services/auth_api.dart#L2434) |
| Bu e-posta ile kayıtlı bir kişi zaten var. | [lib/services/auth_api.dart:2430](../lib/services/auth_api.dart#L2430) |
| Bu e-posta ile kayıtlı hesap yok. | [lib/services/auth_api.dart:2408](../lib/services/auth_api.dart#L2408) |
| Bu hesap henüz etkin değil. | [lib/services/auth_api.dart:2410](../lib/services/auth_api.dart#L2410) |
| Bu ilişki artık güncel değil. | [lib/services/auth_api.dart:2282](../lib/services/auth_api.dart#L2282) |
| Bu isimde bir kapı bulunamadı. Lütfen kapının adını veya numarasını söyleyin. | [lib/services/voice_door_service.dart:503](../lib/services/voice_door_service.dart#L503) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:1620](../lib/services/auth_service.dart#L1620) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:1641](../lib/services/auth_service.dart#L1641) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:2494](../lib/services/auth_service.dart#L2494) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:632](../lib/services/auth_service.dart#L632) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:666](../lib/services/auth_service.dart#L666) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:696](../lib/services/auth_service.dart#L696) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:717](../lib/services/auth_service.dart#L717) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:804](../lib/services/auth_service.dart#L804) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:838](../lib/services/auth_service.dart#L838) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:1852](../lib/services/auth_service.dart#L1852) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:2303](../lib/services/auth_service.dart#L2303) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:2327](../lib/services/auth_service.dart#L2327) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:2475](../lib/services/auth_service.dart#L2475) |
| Bu islem icin yetkiniz bulunmamaktadir. | [lib/services/auth_service.dart:875](../lib/services/auth_service.dart#L875) |
| Bu işlem için yetkiniz yok. | [lib/services/auth_api.dart:2442](../lib/services/auth_api.dart#L2442) |
| Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin. | [lib/services/auth_api.dart:2330](../lib/services/auth_api.dart#L2330) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen kapı ekranındaki güncel karekodu okutun. | [lib/services/auth_api.dart:2363](../lib/services/auth_api.dart#L2363) |
| Bu kapıda QR ile giriş şu an devre dışı. | [lib/services/auth_api.dart:2355](../lib/services/auth_api.dart#L2355) |
| Bu kapıyı açma yetkiniz yok. | [lib/services/auth_api.dart:2379](../lib/services/auth_api.dart#L2379) |
| Bu karekod daha önce kullanıldı. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:2365](../lib/services/auth_api.dart#L2365) |
| Bu kişi zaten site yöneticisi. | [lib/services/auth_api.dart:2412](../lib/services/auth_api.dart#L2412) |
| Bu kişide kurul veya görevli rolü yok. | [lib/services/auth_api.dart:2416](../lib/services/auth_api.dart#L2416) |
| Bu modül için bekleyen bir talebiniz var. | [lib/services/auth_api.dart:2423](../lib/services/auth_api.dart#L2423) |
| Bu modül kapatılamaz. | [lib/services/auth_api.dart:2400](../lib/services/auth_api.dart#L2400) |
| Bu modül yakında. | [lib/services/auth_api.dart:2398](../lib/services/auth_api.dart#L2398) |
| Bu modül zaten açık. | [lib/services/auth_api.dart:2421](../lib/services/auth_api.dart#L2421) |
| Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir. | [lib/services/auth_api.dart:2396](../lib/services/auth_api.dart#L2396) |
| Bu plaka bu sitede zaten kayıtlı. | [lib/services/auth_api.dart:2440](../lib/services/auth_api.dart#L2440) |
| Bu platform MQTT TCP baglantisini desteklemiyor. | [lib/services/mqtt_door_service_stub.dart:41](../lib/services/mqtt_door_service_stub.dart#L41) |
| Bu sitede misafir geçişi kapalı. | [lib/services/auth_api.dart:2357](../lib/services/auth_api.dart#L2357) |
| Bu sitede QR ile giriş kapalı. | [lib/services/auth_api.dart:2353](../lib/services/auth_api.dart#L2353) |
| Bu sitede uygulamadan uzaktan kapı açma kapalı. | [lib/services/auth_api.dart:2351](../lib/services/auth_api.dart#L2351) |
| Bu sitede yerel ağdan kapı açma kapalı. | [lib/services/auth_api.dart:2359](../lib/services/auth_api.dart#L2359) |
| Bu sitenin konum çemberi hatalı tanımlanmış. Lütfen site yöneticinize başvurun. | [lib/services/auth_api.dart:2347](../lib/services/auth_api.dart#L2347) |
| Bu talep artık bekleyen durumda değil. | [lib/services/auth_api.dart:2427](../lib/services/auth_api.dart#L2427) |
| Bu yönetim türü yakında. | [lib/services/auth_api.dart:2404](../lib/services/auth_api.dart#L2404) |
| Cihaz bulunamadı. | [lib/services/auth_api.dart:2391](../lib/services/auth_api.dart#L2391) |
| Cihaz sahiplenme sırasında bir hata oluştu. | [lib/ui/widgets/claim_device_dialog.dart:83](../lib/ui/widgets/claim_device_dialog.dart#L83) |
| Cihaz şu an çevrimdışı. Cihazın internet bağlantısını kontrol edin. | [lib/services/auth_api.dart:2383](../lib/services/auth_api.dart#L2383) |
| Cihazlar yüklenirken bir sorun oluştu. | [lib/ui/views/individual_home_view.dart:173](../lib/ui/views/individual_home_view.dart#L173) |
| Çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:2323](../lib/services/auth_api.dart#L2323) |
| Çok fazla istek gönderildi. | [lib/services/auth_api.dart:2267](../lib/services/auth_api.dart#L2267) |
| Daire bulunamadı. | [lib/services/auth_api.dart:2436](../lib/services/auth_api.dart#L2436) |
| Doğrulama işlemi sırasında hata oluştu. | [lib/services/auth_service.dart:298](../lib/services/auth_service.dart#L298) |
| Geçersiz kapı bilgisi. | [lib/services/auth_api.dart:2375](../lib/services/auth_api.dart#L2375) |
| Geçersiz sorgu. Süzgeçleri kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:2272](../lib/services/auth_api.dart#L2272) |
| Geçersiz yönetim türü. | [lib/services/auth_api.dart:2406](../lib/services/auth_api.dart#L2406) |
| Giriş oturumu bulunamadı. | [lib/ui/widgets/door_logs_accordion.dart:76](../lib/ui/widgets/door_logs_accordion.dart#L76) |
| Gönderilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:2270](../lib/services/auth_api.dart#L2270) |
| GPS doğruluğu yetersiz. Açık alana çıkıp tekrar deneyin. | [lib/services/auth_api.dart:2338](../lib/services/auth_api.dart#L2338) |
| GPS doğruluğu yetersiz$acc. Lütfen açık alana çıkıp tekrar deneyin. | [lib/services/geofence_service.dart:86](../lib/services/geofence_service.dart#L86) |
| GPS sinyali alınamadı (zaman aşımı). Açık alanda tekrar deneyin. | [lib/services/geofence_service.dart:126](../lib/services/geofence_service.dart#L126) |
| Hangi kapıyı açmamı istersiniz?$suffix Örneğin "1. kapıyı aç" veya kapının adını söyleyin. | [lib/services/voice_door_service.dart:501](../lib/services/voice_door_service.dart#L501) |
| Hata: $e | [lib/ui/widgets/device_connectivity_logs_accordion.dart:103](../lib/ui/widgets/device_connectivity_logs_accordion.dart#L103) |
| Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir. | [lib/services/auth_api.dart:2432](../lib/services/auth_api.dart#L2432) |
| İlişki kaydı bulunamadı. | [lib/services/auth_api.dart:2280](../lib/services/auth_api.dart#L2280) |
| İşlem sırasında bir hata oluştu: $e | [lib/ui/dialogs/door_edit_dialog.dart:123](../lib/ui/dialogs/door_edit_dialog.dart#L123) |
| Kapı bulunamadı. | [lib/services/auth_api.dart:2377](../lib/services/auth_api.dart#L2377) |
| Kapı ekranındaki karekod henüz alınamadı. Birkaç saniye sonra tekrar deneyin. | [lib/services/auth_api.dart:2369](../lib/services/auth_api.dart#L2369) |
| Kapı konumunda değilsiniz. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:2345](../lib/services/auth_api.dart#L2345) |
| Kapıyı kapatma veya kilitleme komutu desteklenmiyor. Açmak için "kapıyı aç" deyin. | [lib/services/voice_door_service.dart:493](../lib/services/voice_door_service.dart#L493) |
| Karekodun süresi doldu. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:2367](../lib/services/auth_api.dart#L2367) |
| Kendi şifrenizi Profilim ekranından değiştirin. | [lib/services/auth_api.dart:2326](../lib/services/auth_api.dart#L2326) |
| Kişi bu dairede zaten kayıtlı. | [lib/services/auth_api.dart:2284](../lib/services/auth_api.dart#L2284) |
| Kişi bulunamadı. | [lib/services/auth_api.dart:2276](../lib/services/auth_api.dart#L2276) |
| Kod tekrar gönderilemedi. | [lib/services/auth_service.dart:311](../lib/services/auth_service.dart#L311) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/auth_api.dart:2336](../lib/services/auth_api.dart#L2336) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/geofence_service.dart:88](../lib/services/geofence_service.dart#L88) |
| Konum bilgisi geçersiz. GPS'i kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:2332](../lib/services/auth_api.dart#L2332) |
| Konum izni kalıcı olarak engellenmiş. Ayarlardan izin verin. | [lib/services/geofence_service.dart:119](../lib/services/geofence_service.dart#L119) |
| Konum izni verilmedi. Güvenlik için konum gereklidir. | [lib/services/geofence_service.dart:115](../lib/services/geofence_service.dart#L115) |
| Konum izni verilmedi. Güvenlik için konum gereklidir. | [lib/services/geofence_service.dart:132](../lib/services/geofence_service.dart#L132) |
| Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın. | [lib/services/geofence_service.dart:108](../lib/services/geofence_service.dart#L108) |
| Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın. | [lib/services/geofence_service.dart:129](../lib/services/geofence_service.dart#L129) |
| Lütfen blok ve daire seçiniz. | [lib/ui/dialogs/submit_join_request_dialog.dart:119](../lib/ui/dialogs/submit_join_request_dialog.dart#L119) |
| Lütfen geçerli bir cihaz QR kodu veya Seri No giriniz. | [lib/ui/widgets/claim_device_dialog.dart:54](../lib/ui/widgets/claim_device_dialog.dart#L54) |
| Lütfen yeni cihazın QR kodunu okutun veya seri numarasını girin. | [lib/ui/dialogs/replace_device_dialog.dart:105](../lib/ui/dialogs/replace_device_dialog.dart#L105) |
| Mevcut şifre için çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:2321](../lib/services/auth_api.dart#L2321) |
| Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:2319](../lib/services/auth_api.dart#L2319) |
| Modül bulunamadı. | [lib/services/auth_api.dart:2402](../lib/services/auth_api.dart#L2402) |
| Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz. | [lib/services/auth_api.dart:2419](../lib/services/auth_api.dart#L2419) |
| Okutulan karekod geçersiz. | [lib/services/auth_api.dart:2371](../lib/services/auth_api.dart#L2371) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:2354](../lib/services/auth_service.dart#L2354) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:2458](../lib/services/auth_service.dart#L2458) |
| Plaka biçimi geçersiz. | [lib/services/auth_api.dart:2438](../lib/services/auth_api.dart#L2438) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/auth_api.dart:2334](../lib/services/auth_api.dart#L2334) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/geofence_service.dart:81](../lib/services/geofence_service.dart#L81) |
| Site bulunamadı. | [lib/services/auth_api.dart:2287](../lib/services/auth_api.dart#L2287) |
| Site kurulumu sırasında bir hata oluştu. | [lib/ui/dialogs/setup_site_dialog.dart:214](../lib/ui/dialogs/setup_site_dialog.dart#L214) |
| SSL baglantisi kurulurken hata olustu. | [lib/services/auth_api.dart:2514](../lib/services/auth_api.dart#L2514) |
| Sunucu baglantisinda istemci hatasi olustu. | [lib/services/auth_api.dart:2522](../lib/services/auth_api.dart#L2522) |
| Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:2504](../lib/services/auth_api.dart#L2504) |
| Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:2506](../lib/services/auth_api.dart#L2506) |
| Sunucunun cihaz bağlantısı şu an hazır değil. Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:2381](../lib/services/auth_api.dart#L2381) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:253](../lib/services/auth_service.dart#L253) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:517](../lib/services/auth_service.dart#L517) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:650](../lib/services/auth_service.dart#L650) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:686](../lib/services/auth_service.dart#L686) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:710](../lib/services/auth_service.dart#L710) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:727](../lib/services/auth_service.dart#L727) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:825](../lib/services/auth_service.dart#L825) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:855](../lib/services/auth_service.dart#L855) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:899](../lib/services/auth_service.dart#L899) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1634](../lib/services/auth_service.dart#L1634) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1655](../lib/services/auth_service.dart#L1655) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1866](../lib/services/auth_service.dart#L1866) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2317](../lib/services/auth_service.dart#L2317) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2341](../lib/services/auth_service.dart#L2341) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2400](../lib/services/auth_service.dart#L2400) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2468](../lib/services/auth_service.dart#L2468) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:274](../lib/services/auth_service.dart#L274) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:528](../lib/services/auth_service.dart#L528) |
| Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin. | [lib/services/auth_api.dart:2520](../lib/services/auth_api.dart#L2520) |
| Şifrenizi değiştirmek için mevcut şifrenizi girin. | [lib/services/auth_service.dart:2359](../lib/services/auth_service.dart#L2359) |
| Şifrenizi değiştirmek için mevcut şifrenizi girmelisiniz. | [lib/services/auth_api.dart:2317](../lib/services/auth_api.dart#L2317) |
| Talep bulunamadı. | [lib/services/auth_api.dart:2425](../lib/services/auth_api.dart#L2425) |
| Tanımlı bir kapı bulunamadı. | [lib/services/voice_door_service.dart:505](../lib/services/voice_door_service.dart#L505) |
| Yetkilendirme servisi bulunamadı. | [lib/ui/widgets/dynamic_qr_pass_modal.dart:433](../lib/ui/widgets/dynamic_qr_pass_modal.dart#L433) |


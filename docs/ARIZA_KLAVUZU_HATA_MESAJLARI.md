# Hata mesajı → kaynak (otomatik)

> Kullanıcıya/istemciye görünen metinleri üretildikleri `dosya:satır` ile eşler. `Ctrl+F` ile ekranda gördüğünüz mesajın bir parçasını arayın. Koddan otomatik üretilir: `node tools/klavuz/build.mjs`. Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).

## Sunucu mesajları (772)

Kaynak: `server/src` (`error:`, `message:`, `httpError(...)`, `new Error(...)`). Uygulama bu metinleri HTTP yanıt gövdesinde (`error` alanı) alır.

| Mesaj | Dosya:satır |
| --- | --- |
| "${bName}" blok adı birden fazla kez kullanılmış. Blok adları benzersiz olmalıdır. | [server/src/services/membership_rules.js:481](../server/src/services/membership_rules.js#L481) |
| "${site.name}" sitesi, ${createdBlocks.length} blok ve ${totalApartmentCount} daire ile başarıyla kuruldu! | [server/src/services/membership_service.js:838](../server/src/services/membership_service.js#L838) |
| "${siteName}" sitesi ${apt.block_name \|\| ''} ${apt.unit_label} için katılım başvurunuz başarıyla oluşturuldu. Site yöneticisinin onayı bekleniyor. | [server/src/services/membership_service.js:1039](../server/src/services/membership_service.js#L1039) |
| <Türkçe mesaj> | [server/src/modules/account_common.js:4](../server/src/modules/account_common.js#L4) |
| <Türkçe mesaj> | [server/src/modules/module_request_routes.js:9](../server/src/modules/module_request_routes.js#L9) |
| <Türkçe mesaj> | [server/src/modules/module_routes.js:15](../server/src/modules/module_routes.js#L15) |
| <Türkçe mesaj> | [server/src/modules/site_application_routes.js:14](../server/src/modules/site_application_routes.js#L14) |
| ${debt?.site_name ?  | [server/src/modules/account_common.js:85](../server/src/modules/account_common.js#L85) |
| ${deviceUid} kodlu cihaz ve karekodu basariyla silindi. | [server/src/routes/company_routes.js:464](../server/src/routes/company_routes.js#L464) |
| ${field.body} alani true/false olmalidir. | [server/src/utils/site_rules.js:312](../server/src/utils/site_rules.js#L312) |
| ${fieldName} alanı true/false olmalıdır. | [server/src/services/membership_service.js:1722](../server/src/services/membership_service.js#L1722) |
| ${fileName}: front-matter (--- ... ---) bulunamadı | [server/src/modules/legal_documents.js:143](../server/src/modules/legal_documents.js#L143) |
| ${fileName}: geçersiz id | [server/src/modules/legal_documents.js:149](../server/src/modules/legal_documents.js#L149) |
| ${fileName}: geçersiz version | [server/src/modules/legal_documents.js:157](../server/src/modules/legal_documents.js#L157) |
| ${fileName}: title zorunlu (en çok 200 karakter) | [server/src/modules/legal_documents.js:153](../server/src/modules/legal_documents.js#L153) |
| ${label} ${min} ile ${max} arasında bir tamsayı olmalıdır. | [server/src/services/membership_rules.js:433](../server/src/services/membership_rules.js#L433) |
| ${name} env degiskeni eksik. | [server/src/mailer.js:6](../server/src/mailer.js#L6) |
| ${name}: dosya çok büyük | [server/src/modules/legal_documents.js:222](../server/src/modules/legal_documents.js#L222) |
| ${pass.door_name} aciliyor. | [server/src/routes/guest_passes_routes.js:464](../server/src/routes/guest_passes_routes.js#L464) |
| ${req.full_name} sakini, "${req.block_name \|\| ''} ${req.unit_label}" dairesine ${assignedRole === 'APARTMENT_ADMIN' ? 'Daire Yöneticisi' : 'Aile Üyesi'} olarak başarıyla onaylandı. | [server/src/services/membership_service.js:1301](../server/src/services/membership_service.js#L1301) |
| ${result.revoked_count} aktif karekod basariyla iptal edildi. | [server/src/routes/manager_routes.js:1112](../server/src/routes/manager_routes.js#L1112) |
| ${site?.name ?  | [server/src/modules/account_common.js:69](../server/src/modules/account_common.js#L69) |
| ${targetUserCodes.length} sakin için kapı yetkisi ${actionText}. | [server/src/services/membership_service.js:2535](../server/src/services/membership_service.js#L2535) |
| Abonelik talebiniz onay bekliyor. | [server/src/middlewares/auth_middleware.js:94](../server/src/middlewares/auth_middleware.js#L94) |
| Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:781](../server/src/routes/auth_routes.js#L781) |
| Abonelik talebiniz reddedildi. | [server/src/middlewares/auth_middleware.js:97](../server/src/middlewares/auth_middleware.js#L97) |
| Abonelik talebiniz reddedildi. | [server/src/routes/auth_routes.js:784](../server/src/routes/auth_routes.js#L784) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:673](../server/src/routes/admin_routes.js#L673) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:838](../server/src/routes/admin_routes.js#L838) |
| Ad ve soyad alanları zorunludur. | [server/src/services/membership_service.js:235](../server/src/services/membership_service.js#L235) |
| Ad ve soyad en fazla ${NAME_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:238](../server/src/services/membership_service.js#L238) |
| Aile Reisi (Daire Yöneticisi) başarıyla değiştirildi. | [server/src/services/membership_service.js:2120](../server/src/services/membership_service.js#L2120) |
| Aktif bir doğrulama kodu bulunamadı. Lütfen yeni kod talep ediniz. | [server/src/services/membership_rules.js:68](../server/src/services/membership_rules.js#L68) |
| ANNOUNCEMENT_EMAIL_SECRET veya JWT_SECRET tanimli degil. | [server/src/modules/announcement_email_security.js:45](../server/src/modules/announcement_email_security.js#L45) |
| app_version geçersiz. | [server/src/modules/client_error_service.js:114](../server/src/modules/client_error_service.js#L114) |
| attention source: key ve run zorunlu | [server/src/modules/attention_registry.js:15](../server/src/modules/attention_registry.js#L15) |
| audit action zorunlu | [server/src/modules/audit_service.js:59](../server/src/modules/audit_service.js#L59) |
| bağlantı boşluk veya geçersiz karakter içeremez. | [server/src/modules/platform_config_service.js:108](../server/src/modules/platform_config_service.js#L108) |
| Başvuru bulunamadı. | [server/src/modules/site_application_common.js:25](../server/src/modules/site_application_common.js#L25) |
| beklenmeyen hata | [server/src/modules/drive_service.js:351](../server/src/modules/drive_service.js#L351) |
| Bekleyen abonelik talebi bulunamadi. | [server/src/routes/admin_routes.js:706](../server/src/routes/admin_routes.js#L706) |
| Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz. | [server/src/services/membership_service.js:408](../server/src/services/membership_service.js#L408) |
| Bekleyen site talebi bulunamadi. | [server/src/routes/admin_routes.js:844](../server/src/routes/admin_routes.js#L844) |
| Belge bulunamadı. | [server/src/modules/legal_routes.js:53](../server/src/modules/legal_routes.js#L53) |
| belge deposu okunabilir akis dondurmedi | [server/src/modules/finance_documents_adapter.js:177](../server/src/modules/finance_documents_adapter.js#L177) |
| Belirtilen cihaz hesabınıza ait değil. | [server/src/services/membership_service.js:816](../server/src/services/membership_service.js#L816) |
| Bilinmeyen toplu yükleme türü. | [server/src/modules/bulk_import_plan.js:27](../server/src/modules/bulk_import_plan.js#L27) |
| Bir sorun oluştu. Uygulamadan yeniden deneyin. | [server/src/modules/drive_routes.js:163](../server/src/modules/drive_routes.js#L163) |
| borçlandırma satır sayısı uyuşmuyor (${written.rowCount} / ${lines.length}) | [server/src/modules/finance_service.js:556](../server/src/modules/finance_service.js#L556) |
| Bos olmayan bloklar varken blok sayisi azaltilamaz. | [server/src/services/site_service.js:1182](../server/src/services/site_service.js#L1182) |
| Boylam -180 ile 180 arasinda olmalidir. | [server/src/utils/site_rules.js:337](../server/src/utils/site_rules.js#L337) |
| Bu cihaz arizali olarak isaretlenmis. | [server/src/utils/site_rules.js:488](../server/src/utils/site_rules.js#L488) |
| Bu cihaz baska bir kullanici hesabi tarafindan sahiplenilmis. | [server/src/utils/site_rules.js:486](../server/src/utils/site_rules.js#L486) |
| Bu cihaz icin log gonderme yetkiniz yok. | [server/src/routes/door_log_routes.js:248](../server/src/routes/door_log_routes.js#L248) |
| Bu cihaz şirket envanterinde arızalı olarak işaretlenmiştir. Lütfen şirket yetkilisiyle iletişime geçiniz. | [server/src/services/membership_service.js:649](../server/src/services/membership_service.js#L649) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/routes/admin_routes.js:1346](../server/src/routes/admin_routes.js#L1346) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/utils/site_rules.js:483](../server/src/utils/site_rules.js#L483) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:622](../server/src/services/membership_service.js#L622) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:644](../server/src/services/membership_service.js#L644) |
| Bu cihazin unique id kayitli. | [server/src/utils/validators.js:404](../server/src/utils/validators.js#L404) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:702](../server/src/routes/manager_routes.js#L702) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:761](../server/src/routes/manager_routes.js#L761) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:791](../server/src/routes/manager_routes.js#L791) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:825](../server/src/routes/manager_routes.js#L825) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1502](../server/src/services/membership_service.js#L1502) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1542](../server/src/services/membership_service.js#L1542) |
| Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz. | [server/src/services/membership_service.js:393](../server/src/services/membership_service.js#L393) |
| Bu e-posta adresi için çok fazla kod istendi. Lütfen daha sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:117](../server/src/services/membership_rules.js#L117) |
| Bu e-posta adresine ait hesap artık bulunmuyor. | [server/src/services/site_service.js:2074](../server/src/services/site_service.js#L2074) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:252](../server/src/services/membership_service.js#L252) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:422](../server/src/services/membership_service.js#L422) |
| Bu e-posta baska bir rol icin kayitli. | [server/src/routes/auth_routes.js:596](../server/src/routes/auth_routes.js#L596) |
| Bu e-posta ile onaylanmis bir hesap zaten var. Giris yapin. | [server/src/routes/auth_routes.js:601](../server/src/routes/auth_routes.js#L601) |
| Bu e-posta zaten kayitli. | [server/src/utils/validators.js:358](../server/src/utils/validators.js#L358) |
| Bu gecis linki iptal edilmis. | [server/src/utils/guest_pass_utils.js:122](../server/src/utils/guest_pass_utils.js#L122) |
| Bu gecis linkinin suresi dolmus. | [server/src/utils/guest_pass_utils.js:123](../server/src/utils/guest_pass_utils.js#L123) |
| Bu gecisi olusturan kullanicinin kapiya yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:333](../server/src/routes/guest_passes_routes.js#L333) |
| Bu gecisi olusturan kullanicinin yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:320](../server/src/routes/guest_passes_routes.js#L320) |
| Bu hedef icin OTA yayini yok. | [server/src/routes/firmware_routes.js:165](../server/src/routes/firmware_routes.js#L165) |
| Bu hesap kullanıcının isteğiyle silinmiş (kimliksizleştirilmiş); düzenlenemez veya etkinleştirilemez. | [server/src/routes/admin_routes.js:162](../server/src/routes/admin_routes.js#L162) |
| Bu hesap kullanıcının isteğiyle silinmiş (kimliksizleştirilmiş); kayıtları yasal saklama için korunur ve kalıcı silinemez. | [server/src/routes/admin_routes.js:482](../server/src/routes/admin_routes.js#L482) |
| Bu hesap kullanıcının isteğiyle silinmiş (kimliksizleştirilmiş); kayıtları yasal saklama için korunur ve kalıcı silinemez. | [server/src/routes/admin_routes.js:570](../server/src/routes/admin_routes.js#L570) |
| Bu hesap silinmis. | [server/src/middlewares/auth_middleware.js:75](../server/src/middlewares/auth_middleware.js#L75) |
| Bu hesap silinmis. | [server/src/routes/auth_routes.js:912](../server/src/routes/auth_routes.js#L912) |
| Bu hesap silinmis. | [server/src/services/membership_service.js:1903](../server/src/services/membership_service.js#L1903) |
| Bu hesap silinmis. | [server/src/services/site_setup_core.js:161](../server/src/services/site_setup_core.js#L161) |
| Bu islem icin site yoneticisi yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:140](../server/src/middlewares/auth_middleware.js#L140) |
| Bu islem icin super user yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:111](../server/src/middlewares/auth_middleware.js#L111) |
| Bu işlem için yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1715](../server/src/services/site_service.js#L1715) |
| Bu işlem için yetkiniz yok. | [server/src/modules/people_access.js:13](../server/src/modules/people_access.js#L13) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1759](../server/src/services/site_service.js#L1759) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1841](../server/src/services/site_service.js#L1841) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen cihaz ekranındaki güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:320](../server/src/routes/app_doors_routes.js#L320) |
| Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır. | [server/src/services/qr_access_service.js:43](../server/src/services/qr_access_service.js#L43) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2156](../server/src/services/membership_service.js#L2156) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2177](../server/src/services/membership_service.js#L2177) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:136](../server/src/routes/app_doors_routes.js#L136) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:177](../server/src/routes/app_doors_routes.js#L177) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:300](../server/src/routes/app_doors_routes.js#L300) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/guest_passes_routes.js:287](../server/src/routes/guest_passes_routes.js#L287) |
| Bu kapiya gecis yetkiniz bulunmuyor. | [server/src/routes/app_doors_routes.js:295](../server/src/routes/app_doors_routes.js#L295) |
| Bu kapiyi silme yetkiniz yok. | [server/src/routes/manager_routes.js:1073](../server/src/routes/manager_routes.js#L1073) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:866](../server/src/routes/manager_routes.js#L866) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:908](../server/src/routes/manager_routes.js#L908) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:951](../server/src/routes/manager_routes.js#L951) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1040](../server/src/routes/manager_routes.js#L1040) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1100](../server/src/routes/manager_routes.js#L1100) |
| Bu karekod daha once kullanildi. Lutfen cihaz ekraninda yenilenen guncel karekodu okutun. | [server/src/routes/app_doors_routes.js:337](../server/src/routes/app_doors_routes.js#L337) |
| Bu kişide kurul veya görevli rolü yok. | [server/src/modules/module_routes.js:200](../server/src/modules/module_routes.js#L200) |
| Bu kullanıcı zaten bu sitenin yöneticisidir. | [server/src/services/site_service.js:2085](../server/src/services/site_service.js#L2085) |
| Bu kullanıcı zaten daire yöneticisidir. | [server/src/services/membership_service.js:2068](../server/src/services/membership_service.js#L2068) |
| Bu kullanıcı zaten dairenin Aile Reisidir (Daire Yöneticisi). | [server/src/services/membership_service.js:2078](../server/src/services/membership_service.js#L2078) |
| Bu kullanici adi zaten kayitli. | [server/src/utils/validators.js:361](../server/src/utils/validators.js#L361) |
| Bu modül site için kapalı. | [server/src/modules/bulk_import_routes.js:90](../server/src/modules/bulk_import_routes.js#L90) |
| Bu silme doğrulama kodu artık geçerli değil. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:1930](../server/src/services/site_service.js#L1930) |
| Bu silme talebini yalnızca ilgili sitenin yöneticisi onaylayabilir. | [server/src/services/site_service.js:1690](../server/src/services/site_service.js#L1690) |
| Bu silme talebini yalnızca Süper Kullanıcı onaylayabilir. | [server/src/services/site_service.js:1680](../server/src/services/site_service.js#L1680) |
| Bu site için bekleyen bir silme onayı bulunmamaktadır. | [server/src/services/site_service.js:1697](../server/src/services/site_service.js#L1697) |
| Bu site için bekleyen bir silme talebi bulunmuyor. | [server/src/services/site_service.js:1732](../server/src/services/site_service.js#L1732) |
| Bu site için talep edilmiş aktif bir silme doğrulama kodu bulunmuyor. | [server/src/services/site_service.js:1885](../server/src/services/site_service.js#L1885) |
| Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır. | [server/src/services/membership_service.js:972](../server/src/services/membership_service.js#L972) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/routes/membership_routes.js:144](../server/src/routes/membership_routes.js#L144) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/services/membership_service.js:932](../server/src/services/membership_service.js#L932) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/modules/people_access.js:15](../server/src/modules/people_access.js#L15) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/modules/route_helpers.js:44](../server/src/modules/route_helpers.js#L44) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1333](../server/src/routes/manager_routes.js#L1333) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1359](../server/src/routes/manager_routes.js#L1359) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1387](../server/src/routes/manager_routes.js#L1387) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1414](../server/src/routes/manager_routes.js#L1414) |
| Bu sitede karekod ile giris yonetim tarafindan gecici olarak durdurulmustur. | [server/src/services/door_access_policy.js:111](../server/src/services/door_access_policy.js#L111) |
| Bu sitede karekod ile kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:104](../server/src/services/door_access_policy.js#L104) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/routes/guest_passes_routes.js:275](../server/src/routes/guest_passes_routes.js#L275) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/services/door_access_policy.js:121](../server/src/services/door_access_policy.js#L121) |
| Bu sitede misafir/kurye gecis kodu olusturma kapalidir. | [server/src/routes/guest_passes_routes.js:79](../server/src/routes/guest_passes_routes.js#L79) |
| Bu sitede yerel ag uzerinden kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:131](../server/src/services/door_access_policy.js#L131) |
| Bu sitenin cihazlarini gorme yetkiniz yok. | [server/src/routes/manager_routes.js:1132](../server/src/routes/manager_routes.js#L1132) |
| Bu sitenin katılım taleplerini görme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1129](../server/src/services/membership_service.js#L1129) |
| Bu sitenin loglarini gorme yetkiniz yok. | [server/src/routes/door_log_routes.js:136](../server/src/routes/door_log_routes.js#L136) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2566](../server/src/services/membership_service.js#L2566) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2587](../server/src/services/membership_service.js#L2587) |
| Bu siteye kapi ekleme yetkiniz yok. | [server/src/routes/manager_routes.js:994](../server/src/routes/manager_routes.js#L994) |
| Bu siteyi silme yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1543](../server/src/services/site_service.js#L1543) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:232](../server/src/routes/manager_routes.js#L232) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:400](../server/src/routes/manager_routes.js#L400) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:533](../server/src/routes/manager_routes.js#L533) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:555](../server/src/routes/manager_routes.js#L555) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:580](../server/src/routes/manager_routes.js#L580) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1176](../server/src/routes/manager_routes.js#L1176) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:385](../server/src/routes/auth_routes.js#L385) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:403](../server/src/routes/auth_routes.js#L403) |
| Bu şifre sıfırlama bağlantısının süresi dolmuş (30 dakika). Lütfen mobil uygulamadan yeni bir bağlantı talep ediniz. | [server/src/routes/auth_routes.js:412](../server/src/routes/auth_routes.js#L412) |
| Bu talebi onaylama yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1236](../server/src/services/membership_service.js#L1236) |
| Bu talebi reddetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1345](../server/src/services/membership_service.js#L1345) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1242](../server/src/services/membership_service.js#L1242) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1351](../server/src/services/membership_service.js#L1351) |
| Bu tek kullanimlik gecis linki daha once kullanilmis. | [server/src/utils/guest_pass_utils.js:124](../server/src/utils/guest_pass_utils.js#L124) |
| Cihaz (${device.device_uid}) başarıyla şirket envanterine kaydedildi. | [server/src/routes/admin_routes.js:1608](../server/src/routes/admin_routes.js#L1608) |
| Cihaz (${normalizedUid}) zaten şirket veritabanında kayıtlı. | [server/src/services/device_service.js:903](../server/src/services/device_service.js#L903) |
| Cihaz (${updated.device_uid}) sahipliği sıfırlandı ve şirket stokuna geri döndürüldü. | [server/src/routes/admin_routes.js:1673](../server/src/routes/admin_routes.js#L1673) |
| Cihaz atamasi olan kapilar varken kapi sayisi azaltilamaz. | [server/src/services/site_service.js:1164](../server/src/services/site_service.js#L1164) |
| Cihaz basariyla degistirildi. Kapi yetkileri ve ayarlari aynen korundu. | [server/src/routes/manager_routes.js:965](../server/src/routes/manager_routes.js#L965) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:971](../server/src/services/device_service.js#L971) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:1010](../server/src/services/device_service.js#L1010) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1387](../server/src/routes/admin_routes.js#L1387) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1532](../server/src/routes/admin_routes.js#L1532) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1550](../server/src/routes/admin_routes.js#L1550) |
| Cihaz bulunamadi. | [server/src/routes/company_routes.js:493](../server/src/routes/company_routes.js#L493) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1187](../server/src/routes/manager_routes.js#L1187) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1198](../server/src/routes/manager_routes.js#L1198) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1225](../server/src/routes/manager_routes.js#L1225) |
| Cihaz dogrulamasi gecici olarak yapilamadi. | [server/src/routes/firmware_routes.js:127](../server/src/routes/firmware_routes.js#L127) |
| Cihaz donanimi bu firmware hedefiyle uyusmuyor. | [server/src/routes/firmware_routes.js:144](../server/src/routes/firmware_routes.js#L144) |
| Cihaz durumu okunamadi; biraz sonra tekrar deneyin. | [server/src/routes/company_routes.js:490](../server/src/routes/company_routes.js#L490) |
| Cihaz ekranindaki guncel karekod henuz alinamadi. Birkac saniye sonra tekrar deneyin. | [server/src/routes/app_doors_routes.js:328](../server/src/routes/app_doors_routes.js#L328) |
| Cihaz kaydedildi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1615](../server/src/routes/admin_routes.js#L1615) |
| Cihaz online gorunmuyor. | [server/src/routes/app_doors_routes.js:69](../server/src/routes/app_doors_routes.js#L69) |
| Cihaz QR kodu veya seri numarası boş olamaz. | [server/src/services/membership_rules.js:306](../server/src/services/membership_rules.js#L306) |
| Cihaz QR kodu veya seri numarası çok uzun. | [server/src/services/membership_rules.js:309](../server/src/services/membership_rules.js#L309) |
| Cihaz sahiplenmek için önce e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:568](../server/src/services/membership_service.js#L568) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1557](../server/src/routes/admin_routes.js#L1557) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:1236](../server/src/routes/manager_routes.js#L1236) |
| Cihaz silinemedi. | [server/src/routes/admin_routes.js:1561](../server/src/routes/admin_routes.js#L1561) |
| Cihaz silinemedi. | [server/src/routes/company_routes.js:470](../server/src/routes/company_routes.js#L470) |
| Cihaz silme islemini yalnizca super user yapabilir. | [server/src/routes/manager_routes.js:1214](../server/src/routes/manager_routes.js#L1214) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1343](../server/src/routes/admin_routes.js#L1343) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1406](../server/src/routes/admin_routes.js#L1406) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:614](../server/src/routes/manager_routes.js#L614) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:618](../server/src/routes/manager_routes.js#L618) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:648](../server/src/routes/manager_routes.js#L648) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:653](../server/src/routes/manager_routes.js#L653) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:658](../server/src/routes/manager_routes.js#L658) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/utils/site_rules.js:482](../server/src/utils/site_rules.js#L482) |
| Cihaz sunucuya kaydedilemedi. | [server/src/routes/company_routes.js:402](../server/src/routes/company_routes.js#L402) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/admin_routes.js:1400](../server/src/routes/admin_routes.js#L1400) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:608](../server/src/routes/manager_routes.js#L608) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:642](../server/src/routes/manager_routes.js#L642) |
| Cihaz ve karekod basariyla sunucuya kaydedildi. | [server/src/routes/company_routes.js:397](../server/src/routes/company_routes.js#L397) |
| Cihaz veritabanina kaydedilemedi; islemi tekrar deneyin. | [server/src/routes/company_routes.js:347](../server/src/routes/company_routes.js#L347) |
| Cihaz veritabanindan silinemedi; islemi tekrar deneyin. | [server/src/routes/company_routes.js:429](../server/src/routes/company_routes.js#L429) |
| Cihaz veya bagli oldugu site bulunamadi. | [server/src/routes/door_log_routes.js:245](../server/src/routes/door_log_routes.js#L245) |
| Cok fazla cihaz sahiplenme denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:265](../server/src/middlewares/rate_limiters.js#L265) |
| Cok fazla davet gonderildi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:274](../server/src/middlewares/rate_limiters.js#L274) |
| Cok fazla dogrulama denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:233](../server/src/middlewares/rate_limiters.js#L233) |
| Cok fazla giris denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:175](../server/src/middlewares/rate_limiters.js#L175) |
| Cok fazla hassas islem denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:283](../server/src/middlewares/rate_limiters.js#L283) |
| Cok fazla istek. Biraz sonra tekrar deneyin. | [server/src/routes/company_routes.js:31](../server/src/routes/company_routes.js#L31) |
| Cok fazla kayit denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:224](../server/src/middlewares/rate_limiters.js#L224) |
| Cok fazla kod isteme denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:242](../server/src/middlewares/rate_limiters.js#L242) |
| Cok fazla parametre. | [server/src/middlewares/error_handler.js:32](../server/src/middlewares/error_handler.js#L32) |
| Cok fazla PIN sifirlama istegi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:294](../server/src/middlewares/rate_limiters.js#L294) |
| Cok fazla profil guncelleme istegi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:306](../server/src/middlewares/rate_limiters.js#L306) |
| Cok fazla sifre sifirlama denemesi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:256](../server/src/middlewares/rate_limiters.js#L256) |
| Cok fazla sifre sifirlama istegi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:251](../server/src/middlewares/rate_limiters.js#L251) |
| Cok fazla site kurulum denemesi. Biraz sonra tekrar deneyin. | [server/src/routes/membership_routes.js:41](../server/src/routes/membership_routes.js#L41) |
| Çok fazla anket işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/survey_routes.js:28](../server/src/modules/survey_routes.js#L28) |
| Çok fazla ayar değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/platform_config_routes.js:40](../server/src/modules/platform_config_routes.js#L40) |
| Çok fazla belge işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:52](../server/src/modules/document_routes.js#L52) |
| Çok fazla cihaz kaydı isteği. Biraz sonra tekrar deneyin. | [server/src/modules/push_routes.js:30](../server/src/modules/push_routes.js#L30) |
| Çok fazla davet işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/team_routes.js:51](../server/src/modules/team_routes.js#L51) |
| Çok fazla değişiklik. Biraz sonra tekrar deneyin. | [server/src/modules/brand_theme_routes.js:30](../server/src/modules/brand_theme_routes.js#L30) |
| Çok fazla değişiklik. Biraz sonra tekrar deneyin. | [server/src/modules/management_company_routes.js:54](../server/src/modules/management_company_routes.js#L54) |
| Çok fazla deneme. Biraz sonra tekrar deneyin. | [server/src/modules/notify_channels_routes.js:24](../server/src/modules/notify_channels_routes.js#L24) |
| Çok fazla dışa aktarma isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:430](../server/src/modules/finance_4b_routes.js#L430) |
| Çok fazla doğrulama isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:79](../server/src/modules/finance_4b_routes.js#L79) |
| Çok fazla dosya yükleme denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:62](../server/src/modules/document_routes.js#L62) |
| Çok fazla dosya yükleme isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:215](../server/src/modules/finance_4b_routes.js#L215) |
| Çok fazla Drive işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/drive_routes.js:41](../server/src/modules/drive_routes.js#L41) |
| Çok fazla duyuru işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/announcement_routes.js:61](../server/src/modules/announcement_routes.js#L61) |
| Çok fazla ekipman işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/equipment_routes.js:36](../server/src/modules/equipment_routes.js#L36) |
| Çok fazla faaliyet raporu işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/annual_report_routes.js:23](../server/src/modules/annual_report_routes.js#L23) |
| Çok fazla finans işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/finance_routes.js:50](../server/src/modules/finance_routes.js#L50) |
| Çok fazla firma / sözleşme işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/contracts_routes.js:40](../server/src/modules/contracts_routes.js#L40) |
| Çok fazla fotoğraf yükleme denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/work_tracking_routes.js:56](../server/src/modules/work_tracking_routes.js#L56) |
| Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz. | [server/src/services/membership_rules.js:70](../server/src/services/membership_rules.js#L70) |
| Çok fazla hatalı doğrulama denemesi yapıldı. Kod iptal edildi; lütfen daha sonra yeni bir kod isteyiniz. | [server/src/services/site_service.js:1911](../server/src/services/site_service.js#L1911) |
| Çok fazla hatalı giriş denemesi. Lütfen ${wait} sonra tekrar deneyin ya da "Şifremi unuttum" ile şifrenizi sıfırlayın. | [server/src/routes/auth_routes.js:684](../server/src/routes/auth_routes.js#L684) |
| Çok fazla hatırlatma gönderimi. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:368](../server/src/modules/finance_4b_routes.js#L368) |
| Çok fazla hesap işlemi isteği. Biraz sonra tekrar deneyin. | [server/src/modules/account_routes.js:34](../server/src/modules/account_routes.js#L34) |
| Çok fazla indirme isteği. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:82](../server/src/modules/document_routes.js#L82) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/account_routes.js:26](../server/src/modules/account_routes.js#L26) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/announcement_routes.js:71](../server/src/modules/announcement_routes.js#L71) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/announcement_routes.js:83](../server/src/modules/announcement_routes.js#L83) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/annual_report_routes.js:31](../server/src/modules/annual_report_routes.js#L31) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/app_config_routes.js:23](../server/src/modules/app_config_routes.js#L23) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/brand_theme_routes.js:22](../server/src/modules/brand_theme_routes.js#L22) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/budget_routes.js:50](../server/src/modules/budget_routes.js#L50) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/card_access_routes.js:37](../server/src/modules/card_access_routes.js#L37) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/client_error_routes.js:66](../server/src/modules/client_error_routes.js#L66) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/contracts_routes.js:50](../server/src/modules/contracts_routes.js#L50) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/decision_book_routes.js:39](../server/src/modules/decision_book_routes.js#L39) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/device_integrations_routes.js:56](../server/src/modules/device_integrations_routes.js#L56) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:72](../server/src/modules/document_routes.js#L72) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/drive_routes.js:32](../server/src/modules/drive_routes.js#L32) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/drive_routes.js:47](../server/src/modules/drive_routes.js#L47) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/equipment_routes.js:45](../server/src/modules/equipment_routes.js#L45) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/finance_routes.js:60](../server/src/modules/finance_routes.js#L60) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/finance_routes.js:70](../server/src/modules/finance_routes.js#L70) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/legal_routes.js:35](../server/src/modules/legal_routes.js#L35) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/legal_routes.js:42](../server/src/modules/legal_routes.js#L42) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/management_company_routes.js:46](../server/src/modules/management_company_routes.js#L46) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/metering_routes.js:43](../server/src/modules/metering_routes.js#L43) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/neighbor_board_routes.js:51](../server/src/modules/neighbor_board_routes.js#L51) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/notify_channels_routes.js:32](../server/src/modules/notify_channels_routes.js#L32) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/people_routes.js:53](../server/src/modules/people_routes.js#L53) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/platform_config_routes.js:30](../server/src/modules/platform_config_routes.js#L30) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/platform_rules_routes.js:25](../server/src/modules/platform_rules_routes.js#L25) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/push_routes.js:40](../server/src/modules/push_routes.js#L40) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/push_routes.js:59](../server/src/modules/push_routes.js#L59) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/reservation_routes.js:41](../server/src/modules/reservation_routes.js#L41) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/site_application_routes.js:56](../server/src/modules/site_application_routes.js#L56) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/survey_routes.js:48](../server/src/modules/survey_routes.js#L48) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/team_routes.js:59](../server/src/modules/team_routes.js#L59) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/visitor_log_routes.js:39](../server/src/modules/visitor_log_routes.js#L39) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/work_tracking_routes.js:46](../server/src/modules/work_tracking_routes.js#L46) |
| Çok fazla iş takibi işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/work_tracking_routes.js:36](../server/src/modules/work_tracking_routes.js#L36) |
| Çok fazla işlem. Biraz sonra tekrar deneyin. | [server/src/modules/device_integrations_routes.js:48](../server/src/modules/device_integrations_routes.js#L48) |
| Çok fazla işletme projesi işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/budget_routes.js:41](../server/src/modules/budget_routes.js#L41) |
| Çok fazla kadro işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/team_routes.js:43](../server/src/modules/team_routes.js#L43) |
| Çok fazla karar defteri işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/decision_book_routes.js:29](../server/src/modules/decision_book_routes.js#L29) |
| Çok fazla kart işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/card_access_routes.js:27](../server/src/modules/card_access_routes.js#L27) |
| Çok fazla kayıt işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/people_routes.js:43](../server/src/modules/people_routes.js#L43) |
| Çok fazla kod isteği. Biraz sonra tekrar deneyin. | [server/src/modules/notify_channels_routes.js:19](../server/src/modules/notify_channels_routes.js#L19) |
| Çok fazla komşu panosu işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/neighbor_board_routes.js:43](../server/src/modules/neighbor_board_routes.js#L43) |
| Çok fazla kural değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/platform_rules_routes.js:35](../server/src/modules/platform_rules_routes.js#L35) |
| Çok fazla modül değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/module_routes.js:63](../server/src/modules/module_routes.js#L63) |
| Çok fazla modül talebi. Biraz sonra tekrar deneyin. | [server/src/modules/module_request_routes.js:35](../server/src/modules/module_request_routes.js#L35) |
| Çok fazla olay. | [server/src/modules/device_integrations_routes.js:62](../server/src/modules/device_integrations_routes.js#L62) |
| Çok fazla onay işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/legal_routes.js:49](../server/src/modules/legal_routes.js#L49) |
| Çok fazla oy denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/survey_routes.js:38](../server/src/modules/survey_routes.js#L38) |
| Çok fazla rapor isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:425](../server/src/modules/finance_4b_routes.js#L425) |
| Çok fazla rapor. Biraz sonra tekrar deneyin. | [server/src/modules/client_error_routes.js:42](../server/src/modules/client_error_routes.js#L42) |
| Çok fazla rapor. Biraz sonra tekrar deneyin. | [server/src/modules/client_error_routes.js:58](../server/src/modules/client_error_routes.js#L58) |
| Çok fazla rezervasyon işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/reservation_routes.js:31](../server/src/modules/reservation_routes.js#L31) |
| Çok fazla rol atama denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/module_routes.js:51](../server/src/modules/module_routes.js#L51) |
| Çok fazla sayaç işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/metering_routes.js:34](../server/src/modules/metering_routes.js#L34) |
| Çok fazla site başvurusu işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/site_application_routes.js:46](../server/src/modules/site_application_routes.js#L46) |
| Çok fazla ziyaretçi / kargo işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/visitor_log_routes.js:29](../server/src/modules/visitor_log_routes.js#L29) |
| Daire bilgileri e-posta ile gonderilemedi. | [server/src/routes/admin_routes.js:1314](../server/src/routes/admin_routes.js#L1314) |
| Daire bulunamadı. | [server/src/services/membership_service.js:1492](../server/src/services/membership_service.js#L1492) |
| Daire bulunamadı. | [server/src/services/membership_service.js:1962](../server/src/services/membership_service.js#L1962) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1234](../server/src/routes/admin_routes.js#L1234) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1259](../server/src/routes/admin_routes.js#L1259) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1284](../server/src/routes/admin_routes.js#L1284) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1302](../server/src/routes/admin_routes.js#L1302) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:699](../server/src/routes/manager_routes.js#L699) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:739](../server/src/routes/manager_routes.js#L739) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:758](../server/src/routes/manager_routes.js#L758) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:772](../server/src/routes/manager_routes.js#L772) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:788](../server/src/routes/manager_routes.js#L788) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:822](../server/src/routes/manager_routes.js#L822) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:838](../server/src/routes/manager_routes.js#L838) |
| Daire kullanicisi e-postasi uretilirken cakisma oldu. | [server/src/utils/validators.js:378](../server/src/utils/validators.js#L378) |
| Daire kullanicisi hesabi uretilemedi. | [server/src/utils/validators.js:387](../server/src/utils/validators.js#L387) |
| Daire kullanicisi hesabi uretilirken kullanici adi cakismasi oldu. | [server/src/utils/validators.js:381](../server/src/utils/validators.js#L381) |
| Daire sakini sifirlanamadi. | [server/src/routes/admin_routes.js:1286](../server/src/routes/admin_routes.js#L1286) |
| Daire sakini sifirlandi. | [server/src/routes/admin_routes.js:1281](../server/src/routes/admin_routes.js#L1281) |
| Daire sakini sifirlandi. | [server/src/routes/manager_routes.js:769](../server/src/routes/manager_routes.js#L769) |
| Daire sakininin şifresi başarıyla güncellendi. | [server/src/services/membership_service.js:2033](../server/src/services/membership_service.js#L2033) |
| Daire yöneticisi kendi durumunu pasife alamaz. | [server/src/services/membership_service.js:1738](../server/src/services/membership_service.js#L1738) |
| Daire yöneticisi kendi kendisini daireden çıkaramaz. | [server/src/services/membership_service.js:1656](../server/src/services/membership_service.js#L1656) |
| depolama yolu kok disina cikiyor | [server/src/modules/document_storage.js:152](../server/src/modules/document_storage.js#L152) |
| desteklenmeyen alan türü. | [server/src/modules/platform_config_service.js:179](../server/src/modules/platform_config_service.js#L179) |
| Desteklenmeyen karakter kumesi. | [server/src/middlewares/error_handler.js:30](../server/src/middlewares/error_handler.js#L30) |
| Desteklenmeyen kodlama. | [server/src/middlewares/error_handler.js:29](../server/src/middlewares/error_handler.js#L29) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:326](../server/src/routes/company_routes.js#L326) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:415](../server/src/routes/company_routes.js#L415) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:482](../server/src/routes/company_routes.js#L482) |
| device_uid zorunlu. | [server/src/routes/door_log_routes.js:229](../server/src/routes/door_log_routes.js#L229) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:323](../server/src/routes/company_routes.js#L323) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:411](../server/src/routes/company_routes.js#L411) |
| dizin kimligi ile veritabani kimligi FARKLI; hangisinin dogru oldugunu elle belirleyin | [server/src/modules/document_integrity.js:224](../server/src/modules/document_integrity.js#L224) |
| dizindeki kimlik dosyasi bozuk; elle silip yeniden deneyin | [server/src/modules/document_integrity.js:221](../server/src/modules/document_integrity.js#L221) |
| Dogrulama kodu tekrar e-posta adresinize gonderildi. | [server/src/routes/auth_routes.js:618](../server/src/routes/auth_routes.js#L618) |
| Doğrulama isteği şu an işlenemiyor. Lütfen biraz sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:77](../server/src/services/membership_rules.js#L77) |
| Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır. | [server/src/services/membership_service.js:343](../server/src/services/membership_service.js#L343) |
| Dosya çok büyük. Bir seferde en çok ${BODY_SIZE_LABEL} gönderilebilir. | [server/src/modules/bulk_import_routes.js:112](../server/src/modules/bulk_import_routes.js#L112) |
| DRIVE_TOKEN_KEY en az 32 karakter olmali | [server/src/modules/drive_common.js:40](../server/src/modules/drive_common.js#L40) |
| E-posta adresi gereklidir. | [server/src/routes/auth_routes.js:107](../server/src/routes/auth_routes.js#L107) |
| E-posta adresi gereklidir. | [server/src/services/membership_service.js:497](../server/src/services/membership_service.js#L497) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/admin_routes.js:396](../server/src/routes/admin_routes.js#L396) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/auth_routes.js:873](../server/src/routes/auth_routes.js#L873) |
| E-posta adresiniz başarıyla doğrulandı. Hesabınız aktif! | [server/src/services/membership_service.js:480](../server/src/services/membership_service.js#L480) |
| E-posta adresiniz dogrulanmadi. | [server/src/middlewares/auth_middleware.js:91](../server/src/middlewares/auth_middleware.js#L91) |
| E-posta adresiniz dogrulanmadi. | [server/src/routes/auth_routes.js:778](../server/src/routes/auth_routes.js#L778) |
| E-posta ve doğrulama kodu zorunludur. | [server/src/services/membership_service.js:337](../server/src/services/membership_service.js#L337) |
| E-posta zaten dogrulanmis. Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:605](../server/src/routes/auth_routes.js#L605) |
| email ve password zorunlu. | [server/src/routes/auth_routes.js:699](../server/src/routes/auth_routes.js#L699) |
| email_verified alani true/false olmali. | [server/src/routes/admin_routes.js:347](../server/src/routes/admin_routes.js#L347) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/routes/admin_routes.js:1065](../server/src/routes/admin_routes.js#L1065) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/utils/site_rules.js:421](../server/src/utils/site_rules.js#L421) |
| en fazla ${max} karakter olabilir. | [server/src/modules/platform_config_service.js:101](../server/src/modules/platform_config_service.js#L101) |
| En fazla ${SITE_LIMITS.maxBlocks} blok tanımlanabilir. | [server/src/services/membership_rules.js:471](../server/src/services/membership_rules.js#L471) |
| En fazla ${SITE_LIMITS.maxDoors} kapı tanımlanabilir. | [server/src/services/membership_rules.js:502](../server/src/services/membership_rules.js#L502) |
| en fazla ${spec.max} karakter olabilir. | [server/src/modules/platform_config_service.js:171](../server/src/modules/platform_config_service.js#L171) |
| Enlem -90 ile 90 arasinda olmalidir. | [server/src/utils/site_rules.js:331](../server/src/utils/site_rules.js#L331) |
| Etiketli cihazlar okunamadi. | [server/src/routes/company_routes.js:308](../server/src/routes/company_routes.js#L308) |
| feature_* alanlari true/false olmali. | [server/src/routes/admin_routes.js:1053](../server/src/routes/admin_routes.js#L1053) |
| Firmware dosyasi bulunamadi. | [server/src/routes/firmware_routes.js:240](../server/src/routes/firmware_routes.js#L240) |
| Firmware manifest okunamadi. | [server/src/routes/firmware_routes.js:221](../server/src/routes/firmware_routes.js#L221) |
| Fotoğraf bulunamadı. | [server/src/modules/metering_field_routes.js:183](../server/src/modules/metering_field_routes.js#L183) |
| full_name en az 3 karakter olmali. | [server/src/routes/admin_routes.js:341](../server/src/routes/admin_routes.js#L341) |
| Gecerli bir kapi secin. | [server/src/utils/guest_pass_utils.js:43](../server/src/utils/guest_pass_utils.js#L43) |
| gecersiz adres ozeti | [server/src/modules/announcement_email_security.js:132](../server/src/modules/announcement_email_security.js#L132) |
| Gecersiz alici adresi. | [server/src/mailer.js:681](../server/src/mailer.js#L681) |
| Gecersiz alici adresi. | [server/src/modules/contracts_reminders.js:68](../server/src/modules/contracts_reminders.js#L68) |
| Gecersiz alici adresi. | [server/src/modules/finance_reminder_mail.js:69](../server/src/modules/finance_reminder_mail.js#L69) |
| Gecersiz approval_status degeri. | [server/src/routes/admin_routes.js:726](../server/src/routes/admin_routes.js#L726) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:989](../server/src/routes/manager_routes.js#L989) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:1027](../server/src/routes/manager_routes.js#L1027) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1471](../server/src/routes/admin_routes.js#L1471) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1544](../server/src/routes/admin_routes.js#L1544) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1630](../server/src/routes/admin_routes.js#L1630) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1663](../server/src/routes/admin_routes.js#L1663) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:939](../server/src/routes/manager_routes.js#L939) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1154](../server/src/routes/manager_routes.js#L1154) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1219](../server/src/routes/manager_routes.js#L1219) |
| Gecersiz cihaz unique id. | [server/src/routes/admin_routes.js:1374](../server/src/routes/admin_routes.js#L1374) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1185](../server/src/routes/admin_routes.js#L1185) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1244](../server/src/routes/admin_routes.js#L1244) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1272](../server/src/routes/admin_routes.js#L1272) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1294](../server/src/routes/admin_routes.js#L1294) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:686](../server/src/routes/manager_routes.js#L686) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:752](../server/src/routes/manager_routes.js#L752) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:782](../server/src/routes/manager_routes.js#L782) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:815](../server/src/routes/manager_routes.js#L815) |
| gecersiz depolama alt agaci | [server/src/modules/document_storage.js:36](../server/src/modules/document_storage.js#L36) |
| gecersiz depolama anahtari | [server/src/modules/document_storage.js:147](../server/src/modules/document_storage.js#L147) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:280](../server/src/routes/company_routes.js#L280) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:284](../server/src/routes/company_routes.js#L284) |
| Gecersiz dosya adi. | [server/src/routes/company_routes.js:359](../server/src/routes/company_routes.js#L359) |
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
| Gecersiz kapi ID. | [server/src/routes/admin_routes.js:1322](../server/src/routes/admin_routes.js#L1322) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:855](../server/src/routes/manager_routes.js#L855) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:899](../server/src/routes/manager_routes.js#L899) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:928](../server/src/routes/manager_routes.js#L928) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1018](../server/src/routes/manager_routes.js#L1018) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1064](../server/src/routes/manager_routes.js#L1064) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1091](../server/src/routes/manager_routes.js#L1091) |
| Gecersiz kapi id. | [server/src/routes/app_doors_routes.js:40](../server/src/routes/app_doors_routes.js#L40) |
| Gecersiz karekod verisi. | [server/src/routes/app_doors_routes.js:266](../server/src/routes/app_doors_routes.js#L266) |
| gecersiz klasor girdisi | [server/src/modules/drive_common.js:115](../server/src/modules/drive_common.js#L115) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:323](../server/src/routes/admin_routes.js#L323) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:435](../server/src/routes/admin_routes.js#L435) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:465](../server/src/routes/admin_routes.js#L465) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:670](../server/src/routes/admin_routes.js#L670) |
| Gecersiz kullanim limiti. | [server/src/utils/guest_pass_utils.js:74](../server/src/utils/guest_pass_utils.js#L74) |
| Gecersiz parametreler. | [server/src/services/qr_access_service.js:24](../server/src/services/qr_access_service.js#L24) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:174](../server/src/routes/admin_routes.js#L174) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:344](../server/src/routes/admin_routes.js#L344) |
| Gecersiz rol. | [server/src/routes/auth_routes.js:702](../server/src/routes/auth_routes.js#L702) |
| gecersiz site kodu (depolama anahtari) | [server/src/modules/document_storage.js:139](../server/src/modules/document_storage.js#L139) |
| gecersiz site kodu (dizin) | [server/src/modules/document_storage.js:164](../server/src/modules/document_storage.js#L164) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:835](../server/src/routes/admin_routes.js#L835) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:902](../server/src/routes/admin_routes.js#L902) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1036](../server/src/routes/admin_routes.js#L1036) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1087](../server/src/routes/admin_routes.js#L1087) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1105](../server/src/routes/admin_routes.js#L1105) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1120](../server/src/routes/admin_routes.js#L1120) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1135](../server/src/routes/admin_routes.js#L1135) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1150](../server/src/routes/admin_routes.js#L1150) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1165](../server/src/routes/admin_routes.js#L1165) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:227](../server/src/routes/manager_routes.js#L227) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:362](../server/src/routes/manager_routes.js#L362) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:483](../server/src/routes/manager_routes.js#L483) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:498](../server/src/routes/manager_routes.js#L498) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:513](../server/src/routes/manager_routes.js#L513) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:528](../server/src/routes/manager_routes.js#L528) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:550](../server/src/routes/manager_routes.js#L550) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:575](../server/src/routes/manager_routes.js#L575) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:979](../server/src/routes/manager_routes.js#L979) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:1127](../server/src/routes/manager_routes.js#L1127) |
| Gecersiz token. | [server/src/middlewares/auth_middleware.js:32](../server/src/middlewares/auth_middleware.js#L32) |
| Gecersiz veya suresi dolmus token. | [server/src/middlewares/auth_middleware.js:24](../server/src/middlewares/auth_middleware.js#L24) |
| Gecis baglantisi bulunamadi veya silinmis. | [server/src/routes/guest_passes_routes.js:263](../server/src/routes/guest_passes_routes.js#L263) |
| Gecis baglantisi su an baska bir istekle kullaniliyor. Lutfen tekrar deneyin. | [server/src/routes/guest_passes_routes.js:391](../server/src/routes/guest_passes_routes.js#L391) |
| Gecis bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:211](../server/src/routes/guest_passes_routes.js#L211) |
| Gecis iptal edildi. | [server/src/routes/guest_passes_routes.js:214](../server/src/routes/guest_passes_routes.js#L214) |
| geçerli bir bağlantı değil. | [server/src/modules/platform_config_service.js:114](../server/src/modules/platform_config_service.js#L114) |
| Geçerli bir Cihaz Unique ID (UID) giriniz (12 haneli onaltılık, örn. D4C771A172E0). | [server/src/services/device_service.js:888](../server/src/services/device_service.js#L888) |
| Geçerli bir daire seçiniz. | [server/src/services/membership_service.js:882](../server/src/services/membership_service.js#L882) |
| Geçerli bir e-posta adresi gereklidir. | [server/src/services/site_service.js:2022](../server/src/services/site_service.js#L2022) |
| Geçerli bir e-posta adresi giriniz. | [server/src/routes/auth_routes.js:343](../server/src/routes/auth_routes.js#L343) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:241](../server/src/services/membership_service.js#L241) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:340](../server/src/services/membership_service.js#L340) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:500](../server/src/services/membership_service.js#L500) |
| geçerli bir e-posta adresi olmalıdır. | [server/src/modules/platform_config_service.js:156](../server/src/modules/platform_config_service.js#L156) |
| geçerli bir https:// bağlantısı olmalıdır (kullanıcı adı / parola içeremez). | [server/src/modules/platform_config_service.js:117](../server/src/modules/platform_config_service.js#L117) |
| geçerli bir telefon numarası olmalıdır (örn. +90 212 000 00 00). | [server/src/modules/platform_config_service.js:161](../server/src/modules/platform_config_service.js#L161) |
| Geçersiz blok kimliği. | [server/src/services/membership_service.js:2467](../server/src/services/membership_service.js#L2467) |
| Geçersiz blok seçimi. | [server/src/services/membership_service.js:887](../server/src/services/membership_service.js#L887) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:948](../server/src/services/device_service.js#L948) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:994](../server/src/services/device_service.js#L994) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:1482](../server/src/services/membership_service.js#L1482) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:1928](../server/src/services/membership_service.js#L1928) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:2460](../server/src/services/membership_service.js#L2460) |
| Geçersiz istek gövdesi. | [server/src/modules/client_error_routes.js:35](../server/src/modules/client_error_routes.js#L35) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:331](../server/src/routes/membership_routes.js#L331) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:351](../server/src/routes/membership_routes.js#L351) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:379](../server/src/routes/membership_routes.js#L379) |
| Geçersiz kapı kimliği. | [server/src/services/membership_service.js:2134](../server/src/services/membership_service.js#L2134) |
| Geçersiz katılım tokeni. | [server/src/services/membership_service.js:873](../server/src/services/membership_service.js#L873) |
| Geçersiz kullanıcı kimliği. | [server/src/services/membership_service.js:1638](../server/src/services/membership_service.js#L1638) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:1390](../server/src/services/membership_service.js#L1390) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:2368](../server/src/services/membership_service.js#L2368) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1382](../server/src/routes/manager_routes.js#L1382) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1409](../server/src/routes/manager_routes.js#L1409) |
| Geçersiz parametreler. | [server/src/services/site_service.js:2220](../server/src/services/site_service.js#L2220) |
| Geçersiz site ID. | [server/src/routes/manager_routes.js:1258](../server/src/routes/manager_routes.js#L1258) |
| Geçersiz site ID. | [server/src/routes/membership_routes.js:406](../server/src/routes/membership_routes.js#L406) |
| Geçersiz site katılım kodu. | [server/src/routes/membership_routes.js:147](../server/src/routes/membership_routes.js#L147) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:1114](../server/src/services/membership_service.js#L1114) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:2545](../server/src/services/membership_service.js#L2545) |
| Geçersiz site kodu. | [server/src/modules/card_access_access.js:23](../server/src/modules/card_access_access.js#L23) |
| Geçersiz site kodu. | [server/src/modules/contracts_access.js:42](../server/src/modules/contracts_access.js#L42) |
| Geçersiz site kodu. | [server/src/modules/decision_book_access.js:24](../server/src/modules/decision_book_access.js#L24) |
| Geçersiz site kodu. | [server/src/modules/device_integrations_routes.js:79](../server/src/modules/device_integrations_routes.js#L79) |
| Geçersiz site kodu. | [server/src/modules/equipment_routes.js:55](../server/src/modules/equipment_routes.js#L55) |
| Geçersiz site kodu. | [server/src/modules/metering_field_routes.js:44](../server/src/modules/metering_field_routes.js#L44) |
| Geçersiz site kodu. | [server/src/modules/neighbor_board_routes.js:233](../server/src/modules/neighbor_board_routes.js#L233) |
| Geçersiz site kodu. | [server/src/modules/people_access.js:79](../server/src/modules/people_access.js#L79) |
| Geçersiz site kodu. | [server/src/modules/reservation_access.js:42](../server/src/modules/reservation_access.js#L42) |
| Geçersiz site kodu. | [server/src/modules/route_helpers.js:38](../server/src/modules/route_helpers.js#L38) |
| Geçersiz site kodu. | [server/src/modules/survey_access.js:23](../server/src/modules/survey_access.js#L23) |
| Geçersiz site kodu. | [server/src/modules/visitor_log_access.js:42](../server/src/modules/visitor_log_access.js#L42) |
| Geçersiz site kodu. | [server/src/modules/work_tracking_access.js:42](../server/src/modules/work_tracking_access.js#L42) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1328](../server/src/routes/manager_routes.js#L1328) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1351](../server/src/routes/manager_routes.js#L1351) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1535](../server/src/services/site_service.js#L1535) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1661](../server/src/services/site_service.js#L1661) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1708](../server/src/services/site_service.js#L1708) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1766](../server/src/services/site_service.js#L1766) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1848](../server/src/services/site_service.js#L1848) |
| Geçersiz sorgu parametresi. | [server/src/modules/module_request_routes.js:125](../server/src/modules/module_request_routes.js#L125) |
| Geçersiz sorgu parametresi. | [server/src/modules/module_routes.js:236](../server/src/modules/module_routes.js#L236) |
| Geçersiz şifre sıfırlama bağlantısı. Lütfen e-postanızdaki bağlantıyı kontrol ediniz. | [server/src/routes/auth_routes.js:379](../server/src/routes/auth_routes.js#L379) |
| Geçersiz şifreli değer. | [server/src/modules/device_integrations_service.js:47](../server/src/modules/device_integrations_service.js#L47) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1280](../server/src/routes/manager_routes.js#L1280) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1301](../server/src/routes/manager_routes.js#L1301) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1198](../server/src/services/membership_service.js#L1198) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1318](../server/src/services/membership_service.js#L1318) |
| gider hareketi bulunamadi | [server/src/modules/finance_expenses.js:598](../server/src/modules/finance_expenses.js#L598) |
| Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır. | [server/src/services/membership_service.js:387](../server/src/services/membership_service.js#L387) |
| Girdiğiniz silme doğrulama kodu hatalı. | [server/src/services/site_service.js:1915](../server/src/services/site_service.js#L1915) |
| Giris bilgileri hatali. | [server/src/routes/auth_routes.js:768](../server/src/routes/auth_routes.js#L768) |
| Giris islemi basarisiz. | [server/src/routes/auth_routes.js:800](../server/src/routes/auth_routes.js#L800) |
| Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapilabilir. | [server/src/utils/site_rules.js:398](../server/src/utils/site_rules.js#L398) |
| Gövde bir nesne olmalıdır. | [server/src/modules/client_error_service.js:106](../server/src/modules/client_error_service.js#L106) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:385](../server/src/routes/admin_routes.js#L385) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:941](../server/src/routes/admin_routes.js#L941) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/auth_routes.js:868](../server/src/routes/auth_routes.js#L868) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/manager_routes.js:395](../server/src/routes/manager_routes.js#L395) |
| Güncellenecek alan bulunamadı. | [server/src/services/door_service.js:679](../server/src/services/door_service.js#L679) |
| Günlük test bildirimi sınırına ulaşıldı. Yarın tekrar deneyin. | [server/src/modules/push_routes.js:50](../server/src/modules/push_routes.js#L50) |
| Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez. Kullanıcılar kendi şifrelerini hesaplarına giriş yaparak profil bölümünden değiştirmelidir. | [server/src/routes/admin_routes.js:404](../server/src/routes/admin_routes.js#L404) |
| hardware_type esp32_c3 veya esp32_wroom olmali. | [server/src/routes/admin_routes.js:1501](../server/src/routes/admin_routes.js#L1501) |
| Hesap aktif degil. | [server/src/middlewares/auth_middleware.js:88](../server/src/middlewares/auth_middleware.js#L88) |
| Hesap aktif degil. | [server/src/routes/auth_routes.js:787](../server/src/routes/auth_routes.js#L787) |
| Islem basarisiz. | [server/src/utils/guest_pass_utils.js:242](../server/src/utils/guest_pass_utils.js#L242) |
| Istek govdesi cok buyuk. | [server/src/middlewares/error_handler.js:24](../server/src/middlewares/error_handler.js#L24) |
| Istek govdesi cok buyuk. | [server/src/routes/door_log_routes.js:223](../server/src/routes/door_log_routes.js#L223) |
| Istek yarida kesildi. | [server/src/middlewares/error_handler.js:27](../server/src/middlewares/error_handler.js#L27) |
| install_id geçerli bir UUID olmalıdır. | [server/src/modules/client_error_service.js:110](../server/src/modules/client_error_service.js#L110) |
| İptal edilecek bekleyen davet bulunamadı. | [server/src/services/site_service.js:2362](../server/src/services/site_service.js#L2362) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:440](../server/src/routes/admin_routes.js#L440) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:1195](../server/src/routes/admin_routes.js#L1195) |
| is_active alani true/false olmali. | [server/src/routes/manager_routes.js:1031](../server/src/routes/manager_routes.js#L1031) |
| is_defective alani true/false olmali. | [server/src/routes/admin_routes.js:1634](../server/src/routes/admin_routes.js#L1634) |
| İstek gövdesi geçersiz. | [server/src/modules/bulk_import_routes.js:114](../server/src/modules/bulk_import_routes.js#L114) |
| istemci baglantisi kesildi | [server/src/modules/document_upload.js:50](../server/src/modules/document_upload.js#L50) |
| İşlem sırasında bir hata oluştu. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:425](../server/src/routes/auth_routes.js#L425) |
| Kamera parolası şifrelemesi için CAMERA_SECRET_KEY ya da JWT_SECRET gerekli. | [server/src/modules/device_integrations_service.js:34](../server/src/modules/device_integrations_service.js#L34) |
| Kapı adı boş olamaz. | [server/src/services/door_service.js:654](../server/src/services/door_service.js#L654) |
| Kapı adı zorunludur. | [server/src/services/door_service.js:580](../server/src/services/door_service.js#L580) |
| Kapı bulunamadı. | [server/src/services/membership_service.js:2146](../server/src/services/membership_service.js#L2146) |
| Kapı yetkisi varsayılan ayarlara döndürüldü. | [server/src/services/membership_service.js:2385](../server/src/services/membership_service.js#L2385) |
| Kapi adi zorunludur. | [server/src/routes/manager_routes.js:985](../server/src/routes/manager_routes.js#L985) |
| Kapi basariyla acildi. | [server/src/routes/app_doors_routes.js:408](../server/src/routes/app_doors_routes.js#L408) |
| Kapi bulunamadi veya erisim yetkiniz yok. | [server/src/services/qr_access_service.js:31](../server/src/services/qr_access_service.js#L31) |
| Kapi bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:67](../server/src/routes/guest_passes_routes.js#L67) |
| Kapi bulunamadi. | [server/src/routes/admin_routes.js:1340](../server/src/routes/admin_routes.js#L1340) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:133](../server/src/routes/app_doors_routes.js#L133) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:174](../server/src/routes/app_doors_routes.js#L174) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:432](../server/src/routes/app_doors_routes.js#L432) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:863](../server/src/routes/manager_routes.js#L863) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:905](../server/src/routes/manager_routes.js#L905) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:948](../server/src/routes/manager_routes.js#L948) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1037](../server/src/routes/manager_routes.js#L1037) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1070](../server/src/routes/manager_routes.js#L1070) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1097](../server/src/routes/manager_routes.js#L1097) |
| Kapi bulunamadi. | [server/src/services/door_access_policy.js:68](../server/src/services/door_access_policy.js#L68) |
| Kapi bulunamadi. | [server/src/utils/site_rules.js:481](../server/src/utils/site_rules.js#L481) |
| Kapi cihazi su anda bagli degil. | [server/src/routes/guest_passes_routes.js:470](../server/src/routes/guest_passes_routes.js#L470) |
| Kapi komutu cok sik gonderildi. Biraz sonra tekrar deneyin. | [server/src/middlewares/rate_limiters.js:190](../server/src/middlewares/rate_limiters.js#L190) |
| Kapi loglari alinamadi. | [server/src/routes/door_log_routes.js:101](../server/src/routes/door_log_routes.js#L101) |
| Kapi loglari alinamadi. | [server/src/routes/door_log_routes.js:197](../server/src/routes/door_log_routes.js#L197) |
| Karekod dosyasi bulunamadi. | [server/src/routes/company_routes.js:287](../server/src/routes/company_routes.js#L287) |
| Karekod ile eslesen aktif bir kapi bulunamadi. | [server/src/routes/app_doors_routes.js:284](../server/src/routes/app_doors_routes.js#L284) |
| Karekod talebi çok sık yapıldı. Lütfen birkaç saniye bekleyip tekrar deneyiniz. | [server/src/middlewares/rate_limiters.js:196](../server/src/middlewares/rate_limiters.js#L196) |
| Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:342](../server/src/routes/app_doors_routes.js#L342) |
| Karekodun süresi dolmuş. Lütfen cihaz ekranında yenilenen güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:363](../server/src/routes/app_doors_routes.js#L363) |
| Katılım başvurusu reddedildi. | [server/src/services/membership_service.js:1374](../server/src/services/membership_service.js#L1374) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1220](../server/src/services/membership_service.js#L1220) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1329](../server/src/services/membership_service.js#L1329) |
| Kayit olusturuldu. E-posta adresinize gonderilen 6 haneli kodu girin. | [server/src/routes/auth_routes.js:646](../server/src/routes/auth_routes.js#L646) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:389](../server/src/routes/admin_routes.js#L389) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:443](../server/src/routes/admin_routes.js#L443) |
| Kendi hesabinizi silemezsiniz. | [server/src/routes/admin_routes.js:473](../server/src/routes/admin_routes.js#L473) |
| Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin. | [server/src/routes/admin_routes.js:355](../server/src/routes/admin_routes.js#L355) |
| Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur. | [server/src/utils/site_rules.js:468](../server/src/utils/site_rules.js#L468) |
| Konum yaricapi ${GEOFENCE_RADIUS_MIN} ile ${GEOFENCE_RADIUS_MAX} metre arasinda olmalidir. | [server/src/utils/site_rules.js:348](../server/src/utils/site_rules.js#L348) |
| köşeli parantez, < >, ters eğik çizgi, ters tırnak veya ** içeremez ve #, -, +, *, > ile başlayamaz. | [server/src/modules/platform_config_service.js:174](../server/src/modules/platform_config_service.js#L174) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_rules.js:358](../server/src/services/membership_rules.js#L358) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1678](../server/src/services/membership_service.js#L1678) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1768](../server/src/services/membership_service.js#L1768) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1867](../server/src/services/membership_service.js#L1867) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:2070](../server/src/services/membership_service.js#L2070) |
| Kullanıcı bu daireye ait değil. | [server/src/services/membership_service.js:1974](../server/src/services/membership_service.js#L1974) |
| Kullanıcı bu sitenin yöneticisi değil. | [server/src/utils/site_rules.js:178](../server/src/utils/site_rules.js#L178) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:564](../server/src/services/membership_service.js#L564) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:2406](../server/src/services/membership_service.js#L2406) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:788](../server/src/services/membership_service.js#L788) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:915](../server/src/services/membership_service.js#L915) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:2012](../server/src/services/membership_service.js#L2012) |
| Kullanıcı kodu (userCode) zorunludur. | [server/src/routes/membership_routes.js:355](../server/src/routes/membership_routes.js#L355) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:547](../server/src/services/membership_service.js#L547) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:755](../server/src/services/membership_service.js#L755) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:878](../server/src/services/membership_service.js#L878) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:1058](../server/src/services/membership_service.js#L1058) |
| Kullanıcı site yöneticiliğinden çıkarıldı. | [server/src/services/site_service.js:2339](../server/src/services/site_service.js#L2339) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/admin_routes.js:1308](../server/src/routes/admin_routes.js#L1308) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/manager_routes.js:801](../server/src/routes/manager_routes.js#L801) |
| Kullanici bulunamadi. | [server/src/middlewares/auth_middleware.js:62](../server/src/middlewares/auth_middleware.js#L62) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:164](../server/src/routes/admin_routes.js#L164) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:574](../server/src/routes/admin_routes.js#L574) |
| Kullanici bulunamadi. | [server/src/routes/auth_routes.js:914](../server/src/routes/auth_routes.js#L914) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1507](../server/src/routes/admin_routes.js#L1507) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1584](../server/src/routes/admin_routes.js#L1584) |
| Kullanici ID sayisal olmali. | [server/src/routes/admin_routes.js:1486](../server/src/routes/admin_routes.js#L1486) |
| Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin. | [server/src/utils/validators.js:366](../server/src/utils/validators.js#L366) |
| Kullanici rolu ile secilen rol uyusmuyor. | [server/src/routes/auth_routes.js:775](../server/src/routes/auth_routes.js#L775) |
| Kullanici silinemedi. | [server/src/routes/admin_routes.js:596](../server/src/routes/admin_routes.js#L596) |
| Log senkronizasyonu basarisiz. | [server/src/routes/door_log_routes.js:267](../server/src/routes/door_log_routes.js#L267) |
| logs bir dizi olmali. | [server/src/routes/door_log_routes.js:232](../server/src/routes/door_log_routes.js#L232) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/routes/manager_routes.js:942](../server/src/routes/manager_routes.js#L942) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/utils/site_rules.js:491](../server/src/utils/site_rules.js#L491) |
| Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz. | [server/src/services/site_service.js:1867](../server/src/services/site_service.js#L1867) |
| Lütfen 6 haneli silme doğrulama kodunu giriniz. | [server/src/routes/admin_routes.js:1170](../server/src/routes/admin_routes.js#L1170) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/admin_routes.js:1305](../server/src/routes/admin_routes.js#L1305) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/manager_routes.js:798](../server/src/routes/manager_routes.js#L798) |
| MERSİS numarası 16 haneli olmalıdır. | [server/src/modules/platform_config_service.js:165](../server/src/modules/platform_config_service.js#L165) |
| message ya da stack gereklidir. | [server/src/modules/client_error_service.js:119](../server/src/modules/client_error_service.js#L119) |
| metin olmalıdır. | [server/src/modules/platform_config_service.js:140](../server/src/modules/platform_config_service.js#L140) |
| Mevcut şifre hatalı. | [server/src/services/membership_service.js:1987](../server/src/services/membership_service.js#L1987) |
| Mevcut şifre zorunludur. | [server/src/services/membership_service.js:1953](../server/src/services/membership_service.js#L1953) |
| Mevcut yonetici kodu veya yeni yonetici bilgilerinden yalnizca biri gonderilmeli. | [server/src/routes/admin_routes.js:782](../server/src/routes/admin_routes.js#L782) |
| Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz. | [server/src/modules/module_routes.js:38](../server/src/modules/module_routes.js#L38) |
| MQTT ACL senkronu zaman asimina ugradi (${timeoutMs} ms). | [server/src/mqtt_acl_sync.js:208](../server/src/mqtt_acl_sync.js#L208) |
| MQTT baglantisi hazir degil. | [server/src/routes/admin_routes.js:1461](../server/src/routes/admin_routes.js#L1461) |
| MQTT baglantisi hazir degil. | [server/src/routes/app_doors_routes.js:65](../server/src/routes/app_doors_routes.js#L65) |
| MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1417](../server/src/routes/admin_routes.js#L1417) |
| MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:670](../server/src/routes/manager_routes.js#L670) |
| MQTT cihaz kimligi uretilemedi. | [server/src/routes/admin_routes.js:1421](../server/src/routes/admin_routes.js#L1421) |
| MQTT_SYNC_COMMAND tanimli degil. | [server/src/mqtt_acl_sync.js:169](../server/src/mqtt_acl_sync.js#L169) |
| MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS gecersiz karakter iceriyor. | [server/src/mqtt_acl_sync.js:182](../server/src/mqtt_acl_sync.js#L182) |
| OTA komutu gonderilemedi. | [server/src/routes/admin_routes.js:1463](../server/src/routes/admin_routes.js#L1463) |
| Oturum gecersiz. Lutfen tekrar giris yapin. | [server/src/middlewares/auth_middleware.js:82](../server/src/middlewares/auth_middleware.js#L82) |
| Parolayi degistirmek icin mevcut parolanizi girmelisiniz. | [server/src/routes/auth_routes.js:879](../server/src/routes/auth_routes.js#L879) |
| platform_rules: bilinmeyen kural ${String(key).slice(0, 80)} | [server/src/modules/platform_rules.js:375](../server/src/modules/platform_rules.js#L375) |
| platform_rules: denetim kaydı yazılamadı | [server/src/modules/platform_rules_service.js:361](../server/src/modules/platform_rules_service.js#L361) |
| qr_entry_active alani true/false olmalidir. | [server/src/utils/site_rules.js:319](../server/src/utils/site_rules.js#L319) |
| qr_image_base64 gecerli bir PNG (en fazla 2 MB) olmalidir. | [server/src/routes/company_routes.js:333](../server/src/routes/company_routes.js#L333) |
| qr_rotation_seconds sayisal olmalidir. | [server/src/utils/site_rules.js:359](../server/src/utils/site_rules.js#L359) |
| Rapor çok büyük. | [server/src/modules/client_error_routes.js:34](../server/src/modules/client_error_routes.js#L34) |
| require_geofence alani true/false olmalidir. | [server/src/utils/site_rules.js:325](../server/src/utils/site_rules.js#L325) |
| Route bulunamadi. | [server/src/middlewares/error_handler.js:100](../server/src/middlewares/error_handler.js#L100) |
| Sakin daireden başarıyla silindi. | [server/src/services/membership_service.js:1897](../server/src/services/membership_service.js#L1897) |
| Sakini kalıcı olarak silme yetkisi yalnızca site yöneticilerine aittir. | [server/src/services/membership_service.js:1845](../server/src/services/membership_service.js#L1845) |
| sayac borc satir sayisi uyusmuyor (${written.rowCount} / ${lines.length}) | [server/src/modules/metering_billing.js:268](../server/src/modules/metering_billing.js#L268) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:775](../server/src/routes/admin_routes.js#L775) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:924](../server/src/routes/admin_routes.js#L924) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:321](../server/src/routes/manager_routes.js#L321) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:382](../server/src/routes/manager_routes.js#L382) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:997](../server/src/routes/manager_routes.js#L997) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:1043](../server/src/routes/manager_routes.js#L1043) |
| Secilen yeni cihaz bulunamadi. | [server/src/routes/manager_routes.js:969](../server/src/routes/manager_routes.js#L969) |
| Seçilen alanda aktif sakin bulunamadı. | [server/src/services/membership_service.js:2479](../server/src/services/membership_service.js#L2479) |
| Seçilen daire belirtilen bloğa ait değil. | [server/src/services/membership_service.js:954](../server/src/services/membership_service.js#L954) |
| Seçilen daire bulunamadı veya bu siteye ait değil. | [server/src/services/membership_service.js:950](../server/src/services/membership_service.js#L950) |
| SERVER_SKIP_START=1 production ortaminda YOK SAYILDI (yalniz testler icindir; .env dosyasindan kaldirin). Sunucu normal baslatiliyor. | [server/src/config/env.js:358](../server/src/config/env.js#L358) |
| Sıfırlama anahtarı (token) eksik. | [server/src/routes/auth_routes.js:437](../server/src/routes/auth_routes.js#L437) |
| Sifre 4 haneli sayisal olmali. | [server/src/services/apartment_service.js:244](../server/src/services/apartment_service.js#L244) |
| Sifre en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir. | [server/src/routes/auth_routes.js:858](../server/src/routes/auth_routes.js#L858) |
| sifreli belirtec biçimi geçersiz | [server/src/modules/drive_common.js:55](../server/src/modules/drive_common.js#L55) |
| Silme doğrulama kodu e-posta adresinize (${maskedEmail}) gönderildi. | [server/src/services/site_service.js:1822](../server/src/services/site_service.js#L1822) |
| Silme doğrulama kodunun 10 dakikalık süresi dolmuş. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:1891](../server/src/services/site_service.js#L1891) |
| Site adı en fazla ${SETUP_NAME_MAX} karakter olabilir. | [server/src/services/membership_rules.js:462](../server/src/services/membership_rules.js#L462) |
| Site adı zorunludur. | [server/src/services/membership_rules.js:459](../server/src/services/membership_rules.js#L459) |
| Site adi en az 2 karakter olmali. | [server/src/routes/admin_routes.js:927](../server/src/routes/admin_routes.js#L927) |
| Site bulunamadı. | [server/src/modules/people_access.js:18](../server/src/modules/people_access.js#L18) |
| Site bulunamadı. | [server/src/modules/route_helpers.js:15](../server/src/modules/route_helpers.js#L15) |
| Site bulunamadı. | [server/src/services/membership_service.js:2556](../server/src/services/membership_service.js#L2556) |
| Site bulunamadı. | [server/src/services/site_service.js:1477](../server/src/services/site_service.js#L1477) |
| Site bulunamadı. | [server/src/services/site_service.js:1494](../server/src/services/site_service.js#L1494) |
| Site bulunamadı. | [server/src/services/site_service.js:1554](../server/src/services/site_service.js#L1554) |
| Site bulunamadı. | [server/src/services/site_service.js:1672](../server/src/services/site_service.js#L1672) |
| Site bulunamadı. | [server/src/services/site_service.js:1725](../server/src/services/site_service.js#L1725) |
| Site bulunamadı. | [server/src/services/site_service.js:1776](../server/src/services/site_service.js#L1776) |
| Site bulunamadı. | [server/src/services/site_service.js:1878](../server/src/services/site_service.js#L1878) |
| Site bulunamadı. | [server/src/services/site_service.js:2029](../server/src/services/site_service.js#L2029) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:947](../server/src/routes/admin_routes.js#L947) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1059](../server/src/routes/admin_routes.js#L1059) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1093](../server/src/routes/admin_routes.js#L1093) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:242](../server/src/routes/manager_routes.js#L242) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:405](../server/src/routes/manager_routes.js#L405) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:538](../server/src/routes/manager_routes.js#L538) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:565](../server/src/routes/manager_routes.js#L565) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:594](../server/src/routes/manager_routes.js#L594) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1510](../server/src/routes/admin_routes.js#L1510) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1587](../server/src/routes/admin_routes.js#L1587) |
| Site ID bulunamadi. | [server/src/routes/manager_routes.js:1172](../server/src/routes/manager_routes.js#L1172) |
| Site ID sayisal olmali. | [server/src/routes/admin_routes.js:1489](../server/src/routes/admin_routes.js#L1489) |
| Site katilim QR kodu basariyla yenilendi. Eski QR kodlar iptal edildi. | [server/src/routes/manager_routes.js:590](../server/src/routes/manager_routes.js#L590) |
| Site kaydini yalnizca super user guncelleyebilir. | [server/src/routes/manager_routes.js:357](../server/src/routes/manager_routes.js#L357) |
| Site kaydini yalnizca super user olusturabilir. | [server/src/routes/manager_routes.js:296](../server/src/routes/manager_routes.js#L296) |
| Site kodu olusturulurken cakisma oldu. | [server/src/utils/validators.js:384](../server/src/utils/validators.js#L384) |
| Site kurmak için başvuru yapmalısınız. | [server/src/services/membership_service.js:710](../server/src/services/membership_service.js#L710) |
| Site silme talebi başarıyla iptal edildi / reddedildi. | [server/src/services/site_service.js:1750](../server/src/services/site_service.js#L1750) |
| Site silme talebi oluşturuldu. Site yöneticisinin onayı gerekmektedir. | [server/src/services/site_service.js:1613](../server/src/services/site_service.js#L1613) |
| Site silme talebi oluşturuldu. Süper kullanıcının onayı gerekmektedir. | [server/src/services/site_service.js:1651](../server/src/services/site_service.js#L1651) |
| Site silme talebi zaten oluşturulmuş; Site Yöneticisinin onayı bekleniyor. | [server/src/services/site_service.js:1592](../server/src/services/site_service.js#L1592) |
| Site silme talebi zaten oluşturulmuş; Süper Kullanıcının onayı bekleniyor. | [server/src/services/site_service.js:1630](../server/src/services/site_service.js#L1630) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:869](../server/src/routes/manager_routes.js#L869) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:1179](../server/src/routes/manager_routes.js#L1179) |
| Site talebi baska bir islemle zaten sonuclandirildi. | [server/src/routes/admin_routes.js:889](../server/src/routes/admin_routes.js#L889) |
| Site ve bağlı tüm kayıtlar başarıyla silindi. | [server/src/services/site_service.js:1526](../server/src/services/site_service.js#L1526) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/helpers.js:601](../server/src/utils/helpers.js#L601) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/validators.js:206](../server/src/utils/validators.js#L206) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:805](../server/src/routes/admin_routes.js#L805) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:962](../server/src/routes/admin_routes.js#L962) |
| Site yoneticisi kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:557](../server/src/routes/auth_routes.js#L557) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:659](../server/src/routes/auth_routes.js#L659) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:666](../server/src/routes/auth_routes.js#L666) |
| Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz. | [server/src/utils/site_rules.js:187](../server/src/utils/site_rules.js#L187) |
| Sitenin kurucu yöneticisi (Site Sahibi) yalnızca Süper Kullanıcı tarafından çıkarılabilir. | [server/src/utils/site_rules.js:195](../server/src/utils/site_rules.js#L195) |
| Siteye katılım başvurusu yapabilmek için e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:919](../server/src/services/membership_service.js#L919) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:97](../server/src/mailer.js#L97) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:141](../server/src/mailer.js#L141) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:173](../server/src/mailer.js#L173) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:207](../server/src/mailer.js#L207) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:252](../server/src/mailer.js#L252) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:323](../server/src/mailer.js#L323) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:383](../server/src/mailer.js#L383) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:451](../server/src/mailer.js#L451) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:519](../server/src/mailer.js#L519) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:577](../server/src/mailer.js#L577) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:647](../server/src/mailer.js#L647) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:737](../server/src/mailer.js#L737) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:751](../server/src/mailer.js#L751) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:766](../server/src/mailer.js#L766) |
| SMTP_FROM veya SMTP_USER env degiskeni eksik. | [server/src/mailer.js:798](../server/src/mailer.js#L798) |
| Süper kullanıcı hesabı bu ekrandan silinemez. Hesabın kaldırılması için başka bir süper kullanıcıyla iletişime geçin. | [server/src/modules/account_common.js:63](../server/src/modules/account_common.js#L63) |
| Süper kullanıcı hesabına kayıtlı bir e-posta adresi bulunamadı. | [server/src/services/site_service.js:1788](../server/src/services/site_service.js#L1788) |
| sürüm major.minor.patch biçiminde olmalıdır (örn. 1.2.0). | [server/src/modules/platform_config_service.js:150](../server/src/modules/platform_config_service.js#L150) |
| Şifre en az 4 karakter uzunluğunda olmalıdır. | [server/src/services/membership_service.js:1944](../server/src/services/membership_service.js#L1944) |
| Şifre en az 6 karakter olmalıdır. | [server/src/services/membership_service.js:244](../server/src/services/membership_service.js#L244) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:247](../server/src/services/membership_service.js#L247) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:1947](../server/src/services/membership_service.js#L1947) |
| Şifre güncellenemedi. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:507](../server/src/routes/auth_routes.js#L507) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:444](../server/src/routes/auth_routes.js#L444) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:459](../server/src/routes/auth_routes.js#L459) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:489](../server/src/routes/auth_routes.js#L489) |
| Şifre sıfırlama bağlantısının süresi dolmuş. Lütfen yeni bir talepte bulunun. | [server/src/routes/auth_routes.js:465](../server/src/routes/auth_routes.js#L465) |
| Şifreniz başarıyla güncellendi. Yeni şifrenizle giriş yapabilirsiniz. | [server/src/routes/auth_routes.js:502](../server/src/routes/auth_routes.js#L502) |
| Talep bulunamadı. | [server/src/modules/module_request_routes.js:39](../server/src/modules/module_request_routes.js#L39) |
| tazminat satir sayisi uyusmuyor (${written.rowCount} / ${lines.length}) | [server/src/modules/finance_late_fee.js:586](../server/src/modules/finance_late_fee.js#L586) |
| Tek istekte en fazla ${MAX_DEVICE_LOG_BATCH} kayit gonderilebilir. | [server/src/routes/door_log_routes.js:237](../server/src/routes/door_log_routes.js#L237) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:442](../server/src/services/qr_access_service.js#L442) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:470](../server/src/services/qr_access_service.js#L470) |
| Token parametresi zorunludur. | [server/src/routes/app_doors_routes.js:535](../server/src/routes/app_doors_routes.js#L535) |
| Token zorunludur. | [server/src/services/qr_access_service.js:437](../server/src/services/qr_access_service.js#L437) |
| Toplam daire sayısı en fazla ${SITE_LIMITS.maxApartments} olabilir. | [server/src/services/membership_rules.js:495](../server/src/services/membership_rules.js#L495) |
| toplu eşleme satır sayısı uyuşmuyor | [server/src/modules/finance_accounts.js:963](../server/src/modules/finance_accounts.js#L963) |
| Toplu işlemler geçici olarak kapalı. | [server/src/modules/bulk_import_routes.js:83](../server/src/modules/bulk_import_routes.js#L83) |
| Toplu yetkilendirme için blok, daire veya kullanıcı listesi belirtilmelidir. | [server/src/services/membership_service.js:2472](../server/src/services/membership_service.js#L2472) |
| true veya false olmalıdır. | [server/src/modules/platform_config_service.js:132](../server/src/modules/platform_config_service.js#L132) |
| Üye daireden başarıyla çıkarıldı. | [server/src/services/membership_service.js:1707](../server/src/services/membership_service.js#L1707) |
| Veritabanı sağlık bilgisi alınamadı. | [server/src/services/maintenance_service.js:210](../server/src/services/maintenance_service.js#L210) |
| Veritabanı temizliği başarısız oldu. | [server/src/services/maintenance_service.js:96](../server/src/services/maintenance_service.js#L96) |
| Veritabani saglik bilgisi alinamadi. | [server/src/routes/admin_routes.js:1689](../server/src/routes/admin_routes.js#L1689) |
| Veritabani temizligi sirasinda hata olustu. | [server/src/routes/admin_routes.js:1704](../server/src/routes/admin_routes.js#L1704) |
| yalnızca https:// ile başlayan bağlantı kabul edilir. | [server/src/modules/platform_config_service.js:104](../server/src/modules/platform_config_service.js#L104) |
| Yeni kod istemek için lütfen ${seconds} saniye bekleyiniz. | [server/src/services/membership_rules.js:114](../server/src/services/membership_rules.js#L114) |
| Yeni kullanici kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:514](../server/src/routes/auth_routes.js#L514) |
| Yetkisiz erisim. | [server/src/middlewares/auth_middleware.js:15](../server/src/middlewares/auth_middleware.js#L15) |
| Yetkisiz erisim. | [server/src/middlewares/company_auth.js:43](../server/src/middlewares/company_auth.js#L43) |
| Yetkisiz erisim. | [server/src/routes/admin_routes.js:470](../server/src/routes/admin_routes.js#L470) |
| Yetkisiz erisim. | [server/src/routes/auth_routes.js:815](../server/src/routes/auth_routes.js#L815) |
| Yetkisiz erisim. | [server/src/routes/manager_routes.js:301](../server/src/routes/manager_routes.js#L301) |
| Yönetici daveti iptal edildi. | [server/src/services/site_service.js:2369](../server/src/services/site_service.js#L2369) |
| Yükleme türü bulunamadı. | [server/src/modules/bulk_import_routes.js:86](../server/src/modules/bulk_import_routes.js#L86) |
| Zaten bu dairenin aktif bir sakinisisiniz (${existingMemberRes.rows[0].role}). | [server/src/services/membership_service.js:963](../server/src/services/membership_service.js#L963) |

## Uygulama (Flutter) mesajları (498)

Kaynak: `lib` (`ApiException(...)`, `_errorMessage =`, `lib/services` içindeki `return '...'`).

| Mesaj | Dosya:satır |
| --- | --- |
| "$label" alanı geçersiz. Kontrol edip tekrar deneyin. | [lib/services/contract_api.dart:447](../lib/services/contract_api.dart#L447) |
| <c r="$ref" s="${_Styles.date}"><v>$serial</v></c> | [lib/services/bulk_xlsx_writer.dart:321](../lib/services/bulk_xlsx_writer.dart#L321) |
| <c r="$ref" s="${_Styles.money}"><v>$text</v></c> | [lib/services/bulk_xlsx_writer.dart:316](../lib/services/bulk_xlsx_writer.dart#L316) |
| <c r="$ref" t="inlineStr"$styleAttr><is><t xml:space="preserve">${escapeXml(text)}</t></is></c> | [lib/services/bulk_xlsx_writer.dart:307](../lib/services/bulk_xlsx_writer.dart#L307) |
| <c r="$ref"$styleAttr><v>$text</v></c> | [lib/services/bulk_xlsx_writer.dart:334](../lib/services/bulk_xlsx_writer.dart#L334) |
| ${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8)} | [lib/services/pdf_finance_service.dart:232](../lib/services/pdf_finance_service.dart#L232) |
| ${e.message} Kod 30 dakika geçerlidir; yeni kod için "Kodu Tekrar Gönder"e dokunun. | [lib/services/auth_service.dart:372](../lib/services/auth_service.dart#L372) |
| ${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)} | [lib/services/crash_reporter.dart:617](../lib/services/crash_reporter.dart#L617) |
| ${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)} | [lib/services/push_store.dart:240](../lib/services/push_store.dart#L240) |
| $distance m uzaktasınız, izin verilen mesafe $allowed m. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:3751](../lib/services/auth_api.dart#L3751) |
| $label verisi beklenen formatta degil. | [lib/services/auth_api.dart:4008](../lib/services/auth_api.dart#L4008) |
| $label verisi islenemedi. | [lib/services/auth_api.dart:4006](../lib/services/auth_api.dart#L4006) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/account_api.dart:414](../lib/services/account_api.dart#L414) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/bulk_api.dart:451](../lib/services/bulk_api.dart#L451) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/contract_api.dart:467](../lib/services/contract_api.dart#L467) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/decision_book_api.dart:364](../lib/services/decision_book_api.dart#L364) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/document_api.dart:968](../lib/services/document_api.dart#L968) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/finance_4b_api.dart:1483](../lib/services/finance_4b_api.dart#L1483) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/platform_rules_api.dart:212](../lib/services/platform_rules_api.dart#L212) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/push_api.dart:321](../lib/services/push_api.dart#L321) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/reservation_api.dart:734](../lib/services/reservation_api.dart#L734) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/survey_api.dart:376](../lib/services/survey_api.dart#L376) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/visitor_log_api.dart:395](../lib/services/visitor_log_api.dart#L395) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:945](../lib/services/work_tracking_api.dart#L945) |
| $trimmed Lütfen ${formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/auth_api.dart:3594](../lib/services/auth_api.dart#L3594) |
| $what bilgisi işlenemedi. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1293](../lib/services/finance_4b_api.dart#L1293) |
| $what bilgisi işlenemedi. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1295](../lib/services/finance_4b_api.dart#L1295) |
| $year-${yymmdd.substring(2, 4)}-${yymmdd.substring(4, 6)} | [lib/services/mt940_parser.dart:54](../lib/services/mt940_parser.dart#L54) |
| Aidat tanımı bulunamadı. | [lib/services/auth_api.dart:3917](../lib/services/auth_api.dart#L3917) |
| Aidat ve Finans özelliği bu sitede kapalı. | [lib/services/bank_import_api.dart:35](../lib/services/bank_import_api.dart#L35) |
| Aidat ve Finans özelliği bu sitede kapalı. | [lib/services/finance_payment_api.dart:141](../lib/services/finance_payment_api.dart#L141) |
| Aidat ve Finans özelliği bu sitede kapalı. | [lib/services/payment_notice_api.dart:205](../lib/services/payment_notice_api.dart#L205) |
| Aktarım bulunamadı. | [lib/services/finance_4b_errors.dart:60](../lib/services/finance_4b_errors.dart#L60) |
| Alan bulunamadı ya da artık kullanılamıyor. Listeyi yenileyin. | [lib/services/reservation_api.dart:641](../lib/services/reservation_api.dart#L641) |
| Anket bu durumda bu işleme izin vermiyor. Başkası güncellemiş olabilir; yenileyip tekrar deneyin. | [lib/services/survey_api.dart:351](../lib/services/survey_api.dart#L351) |
| Anket bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/survey_api.dart:349](../lib/services/survey_api.dart#L349) |
| Anket ve Oylama bu site için kapalı. | [lib/services/survey_api.dart:341](../lib/services/survey_api.dart#L341) |
| Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin. | [lib/services/voice_door_service.dart:508](../lib/services/voice_door_service.dart#L508) |
| Anlık konum alınamadı. Lütfen GPS'i kontrol edip tekrar deneyin. | [lib/services/geofence_service.dart:134](../lib/services/geofence_service.dart#L134) |
| Araç bulunamadı. | [lib/services/auth_api.dart:3626](../lib/services/auth_api.dart#L3626) |
| Ayarlar başka biri tarafından değiştirilmiş. Güncel ayarlar yüklendi; kontrol edip yeniden kaydedin. | [lib/services/finance_4b_errors.dart:130](../lib/services/finance_4b_errors.dart#L130) |
| Ayarlar siz bakarken değişti. Ekranı yenileyip tekrar deneyin. | [lib/services/finance_payment_api.dart:137](../lib/services/finance_payment_api.dart#L137) |
| Aynı duyuru az önce yayınlandı. Çift gönderimi önlemek için bir dakika bekleyin. | [lib/services/auth_api.dart:3638](../lib/services/auth_api.dart#L3638) |
| Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Önce daire hesaplarını kontrol edin. | [lib/services/auth_api.dart:3907](../lib/services/auth_api.dart#L3907) |
| Aynı gider kısa süre önce kaydedilmiş görünüyor. Önce gider listesini kontrol edin. | [lib/services/finance_4b_errors.dart:76](../lib/services/finance_4b_errors.dart#L76) |
| Bağlantı hatası: $e | [lib/ui/widgets/door_logs_accordion.dart:113](../lib/ui/widgets/door_logs_accordion.dart#L113) |
| Başlangıç zamanı geçmiş rezervasyon onaylanamaz. | [lib/services/reservation_api.dart:702](../lib/services/reservation_api.dart#L702) |
| Başvuran hesap silinmiş, pasif, e-postası doğrulanmamış ya da onaysız olabilir; başvuru onaylanamaz. | [lib/services/auth_api.dart:3878](../lib/services/auth_api.dart#L3878) |
| Başvuru bulunamadı. | [lib/services/auth_api.dart:3871](../lib/services/auth_api.dart#L3871) |
| Başvuru durumu yanıtı anlaşılamadı. Tekrar deneyin. | [lib/services/auth_api.dart:1225](../lib/services/auth_api.dart#L1225) |
| Başvurudaki yapı verisi geçersiz; onaylanamaz. Reddedip başvuranın yeniden başvurmasını isteyin. | [lib/services/auth_api.dart:3876](../lib/services/auth_api.dart#L3876) |
| Bazı dairelerin bilgisi eksik. Eksikleri tamamlayın ya da bu daireleri atlayarak devam edin. | [lib/services/auth_api.dart:3889](../lib/services/auth_api.dart#L3889) |
| Belge bulunamadı ya da erişiminiz yok. | [lib/services/document_api.dart:934](../lib/services/document_api.dart#L934) |
| Belge bulunamadı. | [lib/services/finance_4b_errors.dart:90](../lib/services/finance_4b_errors.dart#L90) |
| Belge bulunamadı. | [lib/services/legal_api.dart:64](../lib/services/legal_api.dart#L64) |
| Belge bulunamadı. | [lib/services/legal_api.dart:223](../lib/services/legal_api.dart#L223) |
| Belge depolama şu an kullanılamıyor. Gider ek belgesiz kaydedilebilir. | [lib/services/finance_4b_errors.dart:104](../lib/services/finance_4b_errors.dart#L104) |
| Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin. | [lib/services/document_api.dart:950](../lib/services/document_api.dart#L950) |
| Belge ekleme şu an kullanılamıyor. Gider ek belgesiz kaydedilebilir. | [lib/services/finance_4b_errors.dart:86](../lib/services/finance_4b_errors.dart#L86) |
| Belge sürümü bulunamadı. | [lib/services/document_api.dart:936](../lib/services/document_api.dart#L936) |
| Belge yükleme şu an kullanılamıyor. | [lib/services/document_api.dart:953](../lib/services/document_api.dart#L953) |
| Belgenin durumu değişmiş. Listeyi yenileyip tekrar deneyin. | [lib/services/document_api.dart:955](../lib/services/document_api.dart#L955) |
| Bir gidere en çok 5 belge eklenebilir. | [lib/services/finance_4b_errors.dart:88](../lib/services/finance_4b_errors.dart#L88) |
| Bir seferde en çok 5.000 satır yüklenebilir. | [lib/services/bulk_api.dart:31](../lib/services/bulk_api.dart#L31) |
| Birden çok benzer tahsilat var. "Mevcut tahsilata bağla" ile birini seçin. | [lib/services/bank_import_api.dart:29](../lib/services/bank_import_api.dart#L29) |
| Bluetooth islemi basarisiz oldu. | [lib/services/ble_wifi_provision_service.dart:534](../lib/services/ble_wifi_provision_service.dart#L534) |
| Borç hatırlatma bu site için kapalı. Ayarlar bölümünden açın. | [lib/services/finance_4b_errors.dart:117](../lib/services/finance_4b_errors.dart#L117) |
| Borçlandırılacak daire bulunamadı. Hedefi ve daire bilgilerini kontrol edin. | [lib/services/auth_api.dart:3903](../lib/services/auth_api.dart#L3903) |
| Borçlandırılmış tanımın tutarı ve dağıtımı değiştirilemez. Yeni bir tanım ekleyin. | [lib/services/auth_api.dart:3899](../lib/services/auth_api.dart#L3899) |
| Bu adla başka bir hesap var. Farklı bir ad seçin. | [lib/services/finance_4b_errors.dart:56](../lib/services/finance_4b_errors.dart#L56) |
| Bu adla kayıtlı bir firma zaten var. Farklı bir ad girin ya da mevcut firmayı kullanın. | [lib/services/contract_api.dart:422](../lib/services/contract_api.dart#L422) |
| Bu aktarım zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:62](../lib/services/finance_4b_errors.dart#L62) |
| Bu alan şu anda rezervasyona kapalı. | [lib/services/reservation_api.dart:661](../lib/services/reservation_api.dart#L661) |
| Bu alanda aynı saatlerde zaten rezervasyonunuz var. | [lib/services/reservation_api.dart:678](../lib/services/reservation_api.dart#L678) |
| Bu anket oylamaya kapalı. | [lib/services/survey_api.dart:353](../lib/services/survey_api.dart#L353) |
| Bu anketin hedef kitlesinde değilsiniz. | [lib/services/survey_api.dart:359](../lib/services/survey_api.dart#L359) |
| Bu ankette daireniz adına zaten oy kullanılmış (daire başına tek oy). | [lib/services/survey_api.dart:357](../lib/services/survey_api.dart#L357) |
| Bu ankette zaten oy kullandınız. Oy değiştirilemez. | [lib/services/survey_api.dart:355](../lib/services/survey_api.dart#L355) |
| Bu ay henüz bitmedi. Tazminat yalnızca bitmiş ay için hesaplanır. | [lib/services/finance_4b_errors.dart:33](../lib/services/finance_4b_errors.dart#L33) |
| Bu ay için tazminat zaten yazılmış. Değiştirmek için önce son çalıştırmayı iptal edin. | [lib/services/finance_4b_errors.dart:37](../lib/services/finance_4b_errors.dart#L37) |
| Bu ay kapatılamaz: hesaba eşlenmemiş tahsilatlar var. Kasa bölümündeki "Toplu Eşle" ile eşleyin. | [lib/services/finance_4b_errors.dart:69](../lib/services/finance_4b_errors.dart#L69) |
| Bu ay kapatılamaz: zaten kapalı, gelecekte ya da 5 yıldan eski. Listeden bir ay seçin. | [lib/services/auth_api.dart:3895](../lib/services/auth_api.dart#L3895) |
| Bu ay yeniden açılamaz: sonraki aylar için tazminat çalıştırması var. Önce çalıştırmayı iptal edin. | [lib/services/finance_4b_errors.dart:43](../lib/services/finance_4b_errors.dart#L43) |
| Bu ay yeniden açılamaz. Yalnızca en son kapatılan ay açılabilir. | [lib/services/auth_api.dart:3897](../lib/services/auth_api.dart#L3897) |
| Bu başvuru artık bekleyen durumda değil. | [lib/services/auth_api.dart:3873](../lib/services/auth_api.dart#L3873) |
| Bu belge duyuruya eklenemez. Yalnız sakinlere açık, yayındaki belgeler eklenebilir. | [lib/services/document_api.dart:942](../lib/services/document_api.dart#L942) |
| Bu belge yayındaki bir duyuruya ekli. | [lib/services/document_api.dart:938](../lib/services/document_api.dart#L938) |
| Bu belgenin sürüm sınırına ulaşıldı. Eski sürümleri silin. | [lib/services/document_api.dart:932](../lib/services/document_api.dart#L932) |
| Bu cihaz arızalı olarak işaretlenmiş. | [lib/services/auth_api.dart:3797](../lib/services/auth_api.dart#L3797) |
| Bu cihaz başka bir hesaba ait. | [lib/services/auth_api.dart:3795](../lib/services/auth_api.dart#L3795) |
| Bu cihaz bu kapıya atanamaz. | [lib/services/auth_api.dart:3793](../lib/services/auth_api.dart#L3793) |
| Bu çalıştırma iptal edilemiyor: yalnızca son (aktif) tazminat çalıştırması iptal edilir; başka bir yönetici zaten iptal etmiş olabilir. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:41](../lib/services/finance_4b_errors.dart#L41) |
| Bu dairede bu ilişki için aktif bir kişi zaten var. | [lib/services/auth_api.dart:3842](../lib/services/auth_api.dart#L3842) |
| Bu devir yüklemesi zaten geri alınmış. | [lib/services/bulk_api.dart:56](../lib/services/bulk_api.dart#L56) |
| Bu dosya bu hesaba daha önce yüklenmiş. | [lib/services/bank_import_api.dart:19](../lib/services/bank_import_api.dart#L19) |
| Bu dosya türü desteklenmiyor. ${DocumentFileRules.allowedLabel} yükleyin. | [lib/services/document_api.dart:912](../lib/services/document_api.dart#L912) |
| Bu dosya türü kabul edilmiyor. Yalnızca PDF, JPG ve PNG eklenebilir. | [lib/services/finance_4b_errors.dart:95](../lib/services/finance_4b_errors.dart#L95) |
| Bu dönem kapatılmış; kapalı döneme kayıt eklenemez. Kapalı ayı yalnızca süper kullanıcı yeniden açabilir. | [lib/services/auth_api.dart:3893](../lib/services/auth_api.dart#L3893) |
| Bu e-posta ile kayıtlı bir kişi zaten var. | [lib/services/auth_api.dart:3838](../lib/services/auth_api.dart#L3838) |
| Bu e-posta ile kayıtlı hesap yok. | [lib/services/auth_api.dart:3816](../lib/services/auth_api.dart#L3816) |
| Bu fotoğrafı yalnız ekleyen kişi ya da yönetici silebilir. | [lib/services/work_tracking_api.dart:929](../lib/services/work_tracking_api.dart#L929) |
| Bu fotoğrafın yüklemesi zaten sürüyor. Biraz sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:899](../lib/services/work_tracking_api.dart#L899) |
| Bu gider kategorisi pasif. Başka bir kategori seçin. | [lib/services/finance_4b_errors.dart:82](../lib/services/finance_4b_errors.dart#L82) |
| Bu gider zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:74](../lib/services/finance_4b_errors.dart#L74) |
| Bu hatırlatma çalıştırması iptal edilemez (zaten iptal edilmiş). | [lib/services/finance_4b_errors.dart:127](../lib/services/finance_4b_errors.dart#L127) |
| Bu hesap henüz etkin değil. | [lib/services/auth_api.dart:3818](../lib/services/auth_api.dart#L3818) |
| Bu hesap pasif; pasif hesaba yeni hareket yazılamaz. | [lib/services/finance_4b_errors.dart:50](../lib/services/finance_4b_errors.dart#L50) |
| Bu ilişki artık güncel değil. | [lib/services/auth_api.dart:3630](../lib/services/auth_api.dart#L3630) |
| Bu isimde bir kapı bulunamadı. Lütfen kapının adını veya numarasını söyleyin. | [lib/services/voice_door_service.dart:503](../lib/services/voice_door_service.dart#L503) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:2398](../lib/services/auth_service.dart#L2398) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:3269](../lib/services/auth_service.dart#L3269) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:722](../lib/services/auth_service.dart#L722) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:756](../lib/services/auth_service.dart#L756) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:786](../lib/services/auth_service.dart#L786) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:807](../lib/services/auth_service.dart#L807) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:894](../lib/services/auth_service.dart#L894) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:928](../lib/services/auth_service.dart#L928) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:2609](../lib/services/auth_service.dart#L2609) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:3060](../lib/services/auth_service.dart#L3060) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:3084](../lib/services/auth_service.dart#L3084) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:3250](../lib/services/auth_service.dart#L3250) |
| Bu islem icin yetkiniz bulunmamaktadir. | [lib/services/auth_service.dart:965](../lib/services/auth_service.dart#L965) |
| Bu işlem daha önce başka bilgilerle gönderilmiş. Lütfen bilgileri kontrol edip tekrar deneyin. | [lib/services/reservation_api.dart:715](../lib/services/reservation_api.dart#L715) |
| Bu işlem daha önce farklı bilgilerle gönderilmiş görünüyor. Önce daire hesaplarını kontrol edin. | [lib/services/auth_api.dart:3905](../lib/services/auth_api.dart#L3905) |
| Bu işlem için yetkiniz yok. | [lib/services/auth_api.dart:3850](../lib/services/auth_api.dart#L3850) |
| Bu işlem için yetkiniz yok. | [lib/services/decision_book_api.dart:331](../lib/services/decision_book_api.dart#L331) |
| Bu işlem için yetkiniz yok. | [lib/services/device_integrations_api.dart:239](../lib/services/device_integrations_api.dart#L239) |
| Bu işlem için yetkiniz yok. | [lib/services/equipment_api.dart:377](../lib/services/equipment_api.dart#L377) |
| Bu işlem için yetkiniz yok. | [lib/services/reservation_api.dart:633](../lib/services/reservation_api.dart#L633) |
| Bu işlem için yetkiniz yok. | [lib/services/survey_api.dart:343](../lib/services/survey_api.dart#L343) |
| Bu işlem için yetkiniz yok. | [lib/services/visitor_log_api.dart:363](../lib/services/visitor_log_api.dart#L363) |
| Bu işlem için yetkiniz yok. | [lib/services/work_tracking_api.dart:820](../lib/services/work_tracking_api.dart#L820) |
| Bu işlem için yetkiniz yok. Sözleşmeleri yalnızca site yöneticisi düzenleyebilir. | [lib/services/contract_api.dart:414](../lib/services/contract_api.dart#L414) |
| Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin. | [lib/services/auth_api.dart:3738](../lib/services/auth_api.dart#L3738) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen kapı ekranındaki güncel karekodu okutun. | [lib/services/auth_api.dart:3771](../lib/services/auth_api.dart#L3771) |
| Bu kapıda QR ile giriş şu an devre dışı. | [lib/services/auth_api.dart:3763](../lib/services/auth_api.dart#L3763) |
| Bu kapıyı açma yetkiniz yok. | [lib/services/auth_api.dart:3787](../lib/services/auth_api.dart#L3787) |
| Bu karar kesinleşmiş; değiştirilemez ya da silinemez. Düzeltme gerekirse yeni bir karar yazın. | [lib/services/decision_book_api.dart:339](../lib/services/decision_book_api.dart#L339) |
| Bu karekod daha önce kullanıldı. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:3773](../lib/services/auth_api.dart#L3773) |
| Bu kayıt iptal ya da düzeltme için uygun değil. Ters kayıtlar iptal edilemez. | [lib/services/auth_api.dart:3913](../lib/services/auth_api.dart#L3913) |
| Bu kayıt zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/auth_api.dart:3911](../lib/services/auth_api.dart#L3911) |
| Bu kişi zaten site yöneticisi. | [lib/services/auth_api.dart:3820](../lib/services/auth_api.dart#L3820) |
| Bu kişide kurul veya görevli rolü yok. | [lib/services/auth_api.dart:3824](../lib/services/auth_api.dart#L3824) |
| Bu makbuz iptal edilemez. İptal makbuzları iptal edilemez. | [lib/services/finance_4b_errors.dart:24](../lib/services/finance_4b_errors.dart#L24) |
| Bu makbuz zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:22](../lib/services/finance_4b_errors.dart#L22) |
| Bu modül bu site için kapalı. | [lib/services/device_integrations_api.dart:237](../lib/services/device_integrations_api.dart#L237) |
| Bu modül bu site için kapalı. | [lib/services/equipment_api.dart:375](../lib/services/equipment_api.dart#L375) |
| Bu modül için bekleyen bir talebiniz var. | [lib/services/auth_api.dart:3831](../lib/services/auth_api.dart#L3831) |
| Bu modül kapatılamaz. | [lib/services/auth_api.dart:3808](../lib/services/auth_api.dart#L3808) |
| Bu modül yakında. | [lib/services/auth_api.dart:3806](../lib/services/auth_api.dart#L3806) |
| Bu modül zaten açık. | [lib/services/auth_api.dart:3829](../lib/services/auth_api.dart#L3829) |
| Bu ödeme iptal edilmiş; iptal edilmiş ödeme için makbuz düzenlenemez. | [lib/services/finance_4b_errors.dart:20](../lib/services/finance_4b_errors.dart#L20) |
| Bu önek başka bir sitede kullanılıyor. Başka bir önek seçin. | [lib/services/finance_payment_api.dart:135](../lib/services/finance_payment_api.dart#L135) |
| Bu özellik hukuki onay bekliyor; onaylanınca kullanılabilir. | [lib/services/finance_4b_errors.dart:132](../lib/services/finance_4b_errors.dart#L132) |
| Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir. | [lib/services/auth_api.dart:3804](../lib/services/auth_api.dart#L3804) |
| Bu PDF kabul edilemedi. Dekontun ekran görüntüsünü yüklemeyi deneyin. | [lib/services/payment_notice_api.dart:203](../lib/services/payment_notice_api.dart#L203) |
| Bu plaka bu sitede zaten kayıtlı. | [lib/services/auth_api.dart:3848](../lib/services/auth_api.dart#L3848) |
| Bu platform MQTT TCP baglantisini desteklemiyor. | [lib/services/mqtt_door_service_stub.dart:41](../lib/services/mqtt_door_service_stub.dart#L41) |
| Bu satır artık işlenmeyi beklemiyor. Listeyi yenileyin. | [lib/services/bank_import_api.dart:23](../lib/services/bank_import_api.dart#L23) |
| Bu site için başka bir yükleme sürüyor. | [lib/services/bulk_api.dart:35](../lib/services/bulk_api.dart#L35) |
| Bu site için günlük duyuru sınırına ulaşıldı. Yarın tekrar deneyin. | [lib/services/auth_api.dart:3640](../lib/services/auth_api.dart#L3640) |
| Bu site için yetkiniz yok. | [lib/services/bulk_api.dart:52](../lib/services/bulk_api.dart#L52) |
| Bu sitede aynı adlı bir alan zaten var. Başka bir ad seçin. | [lib/services/reservation_api.dart:656](../lib/services/reservation_api.dart#L656) |
| Bu sitede dekont bildirimi henüz açık değil. Yönetime sorun. | [lib/services/payment_notice_api.dart:193](../lib/services/payment_notice_api.dart#L193) |
| Bu sitede kasa ya da banka hesabı tanımlı; tahsilat için bir hesap seçin. | [lib/services/finance_4b_errors.dart:52](../lib/services/finance_4b_errors.dart#L52) |
| Bu sitede misafir geçişi kapalı. | [lib/services/auth_api.dart:3765](../lib/services/auth_api.dart#L3765) |
| Bu sitede QR ile giriş kapalı. | [lib/services/auth_api.dart:3761](../lib/services/auth_api.dart#L3761) |
| Bu sitede talep açabilmek için daire sakini olmalısınız. | [lib/services/work_tracking_api.dart:824](../lib/services/work_tracking_api.dart#L824) |
| Bu sitede uygulamadan uzaktan kapı açma kapalı. | [lib/services/auth_api.dart:3759](../lib/services/auth_api.dart#L3759) |
| Bu sitede yerel ağdan kapı açma kapalı. | [lib/services/auth_api.dart:3767](../lib/services/auth_api.dart#L3767) |
| Bu sitenin konum çemberi hatalı tanımlanmış. Lütfen site yöneticinize başvurun. | [lib/services/auth_api.dart:3755](../lib/services/auth_api.dart#L3755) |
| Bu sitenin kurallarını görme yetkiniz yok. | [lib/services/platform_rules_api.dart:186](../lib/services/platform_rules_api.dart#L186) |
| Bu siteye erişim yetkiniz yok. | [lib/services/contract_api.dart:416](../lib/services/contract_api.dart#L416) |
| Bu siteye erişim yetkiniz yok. | [lib/services/decision_book_api.dart:333](../lib/services/decision_book_api.dart#L333) |
| Bu siteye erişim yetkiniz yok. | [lib/services/device_integrations_api.dart:241](../lib/services/device_integrations_api.dart#L241) |
| Bu siteye erişim yetkiniz yok. | [lib/services/equipment_api.dart:379](../lib/services/equipment_api.dart#L379) |
| Bu siteye erişim yetkiniz yok. | [lib/services/reservation_api.dart:635](../lib/services/reservation_api.dart#L635) |
| Bu siteye erişim yetkiniz yok. | [lib/services/survey_api.dart:345](../lib/services/survey_api.dart#L345) |
| Bu siteye erişim yetkiniz yok. | [lib/services/visitor_log_api.dart:365](../lib/services/visitor_log_api.dart#L365) |
| Bu siteye erişim yetkiniz yok. | [lib/services/work_tracking_api.dart:822](../lib/services/work_tracking_api.dart#L822) |
| Bu tahsilat bağlanamaz (tutar uyuşmuyor, iptal edilmiş ya da başka satıra bağlı). | [lib/services/bank_import_api.dart:31](../lib/services/bank_import_api.dart#L31) |
| Bu talebe daha fazla yorum eklenemez. | [lib/services/work_tracking_api.dart:847](../lib/services/work_tracking_api.dart#L847) |
| Bu talep artık bekleyen durumda değil. | [lib/services/auth_api.dart:3835](../lib/services/auth_api.dart#L3835) |
| Bu talep kapandığı ya da iptal edildiği için değiştirilemez. | [lib/services/work_tracking_api.dart:843](../lib/services/work_tracking_api.dart#L843) |
| Bu tanım bu dönem için zaten borçlandırılmış. Aynı ay ikinci kez borçlandırılamaz. | [lib/services/auth_api.dart:3891](../lib/services/auth_api.dart#L3891) |
| Bu tanım pasif ya da bu dönemde geçerli değil. Tanımı etkinleştirin veya dönemi kontrol edin. | [lib/services/auth_api.dart:3909](../lib/services/auth_api.dart#L3909) |
| Bu tarihin dönemi kapatılmış. Önce dönemi açın. | [lib/services/bank_import_api.dart:33](../lib/services/bank_import_api.dart#L33) |
| Bu tedarikçiden aynı belge numarasıyla iptal edilmemiş bir gider zaten var. | [lib/services/finance_4b_errors.dart:78](../lib/services/finance_4b_errors.dart#L78) |
| Bu yönetim türü yakında. | [lib/services/auth_api.dart:3812](../lib/services/auth_api.dart#L3812) |
| Bu yükleme farklı bilgilerle daha önce gönderilmiş. Dosyayı yeniden seçin. | [lib/services/bank_import_api.dart:37](../lib/services/bank_import_api.dart#L37) |
| Bu yükleme farklı bilgilerle daha önce gönderilmiş. Dosyayı yeniden seçip yükleyin. | [lib/services/bulk_api.dart:50](../lib/services/bulk_api.dart#L50) |
| Bu yükleme türü bulunamadı. | [lib/services/bulk_api.dart:47](../lib/services/bulk_api.dart#L47) |
| Bu yükleme zaten geri alınmış. | [lib/services/bank_import_api.dart:27](../lib/services/bank_import_api.dart#L27) |
| Bu yükleme zaten tamamlanmış. | [lib/services/document_api.dart:944](../lib/services/document_api.dart#L944) |
| Bugün zaten bir hatırlatma gönderildi. Günde en çok bir çalıştırma yapılabilir. | [lib/services/finance_4b_errors.dart:119](../lib/services/finance_4b_errors.dart#L119) |
| Cihaz bulunamadı. | [lib/services/auth_api.dart:3799](../lib/services/auth_api.dart#L3799) |
| Cihaz bulunamadı. Listeyi yenileyip tekrar deneyin. | [lib/services/push_api.dart:304](../lib/services/push_api.dart#L304) |
| Cihaz sahiplenme sırasında bir hata oluştu. | [lib/ui/widgets/claim_device_dialog.dart:83](../lib/ui/widgets/claim_device_dialog.dart#L83) |
| Cihaz şu an çevrimdışı. Cihazın internet bağlantısını kontrol edin. | [lib/services/auth_api.dart:3791](../lib/services/auth_api.dart#L3791) |
| Cihazlar yüklenirken bir sorun oluştu. | [lib/ui/views/individual_home_view.dart:204](../lib/ui/views/individual_home_view.dart#L204) |
| Çok fazla bekleyen bildiriminiz var. Yönetim karar verdikten sonra yenisini gönderin. | [lib/services/payment_notice_api.dart:195](../lib/services/payment_notice_api.dart#L195) |
| Çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:3731](../lib/services/auth_api.dart#L3731) |
| Çok fazla istek gönderildi. | [lib/services/auth_api.dart:3615](../lib/services/auth_api.dart#L3615) |
| Çok fazla kayıt var. Süzgeçle daraltın. | [lib/services/bulk_api.dart:43](../lib/services/bulk_api.dart#L43) |
| Daire bulunamadı. | [lib/services/auth_api.dart:3844](../lib/services/auth_api.dart#L3844) |
| Dekontun tarihi kapalı bir döneme düşüyor. "Açık döneme yaz" seçeneğiyle bugünün tarihine işleyebilirsiniz. | [lib/services/payment_notice_api.dart:199](../lib/services/payment_notice_api.dart#L199) |
| Devam etmek için onay kutusunu işaretleyin. | [lib/services/bulk_api.dart:41](../lib/services/bulk_api.dart#L41) |
| Devam etmek için şifrenizi girin. | [lib/services/account_api.dart:392](../lib/services/account_api.dart#L392) |
| Devir kayıtları değişti. Ayrıntıyı yenileyip tekrar inceleyin. | [lib/services/bulk_api.dart:58](../lib/services/bulk_api.dart#L58) |
| Devir yüklemesi bulunamadı. | [lib/services/bulk_api.dart:60](../lib/services/bulk_api.dart#L60) |
| Dışa aktarılacak veri çok büyük (en çok 20.000 satır). Süzgeçlerle daraltın. | [lib/services/finance_4b_errors.dart:114](../lib/services/finance_4b_errors.dart#L114) |
| Doğrulama işlemi sırasında hata oluştu. | [lib/services/auth_service.dart:376](../lib/services/auth_service.dart#L376) |
| Dosya boyutu yükleme sırasında değişti. Dosyayı yeniden seçip tekrar deneyin. | [lib/services/document_api.dart:924](../lib/services/document_api.dart#L924) |
| Dosya çok büyük (en fazla 10 MB). | [lib/services/payment_notice_api.dart:173](../lib/services/payment_notice_api.dart#L173) |
| Dosya çok büyük. | [lib/services/finance_4b_api.dart:1377](../lib/services/finance_4b_api.dart#L1377) |
| Dosya çok büyük. | [lib/services/finance_4b_api.dart:1384](../lib/services/finance_4b_api.dart#L1384) |
| Dosya çok büyük. Daha küçük bir dosya seçin. | [lib/services/finance_4b_errors.dart:92](../lib/services/finance_4b_errors.dart#L92) |
| Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk. | [lib/services/document_api.dart:914](../lib/services/document_api.dart#L914) |
| Dosya indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/payment_notice_api.dart:161](../lib/services/payment_notice_api.dart#L161) |
| Dosya taraması şu an yapılamıyor. Biraz sonra tekrar deneyin. | [lib/services/document_api.dart:920](../lib/services/document_api.dart#L920) |
| Dosya zararlı yazılım içerdiği için reddedildi. | [lib/services/document_api.dart:918](../lib/services/document_api.dart#L918) |
| Dosyada çalıştırılabilir içerik bulundu; güvenlik nedeniyle kabul edilmedi. | [lib/services/finance_4b_errors.dart:97](../lib/services/finance_4b_errors.dart#L97) |
| Duyuru bulunamadı ya da artık yayında değil. | [lib/services/auth_api.dart:3853](../lib/services/auth_api.dart#L3853) |
| Duyurunun durumu değişmiş. Listeyi yenileyip tekrar deneyin. | [lib/services/auth_api.dart:3855](../lib/services/auth_api.dart#L3855) |
| E-posta gönderimi yapılandırılmamış; hatırlatma gönderilemez. | [lib/services/finance_4b_errors.dart:123](../lib/services/finance_4b_errors.dart#L123) |
| Ekstre çok uzun (5.000 satırdan fazla). Tarih aralığını daraltın. | [lib/services/finance_4b_errors.dart:107](../lib/services/finance_4b_errors.dart#L107) |
| En çok 20 hesap tanımlanabilir. | [lib/services/finance_4b_errors.dart:54](../lib/services/finance_4b_errors.dart#L54) |
| Etkin içerik (betik) taşıyan PDF yüklenemez. | [lib/services/document_api.dart:916](../lib/services/document_api.dart#L916) |
| Firma bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/contract_api.dart:420](../lib/services/contract_api.dart#L420) |
| Firma ve sözleşme takibi bu site için kapalı. | [lib/services/contract_api.dart:412](../lib/services/contract_api.dart#L412) |
| Fotoğraf alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/work_tracking_api.dart:535](../lib/services/work_tracking_api.dart#L535) |
| Fotoğraf alınamadı. Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/work_tracking_api.dart:502](../lib/services/work_tracking_api.dart#L502) |
| Fotoğraf bozuk ya da türü dosya uzantısıyla uyuşmuyor. Başka bir fotoğraf seçin. | [lib/services/work_tracking_api.dart:914](../lib/services/work_tracking_api.dart#L914) |
| Fotoğraf çok büyük olduğu için açılamadı. | [lib/services/work_tracking_api.dart:531](../lib/services/work_tracking_api.dart#L531) |
| Fotoğraf deposu şu anda kullanılamıyor. Biraz sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:910](../lib/services/work_tracking_api.dart#L910) |
| Fotoğraf dosyası sunucuda bulunamadı. | [lib/services/work_tracking_api.dart:912](../lib/services/work_tracking_api.dart#L912) |
| Fotoğraf eklemek ya da silmek için bu sitede daire sakini olmalısınız. | [lib/services/work_tracking_api.dart:932](../lib/services/work_tracking_api.dart#L932) |
| Fotoğraf eksik indi. Tekrar deneyin. | [lib/services/work_tracking_api.dart:544](../lib/services/work_tracking_api.dart#L544) |
| Fotoğraf gönderilirken boyutu değişti. Yeniden seçip tekrar deneyin. | [lib/services/work_tracking_api.dart:916](../lib/services/work_tracking_api.dart#L916) |
| Fotoğraf içeriği boş geldi. Tekrar deneyin. | [lib/services/work_tracking_api.dart:547](../lib/services/work_tracking_api.dart#L547) |
| Fotoğraf okunamadı. Yeniden seçip tekrar deneyin. | [lib/services/work_tracking_api.dart:363](../lib/services/work_tracking_api.dart#L363) |
| Fotoğraf zaten yüklenmiş. | [lib/services/work_tracking_api.dart:901](../lib/services/work_tracking_api.dart#L901) |
| Gecikme tazminatı | [lib/services/pdf_finance_service.dart:544](../lib/services/pdf_finance_service.dart#L544) |
| Gecikme tazminatı bu site için kapalı. Ayarlar bölümünden açın. | [lib/services/finance_4b_errors.dart:27](../lib/services/finance_4b_errors.dart#L27) |
| Gecikme tazminatı için ilk hesaplanacak ay (başlangıç ayı) belirlenmemiş. Ayarlar bölümünden seçin. | [lib/services/finance_4b_errors.dart:29](../lib/services/finance_4b_errors.dart#L29) |
| Geçersiz kapı bilgisi. | [lib/services/auth_api.dart:3783](../lib/services/auth_api.dart#L3783) |
| Geçersiz sorgu. Süzgeçleri kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3620](../lib/services/auth_api.dart#L3620) |
| Geçersiz yönetim türü. | [lib/services/auth_api.dart:3814](../lib/services/auth_api.dart#L3814) |
| Gelir/gider olarak ayrılmış satırlar var. Önce onları tek tek geri alın. | [lib/services/bank_import_api.dart:25](../lib/services/bank_import_api.dart#L25) |
| Gider bulunamadı. | [lib/services/finance_4b_errors.dart:72](../lib/services/finance_4b_errors.dart#L72) |
| Gider kategorisi bulunamadı. | [lib/services/finance_4b_errors.dart:80](../lib/services/finance_4b_errors.dart#L80) |
| Gider kaydı için bir kasa ya da banka hesabı gerekir. Önce Kasa bölümünden hesap ekleyin. | [lib/services/finance_4b_errors.dart:46](../lib/services/finance_4b_errors.dart#L46) |
| Girilen bilgiler geçersiz. | [lib/services/device_integrations_api.dart:244](../lib/services/device_integrations_api.dart#L244) |
| Girilen bilgilerden biri geçersiz. Alanları kontrol edip tekrar deneyin. | [lib/services/contract_api.dart:445](../lib/services/contract_api.dart#L445) |
| Giriş oturumu bulunamadı. | [lib/ui/widgets/door_logs_accordion.dart:76](../lib/ui/widgets/door_logs_accordion.dart#L76) |
| Gönderilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3618](../lib/services/auth_api.dart#L3618) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/contract_api.dart:454](../lib/services/contract_api.dart#L454) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/decision_book_api.dart:355](../lib/services/decision_book_api.dart#L355) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/reservation_api.dart:721](../lib/services/reservation_api.dart#L721) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/survey_api.dart:367](../lib/services/survey_api.dart#L367) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/visitor_log_api.dart:382](../lib/services/visitor_log_api.dart#L382) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/work_tracking_api.dart:853](../lib/services/work_tracking_api.dart#L853) |
| GPS doğruluğu yetersiz. Açık alana çıkıp tekrar deneyin. | [lib/services/auth_api.dart:3746](../lib/services/auth_api.dart#L3746) |
| GPS doğruluğu yetersiz$acc. Lütfen açık alana çıkıp tekrar deneyin. | [lib/services/geofence_service.dart:86](../lib/services/geofence_service.dart#L86) |
| GPS sinyali alınamadı (zaman aşımı). Açık alanda tekrar deneyin. | [lib/services/geofence_service.dart:126](../lib/services/geofence_service.dart#L126) |
| Hangi kapıyı açmamı istersiniz?$suffix Örneğin "1. kapıyı aç" veya kapının adını söyleyin. | [lib/services/voice_door_service.dart:501](../lib/services/voice_door_service.dart#L501) |
| Hata: $e | [lib/ui/widgets/device_connectivity_logs_accordion.dart:103](../lib/ui/widgets/device_connectivity_logs_accordion.dart#L103) |
| Hatalı satırlar var. Düzeltip yeniden yükleyin. | [lib/services/bulk_api.dart:29](../lib/services/bulk_api.dart#L29) |
| Hatırlatma çalıştırması bulunamadı. | [lib/services/finance_4b_errors.dart:125](../lib/services/finance_4b_errors.dart#L125) |
| Hatırlatma gönderilecek kimse bulunamadı. | [lib/services/finance_4b_errors.dart:121](../lib/services/finance_4b_errors.dart#L121) |
| Hedef geçersiz. Seçilen blok ve daireleri kontrol edin. | [lib/services/document_api.dart:940](../lib/services/document_api.dart#L940) |
| Henüz kapatılmış ay yok. | [lib/services/pdf_finance_service.dart:502](../lib/services/pdf_finance_service.dart#L502) |
| Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir. | [lib/services/auth_api.dart:3840](../lib/services/auth_api.dart#L3840) |
| Hesabınız şu anda silinemez. Nedenleri aşağıda görebilirsiniz. | [lib/services/account_api.dart:400](../lib/services/account_api.dart#L400) |
| Hesap bakiyesi siz bakarken değişti. Güncel bakiyeyi kontrol edip yeniden onaylayın. | [lib/services/finance_4b_errors.dart:64](../lib/services/finance_4b_errors.dart#L64) |
| Hesap bulunamadı. | [lib/services/finance_4b_errors.dart:48](../lib/services/finance_4b_errors.dart#L48) |
| Hesap bulunamadı. | [lib/services/finance_payment_api.dart:139](../lib/services/finance_payment_api.dart#L139) |
| IBAN geçersiz. TR ile başlayan 26 haneli, sağlama basamağı doğru bir IBAN girin. | [lib/services/finance_payment_api.dart:133](../lib/services/finance_payment_api.dart#L133) |
| İkili Excel biçimi (.xlsb) desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin. | [lib/services/bulk_file_parser.dart:88](../lib/services/bulk_file_parser.dart#L88) |
| İlişki kaydı bulunamadı. | [lib/services/auth_api.dart:3628](../lib/services/auth_api.dart#L3628) |
| İş takibi bu site için kapalı. | [lib/services/work_tracking_api.dart:818](../lib/services/work_tracking_api.dart#L818) |
| İşlem başarısız ($status) | [lib/services/device_integrations_api.dart:249](../lib/services/device_integrations_api.dart#L249) |
| İşlem başarısız ($status) | [lib/services/equipment_api.dart:391](../lib/services/equipment_api.dart#L391) |
| İşlem başarısız ($status). | [lib/services/legal_api.dart:230](../lib/services/legal_api.dart#L230) |
| İşlem sırasında bir hata oluştu: $e | [lib/ui/dialogs/door_edit_dialog.dart:123](../lib/ui/dialogs/door_edit_dialog.dart#L123) |
| Kapalı aylar: ${through.label} ve öncesi. | [lib/services/pdf_finance_service.dart:503](../lib/services/pdf_finance_service.dart#L503) |
| Kapı bulunamadı. | [lib/services/auth_api.dart:3785](../lib/services/auth_api.dart#L3785) |
| Kapı ekranındaki karekod henüz alınamadı. Birkaç saniye sonra tekrar deneyin. | [lib/services/auth_api.dart:3777](../lib/services/auth_api.dart#L3777) |
| Kapı konumunda değilsiniz. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:3753](../lib/services/auth_api.dart#L3753) |
| Kapıyı kapatma veya kilitleme komutu desteklenmiyor. Açmak için "kapıyı aç" deyin. | [lib/services/voice_door_service.dart:493](../lib/services/voice_door_service.dart#L493) |
| Karar bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/decision_book_api.dart:337](../lib/services/decision_book_api.dart#L337) |
| Karar Defteri bu site için kapalı. | [lib/services/decision_book_api.dart:329](../lib/services/decision_book_api.dart#L329) |
| Karekodun süresi doldu. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:3775](../lib/services/auth_api.dart#L3775) |
| Kaydın durumu bu şekilde değiştirilemez. Kayıt başka biri tarafından kapatılmış olabilir; yenileyip tekrar deneyin. | [lib/services/visitor_log_api.dart:380](../lib/services/visitor_log_api.dart#L380) |
| Kayıt bu durumdan istenen duruma geçirilemez. Başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin. | [lib/services/reservation_api.dart:704](../lib/services/reservation_api.dart#L704) |
| Kayıt bulunamadı ya da erişiminiz yok. | [lib/services/visitor_log_api.dart:367](../lib/services/visitor_log_api.dart#L367) |
| Kendi şifrenizi Profilim ekranından değiştirin. | [lib/services/auth_api.dart:3734](../lib/services/auth_api.dart#L3734) |
| Kişi bu dairede zaten kayıtlı. | [lib/services/auth_api.dart:3632](../lib/services/auth_api.dart#L3632) |
| Kişi bulunamadı. | [lib/services/auth_api.dart:3624](../lib/services/auth_api.dart#L3624) |
| Kişisel verilerinizi 24 saat içinde en fazla 3 kez indirebilirsiniz.$wait | [lib/services/account_api.dart:398](../lib/services/account_api.dart#L398) |
| Kod tekrar gönderilemedi. | [lib/services/auth_service.dart:389](../lib/services/auth_service.dart#L389) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/auth_api.dart:3744](../lib/services/auth_api.dart#L3744) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/geofence_service.dart:88](../lib/services/geofence_service.dart#L88) |
| Konum bilgisi geçersiz. GPS'i kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3740](../lib/services/auth_api.dart#L3740) |
| Konum izni kalıcı olarak engellenmiş. Ayarlardan izin verin. | [lib/services/geofence_service.dart:119](../lib/services/geofence_service.dart#L119) |
| Konum izni verilmedi. Güvenlik için konum gereklidir. | [lib/services/geofence_service.dart:115](../lib/services/geofence_service.dart#L115) |
| Konum izni verilmedi. Güvenlik için konum gereklidir. | [lib/services/geofence_service.dart:132](../lib/services/geofence_service.dart#L132) |
| Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın. | [lib/services/geofence_service.dart:108](../lib/services/geofence_service.dart#L108) |
| Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın. | [lib/services/geofence_service.dart:129](../lib/services/geofence_service.dart#L129) |
| Lütfen blok ve daire seçiniz. | [lib/ui/dialogs/submit_join_request_dialog.dart:119](../lib/ui/dialogs/submit_join_request_dialog.dart#L119) |
| Lütfen geçerli bir cihaz QR kodu veya Seri No giriniz. | [lib/ui/widgets/claim_device_dialog.dart:54](../lib/ui/widgets/claim_device_dialog.dart#L54) |
| Lütfen yeni cihazın QR kodunu okutun veya seri numarasını girin. | [lib/ui/dialogs/replace_device_dialog.dart:105](../lib/ui/dialogs/replace_device_dialog.dart#L105) |
| Makbuz bulunamadı. | [lib/services/finance_4b_errors.dart:18](../lib/services/finance_4b_errors.dart#L18) |
| Makro içeren Excel dosyaları (.xlsm) desteklenmez. Dosyayı makrosuz .xlsx olarak kaydedin. | [lib/services/bulk_file_parser.dart:86](../lib/services/bulk_file_parser.dart#L86) |
| Mali kaydı olan daire silinemez. | [lib/services/auth_api.dart:3915](../lib/services/auth_api.dart#L3915) |
| Mali kayıt bulunamadı. | [lib/services/auth_api.dart:3919](../lib/services/auth_api.dart#L3919) |
| Mevcut şifre için çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:3729](../lib/services/auth_api.dart#L3729) |
| Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3727](../lib/services/auth_api.dart#L3727) |
| Modül bulunamadı. | [lib/services/auth_api.dart:3810](../lib/services/auth_api.dart#L3810) |
| Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz. | [lib/services/auth_api.dart:3827](../lib/services/auth_api.dart#L3827) |
| Okutulan karekod geçersiz. | [lib/services/auth_api.dart:3779](../lib/services/auth_api.dart#L3779) |
| OpenDocument (.ods) dosyaları desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin. | [lib/services/bulk_file_parser.dart:90](../lib/services/bulk_file_parser.dart#L90) |
| Oturum açmanız gerekmektedir. | [lib/services/account_api.dart:495](../lib/services/account_api.dart#L495) |
| Oturum açmanız gerekmektedir. | [lib/services/annual_report_api.dart:31](../lib/services/annual_report_api.dart#L31) |
| Oturum açmanız gerekmektedir. | [lib/services/bank_import_api.dart:282](../lib/services/bank_import_api.dart#L282) |
| Oturum açmanız gerekmektedir. | [lib/services/brand_theme_api.dart:21](../lib/services/brand_theme_api.dart#L21) |
| Oturum açmanız gerekmektedir. | [lib/services/budget_api.dart:117](../lib/services/budget_api.dart#L117) |
| Oturum açmanız gerekmektedir. | [lib/services/bulk_api.dart:525](../lib/services/bulk_api.dart#L525) |
| Oturum açmanız gerekmektedir. | [lib/services/contract_api.dart:535](../lib/services/contract_api.dart#L535) |
| Oturum açmanız gerekmektedir. | [lib/services/decision_book_api.dart:427](../lib/services/decision_book_api.dart#L427) |
| Oturum açmanız gerekmektedir. | [lib/services/device_integrations_api.dart:263](../lib/services/device_integrations_api.dart#L263) |
| Oturum açmanız gerekmektedir. | [lib/services/document_api.dart:1052](../lib/services/document_api.dart#L1052) |
| Oturum açmanız gerekmektedir. | [lib/services/equipment_api.dart:404](../lib/services/equipment_api.dart#L404) |
| Oturum açmanız gerekmektedir. | [lib/services/finance_4b_api.dart:1542](../lib/services/finance_4b_api.dart#L1542) |
| Oturum açmanız gerekmektedir. | [lib/services/finance_payment_api.dart:177](../lib/services/finance_payment_api.dart#L177) |
| Oturum açmanız gerekmektedir. | [lib/services/management_company_api.dart:20](../lib/services/management_company_api.dart#L20) |
| Oturum açmanız gerekmektedir. | [lib/services/meter_api.dart:239](../lib/services/meter_api.dart#L239) |
| Oturum açmanız gerekmektedir. | [lib/services/neighbor_board_api.dart:61](../lib/services/neighbor_board_api.dart#L61) |
| Oturum açmanız gerekmektedir. | [lib/services/payment_notice_api.dart:241](../lib/services/payment_notice_api.dart#L241) |
| Oturum açmanız gerekmektedir. | [lib/services/platform_rules_api.dart:274](../lib/services/platform_rules_api.dart#L274) |
| Oturum açmanız gerekmektedir. | [lib/services/push_service.dart:707](../lib/services/push_service.dart#L707) |
| Oturum açmanız gerekmektedir. | [lib/services/push_service.dart:747](../lib/services/push_service.dart#L747) |
| Oturum açmanız gerekmektedir. | [lib/services/push_service.dart:789](../lib/services/push_service.dart#L789) |
| Oturum açmanız gerekmektedir. | [lib/services/reservation_api.dart:808](../lib/services/reservation_api.dart#L808) |
| Oturum açmanız gerekmektedir. | [lib/services/survey_api.dart:428](../lib/services/survey_api.dart#L428) |
| Oturum açmanız gerekmektedir. | [lib/services/visitor_log_api.dart:463](../lib/services/visitor_log_api.dart#L463) |
| Oturum açmanız gerekmektedir. | [lib/services/work_tracking_api.dart:1018](../lib/services/work_tracking_api.dart#L1018) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:3116](../lib/services/auth_service.dart#L3116) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:3233](../lib/services/auth_service.dart#L3233) |
| Ödeme ile site açma yakında. | [lib/services/auth_api.dart:3883](../lib/services/auth_api.dart#L3883) |
| Önce ilgili dönemi kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır. | [lib/services/finance_4b_errors.dart:31](../lib/services/finance_4b_errors.dart#L31) |
| Önemli uyarılar var. Her birini gözden geçirdiğinizi işaretleyin. | [lib/services/payment_notice_api.dart:197](../lib/services/payment_notice_api.dart#L197) |
| Önizlemeden sonra kayıtlar değişti. Önizlemeyi yenileyip tekrar deneyin. | [lib/services/bank_import_api.dart:21](../lib/services/bank_import_api.dart#L21) |
| Plaka biçimi geçersiz. | [lib/services/auth_api.dart:3846](../lib/services/auth_api.dart#L3846) |
| Rezervasyon bulunamadı ya da erişiminiz yok. | [lib/services/reservation_api.dart:643](../lib/services/reservation_api.dart#L643) |
| Rezervasyon ve Konsiyerj bu site için kapalı. | [lib/services/reservation_api.dart:631](../lib/services/reservation_api.dart#L631) |
| Rezervasyon ve talep için sitede aktif daire sakini olmalısınız. | [lib/services/reservation_api.dart:637](../lib/services/reservation_api.dart#L637) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/auth_api.dart:3742](../lib/services/auth_api.dart#L3742) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/geofence_service.dart:81](../lib/services/geofence_service.dart#L81) |
| Sayfa bilgisi geçersiz. Listeyi yenileyip tekrar deneyin. | [lib/services/contract_api.dart:436](../lib/services/contract_api.dart#L436) |
| Seçilen blok veya daireler bu siteye ait değil. Hedefi yeniden seçin. | [lib/services/auth_api.dart:3859](../lib/services/auth_api.dart#L3859) |
| Seçilen daire bu sitede bulunamadı. Daireyi yeniden seçin. | [lib/services/visitor_log_api.dart:369](../lib/services/visitor_log_api.dart#L369) |
| Seçilen dosya boş. Başka bir dosya seçin. | [lib/services/document_api.dart:922](../lib/services/document_api.dart#L922) |
| Seçilen firma pasif. Başka bir firma seçin ya da firmayı Firmalar sekmesinden etkinleştirin. | [lib/services/contract_api.dart:424](../lib/services/contract_api.dart#L424) |
| Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin. | [lib/services/auth_api.dart:3857](../lib/services/auth_api.dart#L3857) |
| Seçilen kişi bu talebe atanamaz. Listeyi yenileyip tekrar deneyin. | [lib/services/work_tracking_api.dart:832](../lib/services/work_tracking_api.dart#L832) |
| Seçilen saat alanın açık saatlerine uymuyor. Boş saatleri yenileyip başka bir saat seçin. | [lib/services/reservation_api.dart:668](../lib/services/reservation_api.dart#L668) |
| Seçtiğiniz saat bu arada doldu. Boş saatleri yenileyip başka bir saat seçin. | [lib/services/reservation_api.dart:676](../lib/services/reservation_api.dart#L676) |
| Site belge alanı doldu. Eski belgeleri kalıcı olarak silin. | [lib/services/document_api.dart:928](../lib/services/document_api.dart#L928) |
| Site belge kotası dolu. Yeni belge eklenemez. | [lib/services/finance_4b_errors.dart:99](../lib/services/finance_4b_errors.dart#L99) |
| Site bulunamadı. | [lib/services/auth_api.dart:3635](../lib/services/auth_api.dart#L3635) |
| Site bulunamadı. | [lib/services/contract_api.dart:429](../lib/services/contract_api.dart#L429) |
| Site bulunamadı. | [lib/services/decision_book_api.dart:335](../lib/services/decision_book_api.dart#L335) |
| Site bulunamadı. | [lib/services/platform_rules_api.dart:188](../lib/services/platform_rules_api.dart#L188) |
| Site bulunamadı. | [lib/services/reservation_api.dart:639](../lib/services/reservation_api.dart#L639) |
| Site bulunamadı. | [lib/services/survey_api.dart:347](../lib/services/survey_api.dart#L347) |
| Site bulunamadı. | [lib/services/visitor_log_api.dart:371](../lib/services/visitor_log_api.dart#L371) |
| Site bulunamadı. | [lib/services/work_tracking_api.dart:828](../lib/services/work_tracking_api.dart#L828) |
| Site geçersiz. Siteyi yeniden seçin. | [lib/services/contract_api.dart:431](../lib/services/contract_api.dart#L431) |
| Site geçersiz. Siteyi yeniden seçin. | [lib/services/reservation_api.dart:647](../lib/services/reservation_api.dart#L647) |
| Site geçersiz. Siteyi yeniden seçin. | [lib/services/visitor_log_api.dart:373](../lib/services/visitor_log_api.dart#L373) |
| Site geçersiz. Siteyi yeniden seçin. | [lib/services/work_tracking_api.dart:830](../lib/services/work_tracking_api.dart#L830) |
| Site kayıtları şu an meşgul, biraz sonra deneyin. | [lib/services/bulk_api.dart:37](../lib/services/bulk_api.dart#L37) |
| Site kurmak için başvuru yapmalısınız. | [lib/services/auth_api.dart:3867](../lib/services/auth_api.dart#L3867) |
| Site seçimi geçersiz. Ekranı yenileyip tekrar deneyin. | [lib/services/platform_rules_api.dart:190](../lib/services/platform_rules_api.dart#L190) |
| Sitede en çok $areaLimit alan tanımlanabilir. | [lib/services/reservation_api.dart:659](../lib/services/reservation_api.dart#L659) |
| Sitede geçerli rezervasyon üst sınırına ulaşıldı. Yönetimle iletişime geçin. | [lib/services/reservation_api.dart:695](../lib/services/reservation_api.dart#L695) |
| Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin. | [lib/services/reservation_api.dart:713](../lib/services/reservation_api.dart#L713) |
| Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin. | [lib/services/work_tracking_api.dart:845](../lib/services/work_tracking_api.dart#L845) |
| Sitedeki belge sayısı sınırına ulaşıldı. Eski belgeleri kalıcı olarak silin. | [lib/services/document_api.dart:930](../lib/services/document_api.dart#L930) |
| Son 24 saatte en fazla 5 başvuru yapabilirsiniz. Daha sonra tekrar deneyin. | [lib/services/auth_api.dart:3881](../lib/services/auth_api.dart#L3881) |
| Son bir saatte çok sayıda e-postalı duyuru yayınladınız. Biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:3642](../lib/services/auth_api.dart#L3642) |
| Sözleşme bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/contract_api.dart:418](../lib/services/contract_api.dart#L418) |
| SSL baglantisi kurulurken hata olustu. | [lib/services/auth_api.dart:3991](../lib/services/auth_api.dart#L3991) |
| Sunucu baglantisinda istemci hatasi olustu. | [lib/services/auth_api.dart:3999](../lib/services/auth_api.dart#L3999) |
| Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin. | [lib/services/platform_rules_api.dart:117](../lib/services/platform_rules_api.dart#L117) |
| Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:3981](../lib/services/auth_api.dart#L3981) |
| Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/legal_api.dart:225](../lib/services/legal_api.dart#L225) |
| Sunucu meşgul. Biraz sonra tekrar deneyin. | [lib/services/document_api.dart:948](../lib/services/document_api.dart#L948) |
| Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/platform_rules_api.dart:141](../lib/services/platform_rules_api.dart#L141) |
| Sunucu şu anda yoğun. Biraz sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:908](../lib/services/work_tracking_api.dart#L908) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/brand_theme_api.dart:33](../lib/services/brand_theme_api.dart#L33) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/device_integrations_api.dart:212](../lib/services/device_integrations_api.dart#L212) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/equipment_api.dart:355](../lib/services/equipment_api.dart#L355) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/management_company_api.dart:32](../lib/services/management_company_api.dart#L32) |
| Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin. | [lib/services/decision_book_api.dart:173](../lib/services/decision_book_api.dart#L173) |
| Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin. | [lib/services/survey_api.dart:204](../lib/services/survey_api.dart#L204) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/bank_import_api.dart:223](../lib/services/bank_import_api.dart#L223) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/decision_book_api.dart:395](../lib/services/decision_book_api.dart#L395) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1326](../lib/services/finance_4b_api.dart#L1326) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1330](../lib/services/finance_4b_api.dart#L1330) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/finance_payment_api.dart:96](../lib/services/finance_payment_api.dart#L96) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/meter_api.dart:169](../lib/services/meter_api.dart#L169) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/payment_notice_api.dart:148](../lib/services/payment_notice_api.dart#L148) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/platform_rules_api.dart:243](../lib/services/platform_rules_api.dart#L243) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/survey_api.dart:407](../lib/services/survey_api.dart#L407) |
| Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:3983](../lib/services/auth_api.dart#L3983) |
| Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/legal_api.dart:228](../lib/services/legal_api.dart#L228) |
| Sunucunun cihaz bağlantısı şu an hazır değil. Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:3789](../lib/services/auth_api.dart#L3789) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:299](../lib/services/auth_service.dart#L299) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:314](../lib/services/auth_service.dart#L314) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:329](../lib/services/auth_service.dart#L329) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:596](../lib/services/auth_service.dart#L596) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:740](../lib/services/auth_service.dart#L740) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:776](../lib/services/auth_service.dart#L776) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:800](../lib/services/auth_service.dart#L800) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:817](../lib/services/auth_service.dart#L817) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:915](../lib/services/auth_service.dart#L915) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:945](../lib/services/auth_service.dart#L945) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:989](../lib/services/auth_service.dart#L989) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2412](../lib/services/auth_service.dart#L2412) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2623](../lib/services/auth_service.dart#L2623) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3074](../lib/services/auth_service.dart#L3074) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3098](../lib/services/auth_service.dart#L3098) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3175](../lib/services/auth_service.dart#L3175) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3243](../lib/services/auth_service.dart#L3243) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/annual_report_api.dart:43](../lib/services/annual_report_api.dart#L43) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/bank_import_api.dart:219](../lib/services/bank_import_api.dart#L219) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/brand_theme_api.dart:35](../lib/services/brand_theme_api.dart#L35) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/budget_api.dart:77](../lib/services/budget_api.dart#L77) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/device_integrations_api.dart:214](../lib/services/device_integrations_api.dart#L214) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/equipment_api.dart:357](../lib/services/equipment_api.dart#L357) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/finance_payment_api.dart:92](../lib/services/finance_payment_api.dart#L92) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/management_company_api.dart:34](../lib/services/management_company_api.dart#L34) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/neighbor_board_api.dart:74](../lib/services/neighbor_board_api.dart#L74) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/payment_notice_api.dart:144](../lib/services/payment_notice_api.dart#L144) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/ui/widgets/drive_storage_card.dart:62](../lib/ui/widgets/drive_storage_card.dart#L62) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:352](../lib/services/auth_service.dart#L352) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:607](../lib/services/auth_service.dart#L607) |
| Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin. | [lib/services/auth_api.dart:3997](../lib/services/auth_api.dart#L3997) |
| Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin. | [lib/services/bank_import_api.dart:233](../lib/services/bank_import_api.dart#L233) |
| Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin. | [lib/services/meter_api.dart:189](../lib/services/meter_api.dart#L189) |
| Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin. | [lib/services/payment_notice_api.dart:171](../lib/services/payment_notice_api.dart#L171) |
| Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin. | [lib/services/platform_rules_api.dart:147](../lib/services/platform_rules_api.dart#L147) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/contract_api.dart:439](../lib/services/contract_api.dart#L439) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/contract_api.dart:452](../lib/services/contract_api.dart#L452) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/decision_book_api.dart:353](../lib/services/decision_book_api.dart#L353) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/reservation_api.dart:654](../lib/services/reservation_api.dart#L654) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/survey_api.dart:365](../lib/services/survey_api.dart#L365) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/visitor_log_api.dart:378](../lib/services/visitor_log_api.dart#L378) |
| Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin. | [lib/services/work_tracking_api.dart:839](../lib/services/work_tracking_api.dart#L839) |
| Şifre için çok fazla hatalı deneme yapıldı.$wait | [lib/services/account_api.dart:396](../lib/services/account_api.dart#L396) |
| Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin. | [lib/services/account_api.dart:394](../lib/services/account_api.dart#L394) |
| Şifrenizi değiştirmek için mevcut şifrenizi girin. | [lib/services/auth_service.dart:3121](../lib/services/auth_service.dart#L3121) |
| Şifrenizi değiştirmek için mevcut şifrenizi girmelisiniz. | [lib/services/auth_api.dart:3725](../lib/services/auth_api.dart#L3725) |
| Tahsilatın gireceği kasa ya da banka hesabını seçin. | [lib/services/payment_notice_api.dart:201](../lib/services/payment_notice_api.dart#L201) |
| Talebin durumu bu şekilde değiştirilemez. Talep başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin. | [lib/services/work_tracking_api.dart:841](../lib/services/work_tracking_api.dart#L841) |
| Talep bulunamadı ya da erişiminiz yok. | [lib/services/reservation_api.dart:645](../lib/services/reservation_api.dart#L645) |
| Talep bulunamadı ya da erişiminiz yok. | [lib/services/work_tracking_api.dart:826](../lib/services/work_tracking_api.dart#L826) |
| Talep bulunamadı. | [lib/services/auth_api.dart:3833](../lib/services/auth_api.dart#L3833) |
| Tamamlanmamış çok sayıda yüklemeniz var. Birkaç dakika sonra tekrar deneyin. | [lib/services/document_api.dart:946](../lib/services/document_api.dart#L946) |
| Tamamlanmış ya da iptal edilmiş talepte değişiklik yapılamaz. | [lib/services/reservation_api.dart:706](../lib/services/reservation_api.dart#L706) |
| Tanımlı bir kapı bulunamadı. | [lib/services/voice_door_service.dart:505](../lib/services/voice_door_service.dart#L505) |
| Tarih, hesabın açılış tarihinden önce olamaz. | [lib/services/finance_4b_errors.dart:58](../lib/services/finance_4b_errors.dart#L58) |
| Tazminat aylar sırayla hesaplanır. Sıradaki ayı seçin. | [lib/services/finance_4b_errors.dart:35](../lib/services/finance_4b_errors.dart#L35) |
| Tazminat çalıştırması bulunamadı. | [lib/services/finance_4b_errors.dart:39](../lib/services/finance_4b_errors.dart#L39) |
| Tedarikçi bulunamadı. | [lib/services/finance_4b_errors.dart:84](../lib/services/finance_4b_errors.dart#L84) |
| Tek seferde en çok 1000 kişiye e-posta gönderilebilir. Hedefi bölüp ayrı duyurular oluşturun. | [lib/services/auth_api.dart:3863](../lib/services/auth_api.dart#L3863) |
| Teklif zaten karara bağlanmış. | [lib/services/equipment_api.dart:383](../lib/services/equipment_api.dart#L383) |
| Teklifin geçerlilik süresi dolmuş. | [lib/services/equipment_api.dart:381](../lib/services/equipment_api.dart#L381) |
| Toplam tutar değişti. Önizleme yenilendi, tekrar inceleyin. | [lib/services/bulk_api.dart:54](../lib/services/bulk_api.dart#L54) |
| Toplantı tarihi gelmemiş karar kesinleştirilemez. | [lib/services/decision_book_api.dart:341](../lib/services/decision_book_api.dart#L341) |
| Toplu işlemler geçici olarak kapalı. | [lib/services/bulk_api.dart:45](../lib/services/bulk_api.dart#L45) |
| Uygulamayı güncelleyin. | [lib/services/bulk_api.dart:39](../lib/services/bulk_api.dart#L39) |
| Veriler değişti. Önizleme yenilendi, tekrar inceleyin. | [lib/services/bulk_api.dart:27](../lib/services/bulk_api.dart#L27) |
| Veriler önizlemeden sonra değişti. Önizlemeyi yenileyip toplamı kontrol edin. | [lib/services/auth_api.dart:3887](../lib/services/auth_api.dart#L3887) |
| Yalnız .xlsx ve .csv dosyaları yüklenebilir. | [lib/services/bulk_file_parser.dart:92](../lib/services/bulk_file_parser.dart#L92) |
| Yalnızca tahsilat düzeltilebilir. Borç için kaydı iptal edin. | [lib/services/auth_api.dart:3901](../lib/services/auth_api.dart#L3901) |
| Yayın zamanı geçersiz. En az 1 dakika, en çok 1 yıl sonrası seçin. | [lib/services/auth_api.dart:3861](../lib/services/auth_api.dart#L3861) |
| Yetkilendirme servisi bulunamadı. | [lib/ui/widgets/dynamic_qr_pass_modal.dart:433](../lib/ui/widgets/dynamic_qr_pass_modal.dart#L433) |
| Yükleme adresi geçersiz. İşlemi baştan başlatın. | [lib/services/document_api.dart:221](../lib/services/document_api.dart#L221) |
| Yükleme adresi geçersiz. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:855](../lib/services/finance_4b_api.dart#L855) |
| Yükleme isteği eksik gönderildi. Tekrar deneyin. | [lib/services/document_api.dart:926](../lib/services/document_api.dart#L926) |
| Yükleme sunucusu şu an meşgul.$wait | [lib/services/finance_4b_errors.dart:101](../lib/services/finance_4b_errors.dart#L101) |
| Yükleme süresi doldu. Tekrar deneyin. | [lib/services/work_tracking_api.dart:897](../lib/services/work_tracking_api.dart#L897) |
| Yüklenecek satır bulunamadı. | [lib/services/bulk_api.dart:33](../lib/services/bulk_api.dart#L33) |
| Zaten bekleyen bir site başvurunuz var. | [lib/services/auth_api.dart:3869](../lib/services/auth_api.dart#L3869) |
| Ziyaretçi ve kargo kaydı bu site için kapalı. | [lib/services/visitor_log_api.dart:361](../lib/services/visitor_log_api.dart#L361) |


# Hata mesajı → kaynak (otomatik)

> Kullanıcıya/istemciye görünen metinleri üretildikleri `dosya:satır` ile eşler. `Ctrl+F` ile ekranda gördüğünüz mesajın bir parçasını arayın. Koddan otomatik üretilir: `node tools/klavuz/build.mjs`. Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).

## Sunucu mesajları (863)

Kaynak: `server/src` (`error:`, `message:`, `httpError(...)`, `new Error(...)`). Uygulama bu metinleri HTTP yanıt gövdesinde (`error` alanı) alır.

| Mesaj | Dosya:satır |
| --- | --- |
| "${bName}" blok adı birden fazla kez kullanılmış. Blok adları benzersiz olmalıdır. | [server/src/services/membership_rules.js:506](../server/src/services/membership_rules.js#L506) |
| "${site.name}" sitesi, ${createdBlocks.length} blok ve ${totalApartmentCount} daire ile başarıyla kuruldu! | [server/src/services/membership_service.js:895](../server/src/services/membership_service.js#L895) |
| "${siteName}" sitesi ${apt.block_name \|\| ''} ${apt.unit_label} için katılım başvurunuz başarıyla oluşturuldu. Site yöneticisinin onayı bekleniyor. | [server/src/services/membership_service.js:1102](../server/src/services/membership_service.js#L1102) |
| <Türkçe mesaj> | [server/src/modules/account_common.js:4](../server/src/modules/account_common.js#L4) |
| <Türkçe mesaj> | [server/src/modules/module_request_routes.js:9](../server/src/modules/module_request_routes.js#L9) |
| <Türkçe mesaj> | [server/src/modules/module_routes.js:15](../server/src/modules/module_routes.js#L15) |
| <Türkçe mesaj> | [server/src/modules/site_application_routes.js:14](../server/src/modules/site_application_routes.js#L14) |
| ${apartmentLabel(state.apartment.block_name, state.apartment.unit_label)} dairesinin maliki size ${scope === 'toplanti_imza' ? 'toplantı imzası' : 'kurul üyeliği'} için vekalet verdi (${window.valid_until} tarihine kada… | [server/src/modules/apartment_mgmt_proxy.js:69](../server/src/modules/apartment_mgmt_proxy.js#L69) |
| ${cleanEmail} adresine ${VERIFICATION_CODE_DIGITS} haneli doğrulama kodu gönderildi. | [server/src/modules/oauth_login.js:895](../server/src/modules/oauth_login.js#L895) |
| ${debt?.site_name ?  | [server/src/modules/account_common.js:85](../server/src/modules/account_common.js#L85) |
| ${deviceUid} kodlu cihaz ve karekodu basariyla silindi. | [server/src/routes/company_routes.js:464](../server/src/routes/company_routes.js#L464) |
| ${field.body} alani true/false olmalidir. | [server/src/utils/site_rules.js:312](../server/src/utils/site_rules.js#L312) |
| ${fieldName} alanı true/false olmalıdır. | [server/src/services/membership_service.js:1882](../server/src/services/membership_service.js#L1882) |
| ${fileName}: front-matter (--- ... ---) bulunamadı | [server/src/modules/legal_documents.js:143](../server/src/modules/legal_documents.js#L143) |
| ${fileName}: geçersiz id | [server/src/modules/legal_documents.js:149](../server/src/modules/legal_documents.js#L149) |
| ${fileName}: geçersiz version | [server/src/modules/legal_documents.js:157](../server/src/modules/legal_documents.js#L157) |
| ${fileName}: title zorunlu (en çok 200 karakter) | [server/src/modules/legal_documents.js:153](../server/src/modules/legal_documents.js#L153) |
| ${label} ${min} ile ${max} arasında bir tamsayı olmalıdır. | [server/src/services/membership_rules.js:458](../server/src/services/membership_rules.js#L458) |
| ${label} dairesinin yönetimi site yöneticisi tarafından ${next.name} kişisine verildi. Dairede kalmaya devam ediyorsunuz. | [server/src/modules/apartment_mgmt_manager.js:184](../server/src/modules/apartment_mgmt_manager.js#L184) |
| ${label} dairesinin yönetimi site yöneticisi tarafından size verildi. | [server/src/modules/apartment_mgmt_manager.js:175](../server/src/modules/apartment_mgmt_manager.js#L175) |
| ${name} env degiskeni eksik. | [server/src/mailer.js:6](../server/src/mailer.js#L6) |
| ${name}: dosya çok büyük | [server/src/modules/legal_documents.js:222](../server/src/modules/legal_documents.js#L222) |
| ${pass.door_name} aciliyor. | [server/src/routes/guest_passes_routes.js:464](../server/src/routes/guest_passes_routes.js#L464) |
| ${req.full_name} sakini, "${req.block_name \|\| ''} ${req.unit_label}" dairesine ${assignedRole === 'APARTMENT_ADMIN' ? 'Daire Yöneticisi' : 'Aile Üyesi'} olarak başarıyla onaylandı. | [server/src/services/membership_service.js:1388](../server/src/services/membership_service.js#L1388) |
| ${result.revoked_count} aktif karekod basariyla iptal edildi. | [server/src/routes/manager_routes.js:1117](../server/src/routes/manager_routes.js#L1117) |
| ${site?.name ?  | [server/src/modules/account_common.js:69](../server/src/modules/account_common.js#L69) |
| ${targetUserCodes.length} sakin için kapı yetkisi ${actionText}. | [server/src/services/membership_service.js:2828](../server/src/services/membership_service.js#L2828) |
| Abonelik talebiniz onay bekliyor. | [server/src/middlewares/auth_middleware.js:118](../server/src/middlewares/auth_middleware.js#L118) |
| Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:832](../server/src/routes/auth_routes.js#L832) |
| Abonelik talebiniz reddedildi. | [server/src/middlewares/auth_middleware.js:121](../server/src/middlewares/auth_middleware.js#L121) |
| Abonelik talebiniz reddedildi. | [server/src/routes/auth_routes.js:835](../server/src/routes/auth_routes.js#L835) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:770](../server/src/routes/admin_routes.js#L770) |
| action approve veya reject olmali. | [server/src/routes/admin_routes.js:954](../server/src/routes/admin_routes.js#L954) |
| Ad ve soyad alanları zorunludur. | [server/src/services/membership_service.js:262](../server/src/services/membership_service.js#L262) |
| Ad ve soyad en fazla ${NAME_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:265](../server/src/services/membership_service.js#L265) |
| adli kayit: gecersiz neden kodu | [server/src/modules/residency_log.js:184](../server/src/modules/residency_log.js#L184) |
| adli kayit: gecersiz olay turu ${String(event.eventType)} | [server/src/modules/residency_log.js:181](../server/src/modules/residency_log.js#L181) |
| adli kayit: gecersiz toplu olay | [server/src/modules/residency_log.js:249](../server/src/modules/residency_log.js#L249) |
| adli kayit: siteCode ya da apartmentId zorunlu | [server/src/modules/residency_log.js:178](../server/src/modules/residency_log.js#L178) |
| Aile Reisi (Daire Yöneticisi) başarıyla değiştirildi. | [server/src/services/membership_service.js:2337](../server/src/services/membership_service.js#L2337) |
| Aktif bir doğrulama kodu bulunamadı. Lütfen yeni kod talep ediniz. | [server/src/services/membership_rules.js:68](../server/src/services/membership_rules.js#L68) |
| ANNOUNCEMENT_EMAIL_SECRET veya JWT_SECRET tanimli degil. | [server/src/modules/announcement_email_security.js:45](../server/src/modules/announcement_email_security.js#L45) |
| app_version geçersiz. | [server/src/modules/client_error_service.js:114](../server/src/modules/client_error_service.js#L114) |
| attention source: key ve run zorunlu | [server/src/modules/attention_registry.js:15](../server/src/modules/attention_registry.js#L15) |
| audit action zorunlu | [server/src/modules/audit_service.js:59](../server/src/modules/audit_service.js#L59) |
| bağlantı boşluk veya geçersiz karakter içeremez. | [server/src/modules/platform_config_service.js:108](../server/src/modules/platform_config_service.js#L108) |
| Başlangıç tarihi en fazla bir yıl ileride olabilir. | [server/src/modules/apartment_mgmt_rules.js:247](../server/src/modules/apartment_mgmt_rules.js#L247) |
| Başlangıç tarihi geçersiz. | [server/src/modules/apartment_mgmt_rules.js:245](../server/src/modules/apartment_mgmt_rules.js#L245) |
| Başlangıç tarihi geçmişte olamaz. | [server/src/modules/apartment_mgmt_rules.js:246](../server/src/modules/apartment_mgmt_rules.js#L246) |
| Başvuru bulunamadı. | [server/src/modules/site_application_common.js:25](../server/src/modules/site_application_common.js#L25) |
| beklenmeyen hata | [server/src/modules/drive_service.js:351](../server/src/modules/drive_service.js#L351) |
| Bekleyen abonelik talebi bulunamadi. | [server/src/routes/admin_routes.js:812](../server/src/routes/admin_routes.js#L812) |
| Bekleyen kayıt bulunamadı. Lütfen yeniden kayıt olunuz. | [server/src/services/membership_service.js:435](../server/src/services/membership_service.js#L435) |
| Bekleyen site talebi bulunamadi. | [server/src/routes/admin_routes.js:960](../server/src/routes/admin_routes.js#L960) |
| Belge bulunamadı. | [server/src/modules/legal_routes.js:53](../server/src/modules/legal_routes.js#L53) |
| belge deposu okunabilir akis dondurmedi | [server/src/modules/finance_documents_adapter.js:177](../server/src/modules/finance_documents_adapter.js#L177) |
| Belirtilen cihaz hesabınıza ait değil. | [server/src/services/membership_service.js:855](../server/src/services/membership_service.js#L855) |
| Belirtilen cihaz zaten başka bir kapıya atanmış. | [server/src/services/membership_service.js:870](../server/src/services/membership_service.js#L870) |
| Belirtilen cihaz zaten başka bir sitede kullanımda. | [server/src/services/membership_service.js:862](../server/src/services/membership_service.js#L862) |
| Bilinmeyen toplu yükleme türü. | [server/src/modules/bulk_import_plan.js:27](../server/src/modules/bulk_import_plan.js#L27) |
| Bir sorun oluştu. Uygulamadan yeniden deneyin. | [server/src/modules/drive_routes.js:163](../server/src/modules/drive_routes.js#L163) |
| Bitiş tarihi başlangıçtan önce olamaz. | [server/src/modules/apartment_mgmt_rules.js:250](../server/src/modules/apartment_mgmt_rules.js#L250) |
| Bitiş tarihi geçersiz. | [server/src/modules/apartment_mgmt_rules.js:249](../server/src/modules/apartment_mgmt_rules.js#L249) |
| borçlandırma satır sayısı uyuşmuyor (${written.rowCount} / ${lines.length}) | [server/src/modules/finance_service.js:561](../server/src/modules/finance_service.js#L561) |
| Bos olmayan bloklar varken blok sayisi azaltilamaz. | [server/src/services/site_service.js:1303](../server/src/services/site_service.js#L1303) |
| Boylam -180 ile 180 arasinda olmalidir. | [server/src/utils/site_rules.js:337](../server/src/utils/site_rules.js#L337) |
| Bu adda bir site zaten mevcut. Her sitenin adı benzersiz olmalıdır. | [server/src/utils/validators.js:432](../server/src/utils/validators.js#L432) |
| Bu adda onay bekleyen bir site başvurusu zaten bulunmaktadır. Lütfen farklı bir site adı belirleyin. | [server/src/utils/validators.js:436](../server/src/utils/validators.js#L436) |
| Bu cihaz arizali olarak isaretlenmis. | [server/src/utils/site_rules.js:488](../server/src/utils/site_rules.js#L488) |
| Bu cihaz baska bir kullanici hesabi tarafindan sahiplenilmis. | [server/src/utils/site_rules.js:486](../server/src/utils/site_rules.js#L486) |
| Bu cihaz icin log gonderme yetkiniz yok. | [server/src/routes/door_log_routes.js:248](../server/src/routes/door_log_routes.js#L248) |
| Bu cihaz şirket envanterinde arızalı olarak işaretlenmiştir. Lütfen şirket yetkilisiyle iletişime geçiniz. | [server/src/services/membership_service.js:690](../server/src/services/membership_service.js#L690) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/routes/admin_routes.js:1501](../server/src/routes/admin_routes.js#L1501) |
| Bu cihaz yonettiginiz siteye atanamaz. | [server/src/utils/site_rules.js:483](../server/src/utils/site_rules.js#L483) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:663](../server/src/services/membership_service.js#L663) |
| Bu cihaz zaten hesabınıza tanımlı. | [server/src/services/membership_service.js:685](../server/src/services/membership_service.js#L685) |
| Bu cihazin unique id kayitli. | [server/src/utils/validators.js:462](../server/src/utils/validators.js#L462) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:704](../server/src/routes/manager_routes.js#L704) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:766](../server/src/routes/manager_routes.js#L766) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:796](../server/src/routes/manager_routes.js#L796) |
| Bu daireyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:830](../server/src/routes/manager_routes.js#L830) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1607](../server/src/services/membership_service.js#L1607) |
| Bu daireyi yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1647](../server/src/services/membership_service.js#L1647) |
| Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz. | [server/src/modules/oauth_login.js:970](../server/src/modules/oauth_login.js#L970) |
| Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz. | [server/src/services/membership_service.js:420](../server/src/services/membership_service.js#L420) |
| Bu e-posta adresi için çok fazla kod istendi. Lütfen daha sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:117](../server/src/services/membership_rules.js#L117) |
| Bu e-posta adresine ait hesap artık bulunmuyor. | [server/src/services/site_service.js:2272](../server/src/services/site_service.js#L2272) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:279](../server/src/services/membership_service.js#L279) |
| Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır. | [server/src/services/membership_service.js:449](../server/src/services/membership_service.js#L449) |
| Bu e-posta baska bir rol icin kayitli. | [server/src/routes/auth_routes.js:643](../server/src/routes/auth_routes.js#L643) |
| Bu e-posta ile onaylanmis bir hesap zaten var. Giris yapin. | [server/src/routes/auth_routes.js:648](../server/src/routes/auth_routes.js#L648) |
| Bu e-posta zaten kayitli. | [server/src/utils/validators.js:405](../server/src/utils/validators.js#L405) |
| Bu gecis linki iptal edilmis. | [server/src/utils/guest_pass_utils.js:122](../server/src/utils/guest_pass_utils.js#L122) |
| Bu gecis linkinin suresi dolmus. | [server/src/utils/guest_pass_utils.js:123](../server/src/utils/guest_pass_utils.js#L123) |
| Bu gecisi olusturan kullanicinin kapiya yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:333](../server/src/routes/guest_passes_routes.js#L333) |
| Bu gecisi olusturan kullanicinin yetkisi kalmamis. | [server/src/routes/guest_passes_routes.js:320](../server/src/routes/guest_passes_routes.js#L320) |
| Bu hedef icin OTA yayini yok. | [server/src/routes/firmware_routes.js:165](../server/src/routes/firmware_routes.js#L165) |
| Bu hesap kullanıcının isteğiyle silinmiş (kimliksizleştirilmiş); düzenlenemez veya etkinleştirilemez. | [server/src/routes/admin_routes.js:185](../server/src/routes/admin_routes.js#L185) |
| Bu hesap kullanıcının isteğiyle silinmiş (kimliksizleştirilmiş); kayıtları yasal saklama için korunur ve kalıcı silinemez. | [server/src/routes/admin_routes.js:564](../server/src/routes/admin_routes.js#L564) |
| Bu hesap kullanıcının isteğiyle silinmiş (kimliksizleştirilmiş); kayıtları yasal saklama için korunur ve kalıcı silinemez. | [server/src/routes/admin_routes.js:660](../server/src/routes/admin_routes.js#L660) |
| Bu hesap silinmis. | [server/src/middlewares/auth_middleware.js:99](../server/src/middlewares/auth_middleware.js#L99) |
| Bu hesap silinmis. | [server/src/modules/oauth_login.js:634](../server/src/modules/oauth_login.js#L634) |
| Bu hesap silinmis. | [server/src/routes/auth_routes.js:971](../server/src/routes/auth_routes.js#L971) |
| Bu hesap silinmis. | [server/src/services/membership_service.js:2088](../server/src/services/membership_service.js#L2088) |
| Bu hesap silinmis. | [server/src/services/site_setup_core.js:209](../server/src/services/site_setup_core.js#L209) |
| Bu islem icin site yoneticisi yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:171](../server/src/middlewares/auth_middleware.js#L171) |
| Bu islem icin super user yetkisi gerekir. | [server/src/middlewares/auth_middleware.js:142](../server/src/middlewares/auth_middleware.js#L142) |
| Bu işlem için yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1897](../server/src/services/site_service.js#L1897) |
| Bu işlem için yetkiniz yok. | [server/src/modules/people_access.js:13](../server/src/modules/people_access.js#L13) |
| Bu işlem şu anda yapılamıyor. Site yönetimine başvurun. | [server/src/services/membership_service.js:1769](../server/src/services/membership_service.js#L1769) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:1949](../server/src/services/site_service.js#L1949) |
| Bu işlem yalnızca Süper Kullanıcı yetkisiyle gerçekleştirilebilir. | [server/src/services/site_service.js:2031](../server/src/services/site_service.js#L2031) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen cihaz ekranındaki güncel karekodu okutun. | [server/src/routes/app_doors_routes.js:320](../server/src/routes/app_doors_routes.js#L320) |
| Bu kapıda fiziksel bir QR kod okuyucu bulunmamaktadır. | [server/src/services/qr_access_service.js:43](../server/src/services/qr_access_service.js#L43) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2373](../server/src/services/membership_service.js#L2373) |
| Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2394](../server/src/services/membership_service.js#L2394) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:136](../server/src/routes/app_doors_routes.js#L136) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:177](../server/src/routes/app_doors_routes.js#L177) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/app_doors_routes.js:300](../server/src/routes/app_doors_routes.js#L300) |
| Bu kapiya cihaz atanmamis. | [server/src/routes/guest_passes_routes.js:287](../server/src/routes/guest_passes_routes.js#L287) |
| Bu kapiya gecis yetkiniz bulunmuyor. | [server/src/routes/app_doors_routes.js:295](../server/src/routes/app_doors_routes.js#L295) |
| Bu kapiyi silme yetkiniz yok. | [server/src/routes/manager_routes.js:1078](../server/src/routes/manager_routes.js#L1078) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:871](../server/src/routes/manager_routes.js#L871) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:913](../server/src/routes/manager_routes.js#L913) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:956](../server/src/routes/manager_routes.js#L956) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1045](../server/src/routes/manager_routes.js#L1045) |
| Bu kapiyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1105](../server/src/routes/manager_routes.js#L1105) |
| Bu karekod daha once kullanildi. Lutfen cihaz ekraninda yenilenen guncel karekodu okutun. | [server/src/routes/app_doors_routes.js:337](../server/src/routes/app_doors_routes.js#L337) |
| Bu kimlik sağlayıcısıyla giriş şu anda kapalı (sunucu yapılandırması eksik). | [server/src/modules/oauth_login.js:218](../server/src/modules/oauth_login.js#L218) |
| Bu kişide kurul veya görevli rolü yok. | [server/src/modules/module_routes.js:200](../server/src/modules/module_routes.js#L200) |
| Bu kullanıcı zaten bu sitenin yöneticisidir. | [server/src/services/site_service.js:2283](../server/src/services/site_service.js#L2283) |
| Bu kullanıcı zaten daire yöneticisidir. | [server/src/services/membership_service.js:2301](../server/src/services/membership_service.js#L2301) |
| Bu kullanıcı zaten dairenin Aile Reisidir (Daire Yöneticisi). | [server/src/services/membership_service.js:2311](../server/src/services/membership_service.js#L2311) |
| Bu kullanici adi zaten kayitli. | [server/src/utils/validators.js:408](../server/src/utils/validators.js#L408) |
| Bu modül site için kapalı. | [server/src/modules/bulk_import_routes.js:90](../server/src/modules/bulk_import_routes.js#L90) |
| Bu silme doğrulama kodu artık geçerli değil. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:2128](../server/src/services/site_service.js#L2128) |
| Bu silme talebini yalnızca ilgili sitenin yöneticisi onaylayabilir. | [server/src/services/site_service.js:1872](../server/src/services/site_service.js#L1872) |
| Bu silme talebini yalnızca Süper Kullanıcı onaylayabilir. | [server/src/services/site_service.js:1862](../server/src/services/site_service.js#L1862) |
| Bu site için bekleyen bir silme onayı bulunmamaktadır. | [server/src/services/site_service.js:1879](../server/src/services/site_service.js#L1879) |
| Bu site için bekleyen bir silme talebi bulunmuyor. | [server/src/services/site_service.js:1914](../server/src/services/site_service.js#L1914) |
| Bu site için talep edilmiş aktif bir silme doğrulama kodu bulunmuyor. | [server/src/services/site_service.js:2075](../server/src/services/site_service.js#L2075) |
| Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır. | [server/src/services/membership_service.js:1035](../server/src/services/membership_service.js#L1035) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/routes/membership_routes.js:150](../server/src/routes/membership_routes.js#L150) |
| Bu site katılım QR kodu geçersiz veya iptal edilmiş. | [server/src/services/membership_service.js:989](../server/src/services/membership_service.js#L989) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/modules/people_access.js:15](../server/src/modules/people_access.js#L15) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/modules/route_helpers.js:44](../server/src/modules/route_helpers.js#L44) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1338](../server/src/routes/manager_routes.js#L1338) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1364](../server/src/routes/manager_routes.js#L1364) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1392](../server/src/routes/manager_routes.js#L1392) |
| Bu site üzerinde yönetim yetkiniz bulunmuyor. | [server/src/routes/manager_routes.js:1419](../server/src/routes/manager_routes.js#L1419) |
| Bu sitede karekod ile giris yonetim tarafindan gecici olarak durdurulmustur. | [server/src/services/door_access_policy.js:111](../server/src/services/door_access_policy.js#L111) |
| Bu sitede karekod ile kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:104](../server/src/services/door_access_policy.js#L104) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/routes/guest_passes_routes.js:275](../server/src/routes/guest_passes_routes.js#L275) |
| Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir. | [server/src/services/door_access_policy.js:121](../server/src/services/door_access_policy.js#L121) |
| Bu sitede misafir/kurye gecis kodu olusturma kapalidir. | [server/src/routes/guest_passes_routes.js:79](../server/src/routes/guest_passes_routes.js#L79) |
| Bu sitede yerel ag uzerinden kapi acma yetkisi kapalidir. | [server/src/services/door_access_policy.js:131](../server/src/services/door_access_policy.js#L131) |
| Bu sitenin cihazlarini gorme yetkiniz yok. | [server/src/routes/manager_routes.js:1137](../server/src/routes/manager_routes.js#L1137) |
| Bu sitenin katılım taleplerini görme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1192](../server/src/services/membership_service.js#L1192) |
| Bu sitenin loglarini gorme yetkiniz yok. | [server/src/routes/door_log_routes.js:136](../server/src/routes/door_log_routes.js#L136) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2859](../server/src/services/membership_service.js#L2859) |
| Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:2880](../server/src/services/membership_service.js#L2880) |
| Bu siteye kapi ekleme yetkiniz yok. | [server/src/routes/manager_routes.js:999](../server/src/routes/manager_routes.js#L999) |
| Bu siteyi silme yetkiniz bulunmamaktadır. | [server/src/services/site_service.js:1709](../server/src/services/site_service.js#L1709) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:234](../server/src/routes/manager_routes.js#L234) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:402](../server/src/routes/manager_routes.js#L402) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:535](../server/src/routes/manager_routes.js#L535) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:557](../server/src/routes/manager_routes.js#L557) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:582](../server/src/routes/manager_routes.js#L582) |
| Bu siteyi yonetme yetkiniz yok. | [server/src/routes/manager_routes.js:1181](../server/src/routes/manager_routes.js#L1181) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:418](../server/src/routes/auth_routes.js#L418) |
| Bu şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:436](../server/src/routes/auth_routes.js#L436) |
| Bu şifre sıfırlama bağlantısının süresi dolmuş (30 dakika). Lütfen mobil uygulamadan yeni bir bağlantı talep ediniz. | [server/src/routes/auth_routes.js:445](../server/src/routes/auth_routes.js#L445) |
| Bu talebi onaylama yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1299](../server/src/services/membership_service.js#L1299) |
| Bu talebi reddetme yetkiniz bulunmamaktadır. | [server/src/services/membership_service.js:1432](../server/src/services/membership_service.js#L1432) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1305](../server/src/services/membership_service.js#L1305) |
| Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz. | [server/src/services/membership_service.js:1438](../server/src/services/membership_service.js#L1438) |
| Bu tek kullanimlik gecis linki daha once kullanilmis. | [server/src/utils/guest_pass_utils.js:124](../server/src/utils/guest_pass_utils.js#L124) |
| Cihaz (${device.device_uid}) başarıyla şirket envanterine kaydedildi. | [server/src/routes/admin_routes.js:1763](../server/src/routes/admin_routes.js#L1763) |
| Cihaz (${normalizedUid}) zaten şirket veritabanında kayıtlı. | [server/src/services/device_service.js:904](../server/src/services/device_service.js#L904) |
| Cihaz (${updated.device_uid}) sahipliği sıfırlandı ve şirket stokuna geri döndürüldü. | [server/src/routes/admin_routes.js:1828](../server/src/routes/admin_routes.js#L1828) |
| Cihaz atamasi olan kapilar varken kapi sayisi azaltilamaz. | [server/src/services/site_service.js:1285](../server/src/services/site_service.js#L1285) |
| Cihaz basariyla degistirildi. Kapi yetkileri ve ayarlari aynen korundu. | [server/src/routes/manager_routes.js:970](../server/src/routes/manager_routes.js#L970) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:972](../server/src/services/device_service.js#L972) |
| Cihaz bulunamadı. | [server/src/services/device_service.js:1011](../server/src/services/device_service.js#L1011) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1542](../server/src/routes/admin_routes.js#L1542) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1687](../server/src/routes/admin_routes.js#L1687) |
| Cihaz bulunamadi. | [server/src/routes/admin_routes.js:1705](../server/src/routes/admin_routes.js#L1705) |
| Cihaz bulunamadi. | [server/src/routes/company_routes.js:493](../server/src/routes/company_routes.js#L493) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1192](../server/src/routes/manager_routes.js#L1192) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1203](../server/src/routes/manager_routes.js#L1203) |
| Cihaz bulunamadi. | [server/src/routes/manager_routes.js:1230](../server/src/routes/manager_routes.js#L1230) |
| Cihaz dogrulamasi gecici olarak yapilamadi. | [server/src/routes/firmware_routes.js:127](../server/src/routes/firmware_routes.js#L127) |
| Cihaz donanimi bu firmware hedefiyle uyusmuyor. | [server/src/routes/firmware_routes.js:144](../server/src/routes/firmware_routes.js#L144) |
| Cihaz durumu okunamadi; biraz sonra tekrar deneyin. | [server/src/routes/company_routes.js:490](../server/src/routes/company_routes.js#L490) |
| Cihaz ekranindaki guncel karekod henuz alinamadi. Birkac saniye sonra tekrar deneyin. | [server/src/routes/app_doors_routes.js:328](../server/src/routes/app_doors_routes.js#L328) |
| Cihaz kaydedildi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1770](../server/src/routes/admin_routes.js#L1770) |
| Cihaz online gorunmuyor. | [server/src/routes/app_doors_routes.js:69](../server/src/routes/app_doors_routes.js#L69) |
| Cihaz QR kodu veya seri numarası boş olamaz. | [server/src/services/membership_rules.js:331](../server/src/services/membership_rules.js#L331) |
| Cihaz QR kodu veya seri numarası çok uzun. | [server/src/services/membership_rules.js:334](../server/src/services/membership_rules.js#L334) |
| Cihaz sahiplenmek için önce e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:598](../server/src/services/membership_service.js#L598) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1712](../server/src/routes/admin_routes.js#L1712) |
| Cihaz silindi ama MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:1241](../server/src/routes/manager_routes.js#L1241) |
| Cihaz silinemedi. | [server/src/routes/admin_routes.js:1716](../server/src/routes/admin_routes.js#L1716) |
| Cihaz silinemedi. | [server/src/routes/company_routes.js:470](../server/src/routes/company_routes.js#L470) |
| Cihaz silme islemini yalnizca super user yapabilir. | [server/src/routes/manager_routes.js:1219](../server/src/routes/manager_routes.js#L1219) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1498](../server/src/routes/admin_routes.js#L1498) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/admin_routes.js:1561](../server/src/routes/admin_routes.js#L1561) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:616](../server/src/routes/manager_routes.js#L616) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:620](../server/src/routes/manager_routes.js#L620) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:650](../server/src/routes/manager_routes.js#L650) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:655](../server/src/routes/manager_routes.js#L655) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/routes/manager_routes.js:660](../server/src/routes/manager_routes.js#L660) |
| Cihaz sirket hesabinda kayitli degil. | [server/src/utils/site_rules.js:482](../server/src/utils/site_rules.js#L482) |
| Cihaz sunucuya kaydedilemedi. | [server/src/routes/company_routes.js:402](../server/src/routes/company_routes.js#L402) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/admin_routes.js:1555](../server/src/routes/admin_routes.js#L1555) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:610](../server/src/routes/manager_routes.js#L610) |
| Cihaz unique id en az 6 karakter olmali. | [server/src/routes/manager_routes.js:644](../server/src/routes/manager_routes.js#L644) |
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
| Cok fazla site kurulum denemesi. Biraz sonra tekrar deneyin. | [server/src/routes/membership_routes.js:42](../server/src/routes/membership_routes.js#L42) |
| Çok fazla anket işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/survey_routes.js:28](../server/src/modules/survey_routes.js#L28) |
| Çok fazla araç işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/apartment_mgmt_routes.js:113](../server/src/modules/apartment_mgmt_routes.js#L113) |
| Çok fazla ayar değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/platform_config_routes.js:40](../server/src/modules/platform_config_routes.js#L40) |
| Çok fazla belge işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:52](../server/src/modules/document_routes.js#L52) |
| Çok fazla cihaz kaydı isteği. Biraz sonra tekrar deneyin. | [server/src/modules/push_routes.js:30](../server/src/modules/push_routes.js#L30) |
| Çok fazla daire işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/apartment_mgmt_routes.js:76](../server/src/modules/apartment_mgmt_routes.js#L76) |
| Çok fazla davet işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/team_routes.js:51](../server/src/modules/team_routes.js#L51) |
| Çok fazla değişiklik. Biraz sonra tekrar deneyin. | [server/src/modules/brand_theme_routes.js:30](../server/src/modules/brand_theme_routes.js#L30) |
| Çok fazla değişiklik. Biraz sonra tekrar deneyin. | [server/src/modules/management_company_routes.js:54](../server/src/modules/management_company_routes.js#L54) |
| Çok fazla deneme. Biraz sonra tekrar deneyin. | [server/src/modules/notify_channels_routes.js:24](../server/src/modules/notify_channels_routes.js#L24) |
| Çok fazla dışa aktarma isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:431](../server/src/modules/finance_4b_routes.js#L431) |
| Çok fazla doğrulama isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:80](../server/src/modules/finance_4b_routes.js#L80) |
| Çok fazla doğrulama kodu talebi. Lütfen biraz sonra tekrar deneyin. | [server/src/modules/oauth_routes.js:45](../server/src/modules/oauth_routes.js#L45) |
| Çok fazla dosya yükleme denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:62](../server/src/modules/document_routes.js#L62) |
| Çok fazla dosya yükleme isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:216](../server/src/modules/finance_4b_routes.js#L216) |
| Çok fazla döküm istendi. Biraz sonra tekrar deneyin. | [server/src/modules/residency_log_routes.js:33](../server/src/modules/residency_log_routes.js#L33) |
| Çok fazla Drive işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/drive_routes.js:41](../server/src/modules/drive_routes.js#L41) |
| Çok fazla duyuru işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/announcement_routes.js:61](../server/src/modules/announcement_routes.js#L61) |
| Çok fazla ekipman işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/equipment_routes.js:36](../server/src/modules/equipment_routes.js#L36) |
| Çok fazla faaliyet raporu işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/annual_report_routes.js:23](../server/src/modules/annual_report_routes.js#L23) |
| Çok fazla finans işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/finance_routes.js:50](../server/src/modules/finance_routes.js#L50) |
| Çok fazla firma / sözleşme işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/contracts_routes.js:40](../server/src/modules/contracts_routes.js#L40) |
| Çok fazla fotoğraf yükleme denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/work_tracking_routes.js:56](../server/src/modules/work_tracking_routes.js#L56) |
| Çok fazla görüntü isteği. Biraz sonra tekrar deneyin. | [server/src/modules/cctv_routes.js:54](../server/src/modules/cctv_routes.js#L54) |
| Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz. | [server/src/services/membership_rules.js:70](../server/src/services/membership_rules.js#L70) |
| Çok fazla hatalı doğrulama denemesi yapıldı. Kod iptal edildi; lütfen daha sonra yeni bir kod isteyiniz. | [server/src/services/site_service.js:2109](../server/src/services/site_service.js#L2109) |
| Çok fazla hatalı giriş denemesi. Lütfen ${wait} sonra tekrar deneyin ya da "Şifremi unuttum" ile şifrenizi sıfırlayın. | [server/src/routes/auth_routes.js:731](../server/src/routes/auth_routes.js#L731) |
| Çok fazla hatırlatma gönderimi. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:369](../server/src/modules/finance_4b_routes.js#L369) |
| Çok fazla hesap işlemi isteği. Biraz sonra tekrar deneyin. | [server/src/modules/account_routes.js:34](../server/src/modules/account_routes.js#L34) |
| Çok fazla indirme isteği. Biraz sonra tekrar deneyin. | [server/src/modules/document_routes.js:82](../server/src/modules/document_routes.js#L82) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/account_routes.js:26](../server/src/modules/account_routes.js#L26) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/announcement_routes.js:71](../server/src/modules/announcement_routes.js#L71) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/announcement_routes.js:83](../server/src/modules/announcement_routes.js#L83) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/annual_report_routes.js:31](../server/src/modules/annual_report_routes.js#L31) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/apartment_mgmt_routes.js:84](../server/src/modules/apartment_mgmt_routes.js#L84) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/apartment_mgmt_routes.js:103](../server/src/modules/apartment_mgmt_routes.js#L103) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/app_config_routes.js:23](../server/src/modules/app_config_routes.js#L23) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/brand_theme_routes.js:22](../server/src/modules/brand_theme_routes.js#L22) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/budget_routes.js:50](../server/src/modules/budget_routes.js#L50) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/card_access_routes.js:37](../server/src/modules/card_access_routes.js#L37) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/cctv_routes.js:44](../server/src/modules/cctv_routes.js#L44) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/client_error_routes.js:66](../server/src/modules/client_error_routes.js#L66) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/contracts_routes.js:50](../server/src/modules/contracts_routes.js#L50) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/decision_book_routes.js:39](../server/src/modules/decision_book_routes.js#L39) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/device_integrations_routes.js:57](../server/src/modules/device_integrations_routes.js#L57) |
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
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/people_routes.js:56](../server/src/modules/people_routes.js#L56) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/plate_recognition_routes.js:64](../server/src/modules/plate_recognition_routes.js#L64) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/platform_config_routes.js:30](../server/src/modules/platform_config_routes.js#L30) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/platform_rules_routes.js:25](../server/src/modules/platform_rules_routes.js#L25) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/push_routes.js:40](../server/src/modules/push_routes.js#L40) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/push_routes.js:59](../server/src/modules/push_routes.js#L59) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/reservation_routes.js:41](../server/src/modules/reservation_routes.js#L41) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/residency_log_routes.js:24](../server/src/modules/residency_log_routes.js#L24) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/site_application_routes.js:56](../server/src/modules/site_application_routes.js#L56) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/survey_routes.js:48](../server/src/modules/survey_routes.js#L48) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/team_routes.js:59](../server/src/modules/team_routes.js#L59) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/visitor_log_routes.js:39](../server/src/modules/visitor_log_routes.js#L39) |
| Çok fazla istek. Biraz sonra tekrar deneyin. | [server/src/modules/work_tracking_routes.js:46](../server/src/modules/work_tracking_routes.js#L46) |
| Çok fazla iş takibi işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/work_tracking_routes.js:36](../server/src/modules/work_tracking_routes.js#L36) |
| Çok fazla işlem. Biraz sonra tekrar deneyin. | [server/src/modules/device_integrations_routes.js:49](../server/src/modules/device_integrations_routes.js#L49) |
| Çok fazla işletme projesi işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/budget_routes.js:41](../server/src/modules/budget_routes.js#L41) |
| Çok fazla kadro işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/team_routes.js:43](../server/src/modules/team_routes.js#L43) |
| Çok fazla kamera işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/cctv_routes.js:35](../server/src/modules/cctv_routes.js#L35) |
| Çok fazla karar defteri işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/decision_book_routes.js:29](../server/src/modules/decision_book_routes.js#L29) |
| Çok fazla kart işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/card_access_routes.js:27](../server/src/modules/card_access_routes.js#L27) |
| Çok fazla kayıt işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/people_routes.js:46](../server/src/modules/people_routes.js#L46) |
| Çok fazla kişi araması yapıldı. Biraz sonra tekrar deneyin. | [server/src/modules/apartment_mgmt_routes.js:93](../server/src/modules/apartment_mgmt_routes.js#L93) |
| Çok fazla kod isteği. Biraz sonra tekrar deneyin. | [server/src/modules/notify_channels_routes.js:19](../server/src/modules/notify_channels_routes.js#L19) |
| Çok fazla komşu panosu işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/neighbor_board_routes.js:43](../server/src/modules/neighbor_board_routes.js#L43) |
| Çok fazla kural değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/platform_rules_routes.js:35](../server/src/modules/platform_rules_routes.js#L35) |
| çok fazla metin ögesi | [server/src/modules/bank_pdf_worker.js:57](../server/src/modules/bank_pdf_worker.js#L57) |
| Çok fazla misafir plakası işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/plate_recognition_routes.js:56](../server/src/modules/plate_recognition_routes.js#L56) |
| Çok fazla modül değişikliği. Biraz sonra tekrar deneyin. | [server/src/modules/module_routes.js:63](../server/src/modules/module_routes.js#L63) |
| Çok fazla modül talebi. Biraz sonra tekrar deneyin. | [server/src/modules/module_request_routes.js:36](../server/src/modules/module_request_routes.js#L36) |
| Çok fazla olay. | [server/src/modules/device_integrations_routes.js:63](../server/src/modules/device_integrations_routes.js#L63) |
| Çok fazla onay işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/legal_routes.js:49](../server/src/modules/legal_routes.js#L49) |
| Çok fazla oy denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/survey_routes.js:38](../server/src/modules/survey_routes.js#L38) |
| Çok fazla PDF okuma isteği. Biraz sonra tekrar deneyin. | [server/src/modules/bank_import_routes.js:38](../server/src/modules/bank_import_routes.js#L38) |
| Çok fazla plaka işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/plate_recognition_routes.js:47](../server/src/modules/plate_recognition_routes.js#L47) |
| Çok fazla rapor isteği. Biraz sonra tekrar deneyin. | [server/src/modules/finance_4b_routes.js:426](../server/src/modules/finance_4b_routes.js#L426) |
| Çok fazla rapor. Biraz sonra tekrar deneyin. | [server/src/modules/client_error_routes.js:42](../server/src/modules/client_error_routes.js#L42) |
| Çok fazla rapor. Biraz sonra tekrar deneyin. | [server/src/modules/client_error_routes.js:58](../server/src/modules/client_error_routes.js#L58) |
| Çok fazla rezervasyon işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/reservation_routes.js:31](../server/src/modules/reservation_routes.js#L31) |
| Çok fazla rol atama denemesi. Biraz sonra tekrar deneyin. | [server/src/modules/module_routes.js:51](../server/src/modules/module_routes.js#L51) |
| Çok fazla sayaç işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/metering_routes.js:34](../server/src/modules/metering_routes.js#L34) |
| Çok fazla site başvurusu işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/site_application_routes.js:46](../server/src/modules/site_application_routes.js#L46) |
| Çok fazla sosyal giriş denemesi. Lütfen biraz sonra tekrar deneyin. | [server/src/modules/oauth_routes.js:29](../server/src/modules/oauth_routes.js#L29) |
| Çok fazla ziyaretçi / kargo işlemi. Biraz sonra tekrar deneyin. | [server/src/modules/visitor_log_routes.js:29](../server/src/modules/visitor_log_routes.js#L29) |
| Daire bilgileri e-posta ile gonderilemedi. | [server/src/routes/admin_routes.js:1469](../server/src/routes/admin_routes.js#L1469) |
| Daire bulunamadı. | [server/src/services/membership_service.js:1597](../server/src/services/membership_service.js#L1597) |
| Daire bulunamadı. | [server/src/services/membership_service.js:2147](../server/src/services/membership_service.js#L2147) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1384](../server/src/routes/admin_routes.js#L1384) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1409](../server/src/routes/admin_routes.js#L1409) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1439](../server/src/routes/admin_routes.js#L1439) |
| Daire bulunamadi. | [server/src/routes/admin_routes.js:1457](../server/src/routes/admin_routes.js#L1457) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:701](../server/src/routes/manager_routes.js#L701) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:744](../server/src/routes/manager_routes.js#L744) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:763](../server/src/routes/manager_routes.js#L763) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:777](../server/src/routes/manager_routes.js#L777) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:793](../server/src/routes/manager_routes.js#L793) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:827](../server/src/routes/manager_routes.js#L827) |
| Daire bulunamadi. | [server/src/routes/manager_routes.js:843](../server/src/routes/manager_routes.js#L843) |
| Daire kullanicisi e-postasi uretilirken cakisma oldu. | [server/src/utils/validators.js:425](../server/src/utils/validators.js#L425) |
| Daire kullanicisi hesabi uretilemedi. | [server/src/utils/validators.js:445](../server/src/utils/validators.js#L445) |
| Daire kullanicisi hesabi uretilirken kullanici adi cakismasi oldu. | [server/src/utils/validators.js:428](../server/src/utils/validators.js#L428) |
| Daire sakini sifirlanamadi. | [server/src/routes/admin_routes.js:1441](../server/src/routes/admin_routes.js#L1441) |
| Daire sakini sifirlandi. | [server/src/routes/admin_routes.js:1436](../server/src/routes/admin_routes.js#L1436) |
| Daire sakini sifirlandi. | [server/src/routes/manager_routes.js:774](../server/src/routes/manager_routes.js#L774) |
| Daire sakininin şifresi başarıyla güncellendi. | [server/src/services/membership_service.js:2219](../server/src/services/membership_service.js#L2219) |
| Daire yöneticisi kendi durumunu pasife alamaz. | [server/src/services/membership_service.js:1898](../server/src/services/membership_service.js#L1898) |
| Daire yöneticisi kendi kendisini daireden çıkaramaz. | [server/src/services/membership_service.js:1803](../server/src/services/membership_service.js#L1803) |
| Davet bağlantısı gönderildi. | [server/src/modules/people_bulk_service.js:102](../server/src/modules/people_bulk_service.js#L102) |
| depolama yolu kok disina cikiyor | [server/src/modules/document_storage.js:152](../server/src/modules/document_storage.js#L152) |
| desteklenmeyen alan türü. | [server/src/modules/platform_config_service.js:179](../server/src/modules/platform_config_service.js#L179) |
| Desteklenmeyen karakter kumesi. | [server/src/middlewares/error_handler.js:30](../server/src/middlewares/error_handler.js#L30) |
| Desteklenmeyen kimlik sağlayıcısı. | [server/src/modules/oauth_login.js:389](../server/src/modules/oauth_login.js#L389) |
| Desteklenmeyen kodlama. | [server/src/middlewares/error_handler.js:29](../server/src/middlewares/error_handler.js#L29) |
| Desteklenmeyen veya eksik imzalama algoritması. | [server/src/modules/oauth_login.js:170](../server/src/modules/oauth_login.js#L170) |
| Devam etmeden once yeni bir sifre belirlemelisiniz. | [server/src/middlewares/auth_middleware.js:126](../server/src/middlewares/auth_middleware.js#L126) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:326](../server/src/routes/company_routes.js#L326) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:415](../server/src/routes/company_routes.js#L415) |
| device_uid 12 haneli hex (0-9, A-F) olmalidir. | [server/src/routes/company_routes.js:482](../server/src/routes/company_routes.js#L482) |
| device_uid zorunlu. | [server/src/routes/door_log_routes.js:229](../server/src/routes/door_log_routes.js#L229) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:323](../server/src/routes/company_routes.js#L323) |
| device_uid zorunludur. | [server/src/routes/company_routes.js:411](../server/src/routes/company_routes.js#L411) |
| dizin kimligi ile veritabani kimligi FARKLI; hangisinin dogru oldugunu elle belirleyin | [server/src/modules/document_integrity.js:224](../server/src/modules/document_integrity.js#L224) |
| dizindeki kimlik dosyasi bozuk; elle silip yeniden deneyin | [server/src/modules/document_integrity.js:221](../server/src/modules/document_integrity.js#L221) |
| Dogrulama kodu tekrar e-posta adresinize gonderildi. | [server/src/routes/auth_routes.js:665](../server/src/routes/auth_routes.js#L665) |
| Doğrulama isteği şu an işlenemiyor. Lütfen biraz sonra tekrar deneyiniz. | [server/src/services/membership_rules.js:77](../server/src/services/membership_rules.js#L77) |
| Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır. | [server/src/modules/oauth_login.js:924](../server/src/modules/oauth_login.js#L924) |
| Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır. | [server/src/services/membership_service.js:370](../server/src/services/membership_service.js#L370) |
| Dosya çok büyük. Bir seferde en çok ${BODY_SIZE_LABEL} gönderilebilir. | [server/src/modules/bulk_import_routes.js:112](../server/src/modules/bulk_import_routes.js#L112) |
| DRIVE_TOKEN_KEY en az 32 karakter olmali | [server/src/modules/drive_common.js:40](../server/src/modules/drive_common.js#L40) |
| E-posta adresi gereklidir. | [server/src/routes/auth_routes.js:107](../server/src/routes/auth_routes.js#L107) |
| E-posta adresi gereklidir. | [server/src/services/membership_service.js:524](../server/src/services/membership_service.js#L524) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/admin_routes.js:457](../server/src/routes/admin_routes.js#L457) |
| E-posta adresi güvenlik nedeniyle değiştirilemez. | [server/src/routes/auth_routes.js:924](../server/src/routes/auth_routes.js#L924) |
| E-posta adresiniz başarıyla doğrulandı. Hesabınız aktif! | [server/src/services/membership_service.js:507](../server/src/services/membership_service.js#L507) |
| E-posta adresiniz dogrulanmadi. | [server/src/middlewares/auth_middleware.js:115](../server/src/middlewares/auth_middleware.js#L115) |
| E-posta adresiniz dogrulanmadi. | [server/src/routes/auth_routes.js:829](../server/src/routes/auth_routes.js#L829) |
| E-posta ve doğrulama kodu zorunludur. | [server/src/services/membership_service.js:364](../server/src/services/membership_service.js#L364) |
| E-posta zaten dogrulanmis. Abonelik talebiniz onay bekliyor. | [server/src/routes/auth_routes.js:652](../server/src/routes/auth_routes.js#L652) |
| email ve password zorunlu. | [server/src/routes/auth_routes.js:746](../server/src/routes/auth_routes.js#L746) |
| email_verified alani true/false olmali. | [server/src/routes/admin_routes.js:408](../server/src/routes/admin_routes.js#L408) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/routes/admin_routes.js:1207](../server/src/routes/admin_routes.js#L1207) |
| En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir. | [server/src/utils/site_rules.js:421](../server/src/utils/site_rules.js#L421) |
| en fazla ${max} karakter olabilir. | [server/src/modules/platform_config_service.js:101](../server/src/modules/platform_config_service.js#L101) |
| En fazla ${SITE_LIMITS.maxBlocks} blok tanımlanabilir. | [server/src/services/membership_rules.js:496](../server/src/services/membership_rules.js#L496) |
| En fazla ${SITE_LIMITS.maxDoors} kapı tanımlanabilir. | [server/src/services/membership_rules.js:527](../server/src/services/membership_rules.js#L527) |
| en fazla ${spec.max} karakter olabilir. | [server/src/modules/platform_config_service.js:171](../server/src/modules/platform_config_service.js#L171) |
| Enlem -90 ile 90 arasinda olmalidir. | [server/src/utils/site_rules.js:331](../server/src/utils/site_rules.js#L331) |
| Etiketli cihazlar okunamadi. | [server/src/routes/company_routes.js:308](../server/src/routes/company_routes.js#L308) |
| feature_* alanlari true/false olmali. | [server/src/routes/admin_routes.js:1195](../server/src/routes/admin_routes.js#L1195) |
| Firmware dosyasi bulunamadi. | [server/src/routes/firmware_routes.js:240](../server/src/routes/firmware_routes.js#L240) |
| Firmware manifest okunamadi. | [server/src/routes/firmware_routes.js:221](../server/src/routes/firmware_routes.js#L221) |
| Fotoğraf bulunamadı. | [server/src/modules/metering_field_routes.js:183](../server/src/modules/metering_field_routes.js#L183) |
| full_name en az 3 karakter olmali. | [server/src/routes/admin_routes.js:402](../server/src/routes/admin_routes.js#L402) |
| Gecerli bir kapi secin. | [server/src/utils/guest_pass_utils.js:43](../server/src/utils/guest_pass_utils.js#L43) |
| gecersiz adres ozeti | [server/src/modules/announcement_email_security.js:132](../server/src/modules/announcement_email_security.js#L132) |
| Gecersiz alici adresi. | [server/src/mailer.js:681](../server/src/mailer.js#L681) |
| Gecersiz alici adresi. | [server/src/modules/contracts_reminders.js:68](../server/src/modules/contracts_reminders.js#L68) |
| Gecersiz alici adresi. | [server/src/modules/finance_reminder_mail.js:69](../server/src/modules/finance_reminder_mail.js#L69) |
| Gecersiz approval_status degeri. | [server/src/routes/admin_routes.js:832](../server/src/routes/admin_routes.js#L832) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:994](../server/src/routes/manager_routes.js#L994) |
| Gecersiz blok ID. | [server/src/routes/manager_routes.js:1032](../server/src/routes/manager_routes.js#L1032) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1626](../server/src/routes/admin_routes.js#L1626) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1699](../server/src/routes/admin_routes.js#L1699) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1785](../server/src/routes/admin_routes.js#L1785) |
| Gecersiz cihaz ID. | [server/src/routes/admin_routes.js:1818](../server/src/routes/admin_routes.js#L1818) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:944](../server/src/routes/manager_routes.js#L944) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1159](../server/src/routes/manager_routes.js#L1159) |
| Gecersiz cihaz ID. | [server/src/routes/manager_routes.js:1224](../server/src/routes/manager_routes.js#L1224) |
| Gecersiz cihaz unique id. | [server/src/routes/admin_routes.js:1529](../server/src/routes/admin_routes.js#L1529) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1327](../server/src/routes/admin_routes.js#L1327) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1394](../server/src/routes/admin_routes.js#L1394) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1422](../server/src/routes/admin_routes.js#L1422) |
| Gecersiz daire ID. | [server/src/routes/admin_routes.js:1449](../server/src/routes/admin_routes.js#L1449) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:688](../server/src/routes/manager_routes.js#L688) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:757](../server/src/routes/manager_routes.js#L757) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:787](../server/src/routes/manager_routes.js#L787) |
| Gecersiz daire ID. | [server/src/routes/manager_routes.js:820](../server/src/routes/manager_routes.js#L820) |
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
| Gecersiz kapi ID. | [server/src/routes/admin_routes.js:1477](../server/src/routes/admin_routes.js#L1477) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:860](../server/src/routes/manager_routes.js#L860) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:904](../server/src/routes/manager_routes.js#L904) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:933](../server/src/routes/manager_routes.js#L933) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1023](../server/src/routes/manager_routes.js#L1023) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1069](../server/src/routes/manager_routes.js#L1069) |
| Gecersiz kapi ID. | [server/src/routes/manager_routes.js:1096](../server/src/routes/manager_routes.js#L1096) |
| Gecersiz kapi id. | [server/src/routes/app_doors_routes.js:40](../server/src/routes/app_doors_routes.js#L40) |
| Gecersiz karekod verisi. | [server/src/routes/app_doors_routes.js:266](../server/src/routes/app_doors_routes.js#L266) |
| gecersiz klasor girdisi | [server/src/modules/drive_common.js:115](../server/src/modules/drive_common.js#L115) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:384](../server/src/routes/admin_routes.js#L384) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:509](../server/src/routes/admin_routes.js#L509) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:547](../server/src/routes/admin_routes.js#L547) |
| Gecersiz kullanici kodu. | [server/src/routes/admin_routes.js:767](../server/src/routes/admin_routes.js#L767) |
| Gecersiz kullanim limiti. | [server/src/utils/guest_pass_utils.js:74](../server/src/utils/guest_pass_utils.js#L74) |
| Gecersiz parametreler. | [server/src/services/qr_access_service.js:24](../server/src/services/qr_access_service.js#L24) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:225](../server/src/routes/admin_routes.js#L225) |
| Gecersiz rol. | [server/src/routes/admin_routes.js:405](../server/src/routes/admin_routes.js#L405) |
| Gecersiz rol. | [server/src/routes/auth_routes.js:749](../server/src/routes/auth_routes.js#L749) |
| gecersiz site kodu (depolama anahtari) | [server/src/modules/document_storage.js:139](../server/src/modules/document_storage.js#L139) |
| gecersiz site kodu (dizin) | [server/src/modules/document_storage.js:164](../server/src/modules/document_storage.js#L164) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:951](../server/src/routes/admin_routes.js#L951) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1023](../server/src/routes/admin_routes.js#L1023) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1178](../server/src/routes/admin_routes.js#L1178) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1229](../server/src/routes/admin_routes.js#L1229) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1247](../server/src/routes/admin_routes.js#L1247) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1262](../server/src/routes/admin_routes.js#L1262) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1277](../server/src/routes/admin_routes.js#L1277) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1292](../server/src/routes/admin_routes.js#L1292) |
| Gecersiz site kodu. | [server/src/routes/admin_routes.js:1307](../server/src/routes/admin_routes.js#L1307) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:229](../server/src/routes/manager_routes.js#L229) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:364](../server/src/routes/manager_routes.js#L364) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:485](../server/src/routes/manager_routes.js#L485) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:500](../server/src/routes/manager_routes.js#L500) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:515](../server/src/routes/manager_routes.js#L515) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:530](../server/src/routes/manager_routes.js#L530) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:552](../server/src/routes/manager_routes.js#L552) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:577](../server/src/routes/manager_routes.js#L577) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:984](../server/src/routes/manager_routes.js#L984) |
| Gecersiz site kodu. | [server/src/routes/manager_routes.js:1132](../server/src/routes/manager_routes.js#L1132) |
| Gecersiz token. | [server/src/middlewares/auth_middleware.js:53](../server/src/middlewares/auth_middleware.js#L53) |
| Gecersiz veya suresi dolmus token. | [server/src/middlewares/auth_middleware.js:45](../server/src/middlewares/auth_middleware.js#L45) |
| Gecis baglantisi bulunamadi veya silinmis. | [server/src/routes/guest_passes_routes.js:263](../server/src/routes/guest_passes_routes.js#L263) |
| Gecis baglantisi su an baska bir istekle kullaniliyor. Lutfen tekrar deneyin. | [server/src/routes/guest_passes_routes.js:391](../server/src/routes/guest_passes_routes.js#L391) |
| Gecis bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:211](../server/src/routes/guest_passes_routes.js#L211) |
| Gecis iptal edildi. | [server/src/routes/guest_passes_routes.js:214](../server/src/routes/guest_passes_routes.js#L214) |
| geçerli bir bağlantı değil. | [server/src/modules/platform_config_service.js:114](../server/src/modules/platform_config_service.js#L114) |
| Geçerli bir Cihaz Unique ID (UID) giriniz (12 haneli onaltılık, örn. D4C771A172E0). | [server/src/services/device_service.js:889](../server/src/services/device_service.js#L889) |
| Geçerli bir daire seçiniz. | [server/src/services/membership_service.js:939](../server/src/services/membership_service.js#L939) |
| Geçerli bir e-posta adresi gereklidir. | [server/src/services/site_service.js:2220](../server/src/services/site_service.js#L2220) |
| Geçerli bir e-posta adresi giriniz. | [server/src/modules/oauth_login.js:921](../server/src/modules/oauth_login.js#L921) |
| Geçerli bir e-posta adresi giriniz. | [server/src/routes/auth_routes.js:376](../server/src/routes/auth_routes.js#L376) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:268](../server/src/services/membership_service.js#L268) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:367](../server/src/services/membership_service.js#L367) |
| Geçerli bir e-posta adresi giriniz. | [server/src/services/membership_service.js:527](../server/src/services/membership_service.js#L527) |
| geçerli bir e-posta adresi olmalıdır. | [server/src/modules/platform_config_service.js:156](../server/src/modules/platform_config_service.js#L156) |
| geçerli bir https:// bağlantısı olmalıdır (kullanıcı adı / parola içeremez). | [server/src/modules/platform_config_service.js:117](../server/src/modules/platform_config_service.js#L117) |
| geçerli bir telefon numarası olmalıdır (örn. +90 212 000 00 00). | [server/src/modules/platform_config_service.js:161](../server/src/modules/platform_config_service.js#L161) |
| Geçersiz blok kimliği. | [server/src/services/membership_service.js:2735](../server/src/services/membership_service.js#L2735) |
| Geçersiz blok seçimi. | [server/src/services/membership_service.js:944](../server/src/services/membership_service.js#L944) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:949](../server/src/services/device_service.js#L949) |
| Geçersiz cihaz ID. | [server/src/services/device_service.js:995](../server/src/services/device_service.js#L995) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:1587](../server/src/services/membership_service.js#L1587) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:2113](../server/src/services/membership_service.js#L2113) |
| Geçersiz daire kimliği. | [server/src/services/membership_service.js:2726](../server/src/services/membership_service.js#L2726) |
| Geçersiz istek gövdesi. | [server/src/modules/client_error_routes.js:35](../server/src/modules/client_error_routes.js#L35) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:337](../server/src/routes/membership_routes.js#L337) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:357](../server/src/routes/membership_routes.js#L357) |
| Geçersiz kapı ID. | [server/src/routes/membership_routes.js:385](../server/src/routes/membership_routes.js#L385) |
| Geçersiz kapı kimliği. | [server/src/services/membership_service.js:2351](../server/src/services/membership_service.js#L2351) |
| Geçersiz katılım tokeni. | [server/src/services/membership_service.js:930](../server/src/services/membership_service.js#L930) |
| Geçersiz kimlik doğrulama belirteci. | [server/src/modules/oauth_login.js:145](../server/src/modules/oauth_login.js#L145) |
| Geçersiz kimlik doğrulama sağlayıcısı. | [server/src/modules/oauth_login.js:758](../server/src/modules/oauth_login.js#L758) |
| Geçersiz kimlik doğrulama sağlayıcısı. | [server/src/modules/oauth_login.js:800](../server/src/modules/oauth_login.js#L800) |
| Geçersiz kimlik doğrulama sağlayıcısı. | [server/src/modules/oauth_login.js:915](../server/src/modules/oauth_login.js#L915) |
| Geçersiz kimlik doğrulama sağlayıcısı. | [server/src/modules/oauth_login.js:1018](../server/src/modules/oauth_login.js#L1018) |
| Geçersiz kullanıcı kimliği. | [server/src/services/membership_service.js:1756](../server/src/services/membership_service.js#L1756) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:1495](../server/src/services/membership_service.js#L1495) |
| Geçersiz kullanıcı kodu. | [server/src/services/membership_service.js:2585](../server/src/services/membership_service.js#L2585) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1387](../server/src/routes/manager_routes.js#L1387) |
| Geçersiz parametreler. | [server/src/routes/manager_routes.js:1414](../server/src/routes/manager_routes.js#L1414) |
| Geçersiz parametreler. | [server/src/services/site_service.js:2457](../server/src/services/site_service.js#L2457) |
| Geçersiz site ID. | [server/src/routes/manager_routes.js:1263](../server/src/routes/manager_routes.js#L1263) |
| Geçersiz site ID. | [server/src/routes/membership_routes.js:412](../server/src/routes/membership_routes.js#L412) |
| Geçersiz site katılım kodu. | [server/src/routes/membership_routes.js:153](../server/src/routes/membership_routes.js#L153) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:1177](../server/src/services/membership_service.js#L1177) |
| Geçersiz site kimliği. | [server/src/services/membership_service.js:2838](../server/src/services/membership_service.js#L2838) |
| Geçersiz site kodu. | [server/src/modules/card_access_access.js:23](../server/src/modules/card_access_access.js#L23) |
| Geçersiz site kodu. | [server/src/modules/cctv_routes.js:64](../server/src/modules/cctv_routes.js#L64) |
| Geçersiz site kodu. | [server/src/modules/contracts_access.js:42](../server/src/modules/contracts_access.js#L42) |
| Geçersiz site kodu. | [server/src/modules/decision_book_access.js:24](../server/src/modules/decision_book_access.js#L24) |
| Geçersiz site kodu. | [server/src/modules/device_integrations_routes.js:80](../server/src/modules/device_integrations_routes.js#L80) |
| Geçersiz site kodu. | [server/src/modules/equipment_routes.js:55](../server/src/modules/equipment_routes.js#L55) |
| Geçersiz site kodu. | [server/src/modules/metering_field_routes.js:44](../server/src/modules/metering_field_routes.js#L44) |
| Geçersiz site kodu. | [server/src/modules/neighbor_board_routes.js:233](../server/src/modules/neighbor_board_routes.js#L233) |
| Geçersiz site kodu. | [server/src/modules/people_access.js:79](../server/src/modules/people_access.js#L79) |
| Geçersiz site kodu. | [server/src/modules/plate_recognition_routes.js:81](../server/src/modules/plate_recognition_routes.js#L81) |
| Geçersiz site kodu. | [server/src/modules/reservation_access.js:42](../server/src/modules/reservation_access.js#L42) |
| Geçersiz site kodu. | [server/src/modules/route_helpers.js:38](../server/src/modules/route_helpers.js#L38) |
| Geçersiz site kodu. | [server/src/modules/survey_access.js:23](../server/src/modules/survey_access.js#L23) |
| Geçersiz site kodu. | [server/src/modules/visitor_log_access.js:42](../server/src/modules/visitor_log_access.js#L42) |
| Geçersiz site kodu. | [server/src/modules/work_tracking_access.js:42](../server/src/modules/work_tracking_access.js#L42) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1333](../server/src/routes/manager_routes.js#L1333) |
| Geçersiz site kodu. | [server/src/routes/manager_routes.js:1356](../server/src/routes/manager_routes.js#L1356) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1701](../server/src/services/site_service.js#L1701) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1843](../server/src/services/site_service.js#L1843) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1890](../server/src/services/site_service.js#L1890) |
| Geçersiz site kodu. | [server/src/services/site_service.js:1956](../server/src/services/site_service.js#L1956) |
| Geçersiz site kodu. | [server/src/services/site_service.js:2038](../server/src/services/site_service.js#L2038) |
| Geçersiz sorgu parametresi. | [server/src/modules/module_request_routes.js:126](../server/src/modules/module_request_routes.js#L126) |
| Geçersiz sorgu parametresi. | [server/src/modules/module_routes.js:236](../server/src/modules/module_routes.js#L236) |
| Geçersiz şifre sıfırlama bağlantısı. Lütfen e-postanızdaki bağlantıyı kontrol ediniz. | [server/src/routes/auth_routes.js:412](../server/src/routes/auth_routes.js#L412) |
| Geçersiz şifreli değer. | [server/src/modules/device_integrations_service.js:47](../server/src/modules/device_integrations_service.js#L47) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1285](../server/src/routes/manager_routes.js#L1285) |
| Geçersiz talep ID. | [server/src/routes/manager_routes.js:1306](../server/src/routes/manager_routes.js#L1306) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1261](../server/src/services/membership_service.js#L1261) |
| Geçersiz talep kimliği. | [server/src/services/membership_service.js:1405](../server/src/services/membership_service.js#L1405) |
| gider hareketi bulunamadi | [server/src/modules/finance_expenses.js:598](../server/src/modules/finance_expenses.js#L598) |
| Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır. | [server/src/modules/oauth_login.js:965](../server/src/modules/oauth_login.js#L965) |
| Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır. | [server/src/services/membership_service.js:414](../server/src/services/membership_service.js#L414) |
| Girdiğiniz silme doğrulama kodu hatalı. | [server/src/services/site_service.js:2113](../server/src/services/site_service.js#L2113) |
| Giris bilgileri hatali. | [server/src/routes/auth_routes.js:819](../server/src/routes/auth_routes.js#L819) |
| Giris islemi basarisiz. | [server/src/routes/auth_routes.js:851](../server/src/routes/auth_routes.js#L851) |
| Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapilabilir. | [server/src/utils/site_rules.js:398](../server/src/utils/site_rules.js#L398) |
| Giriş doğrulama değeri (nonce) geçersiz. | [server/src/modules/oauth_login.js:716](../server/src/modules/oauth_login.js#L716) |
| Google kimlik doğrulama belirteci geçersiz veya süresi dolmuş. | [server/src/modules/oauth_login.js:258](../server/src/modules/oauth_login.js#L258) |
| Gövde bir nesne olmalıdır. | [server/src/modules/client_error_service.js:106](../server/src/modules/client_error_service.js#L106) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:446](../server/src/routes/admin_routes.js#L446) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/admin_routes.js:1062](../server/src/routes/admin_routes.js#L1062) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/auth_routes.js:919](../server/src/routes/auth_routes.js#L919) |
| Guncellenecek alan gonderilmedi. | [server/src/routes/manager_routes.js:397](../server/src/routes/manager_routes.js#L397) |
| Güncellenecek alan bulunamadı. | [server/src/services/door_service.js:690](../server/src/services/door_service.js#L690) |
| Günlük test bildirimi sınırına ulaşıldı. Yarın tekrar deneyin. | [server/src/modules/push_routes.js:50](../server/src/modules/push_routes.js#L50) |
| Güvenlik kuralı: Daire sakinlerinin şifresi yöneticiler tarafından değiştirilemez. Kullanıcılar kendi şifrelerini hesaplarına giriş yaparak profil bölümünden değiştirmelidir. | [server/src/routes/admin_routes.js:465](../server/src/routes/admin_routes.js#L465) |
| hardware_type esp32_c3 veya esp32_wroom olmali. | [server/src/routes/admin_routes.js:1656](../server/src/routes/admin_routes.js#L1656) |
| Hesabınız doğrulandı. Bu pencereyi kapatıp uygulamaya dönebilirsiniz. | [server/src/modules/oauth_routes.js:234](../server/src/modules/oauth_routes.js#L234) |
| Hesabınız henüz yönetici tarafından onaylanmamıştır. | [server/src/modules/oauth_login.js:610](../server/src/modules/oauth_login.js#L610) |
| Hesabiniz pasif durumda. Yonetici ile iletisime gecin. | [server/src/modules/oauth_login.js:616](../server/src/modules/oauth_login.js#L616) |
| Hesap aktif degil. | [server/src/middlewares/auth_middleware.js:112](../server/src/middlewares/auth_middleware.js#L112) |
| Hesap aktif degil. | [server/src/routes/auth_routes.js:838](../server/src/routes/auth_routes.js#L838) |
| Islem basarisiz. | [server/src/utils/guest_pass_utils.js:242](../server/src/utils/guest_pass_utils.js#L242) |
| Istek govdesi cok buyuk. | [server/src/middlewares/error_handler.js:24](../server/src/middlewares/error_handler.js#L24) |
| Istek govdesi cok buyuk. | [server/src/routes/door_log_routes.js:223](../server/src/routes/door_log_routes.js#L223) |
| Istek yarida kesildi. | [server/src/middlewares/error_handler.js:27](../server/src/middlewares/error_handler.js#L27) |
| İlişik kesildi (pasife alındı). | [server/src/modules/people_bulk_service.js:123](../server/src/modules/people_bulk_service.js#L123) |
| install_id geçerli bir UUID olmalıdır. | [server/src/modules/client_error_service.js:110](../server/src/modules/client_error_service.js#L110) |
| İptal edilecek bekleyen davet bulunamadı. | [server/src/services/site_service.js:2617](../server/src/services/site_service.js#L2617) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:514](../server/src/routes/admin_routes.js#L514) |
| is_active alani true/false olmali. | [server/src/routes/admin_routes.js:1337](../server/src/routes/admin_routes.js#L1337) |
| is_active alani true/false olmali. | [server/src/routes/manager_routes.js:1036](../server/src/routes/manager_routes.js#L1036) |
| is_defective alani true/false olmali. | [server/src/routes/admin_routes.js:1789](../server/src/routes/admin_routes.js#L1789) |
| İstek gövdesi geçersiz. | [server/src/modules/bank_import_routes.js:55](../server/src/modules/bank_import_routes.js#L55) |
| İstek gövdesi geçersiz. | [server/src/modules/bulk_import_routes.js:114](../server/src/modules/bulk_import_routes.js#L114) |
| istemci baglantisi kesildi | [server/src/modules/document_upload.js:50](../server/src/modules/document_upload.js#L50) |
| İşlem sırasında bir hata oluştu. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:458](../server/src/routes/auth_routes.js#L458) |
| JWT_SECRET tanımlı değil | [server/src/modules/apartment_mgmt_service.js:92](../server/src/modules/apartment_mgmt_service.js#L92) |
| Kamera parolası şifrelemesi için CAMERA_SECRET_KEY ya da JWT_SECRET gerekli. | [server/src/modules/device_integrations_service.js:34](../server/src/modules/device_integrations_service.js#L34) |
| Kapı adı boş olamaz. | [server/src/services/door_service.js:665](../server/src/services/door_service.js#L665) |
| Kapı adı zorunludur. | [server/src/services/door_service.js:591](../server/src/services/door_service.js#L591) |
| Kapı bulunamadı. | [server/src/services/membership_service.js:2363](../server/src/services/membership_service.js#L2363) |
| Kapı yetkisi varsayılan ayarlara döndürüldü. | [server/src/services/membership_service.js:2669](../server/src/services/membership_service.js#L2669) |
| Kapi adi zorunludur. | [server/src/routes/manager_routes.js:990](../server/src/routes/manager_routes.js#L990) |
| Kapi basariyla acildi. | [server/src/routes/app_doors_routes.js:408](../server/src/routes/app_doors_routes.js#L408) |
| Kapi bulunamadi veya erisim yetkiniz yok. | [server/src/services/qr_access_service.js:31](../server/src/services/qr_access_service.js#L31) |
| Kapi bulunamadi veya yetkiniz yok. | [server/src/routes/guest_passes_routes.js:67](../server/src/routes/guest_passes_routes.js#L67) |
| Kapi bulunamadi. | [server/src/routes/admin_routes.js:1495](../server/src/routes/admin_routes.js#L1495) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:133](../server/src/routes/app_doors_routes.js#L133) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:174](../server/src/routes/app_doors_routes.js#L174) |
| Kapi bulunamadi. | [server/src/routes/app_doors_routes.js:432](../server/src/routes/app_doors_routes.js#L432) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:868](../server/src/routes/manager_routes.js#L868) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:910](../server/src/routes/manager_routes.js#L910) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:953](../server/src/routes/manager_routes.js#L953) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1042](../server/src/routes/manager_routes.js#L1042) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1075](../server/src/routes/manager_routes.js#L1075) |
| Kapi bulunamadi. | [server/src/routes/manager_routes.js:1102](../server/src/routes/manager_routes.js#L1102) |
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
| Katılım başvurusu reddedildi. | [server/src/services/membership_service.js:1479](../server/src/services/membership_service.js#L1479) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1283](../server/src/services/membership_service.js#L1283) |
| Katılım talebi bulunamadı. | [server/src/services/membership_service.js:1416](../server/src/services/membership_service.js#L1416) |
| Kaydınız reddedilmiştir. | [server/src/modules/oauth_login.js:613](../server/src/modules/oauth_login.js#L613) |
| Kayit olusturuldu. E-posta adresinize gonderilen 6 haneli kodu girin. | [server/src/routes/auth_routes.js:693](../server/src/routes/auth_routes.js#L693) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:450](../server/src/routes/admin_routes.js#L450) |
| Kendi hesabinizi pasif yapamazsiniz. | [server/src/routes/admin_routes.js:517](../server/src/routes/admin_routes.js#L517) |
| Kendi hesabinizi silemezsiniz. | [server/src/routes/admin_routes.js:555](../server/src/routes/admin_routes.js#L555) |
| Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin. | [server/src/routes/admin_routes.js:416](../server/src/routes/admin_routes.js#L416) |
| Kimlik doğrulama anahtarları geçersiz. | [server/src/modules/oauth_login.js:116](../server/src/modules/oauth_login.js#L116) |
| Kimlik doğrulama belirteci biçimi geçersiz. | [server/src/modules/oauth_login.js:149](../server/src/modules/oauth_login.js#L149) |
| Kimlik doğrulama belirteci bu oturum için üretilmemiş (nonce eşleşmiyor). | [server/src/modules/oauth_login.js:770](../server/src/modules/oauth_login.js#L770) |
| Kimlik doğrulama belirteci çözümlenemedi. | [server/src/modules/oauth_login.js:157](../server/src/modules/oauth_login.js#L157) |
| Kimlik doğrulama belirteci imzası geçersiz. | [server/src/modules/oauth_login.js:196](../server/src/modules/oauth_login.js#L196) |
| Kimlik doğrulama belirteci zaman damgası geçersiz. | [server/src/modules/oauth_login.js:207](../server/src/modules/oauth_login.js#L207) |
| Kimlik doğrulama belirtecinin süresi dolmuş. | [server/src/modules/oauth_login.js:202](../server/src/modules/oauth_login.js#L202) |
| Kimlik doğrulama belirtecinin süresi dolmuş. | [server/src/modules/oauth_login.js:302](../server/src/modules/oauth_login.js#L302) |
| Kimlik doğrulama belirtecinin süresi dolmuş. | [server/src/modules/oauth_login.js:323](../server/src/modules/oauth_login.js#L323) |
| Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor. | [server/src/modules/oauth_login.js:221](../server/src/modules/oauth_login.js#L221) |
| Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor. | [server/src/modules/oauth_login.js:298](../server/src/modules/oauth_login.js#L298) |
| Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor. | [server/src/modules/oauth_login.js:315](../server/src/modules/oauth_login.js#L315) |
| Kimlik doğrulama imzası doğrulanamadı (anahtar bulunamadı). | [server/src/modules/oauth_login.js:185](../server/src/modules/oauth_login.js#L185) |
| Kimlik doğrulama kullanıcı tanımlayıcısı (sub) geçersiz. | [server/src/modules/oauth_login.js:231](../server/src/modules/oauth_login.js#L231) |
| Kimlik doğrulama kullanıcı tanımlayıcısı alınamadı. | [server/src/modules/oauth_login.js:452](../server/src/modules/oauth_login.js#L452) |
| Kimlik doğrulama sağlayıcısı (iss) geçersiz. | [server/src/modules/oauth_login.js:213](../server/src/modules/oauth_login.js#L213) |
| Kimlik doğrulama sağlayıcısı (iss) geçersiz. | [server/src/modules/oauth_login.js:295](../server/src/modules/oauth_login.js#L295) |
| Kimlik doğrulama sağlayıcısına şu anda ulaşılamıyor. | [server/src/modules/oauth_login.js:112](../server/src/modules/oauth_login.js#L112) |
| Kimlik doğrulama sağlayıcısına şu anda ulaşılamıyor. | [server/src/modules/oauth_login.js:182](../server/src/modules/oauth_login.js#L182) |
| Kimlik doğrulama sağlayıcısına şu anda ulaşılamıyor. | [server/src/modules/oauth_login.js:254](../server/src/modules/oauth_login.js#L254) |
| Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur. | [server/src/utils/site_rules.js:468](../server/src/utils/site_rules.js#L468) |
| Konum yaricapi ${GEOFENCE_RADIUS_MIN} ile ${GEOFENCE_RADIUS_MAX} metre arasinda olmalidir. | [server/src/utils/site_rules.js:348](../server/src/utils/site_rules.js#L348) |
| köşeli parantez, < >, ters eğik çizgi, ters tırnak veya ** içeremez ve #, -, +, *, > ile başlayamaz. | [server/src/modules/platform_config_service.js:174](../server/src/modules/platform_config_service.js#L174) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_rules.js:383](../server/src/services/membership_rules.js#L383) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1828](../server/src/services/membership_service.js#L1828) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:1931](../server/src/services/membership_service.js#L1931) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:2042](../server/src/services/membership_service.js#L2042) |
| Kullanıcı bu dairede kayıtlı değil. | [server/src/services/membership_service.js:2303](../server/src/services/membership_service.js#L2303) |
| Kullanıcı bu daireye ait değil. | [server/src/services/membership_service.js:2159](../server/src/services/membership_service.js#L2159) |
| Kullanıcı bu sitenin yöneticisi değil. | [server/src/utils/site_rules.js:178](../server/src/utils/site_rules.js#L178) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:594](../server/src/services/membership_service.js#L594) |
| Kullanıcı bulunamadı. | [server/src/services/membership_service.js:2635](../server/src/services/membership_service.js#L2635) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:827](../server/src/services/membership_service.js#L827) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:972](../server/src/services/membership_service.js#L972) |
| Kullanıcı hesabı bulunamadı. | [server/src/services/membership_service.js:2198](../server/src/services/membership_service.js#L2198) |
| Kullanıcı kodu (userCode) zorunludur. | [server/src/routes/membership_routes.js:361](../server/src/routes/membership_routes.js#L361) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:577](../server/src/services/membership_service.js#L577) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:794](../server/src/services/membership_service.js#L794) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:935](../server/src/services/membership_service.js#L935) |
| Kullanıcı oturumu gereklidir. | [server/src/services/membership_service.js:1121](../server/src/services/membership_service.js#L1121) |
| Kullanıcı site yöneticiliğinden çıkarıldı. | [server/src/services/site_service.js:2590](../server/src/services/site_service.js#L2590) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/admin_routes.js:1463](../server/src/routes/admin_routes.js#L1463) |
| Kullanici adi veya PIN hazir degil. | [server/src/routes/manager_routes.js:806](../server/src/routes/manager_routes.js#L806) |
| Kullanici bulunamadi. | [server/src/middlewares/auth_middleware.js:86](../server/src/middlewares/auth_middleware.js#L86) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:187](../server/src/routes/admin_routes.js#L187) |
| Kullanici bulunamadi. | [server/src/routes/admin_routes.js:664](../server/src/routes/admin_routes.js#L664) |
| Kullanici bulunamadi. | [server/src/routes/auth_routes.js:973](../server/src/routes/auth_routes.js#L973) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1662](../server/src/routes/admin_routes.js#L1662) |
| Kullanici ID bulunamadi. | [server/src/routes/admin_routes.js:1739](../server/src/routes/admin_routes.js#L1739) |
| Kullanici ID sayisal olmali. | [server/src/routes/admin_routes.js:1641](../server/src/routes/admin_routes.js#L1641) |
| Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin. | [server/src/utils/validators.js:413](../server/src/utils/validators.js#L413) |
| Kullanici rolu ile secilen rol uyusmuyor. | [server/src/routes/auth_routes.js:826](../server/src/routes/auth_routes.js#L826) |
| Kullanici silinemedi. | [server/src/routes/admin_routes.js:693](../server/src/routes/admin_routes.js#L693) |
| Log senkronizasyonu basarisiz. | [server/src/routes/door_log_routes.js:267](../server/src/routes/door_log_routes.js#L267) |
| logs bir dizi olmali. | [server/src/routes/door_log_routes.js:232](../server/src/routes/door_log_routes.js#L232) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/routes/manager_routes.js:947](../server/src/routes/manager_routes.js#L947) |
| Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID'sini belirtin. | [server/src/utils/site_rules.js:491](../server/src/utils/site_rules.js#L491) |
| Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz. | [server/src/services/site_service.js:2057](../server/src/services/site_service.js#L2057) |
| Lütfen 6 haneli silme doğrulama kodunu giriniz. | [server/src/routes/admin_routes.js:1312](../server/src/routes/admin_routes.js#L1312) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/admin_routes.js:1460](../server/src/routes/admin_routes.js#L1460) |
| Mail gonderimi icin daire sakini e-postasi gerekli. | [server/src/routes/manager_routes.js:803](../server/src/routes/manager_routes.js#L803) |
| MERSİS numarası 16 haneli olmalıdır. | [server/src/modules/platform_config_service.js:165](../server/src/modules/platform_config_service.js#L165) |
| message ya da stack gereklidir. | [server/src/modules/client_error_service.js:119](../server/src/modules/client_error_service.js#L119) |
| metin olmalıdır. | [server/src/modules/platform_config_service.js:140](../server/src/modules/platform_config_service.js#L140) |
| Mevcut şifre hatalı. | [server/src/services/membership_service.js:2172](../server/src/services/membership_service.js#L2172) |
| Mevcut şifre zorunludur. | [server/src/services/membership_service.js:2138](../server/src/services/membership_service.js#L2138) |
| Mevcut yonetici kodu veya yeni yonetici bilgilerinden yalnizca biri gonderilmeli. | [server/src/routes/admin_routes.js:888](../server/src/routes/admin_routes.js#L888) |
| Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz. | [server/src/modules/module_routes.js:38](../server/src/modules/module_routes.js#L38) |
| MQTT ACL senkronu zaman asimina ugradi (${timeoutMs} ms). | [server/src/mqtt_acl_sync.js:208](../server/src/mqtt_acl_sync.js#L208) |
| MQTT baglantisi hazir degil. | [server/src/routes/admin_routes.js:1616](../server/src/routes/admin_routes.js#L1616) |
| MQTT baglantisi hazir degil. | [server/src/routes/app_doors_routes.js:65](../server/src/routes/app_doors_routes.js#L65) |
| MQTT broker senkronu basarisiz. | [server/src/routes/admin_routes.js:1572](../server/src/routes/admin_routes.js#L1572) |
| MQTT broker senkronu basarisiz. | [server/src/routes/manager_routes.js:672](../server/src/routes/manager_routes.js#L672) |
| MQTT cihaz kimligi uretilemedi. | [server/src/routes/admin_routes.js:1576](../server/src/routes/admin_routes.js#L1576) |
| MQTT_SYNC_COMMAND tanimli degil. | [server/src/mqtt_acl_sync.js:169](../server/src/mqtt_acl_sync.js#L169) |
| MQTT_SYNC_COMMAND/MQTT_SYNC_ARGS gecersiz karakter iceriyor. | [server/src/mqtt_acl_sync.js:182](../server/src/mqtt_acl_sync.js#L182) |
| OTA komutu gonderilemedi. | [server/src/routes/admin_routes.js:1618](../server/src/routes/admin_routes.js#L1618) |
| Oturum bulunamadı veya süresi doldu. | [server/src/modules/oauth_login.js:1139](../server/src/modules/oauth_login.js#L1139) |
| Oturum gecersiz. Lutfen tekrar giris yapin. | [server/src/middlewares/auth_middleware.js:106](../server/src/middlewares/auth_middleware.js#L106) |
| Oturum süresi dolmuş veya geçersiz. Lütfen uygulamadan tekrar deneyin. | [server/src/modules/oauth_login.js:1092](../server/src/modules/oauth_login.js#L1092) |
| Parolayi degistirmek icin mevcut parolanizi girmelisiniz. | [server/src/routes/auth_routes.js:930](../server/src/routes/auth_routes.js#L930) |
| PDF çok büyük. En çok 5 MB yüklenebilir. | [server/src/modules/bank_import_routes.js:54](../server/src/modules/bank_import_routes.js#L54) |
| platform_rules: bilinmeyen kural ${String(key).slice(0, 80)} | [server/src/modules/platform_rules.js:385](../server/src/modules/platform_rules.js#L385) |
| platform_rules: denetim kaydı yazılamadı | [server/src/modules/platform_rules_service.js:361](../server/src/modules/platform_rules_service.js#L361) |
| qr_entry_active alani true/false olmalidir. | [server/src/utils/site_rules.js:319](../server/src/utils/site_rules.js#L319) |
| qr_image_base64 gecerli bir PNG (en fazla 2 MB) olmalidir. | [server/src/routes/company_routes.js:333](../server/src/routes/company_routes.js#L333) |
| qr_rotation_seconds sayisal olmalidir. | [server/src/utils/site_rules.js:359](../server/src/utils/site_rules.js#L359) |
| Rapor çok büyük. | [server/src/modules/client_error_routes.js:34](../server/src/modules/client_error_routes.js#L34) |
| require_geofence alani true/false olmalidir. | [server/src/utils/site_rules.js:325](../server/src/utils/site_rules.js#L325) |
| Route bulunamadi. | [server/src/middlewares/error_handler.js:116](../server/src/middlewares/error_handler.js#L116) |
| Sağlayıcıdan gelen e-posta adresi geçersiz. | [server/src/modules/oauth_login.js:460](../server/src/modules/oauth_login.js#L460) |
| Sakin daireden başarıyla silindi. | [server/src/services/membership_service.js:2082](../server/src/services/membership_service.js#L2082) |
| Sakini kalıcı olarak silme yetkisi yalnızca site yöneticilerine aittir. | [server/src/services/membership_service.js:2020](../server/src/services/membership_service.js#L2020) |
| sayac borc satir sayisi uyusmuyor (${written.rowCount} / ${lines.length}) | [server/src/modules/metering_billing.js:273](../server/src/modules/metering_billing.js#L273) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:881](../server/src/routes/admin_routes.js#L881) |
| Sayisal alanlar gecersiz. | [server/src/routes/admin_routes.js:1045](../server/src/routes/admin_routes.js#L1045) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:323](../server/src/routes/manager_routes.js#L323) |
| Sayisal alanlar gecersiz. | [server/src/routes/manager_routes.js:384](../server/src/routes/manager_routes.js#L384) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:1002](../server/src/routes/manager_routes.js#L1002) |
| Secilen blok bu siteye ait degil. | [server/src/routes/manager_routes.js:1048](../server/src/routes/manager_routes.js#L1048) |
| Secilen yeni cihaz bulunamadi. | [server/src/routes/manager_routes.js:974](../server/src/routes/manager_routes.js#L974) |
| Seçilen alanda aktif sakin bulunamadı. | [server/src/services/membership_service.js:2749](../server/src/services/membership_service.js#L2749) |
| Seçilen daire belirtilen bloğa ait değil. | [server/src/services/membership_service.js:1011](../server/src/services/membership_service.js#L1011) |
| Seçilen daire bulunamadı veya bu siteye ait değil. | [server/src/services/membership_service.js:1007](../server/src/services/membership_service.js#L1007) |
| SERVER_SKIP_START=1 production ortaminda YOK SAYILDI (yalniz testler icindir; .env dosyasindan kaldirin). Sunucu normal baslatiliyor. | [server/src/config/env.js:358](../server/src/config/env.js#L358) |
| Sıfırlama anahtarı (token) eksik. | [server/src/routes/auth_routes.js:470](../server/src/routes/auth_routes.js#L470) |
| Sifre 4 haneli sayisal olmali. | [server/src/services/apartment_service.js:296](../server/src/services/apartment_service.js#L296) |
| Sifre en fazla ${MAX_PASSWORD_LENGTH} karakter olabilir. | [server/src/routes/auth_routes.js:909](../server/src/routes/auth_routes.js#L909) |
| sifreli belirtec biçimi geçersiz | [server/src/modules/drive_common.js:55](../server/src/modules/drive_common.js#L55) |
| Silme doğrulama kodu e-posta adresinize (${maskedEmail}) gönderildi. | [server/src/services/site_service.js:2012](../server/src/services/site_service.js#L2012) |
| Silme doğrulama kodunun 10 dakikalık süresi dolmuş. Lütfen yeni bir kod isteyiniz. | [server/src/services/site_service.js:2081](../server/src/services/site_service.js#L2081) |
| Site adı en fazla ${SETUP_NAME_MAX} karakter olabilir. | [server/src/services/membership_rules.js:487](../server/src/services/membership_rules.js#L487) |
| Site adı zorunludur. | [server/src/services/membership_rules.js:484](../server/src/services/membership_rules.js#L484) |
| Site adi en az 2 karakter olmali. | [server/src/routes/admin_routes.js:1048](../server/src/routes/admin_routes.js#L1048) |
| Site bulunamadı. | [server/src/modules/people_access.js:18](../server/src/modules/people_access.js#L18) |
| Site bulunamadı. | [server/src/modules/route_helpers.js:15](../server/src/modules/route_helpers.js#L15) |
| Site bulunamadı. | [server/src/services/membership_service.js:2849](../server/src/services/membership_service.js#L2849) |
| Site bulunamadı. | [server/src/services/site_service.js:1621](../server/src/services/site_service.js#L1621) |
| Site bulunamadı. | [server/src/services/site_service.js:1660](../server/src/services/site_service.js#L1660) |
| Site bulunamadı. | [server/src/services/site_service.js:1720](../server/src/services/site_service.js#L1720) |
| Site bulunamadı. | [server/src/services/site_service.js:1854](../server/src/services/site_service.js#L1854) |
| Site bulunamadı. | [server/src/services/site_service.js:1907](../server/src/services/site_service.js#L1907) |
| Site bulunamadı. | [server/src/services/site_service.js:1966](../server/src/services/site_service.js#L1966) |
| Site bulunamadı. | [server/src/services/site_service.js:2068](../server/src/services/site_service.js#L2068) |
| Site bulunamadı. | [server/src/services/site_service.js:2227](../server/src/services/site_service.js#L2227) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1068](../server/src/routes/admin_routes.js#L1068) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1201](../server/src/routes/admin_routes.js#L1201) |
| Site bulunamadi. | [server/src/routes/admin_routes.js:1235](../server/src/routes/admin_routes.js#L1235) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:244](../server/src/routes/manager_routes.js#L244) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:407](../server/src/routes/manager_routes.js#L407) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:540](../server/src/routes/manager_routes.js#L540) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:567](../server/src/routes/manager_routes.js#L567) |
| Site bulunamadi. | [server/src/routes/manager_routes.js:596](../server/src/routes/manager_routes.js#L596) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1665](../server/src/routes/admin_routes.js#L1665) |
| Site ID bulunamadi. | [server/src/routes/admin_routes.js:1742](../server/src/routes/admin_routes.js#L1742) |
| Site ID bulunamadi. | [server/src/routes/manager_routes.js:1177](../server/src/routes/manager_routes.js#L1177) |
| Site ID sayisal olmali. | [server/src/routes/admin_routes.js:1644](../server/src/routes/admin_routes.js#L1644) |
| Site katilim QR kodu basariyla yenilendi. Eski QR kodlar iptal edildi. | [server/src/routes/manager_routes.js:592](../server/src/routes/manager_routes.js#L592) |
| Site kaydini yalnizca super user guncelleyebilir. | [server/src/routes/manager_routes.js:359](../server/src/routes/manager_routes.js#L359) |
| Site kaydini yalnizca super user olusturabilir. | [server/src/routes/manager_routes.js:298](../server/src/routes/manager_routes.js#L298) |
| Site kodu olusturulurken cakisma oldu. | [server/src/utils/validators.js:442](../server/src/utils/validators.js#L442) |
| Site kurmak için başvuru yapmalısınız. | [server/src/services/membership_service.js:751](../server/src/services/membership_service.js#L751) |
| Site silme talebi başarıyla iptal edildi / reddedildi. | [server/src/services/site_service.js:1940](../server/src/services/site_service.js#L1940) |
| Site silme talebi oluşturuldu. Site yöneticisinin onayı gerekmektedir. | [server/src/services/site_service.js:1787](../server/src/services/site_service.js#L1787) |
| Site silme talebi oluşturuldu. Süper kullanıcının onayı gerekmektedir. | [server/src/services/site_service.js:1833](../server/src/services/site_service.js#L1833) |
| Site silme talebi zaten oluşturulmuş; Site Yöneticisinin onayı bekleniyor. | [server/src/services/site_service.js:1758](../server/src/services/site_service.js#L1758) |
| Site silme talebi zaten oluşturulmuş; Süper Kullanıcının onayı bekleniyor. | [server/src/services/site_service.js:1804](../server/src/services/site_service.js#L1804) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:874](../server/src/routes/manager_routes.js#L874) |
| Site sirket tarafindan onaylanmadan cihaza kapi atayamazsiniz. | [server/src/routes/manager_routes.js:1184](../server/src/routes/manager_routes.js#L1184) |
| Site talebi baska bir islemle zaten sonuclandirildi. | [server/src/routes/admin_routes.js:1005](../server/src/routes/admin_routes.js#L1005) |
| Site ve bağlı tüm kayıtlar başarıyla silindi. | [server/src/services/site_service.js:1692](../server/src/services/site_service.js#L1692) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/helpers.js:604](../server/src/utils/helpers.js#L604) |
| Site yoneticisi bilgileri gecersiz. | [server/src/utils/validators.js:235](../server/src/utils/validators.js#L235) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:911](../server/src/routes/admin_routes.js#L911) |
| Site yoneticisi bulunamadi. | [server/src/routes/admin_routes.js:1083](../server/src/routes/admin_routes.js#L1083) |
| Site yoneticisi kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:604](../server/src/routes/auth_routes.js#L604) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:706](../server/src/routes/auth_routes.js#L706) |
| Site yoneticisi onay akisi kapatildi. | [server/src/routes/auth_routes.js:713](../server/src/routes/auth_routes.js#L713) |
| Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz. | [server/src/utils/site_rules.js:187](../server/src/utils/site_rules.js#L187) |
| Sitenin kurucu yöneticisi (Site Sahibi) yalnızca Süper Kullanıcı tarafından çıkarılabilir. | [server/src/utils/site_rules.js:195](../server/src/utils/site_rules.js#L195) |
| Siteye katılım başvurusu yapabilmek için e-posta adresinizi doğrulamanız gerekmektedir. | [server/src/services/membership_service.js:976](../server/src/services/membership_service.js#L976) |
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
| Süper kullanıcı hesabına kayıtlı bir e-posta adresi bulunamadı. | [server/src/services/site_service.js:1978](../server/src/services/site_service.js#L1978) |
| sürüm major.minor.patch biçiminde olmalıdır (örn. 1.2.0). | [server/src/modules/platform_config_service.js:150](../server/src/modules/platform_config_service.js#L150) |
| Şifre en az 4 karakter uzunluğunda olmalıdır. | [server/src/services/membership_service.js:2129](../server/src/services/membership_service.js#L2129) |
| Şifre en az 6 karakter olmalıdır. | [server/src/services/membership_service.js:271](../server/src/services/membership_service.js#L271) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:274](../server/src/services/membership_service.js#L274) |
| Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir. | [server/src/services/membership_service.js:2132](../server/src/services/membership_service.js#L2132) |
| Şifre güncellenemedi. Lütfen daha sonra tekrar deneyiniz. | [server/src/routes/auth_routes.js:554](../server/src/routes/auth_routes.js#L554) |
| Şifre sıfırlama bağlantısı e-posta adresine gönderildi. | [server/src/modules/people_bulk_service.js:68](../server/src/modules/people_bulk_service.js#L68) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:477](../server/src/routes/auth_routes.js#L477) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:492](../server/src/routes/auth_routes.js#L492) |
| Şifre sıfırlama bağlantısı geçersiz veya daha önce kullanılmış. | [server/src/routes/auth_routes.js:524](../server/src/routes/auth_routes.js#L524) |
| Şifre sıfırlama bağlantısı gönderildi. | [server/src/modules/people_bulk_service.js:98](../server/src/modules/people_bulk_service.js#L98) |
| Şifre sıfırlama bağlantısı gönderildi. | [server/src/modules/people_bulk_service.js:115](../server/src/modules/people_bulk_service.js#L115) |
| Şifre sıfırlama bağlantısının süresi dolmuş. Lütfen yeni bir talepte bulunun. | [server/src/routes/auth_routes.js:498](../server/src/routes/auth_routes.js#L498) |
| Şifreniz başarıyla güncellendi. Yeni şifrenizle giriş yapabilirsiniz. | [server/src/routes/auth_routes.js:549](../server/src/routes/auth_routes.js#L549) |
| Talep bulunamadı. | [server/src/modules/module_request_routes.js:40](../server/src/modules/module_request_routes.js#L40) |
| tazminat satir sayisi uyusmuyor (${written.rowCount} / ${lines.length}) | [server/src/modules/finance_late_fee.js:586](../server/src/modules/finance_late_fee.js#L586) |
| Tek istekte en fazla ${MAX_DEVICE_LOG_BATCH} kayit gonderilebilir. | [server/src/routes/door_log_routes.js:237](../server/src/routes/door_log_routes.js#L237) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:442](../server/src/services/qr_access_service.js#L442) |
| Token bulunamadı. | [server/src/services/qr_access_service.js:470](../server/src/services/qr_access_service.js#L470) |
| Token parametresi zorunludur. | [server/src/routes/app_doors_routes.js:535](../server/src/routes/app_doors_routes.js#L535) |
| Token zorunludur. | [server/src/services/qr_access_service.js:437](../server/src/services/qr_access_service.js#L437) |
| Toplam daire sayısı en fazla ${SITE_LIMITS.maxApartments} olabilir. | [server/src/services/membership_rules.js:520](../server/src/services/membership_rules.js#L520) |
| toplu eşleme satır sayısı uyuşmuyor | [server/src/modules/finance_accounts.js:963](../server/src/modules/finance_accounts.js#L963) |
| Toplu işlemler geçici olarak kapalı. | [server/src/modules/bulk_import_routes.js:83](../server/src/modules/bulk_import_routes.js#L83) |
| Toplu yetkilendirme için blok, daire veya kullanıcı listesi belirtilmelidir. | [server/src/services/membership_service.js:2742](../server/src/services/membership_service.js#L2742) |
| true veya false olmalıdır. | [server/src/modules/platform_config_service.js:132](../server/src/modules/platform_config_service.js#L132) |
| Uygulamaya davet bağlantısı gönderildi. | [server/src/modules/people_bulk_service.js:118](../server/src/modules/people_bulk_service.js#L118) |
| Üye daireden başarıyla çıkarıldı. | [server/src/services/membership_service.js:1867](../server/src/services/membership_service.js#L1867) |
| Vekalet en fazla bir yıl geçerli olabilir. | [server/src/modules/apartment_mgmt_rules.js:251](../server/src/modules/apartment_mgmt_rules.js#L251) |
| Veritabanı sağlık bilgisi alınamadı. | [server/src/services/maintenance_service.js:215](../server/src/services/maintenance_service.js#L215) |
| Veritabanı temizliği başarısız oldu. | [server/src/services/maintenance_service.js:101](../server/src/services/maintenance_service.js#L101) |
| Veritabani saglik bilgisi alinamadi. | [server/src/routes/admin_routes.js:1844](../server/src/routes/admin_routes.js#L1844) |
| Veritabani temizligi sirasinda hata olustu. | [server/src/routes/admin_routes.js:1859](../server/src/routes/admin_routes.js#L1859) |
| yalnızca https:// ile başlayan bağlantı kabul edilir. | [server/src/modules/platform_config_service.js:104](../server/src/modules/platform_config_service.js#L104) |
| Yeni kod istemek için lütfen ${seconds} saniye bekleyiniz. | [server/src/services/membership_rules.js:114](../server/src/services/membership_rules.js#L114) |
| Yeni kullanici kaydi yalnizca super user tarafindan yapilir. | [server/src/routes/auth_routes.js:561](../server/src/routes/auth_routes.js#L561) |
| Yeni şifre mevcut şifrenizle aynı olamaz. | [server/src/routes/auth_routes.js:938](../server/src/routes/auth_routes.js#L938) |
| Yetkisiz erisim. | [server/src/middlewares/auth_middleware.js:36](../server/src/middlewares/auth_middleware.js#L36) |
| Yetkisiz erisim. | [server/src/middlewares/company_auth.js:43](../server/src/middlewares/company_auth.js#L43) |
| Yetkisiz erisim. | [server/src/routes/admin_routes.js:552](../server/src/routes/admin_routes.js#L552) |
| Yetkisiz erisim. | [server/src/routes/auth_routes.js:866](../server/src/routes/auth_routes.js#L866) |
| Yetkisiz erisim. | [server/src/routes/manager_routes.js:303](../server/src/routes/manager_routes.js#L303) |
| Yönetici daveti iptal edildi. | [server/src/services/site_service.js:2644](../server/src/services/site_service.js#L2644) |
| Yükleme türü bulunamadı. | [server/src/modules/bulk_import_routes.js:86](../server/src/modules/bulk_import_routes.js#L86) |
| Zaten bu dairenin aktif bir sakinisisiniz (${existingMemberRes.rows[0].role}). | [server/src/services/membership_service.js:1026](../server/src/services/membership_service.js#L1026) |

## Uygulama (Flutter) mesajları (528)

Kaynak: `lib` (`ApiException(...)`, `_errorMessage =`, `lib/services` içindeki `return '...'`).

| Mesaj | Dosya:satır |
| --- | --- |
| "$label" alanı geçersiz. Kontrol edip tekrar deneyin. | [lib/services/contract_api.dart:447](../lib/services/contract_api.dart#L447) |
| <c r="$ref" s="${_Styles.date}"><v>$serial</v></c> | [lib/services/bulk_xlsx_writer.dart:321](../lib/services/bulk_xlsx_writer.dart#L321) |
| <c r="$ref" s="${_Styles.money}"><v>$text</v></c> | [lib/services/bulk_xlsx_writer.dart:316](../lib/services/bulk_xlsx_writer.dart#L316) |
| <c r="$ref" t="inlineStr"$styleAttr><is><t xml:space="preserve">${escapeXml(text)}</t></is></c> | [lib/services/bulk_xlsx_writer.dart:307](../lib/services/bulk_xlsx_writer.dart#L307) |
| <c r="$ref"$styleAttr><v>$text</v></c> | [lib/services/bulk_xlsx_writer.dart:334](../lib/services/bulk_xlsx_writer.dart#L334) |
| ${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8)} | [lib/services/pdf_finance_service.dart:232](../lib/services/pdf_finance_service.dart#L232) |
| ${e.message} Kod 30 dakika geçerlidir; yeni kod için "Kodu Tekrar Gönder"e dokunun. | [lib/services/auth_service.dart:535](../lib/services/auth_service.dart#L535) |
| ${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)} | [lib/services/crash_reporter.dart:617](../lib/services/crash_reporter.dart#L617) |
| ${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)} | [lib/services/push_store.dart:240](../lib/services/push_store.dart#L240) |
| $distance m uzaktasınız, izin verilen mesafe $allowed m. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:3958](../lib/services/auth_api.dart#L3958) |
| $label verisi beklenen formatta degil. | [lib/services/auth_api.dart:4215](../lib/services/auth_api.dart#L4215) |
| $label verisi islenemedi. | [lib/services/auth_api.dart:4213](../lib/services/auth_api.dart#L4213) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/account_api.dart:414](../lib/services/account_api.dart#L414) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/bulk_api.dart:451](../lib/services/bulk_api.dart#L451) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/contract_api.dart:467](../lib/services/contract_api.dart#L467) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/decision_book_api.dart:364](../lib/services/decision_book_api.dart#L364) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/document_api.dart:968](../lib/services/document_api.dart#L968) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/finance_4b_api.dart:1497](../lib/services/finance_4b_api.dart#L1497) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/platform_rules_api.dart:212](../lib/services/platform_rules_api.dart#L212) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/push_api.dart:321](../lib/services/push_api.dart#L321) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/reservation_api.dart:734](../lib/services/reservation_api.dart#L734) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/survey_api.dart:376](../lib/services/survey_api.dart#L376) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/visitor_log_api.dart:395](../lib/services/visitor_log_api.dart#L395) |
| $trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:945](../lib/services/work_tracking_api.dart#L945) |
| $trimmed Lütfen ${formatWait(retryAfter)} sonra tekrar deneyin. | [lib/services/auth_api.dart:3801](../lib/services/auth_api.dart#L3801) |
| $what bilgisi işlenemedi. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1307](../lib/services/finance_4b_api.dart#L1307) |
| $what bilgisi işlenemedi. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1309](../lib/services/finance_4b_api.dart#L1309) |
| $year-${yymmdd.substring(2, 4)}-${yymmdd.substring(4, 6)} | [lib/services/mt940_parser.dart:54](../lib/services/mt940_parser.dart#L54) |
| Aidat tanımı bulunamadı. | [lib/services/auth_api.dart:4124](../lib/services/auth_api.dart#L4124) |
| Aidat ve Finans özelliği bu sitede kapalı. | [lib/services/bank_import_api.dart:38](../lib/services/bank_import_api.dart#L38) |
| Aidat ve Finans özelliği bu sitede kapalı. | [lib/services/finance_payment_api.dart:141](../lib/services/finance_payment_api.dart#L141) |
| Aidat ve Finans özelliği bu sitede kapalı. | [lib/services/payment_notice_api.dart:205](../lib/services/payment_notice_api.dart#L205) |
| Aktarım bulunamadı. | [lib/services/finance_4b_errors.dart:60](../lib/services/finance_4b_errors.dart#L60) |
| Alan bulunamadı ya da artık kullanılamıyor. Listeyi yenileyin. | [lib/services/reservation_api.dart:641](../lib/services/reservation_api.dart#L641) |
| Anket bu durumda bu işleme izin vermiyor. Başkası güncellemiş olabilir; yenileyip tekrar deneyin. | [lib/services/survey_api.dart:351](../lib/services/survey_api.dart#L351) |
| Anket bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/survey_api.dart:349](../lib/services/survey_api.dart#L349) |
| Anket ve Oylama bu site için kapalı. | [lib/services/survey_api.dart:341](../lib/services/survey_api.dart#L341) |
| Anlaşılamadı. Lütfen örneğin "1. kapıyı aç" veya "otopark kapısını aç" deyin. | [lib/services/voice_door_service.dart:508](../lib/services/voice_door_service.dart#L508) |
| Anlık görüntü adresi boşluk içeremez. | [lib/services/cctv_api.dart:197](../lib/services/cctv_api.dart#L197) |
| Anlık görüntü adresi https:// ile başlamalı. | [lib/services/cctv_api.dart:196](../lib/services/cctv_api.dart#L196) |
| Anlık konum alınamadı. Lütfen GPS'i kontrol edip tekrar deneyin. | [lib/services/geofence_service.dart:134](../lib/services/geofence_service.dart#L134) |
| Araç bulunamadı. | [lib/services/auth_api.dart:3833](../lib/services/auth_api.dart#L3833) |
| Ayarlar başka biri tarafından değiştirilmiş. Güncel ayarlar yüklendi; kontrol edip yeniden kaydedin. | [lib/services/finance_4b_errors.dart:130](../lib/services/finance_4b_errors.dart#L130) |
| Ayarlar siz bakarken değişti. Ekranı yenileyip tekrar deneyin. | [lib/services/finance_payment_api.dart:137](../lib/services/finance_payment_api.dart#L137) |
| Aynı duyuru az önce yayınlandı. Çift gönderimi önlemek için bir dakika bekleyin. | [lib/services/auth_api.dart:3845](../lib/services/auth_api.dart#L3845) |
| Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Önce daire hesaplarını kontrol edin. | [lib/services/auth_api.dart:4114](../lib/services/auth_api.dart#L4114) |
| Aynı gider kısa süre önce kaydedilmiş görünüyor. Önce gider listesini kontrol edin. | [lib/services/finance_4b_errors.dart:76](../lib/services/finance_4b_errors.dart#L76) |
| Aynı tutar ve tarihte başka bir banka satırının tahsilatı var; çift tahsilat olmasın diye kontrol edin. | [lib/services/bank_import_api.dart:30](../lib/services/bank_import_api.dart#L30) |
| Bağlantı hatası: $e | [lib/ui/widgets/door_logs_accordion.dart:113](../lib/ui/widgets/door_logs_accordion.dart#L113) |
| Başlangıç zamanı geçmiş rezervasyon onaylanamaz. | [lib/services/reservation_api.dart:702](../lib/services/reservation_api.dart#L702) |
| Başvuran hesap silinmiş, pasif, e-postası doğrulanmamış ya da onaysız olabilir; başvuru onaylanamaz. | [lib/services/auth_api.dart:4085](../lib/services/auth_api.dart#L4085) |
| Başvuru bulunamadı. | [lib/services/auth_api.dart:4078](../lib/services/auth_api.dart#L4078) |
| Başvuru durumu yanıtı anlaşılamadı. Tekrar deneyin. | [lib/services/auth_api.dart:1432](../lib/services/auth_api.dart#L1432) |
| Başvurudaki yapı verisi geçersiz; onaylanamaz. Reddedip başvuranın yeniden başvurmasını isteyin. | [lib/services/auth_api.dart:4083](../lib/services/auth_api.dart#L4083) |
| Bazı dairelerin bilgisi eksik. Eksikleri tamamlayın ya da bu daireleri atlayarak devam edin. | [lib/services/auth_api.dart:4096](../lib/services/auth_api.dart#L4096) |
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
| Bilinmeyen yer tutucu: ${unknown.first}. | [lib/services/cctv_api.dart:188](../lib/services/cctv_api.dart#L188) |
| Bir gidere en çok 5 belge eklenebilir. | [lib/services/finance_4b_errors.dart:88](../lib/services/finance_4b_errors.dart#L88) |
| Bir seferde en çok 5.000 satır yüklenebilir. | [lib/services/bulk_api.dart:31](../lib/services/bulk_api.dart#L31) |
| Birden çok benzer tahsilat var. "Mevcut tahsilata bağla" ile birini seçin. | [lib/services/bank_import_api.dart:32](../lib/services/bank_import_api.dart#L32) |
| Bluetooth islemi basarisiz oldu. | [lib/services/ble_wifi_provision_service.dart:534](../lib/services/ble_wifi_provision_service.dart#L534) |
| Borç hatırlatma bu site için kapalı. Ayarlar bölümünden açın. | [lib/services/finance_4b_errors.dart:117](../lib/services/finance_4b_errors.dart#L117) |
| Borçlandırılacak daire bulunamadı. Hedefi ve daire bilgilerini kontrol edin. | [lib/services/auth_api.dart:4110](../lib/services/auth_api.dart#L4110) |
| Borçlandırılmış tanımın tutarı ve dağıtımı değiştirilemez. Yeni bir tanım ekleyin. | [lib/services/auth_api.dart:4106](../lib/services/auth_api.dart#L4106) |
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
| Bu ay kapatılamaz: zaten kapalı, gelecekte ya da 5 yıldan eski. Listeden bir ay seçin. | [lib/services/auth_api.dart:4102](../lib/services/auth_api.dart#L4102) |
| Bu ay yeniden açılamaz: sonraki aylar için tazminat çalıştırması var. Önce çalıştırmayı iptal edin. | [lib/services/finance_4b_errors.dart:43](../lib/services/finance_4b_errors.dart#L43) |
| Bu ay yeniden açılamaz. Yalnızca en son kapatılan ay açılabilir. | [lib/services/auth_api.dart:4104](../lib/services/auth_api.dart#L4104) |
| Bu başvuru artık bekleyen durumda değil. | [lib/services/auth_api.dart:4080](../lib/services/auth_api.dart#L4080) |
| Bu belge duyuruya eklenemez. Yalnız sakinlere açık, yayındaki belgeler eklenebilir. | [lib/services/document_api.dart:942](../lib/services/document_api.dart#L942) |
| Bu belge yayındaki bir duyuruya ekli. | [lib/services/document_api.dart:938](../lib/services/document_api.dart#L938) |
| Bu belgenin sürüm sınırına ulaşıldı. Eski sürümleri silin. | [lib/services/document_api.dart:932](../lib/services/document_api.dart#L932) |
| Bu cihaz arızalı olarak işaretlenmiş. | [lib/services/auth_api.dart:4004](../lib/services/auth_api.dart#L4004) |
| Bu cihaz başka bir hesaba ait. | [lib/services/auth_api.dart:4002](../lib/services/auth_api.dart#L4002) |
| Bu cihaz bu kapıya atanamaz. | [lib/services/auth_api.dart:4000](../lib/services/auth_api.dart#L4000) |
| Bu çalıştırma iptal edilemiyor: yalnızca son (aktif) tazminat çalıştırması iptal edilir; başka bir yönetici zaten iptal etmiş olabilir. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:41](../lib/services/finance_4b_errors.dart#L41) |
| Bu dairede bu ilişki için aktif bir kişi zaten var. | [lib/services/auth_api.dart:4049](../lib/services/auth_api.dart#L4049) |
| Bu devir yüklemesi zaten geri alınmış. | [lib/services/bulk_api.dart:56](../lib/services/bulk_api.dart#L56) |
| Bu dosya bu hesaba daha önce yüklenmiş. | [lib/services/bank_import_api.dart:20](../lib/services/bank_import_api.dart#L20) |
| Bu dosya türü desteklenmiyor. ${DocumentFileRules.allowedLabel} yükleyin. | [lib/services/document_api.dart:912](../lib/services/document_api.dart#L912) |
| Bu dosya türü kabul edilmiyor. Yalnızca PDF, JPG ve PNG eklenebilir. | [lib/services/finance_4b_errors.dart:95](../lib/services/finance_4b_errors.dart#L95) |
| Bu dönem kapatılmış; kapalı döneme kayıt eklenemez. Kapalı ayı yalnızca süper kullanıcı yeniden açabilir. | [lib/services/auth_api.dart:4100](../lib/services/auth_api.dart#L4100) |
| Bu e-posta ile kayıtlı bir kişi zaten var. | [lib/services/auth_api.dart:4045](../lib/services/auth_api.dart#L4045) |
| Bu e-posta ile kayıtlı hesap yok. | [lib/services/auth_api.dart:4023](../lib/services/auth_api.dart#L4023) |
| Bu fotoğrafı yalnız ekleyen kişi ya da yönetici silebilir. | [lib/services/work_tracking_api.dart:929](../lib/services/work_tracking_api.dart#L929) |
| Bu fotoğrafın yüklemesi zaten sürüyor. Biraz sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:899](../lib/services/work_tracking_api.dart#L899) |
| Bu gider kategorisi pasif. Başka bir kategori seçin. | [lib/services/finance_4b_errors.dart:82](../lib/services/finance_4b_errors.dart#L82) |
| Bu gider zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:74](../lib/services/finance_4b_errors.dart#L74) |
| Bu hatırlatma çalıştırması iptal edilemez (zaten iptal edilmiş). | [lib/services/finance_4b_errors.dart:127](../lib/services/finance_4b_errors.dart#L127) |
| Bu hesap henüz etkin değil. | [lib/services/auth_api.dart:4025](../lib/services/auth_api.dart#L4025) |
| Bu hesap pasif; pasif hesaba yeni hareket yazılamaz. | [lib/services/finance_4b_errors.dart:50](../lib/services/finance_4b_errors.dart#L50) |
| Bu ilişki artık güncel değil. | [lib/services/auth_api.dart:3837](../lib/services/auth_api.dart#L3837) |
| Bu isimde bir kapı bulunamadı. Lütfen kapının adını veya numarasını söyleyin. | [lib/services/voice_door_service.dart:503](../lib/services/voice_door_service.dart#L503) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:2607](../lib/services/auth_service.dart#L2607) |
| Bu islem icin site yonetim yetkisi gerekir. | [lib/services/auth_service.dart:3478](../lib/services/auth_service.dart#L3478) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:885](../lib/services/auth_service.dart#L885) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:919](../lib/services/auth_service.dart#L919) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:949](../lib/services/auth_service.dart#L949) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:970](../lib/services/auth_service.dart#L970) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:1057](../lib/services/auth_service.dart#L1057) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:1091](../lib/services/auth_service.dart#L1091) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:2818](../lib/services/auth_service.dart#L2818) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:3269](../lib/services/auth_service.dart#L3269) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:3293](../lib/services/auth_service.dart#L3293) |
| Bu islem icin super user yetkisi gerekir. | [lib/services/auth_service.dart:3459](../lib/services/auth_service.dart#L3459) |
| Bu islem icin yetkiniz bulunmamaktadir. | [lib/services/auth_service.dart:1128](../lib/services/auth_service.dart#L1128) |
| Bu işlem daha önce başka bilgilerle gönderilmiş. Lütfen bilgileri kontrol edip tekrar deneyin. | [lib/services/reservation_api.dart:715](../lib/services/reservation_api.dart#L715) |
| Bu işlem daha önce farklı bilgilerle gönderilmiş görünüyor. Önce daire hesaplarını kontrol edin. | [lib/services/auth_api.dart:4112](../lib/services/auth_api.dart#L4112) |
| Bu işlem için yetkiniz yok. | [lib/services/auth_api.dart:4057](../lib/services/auth_api.dart#L4057) |
| Bu işlem için yetkiniz yok. | [lib/services/cctv_api.dart:287](../lib/services/cctv_api.dart#L287) |
| Bu işlem için yetkiniz yok. | [lib/services/decision_book_api.dart:331](../lib/services/decision_book_api.dart#L331) |
| Bu işlem için yetkiniz yok. | [lib/services/device_integrations_api.dart:239](../lib/services/device_integrations_api.dart#L239) |
| Bu işlem için yetkiniz yok. | [lib/services/equipment_api.dart:377](../lib/services/equipment_api.dart#L377) |
| Bu işlem için yetkiniz yok. | [lib/services/plate_recognition_api.dart:426](../lib/services/plate_recognition_api.dart#L426) |
| Bu işlem için yetkiniz yok. | [lib/services/reservation_api.dart:633](../lib/services/reservation_api.dart#L633) |
| Bu işlem için yetkiniz yok. | [lib/services/survey_api.dart:343](../lib/services/survey_api.dart#L343) |
| Bu işlem için yetkiniz yok. | [lib/services/visitor_log_api.dart:363](../lib/services/visitor_log_api.dart#L363) |
| Bu işlem için yetkiniz yok. | [lib/services/work_tracking_api.dart:820](../lib/services/work_tracking_api.dart#L820) |
| Bu işlem için yetkiniz yok. Sözleşmeleri yalnızca site yöneticisi düzenleyebilir. | [lib/services/contract_api.dart:414](../lib/services/contract_api.dart#L414) |
| Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin. | [lib/services/auth_api.dart:3945](../lib/services/auth_api.dart#L3945) |
| Bu kapıda dinamik karekod geçerlidir. Lütfen kapı ekranındaki güncel karekodu okutun. | [lib/services/auth_api.dart:3978](../lib/services/auth_api.dart#L3978) |
| Bu kapıda QR ile giriş şu an devre dışı. | [lib/services/auth_api.dart:3970](../lib/services/auth_api.dart#L3970) |
| Bu kapıyı açma yetkiniz yok. | [lib/services/auth_api.dart:3994](../lib/services/auth_api.dart#L3994) |
| Bu karar kesinleşmiş; değiştirilemez ya da silinemez. Düzeltme gerekirse yeni bir karar yazın. | [lib/services/decision_book_api.dart:339](../lib/services/decision_book_api.dart#L339) |
| Bu karekod daha önce kullanıldı. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:3980](../lib/services/auth_api.dart#L3980) |
| Bu kayıt iptal ya da düzeltme için uygun değil. Ters kayıtlar iptal edilemez. | [lib/services/auth_api.dart:4120](../lib/services/auth_api.dart#L4120) |
| Bu kayıt zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/auth_api.dart:4118](../lib/services/auth_api.dart#L4118) |
| Bu kişi zaten site yöneticisi. | [lib/services/auth_api.dart:4027](../lib/services/auth_api.dart#L4027) |
| Bu kişide kurul veya görevli rolü yok. | [lib/services/auth_api.dart:4031](../lib/services/auth_api.dart#L4031) |
| Bu makbuz iptal edilemez. İptal makbuzları iptal edilemez. | [lib/services/finance_4b_errors.dart:24](../lib/services/finance_4b_errors.dart#L24) |
| Bu makbuz zaten iptal edilmiş. Listeyi yenileyip kontrol edin. | [lib/services/finance_4b_errors.dart:22](../lib/services/finance_4b_errors.dart#L22) |
| Bu modül bu site için kapalı. | [lib/services/cctv_api.dart:285](../lib/services/cctv_api.dart#L285) |
| Bu modül bu site için kapalı. | [lib/services/device_integrations_api.dart:237](../lib/services/device_integrations_api.dart#L237) |
| Bu modül bu site için kapalı. | [lib/services/equipment_api.dart:375](../lib/services/equipment_api.dart#L375) |
| Bu modül için bekleyen bir talebiniz var. | [lib/services/auth_api.dart:4038](../lib/services/auth_api.dart#L4038) |
| Bu modül kapatılamaz. | [lib/services/auth_api.dart:4015](../lib/services/auth_api.dart#L4015) |
| Bu modül yakında. | [lib/services/auth_api.dart:4013](../lib/services/auth_api.dart#L4013) |
| Bu modül zaten açık. | [lib/services/auth_api.dart:4036](../lib/services/auth_api.dart#L4036) |
| Bu ödeme iptal edilmiş; iptal edilmiş ödeme için makbuz düzenlenemez. | [lib/services/finance_4b_errors.dart:20](../lib/services/finance_4b_errors.dart#L20) |
| Bu önek başka bir sitede kullanılıyor. Başka bir önek seçin. | [lib/services/finance_payment_api.dart:135](../lib/services/finance_payment_api.dart#L135) |
| Bu özellik hukuki onay bekliyor; onaylanınca kullanılabilir. | [lib/services/finance_4b_errors.dart:132](../lib/services/finance_4b_errors.dart#L132) |
| Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir. | [lib/services/auth_api.dart:4011](../lib/services/auth_api.dart#L4011) |
| Bu PDF kabul edilemedi. Dekontun ekran görüntüsünü yüklemeyi deneyin. | [lib/services/payment_notice_api.dart:203](../lib/services/payment_notice_api.dart#L203) |
| Bu PDF taranmış bir resim; metni okunamıyor. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin. | [lib/services/bank_import_api.dart:42](../lib/services/bank_import_api.dart#L42) |
| Bu plaka bu sitede zaten kayıtlı. | [lib/services/auth_api.dart:4055](../lib/services/auth_api.dart#L4055) |
| Bu platform MQTT TCP baglantisini desteklemiyor. | [lib/services/mqtt_door_service_stub.dart:41](../lib/services/mqtt_door_service_stub.dart#L41) |
| Bu satır artık işlenmeyi beklemiyor. Listeyi yenileyin. | [lib/services/bank_import_api.dart:24](../lib/services/bank_import_api.dart#L24) |
| Bu site için başka bir yükleme sürüyor. | [lib/services/bulk_api.dart:35](../lib/services/bulk_api.dart#L35) |
| Bu site için günlük duyuru sınırına ulaşıldı. Yarın tekrar deneyin. | [lib/services/auth_api.dart:3847](../lib/services/auth_api.dart#L3847) |
| Bu site için yetkiniz yok. | [lib/services/bulk_api.dart:52](../lib/services/bulk_api.dart#L52) |
| Bu sitede aynı adlı bir alan zaten var. Başka bir ad seçin. | [lib/services/reservation_api.dart:656](../lib/services/reservation_api.dart#L656) |
| Bu sitede dekont bildirimi henüz açık değil. Yönetime sorun. | [lib/services/payment_notice_api.dart:193](../lib/services/payment_notice_api.dart#L193) |
| Bu sitede kasa ya da banka hesabı tanımlı; tahsilat için bir hesap seçin. | [lib/services/finance_4b_errors.dart:52](../lib/services/finance_4b_errors.dart#L52) |
| Bu sitede misafir geçişi kapalı. | [lib/services/auth_api.dart:3972](../lib/services/auth_api.dart#L3972) |
| Bu sitede QR ile giriş kapalı. | [lib/services/auth_api.dart:3968](../lib/services/auth_api.dart#L3968) |
| Bu sitede talep açabilmek için daire sakini olmalısınız. | [lib/services/work_tracking_api.dart:824](../lib/services/work_tracking_api.dart#L824) |
| Bu sitede uygulamadan uzaktan kapı açma kapalı. | [lib/services/auth_api.dart:3966](../lib/services/auth_api.dart#L3966) |
| Bu sitede yerel ağdan kapı açma kapalı. | [lib/services/auth_api.dart:3974](../lib/services/auth_api.dart#L3974) |
| Bu sitenin konum çemberi hatalı tanımlanmış. Lütfen site yöneticinize başvurun. | [lib/services/auth_api.dart:3962](../lib/services/auth_api.dart#L3962) |
| Bu sitenin kurallarını görme yetkiniz yok. | [lib/services/platform_rules_api.dart:186](../lib/services/platform_rules_api.dart#L186) |
| Bu siteye erişim yetkiniz yok. | [lib/services/cctv_api.dart:289](../lib/services/cctv_api.dart#L289) |
| Bu siteye erişim yetkiniz yok. | [lib/services/contract_api.dart:416](../lib/services/contract_api.dart#L416) |
| Bu siteye erişim yetkiniz yok. | [lib/services/decision_book_api.dart:333](../lib/services/decision_book_api.dart#L333) |
| Bu siteye erişim yetkiniz yok. | [lib/services/device_integrations_api.dart:241](../lib/services/device_integrations_api.dart#L241) |
| Bu siteye erişim yetkiniz yok. | [lib/services/equipment_api.dart:379](../lib/services/equipment_api.dart#L379) |
| Bu siteye erişim yetkiniz yok. | [lib/services/plate_recognition_api.dart:428](../lib/services/plate_recognition_api.dart#L428) |
| Bu siteye erişim yetkiniz yok. | [lib/services/reservation_api.dart:635](../lib/services/reservation_api.dart#L635) |
| Bu siteye erişim yetkiniz yok. | [lib/services/survey_api.dart:345](../lib/services/survey_api.dart#L345) |
| Bu siteye erişim yetkiniz yok. | [lib/services/visitor_log_api.dart:365](../lib/services/visitor_log_api.dart#L365) |
| Bu siteye erişim yetkiniz yok. | [lib/services/work_tracking_api.dart:822](../lib/services/work_tracking_api.dart#L822) |
| Bu tahsilat bağlanamaz (tutar uyuşmuyor, iptal edilmiş ya da başka satıra bağlı). | [lib/services/bank_import_api.dart:34](../lib/services/bank_import_api.dart#L34) |
| Bu talebe daha fazla yorum eklenemez. | [lib/services/work_tracking_api.dart:847](../lib/services/work_tracking_api.dart#L847) |
| Bu talep artık bekleyen durumda değil. | [lib/services/auth_api.dart:4042](../lib/services/auth_api.dart#L4042) |
| Bu talep kapandığı ya da iptal edildiği için değiştirilemez. | [lib/services/work_tracking_api.dart:843](../lib/services/work_tracking_api.dart#L843) |
| Bu tanım bu dönem için zaten borçlandırılmış. Aynı ay ikinci kez borçlandırılamaz. | [lib/services/auth_api.dart:4098](../lib/services/auth_api.dart#L4098) |
| Bu tanım pasif ya da bu dönemde geçerli değil. Tanımı etkinleştirin veya dönemi kontrol edin. | [lib/services/auth_api.dart:4116](../lib/services/auth_api.dart#L4116) |
| Bu tarihin dönemi kapatılmış. Önce dönemi açın. | [lib/services/bank_import_api.dart:36](../lib/services/bank_import_api.dart#L36) |
| Bu tedarikçiden aynı belge numarasıyla iptal edilmemiş bir gider zaten var. | [lib/services/finance_4b_errors.dart:78](../lib/services/finance_4b_errors.dart#L78) |
| Bu yönetim türü yakında. | [lib/services/auth_api.dart:4019](../lib/services/auth_api.dart#L4019) |
| Bu yükleme farklı bilgilerle daha önce gönderilmiş. Dosyayı yeniden seçin. | [lib/services/bank_import_api.dart:40](../lib/services/bank_import_api.dart#L40) |
| Bu yükleme farklı bilgilerle daha önce gönderilmiş. Dosyayı yeniden seçip yükleyin. | [lib/services/bulk_api.dart:50](../lib/services/bulk_api.dart#L50) |
| Bu yükleme türü bulunamadı. | [lib/services/bulk_api.dart:47](../lib/services/bulk_api.dart#L47) |
| Bu yükleme zaten geri alınmış. | [lib/services/bank_import_api.dart:28](../lib/services/bank_import_api.dart#L28) |
| Bu yükleme zaten tamamlanmış. | [lib/services/document_api.dart:944](../lib/services/document_api.dart#L944) |
| Bugün zaten bir hatırlatma gönderildi. Günde en çok bir çalıştırma yapılabilir. | [lib/services/finance_4b_errors.dart:119](../lib/services/finance_4b_errors.dart#L119) |
| Cihaz bulunamadı. | [lib/services/auth_api.dart:4006](../lib/services/auth_api.dart#L4006) |
| Cihaz bulunamadı. Listeyi yenileyip tekrar deneyin. | [lib/services/push_api.dart:304](../lib/services/push_api.dart#L304) |
| Cihaz sahiplenme sırasında bir hata oluştu. | [lib/ui/widgets/claim_device_dialog.dart:83](../lib/ui/widgets/claim_device_dialog.dart#L83) |
| Cihaz şu an çevrimdışı. Cihazın internet bağlantısını kontrol edin. | [lib/services/auth_api.dart:3998](../lib/services/auth_api.dart#L3998) |
| Cihazlar yüklenirken bir sorun oluştu. | [lib/ui/views/individual_home_view.dart:208](../lib/ui/views/individual_home_view.dart#L208) |
| Çok fazla bekleyen bildiriminiz var. Yönetim karar verdikten sonra yenisini gönderin. | [lib/services/payment_notice_api.dart:195](../lib/services/payment_notice_api.dart#L195) |
| Çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:3938](../lib/services/auth_api.dart#L3938) |
| Çok fazla istek gönderildi. | [lib/services/auth_api.dart:3822](../lib/services/auth_api.dart#L3822) |
| Çok fazla kayıt var. Süzgeçle daraltın. | [lib/services/bulk_api.dart:43](../lib/services/bulk_api.dart#L43) |
| Daire bulunamadı. | [lib/services/auth_api.dart:4051](../lib/services/auth_api.dart#L4051) |
| Dekontun tarihi kapalı bir döneme düşüyor. "Açık döneme yaz" seçeneğiyle bugünün tarihine işleyebilirsiniz. | [lib/services/payment_notice_api.dart:199](../lib/services/payment_notice_api.dart#L199) |
| Devam etmek için onay kutusunu işaretleyin. | [lib/services/bulk_api.dart:41](../lib/services/bulk_api.dart#L41) |
| Devam etmek için şifrenizi girin. | [lib/services/account_api.dart:392](../lib/services/account_api.dart#L392) |
| Devir kayıtları değişti. Ayrıntıyı yenileyip tekrar inceleyin. | [lib/services/bulk_api.dart:58](../lib/services/bulk_api.dart#L58) |
| Devir yüklemesi bulunamadı. | [lib/services/bulk_api.dart:60](../lib/services/bulk_api.dart#L60) |
| Dışa aktarılacak veri çok büyük (en çok 20.000 satır). Süzgeçlerle daraltın. | [lib/services/finance_4b_errors.dart:114](../lib/services/finance_4b_errors.dart#L114) |
| Doğrulama işlemi sırasında hata oluştu. | [lib/services/auth_service.dart:539](../lib/services/auth_service.dart#L539) |
| Dosya boyutu yükleme sırasında değişti. Dosyayı yeniden seçip tekrar deneyin. | [lib/services/document_api.dart:924](../lib/services/document_api.dart#L924) |
| Dosya çok büyük (en fazla 10 MB). | [lib/services/payment_notice_api.dart:173](../lib/services/payment_notice_api.dart#L173) |
| Dosya çok büyük. | [lib/services/finance_4b_api.dart:1391](../lib/services/finance_4b_api.dart#L1391) |
| Dosya çok büyük. | [lib/services/finance_4b_api.dart:1398](../lib/services/finance_4b_api.dart#L1398) |
| Dosya çok büyük. Daha küçük bir dosya seçin. | [lib/services/finance_4b_errors.dart:92](../lib/services/finance_4b_errors.dart#L92) |
| Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk. | [lib/services/document_api.dart:914](../lib/services/document_api.dart#L914) |
| Dosya indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/payment_notice_api.dart:161](../lib/services/payment_notice_api.dart#L161) |
| Dosya taraması şu an yapılamıyor. Biraz sonra tekrar deneyin. | [lib/services/document_api.dart:920](../lib/services/document_api.dart#L920) |
| Dosya zararlı yazılım içerdiği için reddedildi. | [lib/services/document_api.dart:918](../lib/services/document_api.dart#L918) |
| Dosyada çalıştırılabilir içerik bulundu; güvenlik nedeniyle kabul edilmedi. | [lib/services/finance_4b_errors.dart:97](../lib/services/finance_4b_errors.dart#L97) |
| Duyuru bulunamadı ya da artık yayında değil. | [lib/services/auth_api.dart:4060](../lib/services/auth_api.dart#L4060) |
| Duyurunun durumu değişmiş. Listeyi yenileyip tekrar deneyin. | [lib/services/auth_api.dart:4062](../lib/services/auth_api.dart#L4062) |
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
| Geçersiz kapı bilgisi. | [lib/services/auth_api.dart:3990](../lib/services/auth_api.dart#L3990) |
| Geçersiz sorgu. Süzgeçleri kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3827](../lib/services/auth_api.dart#L3827) |
| Geçersiz yönetim türü. | [lib/services/auth_api.dart:4021](../lib/services/auth_api.dart#L4021) |
| Gelir/gider olarak ayrılmış satırlar var. Önce onları tek tek geri alın. | [lib/services/bank_import_api.dart:26](../lib/services/bank_import_api.dart#L26) |
| Gider bulunamadı. | [lib/services/finance_4b_errors.dart:72](../lib/services/finance_4b_errors.dart#L72) |
| Gider kategorisi bulunamadı. | [lib/services/finance_4b_errors.dart:80](../lib/services/finance_4b_errors.dart#L80) |
| Gider kaydı için bir kasa ya da banka hesabı gerekir. Önce Kasa bölümünden hesap ekleyin. | [lib/services/finance_4b_errors.dart:46](../lib/services/finance_4b_errors.dart#L46) |
| Girilen bilgiler geçersiz. | [lib/services/device_integrations_api.dart:244](../lib/services/device_integrations_api.dart#L244) |
| Girilen bilgilerden biri geçersiz. Alanları kontrol edip tekrar deneyin. | [lib/services/contract_api.dart:445](../lib/services/contract_api.dart#L445) |
| Giriş oturumu bulunamadı. | [lib/ui/widgets/door_logs_accordion.dart:76](../lib/ui/widgets/door_logs_accordion.dart#L76) |
| Gönderilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3825](../lib/services/auth_api.dart#L3825) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/contract_api.dart:454](../lib/services/contract_api.dart#L454) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/decision_book_api.dart:355](../lib/services/decision_book_api.dart#L355) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/reservation_api.dart:721](../lib/services/reservation_api.dart#L721) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/survey_api.dart:367](../lib/services/survey_api.dart#L367) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/visitor_log_api.dart:382](../lib/services/visitor_log_api.dart#L382) |
| Gönderilen içerik çok büyük. Metni kısaltın. | [lib/services/work_tracking_api.dart:853](../lib/services/work_tracking_api.dart#L853) |
| GPS doğruluğu yetersiz. Açık alana çıkıp tekrar deneyin. | [lib/services/auth_api.dart:3953](../lib/services/auth_api.dart#L3953) |
| GPS doğruluğu yetersiz$acc. Lütfen açık alana çıkıp tekrar deneyin. | [lib/services/geofence_service.dart:86](../lib/services/geofence_service.dart#L86) |
| GPS sinyali alınamadı (zaman aşımı). Açık alanda tekrar deneyin. | [lib/services/geofence_service.dart:126](../lib/services/geofence_service.dart#L126) |
| Hangi kapıyı açmamı istersiniz?$suffix Örneğin "1. kapıyı aç" veya kapının adını söyleyin. | [lib/services/voice_door_service.dart:501](../lib/services/voice_door_service.dart#L501) |
| Hata: $e | [lib/ui/widgets/device_connectivity_logs_accordion.dart:103](../lib/ui/widgets/device_connectivity_logs_accordion.dart#L103) |
| Hatalı satırlar var. Düzeltip yeniden yükleyin. | [lib/services/bulk_api.dart:29](../lib/services/bulk_api.dart#L29) |
| Hatırlatma çalıştırması bulunamadı. | [lib/services/finance_4b_errors.dart:125](../lib/services/finance_4b_errors.dart#L125) |
| Hatırlatma gönderilecek kimse bulunamadı. | [lib/services/finance_4b_errors.dart:121](../lib/services/finance_4b_errors.dart#L121) |
| Hedef geçersiz. Seçilen blok ve daireleri kontrol edin. | [lib/services/document_api.dart:940](../lib/services/document_api.dart#L940) |
| Henüz kapatılmış ay yok. | [lib/services/pdf_finance_service.dart:502](../lib/services/pdf_finance_service.dart#L502) |
| Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir. | [lib/services/auth_api.dart:4047](../lib/services/auth_api.dart#L4047) |
| Hesabınız şu anda silinemez. Nedenleri aşağıda görebilirsiniz. | [lib/services/account_api.dart:400](../lib/services/account_api.dart#L400) |
| Hesap bakiyesi siz bakarken değişti. Güncel bakiyeyi kontrol edip yeniden onaylayın. | [lib/services/finance_4b_errors.dart:64](../lib/services/finance_4b_errors.dart#L64) |
| Hesap bulunamadı. | [lib/services/finance_4b_errors.dart:48](../lib/services/finance_4b_errors.dart#L48) |
| Hesap bulunamadı. | [lib/services/finance_payment_api.dart:139](../lib/services/finance_payment_api.dart#L139) |
| IBAN geçersiz. TR ile başlayan 26 haneli, sağlama basamağı doğru bir IBAN girin. | [lib/services/finance_payment_api.dart:133](../lib/services/finance_payment_api.dart#L133) |
| İkili Excel biçimi (.xlsb) desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin. | [lib/services/bulk_file_parser.dart:88](../lib/services/bulk_file_parser.dart#L88) |
| İlişki kaydı bulunamadı. | [lib/services/auth_api.dart:3835](../lib/services/auth_api.dart#L3835) |
| İş takibi bu site için kapalı. | [lib/services/work_tracking_api.dart:818](../lib/services/work_tracking_api.dart#L818) |
| İşlem başarısız ($status) | [lib/services/cctv_api.dart:301](../lib/services/cctv_api.dart#L301) |
| İşlem başarısız ($status) | [lib/services/device_integrations_api.dart:249](../lib/services/device_integrations_api.dart#L249) |
| İşlem başarısız ($status) | [lib/services/equipment_api.dart:391](../lib/services/equipment_api.dart#L391) |
| İşlem başarısız ($status) | [lib/services/plate_recognition_api.dart:434](../lib/services/plate_recognition_api.dart#L434) |
| İşlem başarısız ($status). | [lib/services/legal_api.dart:230](../lib/services/legal_api.dart#L230) |
| İşlem sırasında bir hata oluştu: $e | [lib/ui/dialogs/door_edit_dialog.dart:123](../lib/ui/dialogs/door_edit_dialog.dart#L123) |
| Kapalı aylar: ${through.label} ve öncesi. | [lib/services/pdf_finance_service.dart:503](../lib/services/pdf_finance_service.dart#L503) |
| Kapı bulunamadı. | [lib/services/auth_api.dart:3992](../lib/services/auth_api.dart#L3992) |
| Kapı ekranındaki karekod henüz alınamadı. Birkaç saniye sonra tekrar deneyin. | [lib/services/auth_api.dart:3984](../lib/services/auth_api.dart#L3984) |
| Kapı konumunda değilsiniz. Lütfen kapıya yaklaşın. | [lib/services/auth_api.dart:3960](../lib/services/auth_api.dart#L3960) |
| Kapıyı kapatma veya kilitleme komutu desteklenmiyor. Açmak için "kapıyı aç" deyin. | [lib/services/voice_door_service.dart:493](../lib/services/voice_door_service.dart#L493) |
| Karar bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/decision_book_api.dart:337](../lib/services/decision_book_api.dart#L337) |
| Karar Defteri bu site için kapalı. | [lib/services/decision_book_api.dart:329](../lib/services/decision_book_api.dart#L329) |
| Karekodun süresi doldu. Ekranda yenilenen güncel karekodu okutun. | [lib/services/auth_api.dart:3982](../lib/services/auth_api.dart#L3982) |
| Kaydın durumu bu şekilde değiştirilemez. Kayıt başka biri tarafından kapatılmış olabilir; yenileyip tekrar deneyin. | [lib/services/visitor_log_api.dart:380](../lib/services/visitor_log_api.dart#L380) |
| Kayıt bağlantı şablonu boşluk içeremez. | [lib/services/cctv_api.dart:186](../lib/services/cctv_api.dart#L186) |
| Kayıt bağlantı şablonu https:// ile başlamalı. | [lib/services/cctv_api.dart:185](../lib/services/cctv_api.dart#L185) |
| Kayıt bu durumdan istenen duruma geçirilemez. Başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin. | [lib/services/reservation_api.dart:704](../lib/services/reservation_api.dart#L704) |
| Kayıt bulunamadı ya da erişiminiz yok. | [lib/services/cctv_api.dart:293](../lib/services/cctv_api.dart#L293) |
| Kayıt bulunamadı ya da erişiminiz yok. | [lib/services/visitor_log_api.dart:367](../lib/services/visitor_log_api.dart#L367) |
| Kendi şifrenizi Profilim ekranından değiştirin. | [lib/services/auth_api.dart:3941](../lib/services/auth_api.dart#L3941) |
| Kişi bu dairede zaten kayıtlı. | [lib/services/auth_api.dart:3839](../lib/services/auth_api.dart#L3839) |
| Kişi bulunamadı. | [lib/services/auth_api.dart:3831](../lib/services/auth_api.dart#L3831) |
| Kişisel verilerinizi 24 saat içinde en fazla 3 kez indirebilirsiniz.$wait | [lib/services/account_api.dart:398](../lib/services/account_api.dart#L398) |
| Kod tekrar gönderilemedi. | [lib/services/auth_service.dart:552](../lib/services/auth_service.dart#L552) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/auth_api.dart:3951](../lib/services/auth_api.dart#L3951) |
| Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin. | [lib/services/geofence_service.dart:88](../lib/services/geofence_service.dart#L88) |
| Konum bilgisi geçersiz. GPS'i kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3947](../lib/services/auth_api.dart#L3947) |
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
| Mali kaydı olan daire silinemez. | [lib/services/auth_api.dart:4122](../lib/services/auth_api.dart#L4122) |
| Mali kayıt bulunamadı. | [lib/services/auth_api.dart:4126](../lib/services/auth_api.dart#L4126) |
| Mevcut şifre için çok fazla hatalı deneme yapıldı.$wait | [lib/services/auth_api.dart:3936](../lib/services/auth_api.dart#L3936) |
| Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin. | [lib/services/auth_api.dart:3934](../lib/services/auth_api.dart#L3934) |
| Modül bulunamadı. | [lib/services/auth_api.dart:4017](../lib/services/auth_api.dart#L4017) |
| Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz. | [lib/services/auth_api.dart:4034](../lib/services/auth_api.dart#L4034) |
| Okutulan karekod geçersiz. | [lib/services/auth_api.dart:3986](../lib/services/auth_api.dart#L3986) |
| OpenDocument (.ods) dosyaları desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin. | [lib/services/bulk_file_parser.dart:90](../lib/services/bulk_file_parser.dart#L90) |
| Oturum açmanız gerekmektedir. | [lib/services/account_api.dart:495](../lib/services/account_api.dart#L495) |
| Oturum açmanız gerekmektedir. | [lib/services/annual_report_api.dart:31](../lib/services/annual_report_api.dart#L31) |
| Oturum açmanız gerekmektedir. | [lib/services/apartment_management_api.dart:154](../lib/services/apartment_management_api.dart#L154) |
| Oturum açmanız gerekmektedir. | [lib/services/bank_import_api.dart:296](../lib/services/bank_import_api.dart#L296) |
| Oturum açmanız gerekmektedir. | [lib/services/brand_theme_api.dart:21](../lib/services/brand_theme_api.dart#L21) |
| Oturum açmanız gerekmektedir. | [lib/services/budget_api.dart:117](../lib/services/budget_api.dart#L117) |
| Oturum açmanız gerekmektedir. | [lib/services/bulk_api.dart:525](../lib/services/bulk_api.dart#L525) |
| Oturum açmanız gerekmektedir. | [lib/services/cctv_api.dart:314](../lib/services/cctv_api.dart#L314) |
| Oturum açmanız gerekmektedir. | [lib/services/contract_api.dart:535](../lib/services/contract_api.dart#L535) |
| Oturum açmanız gerekmektedir. | [lib/services/decision_book_api.dart:427](../lib/services/decision_book_api.dart#L427) |
| Oturum açmanız gerekmektedir. | [lib/services/device_integrations_api.dart:263](../lib/services/device_integrations_api.dart#L263) |
| Oturum açmanız gerekmektedir. | [lib/services/document_api.dart:1052](../lib/services/document_api.dart#L1052) |
| Oturum açmanız gerekmektedir. | [lib/services/equipment_api.dart:404](../lib/services/equipment_api.dart#L404) |
| Oturum açmanız gerekmektedir. | [lib/services/finance_4b_api.dart:1556](../lib/services/finance_4b_api.dart#L1556) |
| Oturum açmanız gerekmektedir. | [lib/services/finance_payment_api.dart:177](../lib/services/finance_payment_api.dart#L177) |
| Oturum açmanız gerekmektedir. | [lib/services/management_company_api.dart:20](../lib/services/management_company_api.dart#L20) |
| Oturum açmanız gerekmektedir. | [lib/services/meter_api.dart:239](../lib/services/meter_api.dart#L239) |
| Oturum açmanız gerekmektedir. | [lib/services/neighbor_board_api.dart:61](../lib/services/neighbor_board_api.dart#L61) |
| Oturum açmanız gerekmektedir. | [lib/services/payment_notice_api.dart:241](../lib/services/payment_notice_api.dart#L241) |
| Oturum açmanız gerekmektedir. | [lib/services/plate_recognition_api.dart:447](../lib/services/plate_recognition_api.dart#L447) |
| Oturum açmanız gerekmektedir. | [lib/services/platform_rules_api.dart:274](../lib/services/platform_rules_api.dart#L274) |
| Oturum açmanız gerekmektedir. | [lib/services/push_service.dart:707](../lib/services/push_service.dart#L707) |
| Oturum açmanız gerekmektedir. | [lib/services/push_service.dart:747](../lib/services/push_service.dart#L747) |
| Oturum açmanız gerekmektedir. | [lib/services/push_service.dart:789](../lib/services/push_service.dart#L789) |
| Oturum açmanız gerekmektedir. | [lib/services/reservation_api.dart:808](../lib/services/reservation_api.dart#L808) |
| Oturum açmanız gerekmektedir. | [lib/services/survey_api.dart:428](../lib/services/survey_api.dart#L428) |
| Oturum açmanız gerekmektedir. | [lib/services/visitor_log_api.dart:463](../lib/services/visitor_log_api.dart#L463) |
| Oturum açmanız gerekmektedir. | [lib/services/work_tracking_api.dart:1018](../lib/services/work_tracking_api.dart#L1018) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:3325](../lib/services/auth_service.dart#L3325) |
| Oturum bulunamadi. | [lib/services/auth_service.dart:3442](../lib/services/auth_service.dart#L3442) |
| Ödeme ile site açma yakında. | [lib/services/auth_api.dart:4090](../lib/services/auth_api.dart#L4090) |
| Önce ilgili dönemi kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır. | [lib/services/finance_4b_errors.dart:31](../lib/services/finance_4b_errors.dart#L31) |
| Önemli uyarılar var. Her birini gözden geçirdiğinizi işaretleyin. | [lib/services/payment_notice_api.dart:197](../lib/services/payment_notice_api.dart#L197) |
| Önizlemeden sonra kayıtlar değişti. Önizlemeyi yenileyip tekrar deneyin. | [lib/services/bank_import_api.dart:22](../lib/services/bank_import_api.dart#L22) |
| Plaka biçimi geçersiz. | [lib/services/auth_api.dart:4053](../lib/services/auth_api.dart#L4053) |
| Plaka Tanıma modülü bu site için kapalı. | [lib/services/plate_recognition_api.dart:424](../lib/services/plate_recognition_api.dart#L424) |
| Rezervasyon bulunamadı ya da erişiminiz yok. | [lib/services/reservation_api.dart:643](../lib/services/reservation_api.dart#L643) |
| Rezervasyon ve Konsiyerj bu site için kapalı. | [lib/services/reservation_api.dart:631](../lib/services/reservation_api.dart#L631) |
| Rezervasyon ve talep için sitede aktif daire sakini olmalısınız. | [lib/services/reservation_api.dart:637](../lib/services/reservation_api.dart#L637) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/auth_api.dart:3949](../lib/services/auth_api.dart#L3949) |
| Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz. | [lib/services/geofence_service.dart:81](../lib/services/geofence_service.dart#L81) |
| Sayfa bilgisi geçersiz. Listeyi yenileyip tekrar deneyin. | [lib/services/contract_api.dart:436](../lib/services/contract_api.dart#L436) |
| Seçilen blok veya daireler bu siteye ait değil. Hedefi yeniden seçin. | [lib/services/auth_api.dart:4066](../lib/services/auth_api.dart#L4066) |
| Seçilen daire bu sitede bulunamadı. Daireyi yeniden seçin. | [lib/services/visitor_log_api.dart:369](../lib/services/visitor_log_api.dart#L369) |
| Seçilen dosya boş. Başka bir dosya seçin. | [lib/services/document_api.dart:922](../lib/services/document_api.dart#L922) |
| Seçilen firma pasif. Başka bir firma seçin ya da firmayı Firmalar sekmesinden etkinleştirin. | [lib/services/contract_api.dart:424](../lib/services/contract_api.dart#L424) |
| Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin. | [lib/services/auth_api.dart:4064](../lib/services/auth_api.dart#L4064) |
| Seçilen kişi bu talebe atanamaz. Listeyi yenileyip tekrar deneyin. | [lib/services/work_tracking_api.dart:832](../lib/services/work_tracking_api.dart#L832) |
| Seçilen saat alanın açık saatlerine uymuyor. Boş saatleri yenileyip başka bir saat seçin. | [lib/services/reservation_api.dart:668](../lib/services/reservation_api.dart#L668) |
| Seçtiğiniz saat bu arada doldu. Boş saatleri yenileyip başka bir saat seçin. | [lib/services/reservation_api.dart:676](../lib/services/reservation_api.dart#L676) |
| Site belge alanı doldu. Eski belgeleri kalıcı olarak silin. | [lib/services/document_api.dart:928](../lib/services/document_api.dart#L928) |
| Site belge kotası dolu. Yeni belge eklenemez. | [lib/services/finance_4b_errors.dart:99](../lib/services/finance_4b_errors.dart#L99) |
| Site bulunamadı. | [lib/services/auth_api.dart:3842](../lib/services/auth_api.dart#L3842) |
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
| Site kurmak için başvuru yapmalısınız. | [lib/services/auth_api.dart:4074](../lib/services/auth_api.dart#L4074) |
| Site seçimi geçersiz. Ekranı yenileyip tekrar deneyin. | [lib/services/platform_rules_api.dart:190](../lib/services/platform_rules_api.dart#L190) |
| Sitede en çok $areaLimit alan tanımlanabilir. | [lib/services/reservation_api.dart:659](../lib/services/reservation_api.dart#L659) |
| Sitede geçerli rezervasyon üst sınırına ulaşıldı. Yönetimle iletişime geçin. | [lib/services/reservation_api.dart:695](../lib/services/reservation_api.dart#L695) |
| Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin. | [lib/services/reservation_api.dart:713](../lib/services/reservation_api.dart#L713) |
| Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin. | [lib/services/work_tracking_api.dart:845](../lib/services/work_tracking_api.dart#L845) |
| Sitedeki belge sayısı sınırına ulaşıldı. Eski belgeleri kalıcı olarak silin. | [lib/services/document_api.dart:930](../lib/services/document_api.dart#L930) |
| Son 24 saatte en fazla 5 başvuru yapabilirsiniz. Daha sonra tekrar deneyin. | [lib/services/auth_api.dart:4088](../lib/services/auth_api.dart#L4088) |
| Son bir saatte çok sayıda e-postalı duyuru yayınladınız. Biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:3849](../lib/services/auth_api.dart#L3849) |
| Sözleşme bulunamadı ya da erişiminiz yok. Listeyi yenileyin. | [lib/services/contract_api.dart:418](../lib/services/contract_api.dart#L418) |
| SSL baglantisi kurulurken hata olustu. | [lib/services/auth_api.dart:4198](../lib/services/auth_api.dart#L4198) |
| Sunucu baglantisinda istemci hatasi olustu. | [lib/services/auth_api.dart:4206](../lib/services/auth_api.dart#L4206) |
| Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin. | [lib/services/platform_rules_api.dart:117](../lib/services/platform_rules_api.dart#L117) |
| Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:4188](../lib/services/auth_api.dart#L4188) |
| Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/legal_api.dart:225](../lib/services/legal_api.dart#L225) |
| Sunucu meşgul. Biraz sonra tekrar deneyin. | [lib/services/document_api.dart:948](../lib/services/document_api.dart#L948) |
| Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/platform_rules_api.dart:141](../lib/services/platform_rules_api.dart#L141) |
| Sunucu şu anda yoğun. Biraz sonra tekrar deneyin. | [lib/services/work_tracking_api.dart:908](../lib/services/work_tracking_api.dart#L908) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/apartment_management_api.dart:79](../lib/services/apartment_management_api.dart#L79) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/brand_theme_api.dart:33](../lib/services/brand_theme_api.dart#L33) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/cctv_api.dart:253](../lib/services/cctv_api.dart#L253) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/device_integrations_api.dart:212](../lib/services/device_integrations_api.dart#L212) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/equipment_api.dart:355](../lib/services/equipment_api.dart#L355) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/management_company_api.dart:32](../lib/services/management_company_api.dart#L32) |
| Sunucu yanıt vermedi, tekrar deneyin. | [lib/services/plate_recognition_api.dart:391](../lib/services/plate_recognition_api.dart#L391) |
| Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin. | [lib/services/decision_book_api.dart:173](../lib/services/decision_book_api.dart#L173) |
| Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin. | [lib/services/survey_api.dart:204](../lib/services/survey_api.dart#L204) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/bank_import_api.dart:237](../lib/services/bank_import_api.dart#L237) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/decision_book_api.dart:395](../lib/services/decision_book_api.dart#L395) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1340](../lib/services/finance_4b_api.dart#L1340) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:1344](../lib/services/finance_4b_api.dart#L1344) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/finance_payment_api.dart:96](../lib/services/finance_payment_api.dart#L96) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/meter_api.dart:169](../lib/services/meter_api.dart#L169) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/payment_notice_api.dart:148](../lib/services/payment_notice_api.dart#L148) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/platform_rules_api.dart:243](../lib/services/platform_rules_api.dart#L243) |
| Sunucu yanıtı okunamadı. Lütfen tekrar deneyin. | [lib/services/survey_api.dart:407](../lib/services/survey_api.dart#L407) |
| Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:4190](../lib/services/auth_api.dart#L4190) |
| Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin. | [lib/services/legal_api.dart:228](../lib/services/legal_api.dart#L228) |
| Sunucunun cihaz bağlantısı şu an hazır değil. Lütfen biraz sonra tekrar deneyin. | [lib/services/auth_api.dart:3996](../lib/services/auth_api.dart#L3996) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:304](../lib/services/auth_service.dart#L304) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:319](../lib/services/auth_service.dart#L319) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:363](../lib/services/auth_service.dart#L363) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:492](../lib/services/auth_service.dart#L492) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:759](../lib/services/auth_service.dart#L759) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:903](../lib/services/auth_service.dart#L903) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:939](../lib/services/auth_service.dart#L939) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:963](../lib/services/auth_service.dart#L963) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:980](../lib/services/auth_service.dart#L980) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1078](../lib/services/auth_service.dart#L1078) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1108](../lib/services/auth_service.dart#L1108) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:1152](../lib/services/auth_service.dart#L1152) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2621](../lib/services/auth_service.dart#L2621) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:2832](../lib/services/auth_service.dart#L2832) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3283](../lib/services/auth_service.dart#L3283) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3307](../lib/services/auth_service.dart#L3307) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3384](../lib/services/auth_service.dart#L3384) |
| Sunucuya baglanilamadi. | [lib/services/auth_service.dart:3452](../lib/services/auth_service.dart#L3452) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/annual_report_api.dart:43](../lib/services/annual_report_api.dart#L43) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/apartment_management_api.dart:59](../lib/services/apartment_management_api.dart#L59) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/apartment_management_api.dart:81](../lib/services/apartment_management_api.dart#L81) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/bank_import_api.dart:233](../lib/services/bank_import_api.dart#L233) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/brand_theme_api.dart:35](../lib/services/brand_theme_api.dart#L35) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/budget_api.dart:77](../lib/services/budget_api.dart#L77) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/cctv_api.dart:255](../lib/services/cctv_api.dart#L255) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/device_integrations_api.dart:214](../lib/services/device_integrations_api.dart#L214) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/equipment_api.dart:357](../lib/services/equipment_api.dart#L357) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/finance_payment_api.dart:92](../lib/services/finance_payment_api.dart#L92) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/management_company_api.dart:34](../lib/services/management_company_api.dart#L34) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/neighbor_board_api.dart:74](../lib/services/neighbor_board_api.dart#L74) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/payment_notice_api.dart:144](../lib/services/payment_notice_api.dart#L144) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/services/plate_recognition_api.dart:393](../lib/services/plate_recognition_api.dart#L393) |
| Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin. | [lib/ui/widgets/drive_storage_card.dart:62](../lib/ui/widgets/drive_storage_card.dart#L62) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:387](../lib/services/auth_service.dart#L387) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:427](../lib/services/auth_service.dart#L427) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:515](../lib/services/auth_service.dart#L515) |
| Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz. | [lib/services/auth_service.dart:770](../lib/services/auth_service.dart#L770) |
| Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin. | [lib/services/auth_api.dart:4204](../lib/services/auth_api.dart#L4204) |
| Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin. | [lib/services/bank_import_api.dart:247](../lib/services/bank_import_api.dart#L247) |
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
| Şifrenizi değiştirmek için mevcut şifrenizi girin. | [lib/services/auth_service.dart:3330](../lib/services/auth_service.dart#L3330) |
| Şifrenizi değiştirmek için mevcut şifrenizi girmelisiniz. | [lib/services/auth_api.dart:3932](../lib/services/auth_api.dart#L3932) |
| Tahsilatın gireceği kasa ya da banka hesabını seçin. | [lib/services/payment_notice_api.dart:201](../lib/services/payment_notice_api.dart#L201) |
| Talebin durumu bu şekilde değiştirilemez. Talep başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin. | [lib/services/work_tracking_api.dart:841](../lib/services/work_tracking_api.dart#L841) |
| Talep bulunamadı ya da erişiminiz yok. | [lib/services/reservation_api.dart:645](../lib/services/reservation_api.dart#L645) |
| Talep bulunamadı ya da erişiminiz yok. | [lib/services/work_tracking_api.dart:826](../lib/services/work_tracking_api.dart#L826) |
| Talep bulunamadı. | [lib/services/auth_api.dart:4040](../lib/services/auth_api.dart#L4040) |
| Tamamlanmamış çok sayıda yüklemeniz var. Birkaç dakika sonra tekrar deneyin. | [lib/services/document_api.dart:946](../lib/services/document_api.dart#L946) |
| Tamamlanmış ya da iptal edilmiş talepte değişiklik yapılamaz. | [lib/services/reservation_api.dart:706](../lib/services/reservation_api.dart#L706) |
| Tanımlı bir kapı bulunamadı. | [lib/services/voice_door_service.dart:505](../lib/services/voice_door_service.dart#L505) |
| Tarih, hesabın açılış tarihinden önce olamaz. | [lib/services/finance_4b_errors.dart:58](../lib/services/finance_4b_errors.dart#L58) |
| Tazminat aylar sırayla hesaplanır. Sıradaki ayı seçin. | [lib/services/finance_4b_errors.dart:35](../lib/services/finance_4b_errors.dart#L35) |
| Tazminat çalıştırması bulunamadı. | [lib/services/finance_4b_errors.dart:39](../lib/services/finance_4b_errors.dart#L39) |
| Tedarikçi bulunamadı. | [lib/services/finance_4b_errors.dart:84](../lib/services/finance_4b_errors.dart#L84) |
| Tek seferde en çok 1000 kişiye e-posta gönderilebilir. Hedefi bölüp ayrı duyurular oluşturun. | [lib/services/auth_api.dart:4070](../lib/services/auth_api.dart#L4070) |
| Teklif zaten karara bağlanmış. | [lib/services/equipment_api.dart:383](../lib/services/equipment_api.dart#L383) |
| Teklifin geçerlilik süresi dolmuş. | [lib/services/equipment_api.dart:381](../lib/services/equipment_api.dart#L381) |
| Toplam tutar değişti. Önizleme yenilendi, tekrar inceleyin. | [lib/services/bulk_api.dart:54](../lib/services/bulk_api.dart#L54) |
| Toplantı tarihi gelmemiş karar kesinleştirilemez. | [lib/services/decision_book_api.dart:341](../lib/services/decision_book_api.dart#L341) |
| Toplu işlemler geçici olarak kapalı. | [lib/services/bulk_api.dart:45](../lib/services/bulk_api.dart#L45) |
| Uygulamayı güncelleyin. | [lib/services/bulk_api.dart:39](../lib/services/bulk_api.dart#L39) |
| Veriler değişti. Önizleme yenilendi, tekrar inceleyin. | [lib/services/bulk_api.dart:27](../lib/services/bulk_api.dart#L27) |
| Veriler önizlemeden sonra değişti. Önizlemeyi yenileyip toplamı kontrol edin. | [lib/services/auth_api.dart:4094](../lib/services/auth_api.dart#L4094) |
| Yalnız .xlsx ve .csv dosyaları yüklenebilir. | [lib/services/bulk_file_parser.dart:92](../lib/services/bulk_file_parser.dart#L92) |
| Yalnızca tahsilat düzeltilebilir. Borç için kaydı iptal edin. | [lib/services/auth_api.dart:4108](../lib/services/auth_api.dart#L4108) |
| Yayın zamanı geçersiz. En az 1 dakika, en çok 1 yıl sonrası seçin. | [lib/services/auth_api.dart:4068](../lib/services/auth_api.dart#L4068) |
| Yeni şifreler birbiriyle eşleşmiyor. | [lib/ui/dialogs/force_change_password_dialog.dart:82](../lib/ui/dialogs/force_change_password_dialog.dart#L82) |
| Yetkilendirme servisi bulunamadı. | [lib/ui/widgets/dynamic_qr_pass_modal.dart:433](../lib/ui/widgets/dynamic_qr_pass_modal.dart#L433) |
| Yükleme adresi geçersiz. İşlemi baştan başlatın. | [lib/services/document_api.dart:221](../lib/services/document_api.dart#L221) |
| Yükleme adresi geçersiz. Lütfen tekrar deneyin. | [lib/services/finance_4b_api.dart:856](../lib/services/finance_4b_api.dart#L856) |
| Yükleme isteği eksik gönderildi. Tekrar deneyin. | [lib/services/document_api.dart:926](../lib/services/document_api.dart#L926) |
| Yükleme sunucusu şu an meşgul.$wait | [lib/services/finance_4b_errors.dart:101](../lib/services/finance_4b_errors.dart#L101) |
| Yükleme süresi doldu. Tekrar deneyin. | [lib/services/work_tracking_api.dart:897](../lib/services/work_tracking_api.dart#L897) |
| Yüklenecek satır bulunamadı. | [lib/services/bulk_api.dart:33](../lib/services/bulk_api.dart#L33) |
| Zaten bekleyen bir site başvurunuz var. | [lib/services/auth_api.dart:4076](../lib/services/auth_api.dart#L4076) |
| Ziyaretçi ve kargo kaydı bu site için kapalı. | [lib/services/visitor_log_api.dart:361](../lib/services/visitor_log_api.dart#L361) |


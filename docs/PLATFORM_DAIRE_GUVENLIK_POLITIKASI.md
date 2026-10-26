# Daire güvenlik ve koruma politikası (migration 074)

Amaç: ev içi şiddet riski altındaki bir kişinin, daire adminiyle (eş, malik, kiracı) arasındaki yetki farkı yüzünden kapı erişimini, mahremiyetini ve çıkış hakkını kaybetmemesi.
Bu belge `docs/PLATFORM_DAIRE_YONETIMI.md` içindeki rol modelini SERTLEŞTİRİR; çelişkide bu belge önceliklidir.

> Bu uygulama polisin, mahkemenin ya da sosyal hizmet kuruluşlarının yerine geçmez. Sistem bir iddiayı DOĞRULAYAMAZ ve otomatik kilitleme YAPMAZ; kararı insan (site yöneticisi) verir.

## Tehdit modeli

Saldırgan daire admini ya da malik olabilir. Kapı açma gibi önemli işler yapıldığı için admin yetkisi kötüye kullanılabilir:
(1) mağduru daireden / kapıdan çıkarma, (2) mağdurun giriş-çıkış saatlerini, konumunu izleme, (3) mağdurun yardım istemesini fark edip engelleme, (4) mağduru uygulamada bulup baskı kurma.
Mağdur adminin yetkisini elinden alamaz; bu yüzden korumalar "admin ne yapamaz" ve "mağdur ne yapabilir" olarak tanımlanır.

## Kurallar

| # | Kural | Uygulama |
|---|---|---|
| 1 | Kişi bazlı kapı erişimi bağımsızdır: admin, YETİŞKİN bir üyenin (aile üyesi dahil) bağlarını / kapı erişimini TEK TARAFLI kesemez. Admin yetişkin üyeyi çıkarmak isterse üyeye onay isteği gider; onaylarsa kesilir, reddederse ya da 7 gün yanıtsız kalırsa istek kapanır (otomatik kesme YOK). Anlaşmazlıkta site yönetimi karar verir. | `DELETE .../family/:residencyId` -> `member_removal` talebi; eski uçlar (`removeApartmentMember`, `toggleApartmentMemberStatus`) daire-admini-yalnız çağıranlar için yetişkine `403 CONSENT_REQUIRED` |
| 1b | Admin yalnız 18 yaşından küçük işaretli üyeleri ve hesabı olmayan kişileri (kesilecek erişim yok) tek taraflı çıkarır. Aile üyesi eklerken "18 yaşından küçük" seçeneği vardır; yetişkin varsayılandır. | `apartment_residencies.is_minor`, `adminMayRemoveWithoutConsent` |
| 1c | Malik-kiracı karşılıklı onay kuralı aynen. | `disconnect` talebi |
| 2 | Herkes kendi bağını kendisi keser: "Bu daireden ayrıl", onaysız, tek taraflı. Ayrılma diğerlerine BİLDİRİLMEZ (admin listesinde yalnız kişi kalkar); denetim kaydına yazılır. | `POST /app/apartments/:id/leave` |
| 3 | Gizlilik: admin / malik diğer üyelerin KİŞİ BAZLI kapı geçiş kayıtlarını, giriş-çıkış saatlerini, konumunu GÖRMEZ. Kapı açma bildirimi başkasına gitmez. | Aşağıdaki denetim; geçiş günlüğü yalnız site yönetimi (`requireSiteManager`) ve kişinin kendi kaydında |
| 4 | Kişi arama: e-posta / kullanıcı adı / telefon YALNIZ TAM EŞLEŞME; ad-soyad ile bulanık arama yalnız "Beni aramalarda göster"i AÇMIŞ kişileri döner (varsayılan KAPALI, Profilim'de). Sonuçlar maskeli, daire / site / adres bilgisi yok. Saatte 60. Her arama maskeli sorguyla audit'e yazılır. | `classifySearchQuery`, `users.search_visible` |
| 5 | Güvenlik talebi: yetişkin her üye site yönetimine GİZLİ talep açar. Talebi YALNIZ site yöneticisi ve süper görür. Hiçbir bildirimde talep eden adı geçmez; talep açıldığı haneden kimseye bildirilmez. | `apartment_safety_requests` |
| 5b | Site yöneticisi araçları: (a) daire adminini değiştir, (b) kişinin DAİRE KAPI ERİŞİMİNİ askıya al / geri aç (neden kodu court_order / safety / other + zorunlu not; bağlar korunur; kişiye bildirim GİTMEZ), (c) talebe not ekle / kapat. Her işlem audit'e. | `apartment_access_suspensions`, `toggleApartmentMemberStatus` |
| 6 | Bilgi kartı: güvenlik bölümünde "Acil tehlikede 112'yi arayın" ve destek hatları. | Dairem > Güvenlik ve destek |

## Gizlilik denetimi (kural 3)

Sakin tarafı uçları incelendi:
- `/app/doors/:id/open`, `/status`, `qr-*`: yalnız çağıranın kendi eylemi; başkasının kaydı dönmez.
- `/app/guest-passes`: yalnız `created_by_user_code = çağıran`.
- Kapı geçiş günlüğü (`/manager/door-logs`, `/admin/door-logs`): `requireSiteManager` / süper; sakin ve daire admini erişemez.
- `/app/apartments/mine`: üyelerin YALNIZ adı döner (telefon / e-posta / saat / konum yok).
- Ziyaretçi / kargo ve plaka sakin uçları daire düzeyindedir (kişi bazlı geçiş içermez).
Bilinen kalan nokta: eski `getMyApartments` (Daire Kullanıcıları ekranı) aynı dairedekilerin e-posta / telefonunu döner; geçiş kaydı içermez, ancak iletişim bilgisidir.

## Güvenlik talebi ve askıya alma kayıtları

- `apartment_safety_requests` (durum `open` / `in_review` / `resolved`), `apartment_safety_notes`, `apartment_access_suspensions`. Siteler arası yalıtım: tüm sorgular `site_code` ile.
- Denetim kayıtlarının hedef türü `safety_request` / `access_suspension` olduğundan Kişi / Daire geçmişi uçlarında (kurul üyesi okur) GÖRÜNMEZ; talep metni ve talep eden adı denetim kaydına YAZILMAZ.
- Saklama: kapanan talep `resolved_at` taşır; 90 gün sonra silinmeye aday sayılır, ancak OTOMATİK SİLME KAPALIDIR (site yönetimi karar verir).
- Talep başına açık talep sınırı 3; gün başına 10 talep (kötüye kullanım).
- Askıya alınan kişi "Dairem" işlemlerini yapamaz (neden gösterilmez), davetle / onayla geri bağlanamaz, daire admini eski uçlarla yeniden etkinleştiremez. Katılım başvurusu da reddedilir: katılım QR'ı ile başvuru `403 ACCESS_SUSPENDED`, askılı kişinin bekleyen başvurusunu onaylamak `409 ACCESS_SUSPENDED` döner (`membership_service.js`; ayrıntı `docs/PLATFORM_DAIRE_YONETIMI.md` «Askıya alınmış kişinin katılım başvurusu»).

## KVKK

Ev içi şiddet bilgisi ve koruma kararı bilgisi özel hassasiyetli kişisel veridir (özel nitelikli veri sınırında). Yalnız gerekli asgari bilgi toplanır (kısa serbest metin, isteğe bağlı iletişim tercihi),
erişim yalnız site yöneticisi ve süper kullanıcıyla sınırlıdır, saklama kısa tutulur. Site yöneticisinin aydınlatma yükümlülüğü ve veri sorumlusu sıfatı ayrıca değerlendirilmelidir.

## Sınırlar ve [AVUKAT DOĞRULASIN]

- [AVUKAT DOĞRULASIN] 6284 sayılı Kanun çerçevesi: koruyucu / önleyici tedbir kararlarının site yönetimine bildirilmesi, site yönetiminin yükümlülüğü ve sorumluluğu; askıya alma kararının hukuki dayanağı ve itiraz yolu.
- [AVUKAT DOĞRULASIN] Site yöneticisinin bir kişinin kapı erişimini askıya alırken malikin mülkiyet / kiracının kullanım hakkıyla ilişkisi; "geçici ve gerekçeli" koşulunun sınırları.
- Sistem yalnız kayıt tutar ve araç sağlar; talebin gerçekliğini değerlendirmek insanın görevidir. Suistimal (yalan talep) riski, kararın insanda olması ve her işlemin denetlenmesiyle dengelenir.
- Telefon bildirimi ve e-posta bu olaylar için kullanılmaz (provoke etmemek için); iletişimi site yöneticisi yürütür.
- Yardım hatları kaynaklarla doğrulandı: 112 Acil Çağrı Merkezi; ALO 183 Sosyal Destek Hattı (ücretsiz, 7/24); KADES (Emniyet Kadın Acil Destek uygulaması); ŞÖNİM (Şiddet Önleme ve İzleme Merkezi). Numara / ad değişirse uygulamadaki sabit metin (`my_apartment_view.dart`) güncellenmelidir.

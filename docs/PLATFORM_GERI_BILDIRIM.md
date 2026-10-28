# Geri Bildirim (sayfa bağlamlı) — sözleşme

Kaynak: `docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md`, Dalga D, **P1-14**, karar **K11**.
Kapsam: her ekrandan erişilen, **ekran adı ve rotası otomatik eklenen** geri bildirim formu; en çok 4 dosya eki; yönetici ve platform sahibi için liste ucu.
Modül değildir (platform düzeyi özellik): modül kapısı yoktur, `catalog.js` ve çekirdek 8 modülün davranışı değişmez.

## Kullanıcı tarafı

- **Giriş noktaları** (`HomePage`, her ekranda geçerli): çekmecede "Yardım ve Destek"in hemen altında **Geri bildirim**; sağ üstteki dişliden açılan
  Ayarlar panelinde **Geri bildirim gönder**. AppBar'a yeni düğme eklenmedi (320 dp x 2,0 yazı ölçeğinde sığmaz).
- **Ekran bağlamı** (`FeedbackScreenContext`): form açılırken ekrandaki sayfanın adı (`Panel`, `Talepler` ...), rotası (`menu/<öğe>`, sakin modunda
  `menu/<öğe>:sakin`) ve bağlı site (seçili kapsam ya da tek bağlı site) **otomatik** eklenir. Formda salt görünür bir kartta gösterilir
  ("Gönderildiği ekran (otomatik eklenir)"); kullanıcı değiştiremez. Sunucu bağlamı olduğu gibi saklar, güncelleme ucu yoktur.
- **Metin**: 1-2000 karakter. Formda kimlerin göreceği yazar: site yönetimi ve platform ekibi (KVKK şeffaflığı).
- **Ekler** (karar K11): en çok **4 dosya**, dosya başı **5 MB**, toplam **20 MB** (JPEG / PNG / WebP). Dosyalar iş takibindeki fotoğraf hazırlığından
  geçer (`WorkPhotoPicker`): uzun kenar en çok 2560 px, JPEG kalite 85, EXIF (GPS dahil) silinir; hazırlanamayan görselde üstveri ayıklanır, ayıklanamazsa
  yüklenmez. Sınırlar istemcide de denetlenir.
- **Gönderim iki adımlıdır** (iş takibi fotoğraf eki deseni): önce kayıt (metin + bağlam + ek üstverisi), sonra her dosya sırayla yüklenir. Kayıt açıldıktan
  sonra form bir daha gönderilmez (çift kayıt olmaz); yüklenemeyen dosya dürüstçe bildirilir ("Geri bildiriminiz alındı; N dosya yüklenemedi"), yalnız eksik
  dosyalar yeniden denenir. Oturum / hız sınırı hatasında kalan dosyalar denenmez.
- **Gelen geri bildirimler** (`FeedbackInboxPage`): Ayarlar panelinde yalnız süper kullanıcıya ve site yöneticisine görünür; kayıt başına gönderen + rol,
  zaman, ekran (ad + rota), site, sürüm / platform, metin ve ek dosyalar (dokununca açılır). İmleçli sayfalama.

## Sunucu uçları (`server/src/modules/feedback_*.js`)

| Uç | Kim | Not |
| --- | --- | --- |
| `POST /app/feedback` | kimliği doğrulanmış her aktif kullanıcı | gövde: `message`, `screen_name`, `screen_route`, `site_code?`, `app_version?`, `platform?`, `attachments?[{file_name, mime_type, size_bytes}]`; 201 `{ feedback }` (ekler `uploading`) |
| `PUT /app/feedback/:id/attachments/:attId/content` | yalnız kaydı açan | ham gövde `application/octet-stream`, zorunlu `Content-Length` (= bildirilen boyut); 200 `{ attachment }` |
| `GET /manager/sites/:siteCode/feedback` | o sitenin yöneticisi (yönetici bağı, SITE_OWNER / SITE_ADMIN) + süper kullanıcı | `?limit=1..100&cursor=`; kurul / görevli / sakin / başka site yöneticisi **403 FORBIDDEN_SITE** |
| `GET /manager/sites/:siteCode/feedback/:id/attachments/:attId/content` | aynı | yalnız hazır ek; başka sitenin eki 404 |
| `GET /admin/feedback` | yalnız süper kullanıcı | tüm kayıtlar (siteye bağlı olmayanlar dahil) + `site_name`; `?site_code=` süzer; diğerleri **403** |
| `GET /admin/feedback/:id/attachments/:attId/content` | yalnız süper kullanıcı | |

- **Sınır aşımı 400** (sunucu istemciye güvenmez): `FEEDBACK_TOO_MANY_ATTACHMENTS` (> 4), `FEEDBACK_ATTACHMENT_TOO_LARGE` (> 5 MB),
  `FEEDBACK_ATTACHMENTS_TOO_LARGE` (> 20 MB; 4 x 5 MB zaten 20 MB olduğundan ikinci savunma hattıdır), `FEEDBACK_ATTACHMENT_TYPE_NOT_ALLOWED`, `INVALID_BODY`
  (metin / ekran / rota / site). PUT'ta Content-Length aşımı da 400; içerik imzası uyuşmazlığı 415; piksel bombası 415 (`ATTACHMENT_DIMENSIONS_TOO_LARGE`).
- **Rol ve site ilişkisi sunucuda türetilir**: süper kullanıcı `super_user`; siteyle gönderende yönetici bağı `site_manager`, aktif üyelik rolü küçük harfle
  (`site_owner`, `site_admin`, `board_member`, `staff`, `resident`), CRM kişisi `resident`; ilişki yoksa **403 FORBIDDEN_SITE**; site verilmediyse hesap rolü.
  İstemcinin bildirdiği rol alanı dinlenmez.
- **Kotalar** (DB düzeyi, süreçler arası): kullanıcı başına saatte 5 geri bildirim (`429 FEEDBACK_RATE_LIMITED`), 24 saatte 100 MB bildirilen ek
  (`429 FEEDBACK_QUOTA_EXCEEDED`); ayrıca HTTP hız sınırları.
- **Audit** (`feedback.created`, `feedback.attachment_added`): kimlik, rol, rota, ek sayısı / bayt; **metin ve dosya adı yazılmaz**.

## Veri ve depolama (migration 103)

- `feedback_reports` (site, kullanıcı, rol, `screen_name`, `screen_route`, metin, sürüm, platform) ve `feedback_attachments` (`uploading` -> `ready`,
  `storage_key` sunucuda üretilir). Site silinince CASCADE; kullanıcı satırı fiziksel silinirse `user_code` SET NULL ("Silinmiş Kullanıcı").
- DDL hem `server/migrations/103_feedback.sql` hem `feedback_schema.js` (`ensureFeedbackSchema`, `db.js`'te dev blok DIŞINDA, katalog kontrollü).
- Dosyalar `<DOCUMENTS_DIR>/feedback_attachments/<site | 1000000000>/<uuid>` (belgelerin `sites/` ve iş takibinin `work_attachments/` ağaçlarından AYRI);
  siteye bağlı olmayan geri bildirim `1000000000` dizinine yazılır. Yükleme akışı belge / iş takibi ilkelleriyle aynıdır (imza, fsync, `link` ile atomik
  yerleştirme, sha256). 2 saati aşan `uploading` satırlar bakım işinde silinir (`document_maintenance.js` -> `feedback_maintenance.js`).

## Bilinen sınırlar / açık işler

- `feedback_attachments/` dizini `deploy/ops/backup_db.sh` arşivlerine EKLENMEDİ (yedek betiği belge ve iş takibi fotoğrafı için ayrı arşiv tutar). Metin DB
  dökümüyle yedeklenir; ekler için ayrı arşiv gerekirse karar sahibindedir.
- Yetim dosya süpürmesi yoktur (yalnız DB adımı çökerse oluşur; küçük hacim).
- Hesap silme önizlemesi ve kişisel veri dışa aktarma kapsamına geri bildirim EKLENMEDİ (gönderen "Silinmiş Kullanıcı" görünür, metin kalır).
- Gerçek PostgreSQL koşusu yapılmadı: SQL katı sahte veritabanıyla ve DDL eşitlik testleriyle doğrulandı.

# Durum sözlüğü (A–E): roller, durumlar ve terimler

Sistemde geçen **rol**, **durum** ve **terimlerin** tek belgelik sözlüğü. Her değer koddan alınmıştır (2026-10-28 itibarıyla): veritabanı
`CHECK (... IN (...))` kısıtları (`server/migrations/`), sunucu sabitleri (`server/src/`) ve istemcideki Türkçe etiketler
(`lib/models/`). Uydurma değer yoktur; bir değerin istemci modelinde **etiketi yoksa** "—" yazılır (anlamı gerekiyorsa parantez içinde ilgili belgeden verilir).
Ekranların listesi için kardeş belge: `docs/EKRAN_ENVANTERI.md`.

**Okuma kılavuzu.** *Kod* = veritabanı/API değeri (`snake_case`, bazı tablolarda `BÜYÜK_HARF`); *Etiket* = istemcide görünen ad.
**A–E**, bu belgenin beş bölümüdür: **A** Roller ve bağlar · **B** Hesap, üyelik ve başvuru durumları · **C** Kapı, cihaz ve geçiş ·
**D** Finans ve para · **E** Modüller ve iş akışı durumları.
(Not: Astra karşılaştırma raporundaki "A–E sınıfı" — mevcut-tam / mevcut-eksik / yeni / ertelenmiş / sahip kararı — bir proje yönetimi
sınıflamasıdır ve bu belgenin harfleriyle ilgisi yoktur.)

### Bir bakışta

| Terim | Kısa anlam | Ayrıntı |
| --- | --- | --- |
| Hesap rolü | `super_user` · `site_manager` · `apartment_owner` · `individual` (kim olduğu) | A1 |
| Bağ rolü | Bir sitedeki yer: `SITE_OWNER`/`SITE_ADMIN` (yönetici), `BOARD_MEMBER` (kurul, salt okunur), `STAFF` (görevli), `RESIDENT` | A2 |
| Yönetici Paneli / Sakin Modu | Aynı yönetici hesabının iki görünümü; yazma yetkisi yalnız yönetici modunda | A5 |
| Panel | Ana sayfa = modül vitrini (kapı paneli "Kapılar" öğesindedir) | A5, `EKRAN_ENVANTERI.md` |
| Site başvurusu | Bireysel hesap → süper kullanıcı onayı → `site_manager` | B2 |
| Çekirdek / seçmeli modül | Çekirdek: her sitede hep açık (8); seçmeli: süper açar, yönetici talep eder (15; 2'si "yakında") | E1 |
| Misafir / Kurye geçişi | Süreli, kullanım sınırlı geçiş linki (`guest_passes`) | C4 |
| Defter | Yalnız eklenen borç/tahsilat/ters kayıt satırları; tutarlar kuruş | D1 |
| İki hesap | "İşletme Projesi (Aidat) Hesabı" (dairede oturan öder) ve "Yatırım ve Demirbaş (Fon) Hesabı" (malik öder) | D2 |
| Dekont bildirimi | Sakinin ödeme bildirimi: İnceleniyor → Onaylandı / İptal edildi / Geri çekildi | D3 |

---

## A. Roller ve bağlar

Sistemde **dört katman** rol vardır: hesap rolü (kim olduğu), site bağı (bir sitede ne olduğu), daire bağı (bir dairede ne olduğu) ve
istemci modu (şu an hangi gözle baktığı). Hepsi aynı kişide birlikte bulunabilir.

### A1. Hesap rolü — `users.role`

Kısıt: `server/migrations/017_users_role_individual.sql`. İstemci: `lib/models/user_role.dart` (`UserRole`).

| Kod | Etiket (`UserRole.label`) | Denetim kaydında | Anlamı |
| --- | --- | --- | --- |
| `super_user` | Super User | Süper Kullanıcı | Platformu yöneten şirket hesabı: modülleri açar, site/modül başvurularını karara bağlar, kullanıcı ve cihazları yönetir. Modül süzgeci uygulanmaz. |
| `site_manager` | Site Yoneticisi | Site Yöneticisi | Bir ya da birden çok siteyi yönetir. AppBar'daki hapla **Yönetici Paneli** ↔ **Sakin Modu** arasında geçer. |
| `apartment_owner` | Daire Kullanicisi | Daire Sakini | Daireye bağlı sakin hesabı: kapı, borç, duyuru, talep, rezervasyon gibi sakin ekranlarını görür. |
| `individual` | Bireysel Kullanici | Bireysel Kullanıcı | Kendi kaydolan hesap (`/auth/register-individual` + 6 haneli e-posta kodu). Site kurmak için **başvurur** ya da bir daireye **katılır**. |

Not: `UserRole.label` değerleri kodda aksansız yazılmıştır (örn. "Site Yoneticisi"); denetim kaydı ekranı (`lib/models/audit_log.dart`)
aksanlı adları kullanır.

### A2. Site bağı — `site_memberships.role` (ve `site_manager_sites`)

Kısıt: `server/migrations/029_platform_modules.sql`. Etiketler: `lib/models/audit_log.dart`, `lib/models/staff_role_record.dart`.

| Kod | Etiket | Anlamı |
| --- | --- | --- |
| `SITE_OWNER` | Site Sahibi | Yönetici bağı. Sunucu `SITE_OWNER` ile `SITE_ADMIN`'i aynı sınıfta (`manager`) sayar. |
| `SITE_ADMIN` | Site Yöneticisi | Yönetici bağı (yukarıdaki gibi). |
| `RESIDENT` | — | Site üyeliği olan sakin (tek başına kapı erişimi **sağlamaz**). |
| `BOARD_MEMBER` | Yönetim Kurulu / Denetçi | **Salt okunur** kurul bağı: çoğu yönetim ekranını görür, yazamaz. |
| `STAFF` | Görevli | Kapıcı, güvenlik, teknik görevli, danışma gibi görevli bağı; çoğu ekranda yoktur. |

**İstemcinin gördüğü bağ rolü** (`GET /app/my-modules` → `role`; öncelik sırası, `server/src/modules/module_service.js`):
`manager` (4: `site_manager_sites` ya da aktif `SITE_OWNER`/`SITE_ADMIN`) > `board_member` (3) > `staff` (2) > `resident` (1: aktif daire
üyeliği, eski `apartments.resident_user_code`, `RESIDENT` ya da `is_allowed` kapı izni). `door_access` bayrağı yalnız yönetici,
aktif daire üyeliği/sakin ve kapı izni olan bağlarda `true`'dur; `board_member` ve `staff` bağları kapı erişimi sağlamaz.

### A3. Görev türü — `site_team_duties.duty` (yönetim kadrosu)

Kısıt: `server/migrations/058_team_and_invitations.sql`. Etiketler: `lib/models/team.dart` (`kTeamDutyLabels`).

| Kod | Etiket | Verdiği site bağı (`membershipRoleForDuty`) |
| --- | --- | --- |
| `board_member` | Yönetim kurulu üyesi | `BOARD_MEMBER` |
| `auditor` | Denetçi | `BOARD_MEMBER` |
| `doorman` | Kapıcı | `STAFF` |
| `technical` | Teknik görevli | `STAFF` |
| `reception` | Danışma | `STAFF` |
| `other` | Diğer | `STAFF` |

### A4. Daire bağı

| Kavram | Kod → Etiket | Kaynak |
| --- | --- | --- |
| Daire üyeliği (`apartment_memberships.role`) | `APARTMENT_ADMIN` → Daire Yöneticisi ("daire admini"; dairede güncel kiracı varsa kural gereği kiracıdır, migration 081) · `FAMILY_MEMBER` → Aile Üyesi | `016_membership_v2_schema.sql`, `lib/models/audit_log.dart` |
| Daire ilişkisi (`apartment_residencies.relation`) | `owner` → Malik · `tenant` → Kiracı · `family_member` → Aile üyesi · `resident` → Sakin | `031_people_and_apartments.sql`, `lib/models/residency_relation.dart` |
| Hesap muhatabı (`apartment_residencies.is_account_holder`; çoklu malik, K7) | `true` → dairenin borç/tahakkuk/Borcum/hatırlatma muhatabı olan TEK malik (dairede tam biri) · `false` → ortak malik (kayıtlı; malik yetkisi ve borç görünümü yok; Dairem'de `my_role = co_owner`) | `104_apartment_multi_owner.sql`, `docs/PLATFORM_COKLU_MALIK.md` |
| Borç muhatabı (`apartments.responsible_party`) | `owner` → Malik · `tenant` → Kiracı · `both` → İkisi | `031_people_and_apartments.sql`, `ResponsibleParty` |
| Hesap tarafı (`account_party`; dekont, sayaç, defter) | `owner` → Ev sahibi hesabı · `tenant` → Kiracı hesabı | `066_payment_notices.sql`, `lib/models/finance.dart` (`AccountParty`) |
| Borçlanan taraf (`ChargeParty`) | `occupant` → Dairede oturan · `owner` → Ev sahibi | `lib/models/finance.dart` |
| Vekâlet kapsamı (`apartment_proxies.scope`) | `toplanti_imza`, `kurul_uyeligi` — | `074_apartment_management.sql` |
| Yönetim firması üyeliği (`management_company_members.role`) | `owner`, `staff` — | `062_management_companies.sql` |

### A5. İstemci modu ve kitle

| Terim | Anlamı | Kaynak |
| --- | --- | --- |
| Yönetici modu / **Yönetici Paneli** | Yazma yetkili yönetim görünümü. Yazma kararı `_canManagePeople`: süper ya da yönetici modundaki `site_manager`. | `lib/ui/pages/home_page.dart` |
| **Sakin Modu** | Yönetici hesabının kendi dairesi gözüyle görünümü (Borcum, Dairem, Taleplerim, ...). | `home_page.dart` (`_isResidentMode`) |
| Panel kitlesi (`ShowcaseAudience`) | `admin` (yönetici/süper) · `resident` (daire sakini, sakin modu) · `individual` (bireysel) | `lib/ui/helpers/module_showcase.dart` |
| **Panel** | Modül vitrini (ana sayfa). Kapı paneli artık "Kapılar" öğesidir. | `yan_menu.dart`, `home_page.dart` |

### A6. Yönetim türü ve terim katmanı — `sites.management_type`

Kısıt: `029_platform_modules.sql`. Etiketler: `lib/models/management_type.dart`. Türe göre ekran terimleri değişir
(`lib/models/management_terms.dart`: varsayılan **Daire / Sakin / Malik / Aidat / Blok**); iş mantığı ve API alan adları değişmez.

| Kod | Etiket |
| --- | --- |
| `apartment_site` | Apartman ve Site |
| `residence` | Rezidans |
| `business_center` | İş Merkezi |
| `cooperative` | Kooperatif |
| `shopping_mall` | Alışveriş Merkezi |

---

## B. Hesap, üyelik ve başvuru durumları

### B1. Hesap bayrakları ve giriş engelleri — `users`

Giriş kapıları (`server/src/routes/auth_routes.js`, `POST /auth/login`):

| Durum | Sonuç |
| --- | --- |
| `email_verified = false` | 403 "E-posta adresiniz dogrulanmadi." |
| `approval_status = 'pending'` | 403 "Abonelik talebiniz onay bekliyor." |
| `approval_status = 'rejected'` | 403 "Abonelik talebiniz reddedildi." |
| `is_active = false` | 403 "Hesap aktif degil." |
| `must_change_password = true` (migration 077) | Giriş olur, ama oturum yalnız parola değiştirebilir: `GET /me`, `PATCH /me`, yasal onay (`/me/consents`) ve çıkış dışındaki uçlar 403 `PASSWORD_CHANGE_REQUIRED` döner (`auth_middleware.js`); istemci `force_change_password_dialog.dart` açar. |

`users.approval_status` kısıtı: `pending` · `approved` · `rejected` (`004_user_verification_and_approval.sql`). Eski site yöneticisi kayıt akışı
(`/auth/register`, `/auth/site-manager/*`) **kapalıdır** (410); yeni kayıt `register-individual` ile yapılır.

**Bekleyen kayıt (`pending_registrations`, migration 028).** Bireysel kayıtta e-posta doğrulanana kadar `users` satırı **açılmaz**; 6 haneli kod
30 dk geçerlidir, kod başına 5 ve 30 dk pencerede 10 deneme hakkı vardır (`membership_rules.js`: `VERIFICATION_CODE_TTL_MINUTES`,
`VERIFICATION_MAX_ATTEMPTS_*`). Eski 4 haneli kodlar geçiş için hâlâ biçim olarak kabul edilir.

### B2. Başvuru, talep ve davet durumları

Aşağıdaki dört ailede kodlar aynıdır; etiketler tablodadır.

| Kayıt | Tablo.sütun (kısıt) | Kodlar | Etiketler |
| --- | --- | --- | --- |
| Daireye katıl isteği | `join_requests.status` (016) | `PENDING` · `APPROVED` · `REJECTED` · `CANCELLED` | Onay Bekliyor · Onaylandı · Reddedildi · (ayrı etiketi yok: kart "Onay Bekliyor" gibi çizer) |
| **Site başvurusu** (site yöneticisi olma) | `site_applications.status` (033) | `pending` · `approved` · `rejected` · `cancelled` | Bekliyor · Onaylandı · Reddedildi · İptal edildi (tanınmayan değer: "Durum bilinmiyor") |
| Site başvurusu ödeme durumu | `site_applications.payment_status` (033) | `not_required` · `pending` · `paid` · `failed` · `refunded` | — (ödeme sistemi henüz yok; "Yakında…") |
| Modül talebi | `module_requests.status` (030) | `pending` · `approved` · `rejected` · `cancelled` | Bekliyor · Onaylandı · Reddedildi · Geri çekildi |
| Site onayı | `sites.approval_status` (077) | `pending` · `approved` · `rejected` | — |
| Site abonelik kaydı | `site_subscriptions.status` (033) | `active` · `trial` · `past_due` · `cancelled` · `expired` | — (yalnız "Deneme bitişi" metni görünür) |
| Abonelik kaynağı | `site_subscriptions.source` (033) | `manual_approval` · `payment` · `admin` | — |
| Site yöneticisi daveti | `site_manager_invitations.status` (023) | `PENDING` · `ACCEPTED` · `EXPIRED` · `REVOKED` | — |
| Uygulamaya/kadroya davet | `person_invitations.status` (058) | `pending` · `accepted` · `revoked` · `declined` · `expired` | — |
| Daire bağlantı isteği | `apartment_link_requests.status` (074) | `pending` · `approved` · `rejected` · `expired` · `cancelled` | — |
| Bağlantı isteği türü | `apartment_link_requests.kind` (074) | `tenant_invite` · `family_invite` · `disconnect` · `member_removal` | — |
| Daire yönetici devri | `apartment_admin_delegations.state` (074) | `pending_account` · `active` · `ended` | — |
| Daire güvenlik talebi | `apartment_safety_requests.status` (074) | `open` · `in_review` · `resolved` | — |
| Erişim askısı nedeni | `apartment_access_suspensions.reason_code` (074) | `court_order` · `safety` · `other` | — |
| OAuth kimliği | `user_oauth_identities.provider` (076) | `google` · `apple` | — |

Daire geçmişi olayları (`apartment_residency_log.event_type`, 075): `moved_in`, `moved_out`, `role_changed`, `admin_changed`,
`link_cut_mutual`, `member_removed`, `member_left`, `access_suspended`, `access_lifted`, `handover` (detay: `docs/PLATFORM_ADLI_KAYIT.md`).

---

## C. Kapı, cihaz ve geçiş

### C1. Kapı erişim kapsamı — `site_doors.access_scope` (016)

| Kod | Etiket (`DoorPermissionRecord.accessScopeLabel`) |
| --- | --- |
| `SITE_COMMON` | Site Ortak Kapısı |
| `BLOCK` | "{blok adı} Kapısı" (blok adı yoksa Blok Kapısı) |
| `CUSTOM` | Özel / Ekstra Kapı |

Kişi bazlı izin kaynağı (`accessSource`, `door_permission_record.dart`): `SITE_COMMON`, `BLOCK_DEFAULT`, `OVERRIDE_ALLOWED`, `OVERRIDE_DENIED`, `NO_ACCESS`.

### C2. Kapı/cihaz çalışma durumu (`DoorRuntimeStatus`, `lib/models/door_runtime_status.dart`)

| Alan | Anlamı |
| --- | --- |
| `mqtt_bridge_connected` | Sunucudaki MQTT köprüsü broker'a bağlı. |
| `mqtt_connected` | Cihaz broker'a bağlı (MQTT çevrimiçi). |
| `door_locked` | Kapı kilit durumu (`null` = bilinmiyor). |
| `local_control.available` (+ `ip`, `port`, `token`) | Yerel ağdan (UDP, protokol v2) kontrol mümkün. |
| `ota_status` | Etiket: **Güncel** · **İndiriliyor** · **Beklemede** · **Hata** (tanınmayan metin olduğu gibi). |
| `last_event`, `last_seen_at` | Cihazdan gelen son olay ve zamanı. |

**Komut verilebilir mi** (`commandEnabled`): (köprü bağlı **ve** cihaz bağlı) **ya da** (yerel kontrol uygun **ve** token **ve** IP var).

### C3. Kapı kaydı tetikleyicisi — `door_access_logs.trigger_type`

Sunucu sabiti `ALLOWED_TRIGGER_TYPES` (`server/src/services/door_log_service.js`); etiketler `DoorAccessLogRecord.triggerTypeDisplay`.

| Kod | Etiket |
| --- | --- |
| `cloud_app`, `mqtt`, `mqtt_pulse`, `remote` | Mobil Bulut |
| `voice` | Sesli Komut |
| `local_wifi` | Yerel Wi-Fi |
| `local_udp` | Yerel Wi-Fi (UDP) |
| `local_http` | Yerel Wi-Fi (HTTP) |
| `local_ble`, `ble` | Bluetooth |
| `guest_pass` | Misafir Linki |
| `offline_sync` | Çevrimdışı (ESP32) |
| `qr_scanner` | GM60 QR Okuyucu |
| `screen_qr` | Ekran QR Tarama |
| `display_btn` | Ekran Butonu |
| `admin_display_btn` | Ekran Yönetici PIN |
| `physical_btn` | Fiziksel Buton |
| `serial_btn` | Seri Port |

Kayıtta kullanıcı rolü: `super_user` → Süper Yönetici · `site_manager` → Site Yöneticisi · `apartment_owner` → Daire Sakini · `guest_pass` → Misafir / Kurye
(sunucu ayrıca `individual` kabul eder).

### C4. Misafir geçişi (`guest_passes`, migration 008)

Tür (`pass_type`, `GUEST_PASS_TYPES`): `single_use` (varsayılan; tek kullanım, varsayılan süre 30 dk) · `time_limited` (süreli, çok kullanımlı;
varsayılan süre 120 dk, varsayılan 10 kullanım, en çok 50). Süre 5-1440 dk arasına sıkıştırılır. Bir link **geçerlidir**: `is_active = TRUE`
**ve** `used_count < max_uses` **ve** `expires_at > şimdi` (`guest_passes_routes.js`); tüketilmiş tek kullanımlık link `is_active`'i değiştirmez,
`used_count` ile elenir. Kapı kaydında `guest_pass` tetikleyicisiyle görünür. Ekranlarda adı: **Misafir / Kurye** geçiş linki
(varsayılan başlık `Misafir / Kurye`; "Ziyaretçi kodu" hızlı işlemi aynı akıştır).

### C5. Plaka kararı — `plate_decisions` (073)

| `decision` | Anlamı (`docs/PLATFORM_PLAKA_TANIMA.md`) |
| --- | --- |
| `ALLOWED` | Plaka aktif araç listesinde (`vehicle`) ya da geçerli misafir izninde (`guest_permit`). |
| `DENIED` | Kara listede (`blacklist`; araç listesinden ve misafir izninden **önce** değerlendirilir). |
| `UNKNOWN` | Okuma güveni eşiğin altında (`low_confidence`) ya da kayıtsız (`not_registered`). |

`auto_action`: `none` · `would_open` · `suppressed_cooldown` · `suppressed_rate` (**kapı açılmaz**; kapı açma bu modülde "Yakında…").

### C6. Kamera ve bağlantı durumları

| Kayıt | Kod |
| --- | --- |
| Kamera markası (`camera_devices.brand`, 065) | `hikvision` · `tiandy` · `onvif` |
| CCTV kamera türü (`cctv_cameras.kind`, 072) | `ip_camera` · `nvr_channel` |
| Drive bağlantısı (`site_drive_connections.status`, 060) | `connected` · `error` · `disconnected` |
| Drive dosyası (`drive_files.status`, 060) | `pending` · `stored` |
| Kart ödeme sağlayıcısı (`payment_provider_settings.provider`, 065) | `iyzico` · `paytr` (sağlayıcılar "Yakında…") |

---

## D. Finans ve para

**Para birimi.** Tutarlar **tamsayı kuruştur** (`amount_minor`, `*_minor`); para birimi `TRY`. Bozuk tutar sessizce 0 yapılmaz.

### D1. Defter ve borç

Defter (`ledger_entries`, 034) **yalnız eklenir** (silinmez). `amount_minor > 0` = borç, `< 0` = tahsilat; bakiye `SUM(amount_minor)`'dır.

| Kod | Etiket (`LedgerKind`) | İşaret |
| --- | --- | --- |
| `charge` | Borç | `> 0` |
| `payment` | Tahsilat | `< 0` |
| `reversal` | Ters kayıt | karşı işaret, `reverses_entry_id` dolu |

| Kavram | Kod → Etiket | Kaynak |
| --- | --- | --- |
| Ödeme yöntemi (`method`) | `cash` → Nakit · `transfer` → Havale / EFT · `cheque` → Çek | `PaymentMethod` (`finance.dart`) |
| Aidat tanımı türü (`fee_definitions.kind`) | `recurring` → Aylık aidat · `one_time` → Tek seferlik | `FeeKind` |
| Dağıtım (`fee_definitions.distribution`) | `equal` → Eşit bölüş · `fixed` → Sabit tutar · `category` → Kategoriye göre · `land_share` → Arsa payına göre · `area` → Metrekareye göre | `FeeDistribution` |
| Hedef (`target_type`) | `site` → Tüm site · `blocks` → Bloklar · `apartments` → Daireler | `FeeTargetType` |
| Dönem | Ayın 1'i (`period` günü 1 olmalı) | `034_finance.sql` kısıtı |
| Yaşlandırma kovası | Vadesi gelmemiş · 0-30 · 31-60 · 61-90 · 91-180 · 181-365 · 366+ gün | `AgingBucket` |

### D2. İki hesap ve kasa türleri

| Kod | Etiket | Borcu kim öder |
| --- | --- | --- |
| `operating` (`expense_categories.fund` / fon) | **İşletme Projesi (Aidat) Hesabı** (kısa: Aidat Hesabı) | Dairede oturan (kiracı varsa kiracı) |
| `capital` | **Yatırım ve Demirbaş (Fon) Hesabı** (kısa: Fon Hesabı) | Malik |

Kaynak: `lib/models/finance_funds.dart` (adların tek kaynağı). Ekranlarda "kasa" yerine bu **Hesap** adları kullanılır.
Fiziksel hesap türü (`finance_accounts.kind`): `cash` → **Kasa** · `bank` → **Banka** (`CashAccountKind`).

| Hareket (`account_movements.kind`) | Etiket (`MovementKind`) |
| --- | --- |
| `opening` | Açılış |
| `collection` | Tahsilat |
| `expense` | Gider |
| `transfer_out` / `transfer_in` | Aktarım (çıkış) / Aktarım (giriş) |
| `adjustment` | Düzeltme (nedeni: `bank_fee` Banka masrafı · `bank_interest` Banka faizi · `cash_count` Sayım farkı · `other` Diğer) |
| `reversal` | Ters kayıt |

### D3. Dekont, banka ve makbuz

| Kayıt | Kodlar | Etiketler |
| --- | --- | --- |
| **Dekont bildirimi** (`payment_notices.status`, 066) | `uploading` · `pending` · `approved` · `rejected` · `withdrawn` | Yükleniyor · İnceleniyor · Onaylandı · İptal edildi · Geri çekildi (`NoticeStatus`) |
| Dekont iptal nedeni | `not_received` · `amount_mismatch` · `wrong_apartment` · `duplicate` · `unreadable` · `other` | Ödeme hesaba ulaşmadı · Tutar uyuşmuyor · Yanlış daire · Daha önce kaydedilmiş · Dekont okunamadı · Diğer |
| Dekont kaynağı (`origin`) | `resident_app` · `resident_share` · `manager` | — |
| **Banka ekstre satırı** (`bank_statement_lines.status`, 067) | `unmatched` · `suggested` · `posted` · `linked` · `classified` · `ignored` · `reverted` | — (modelde etiket yok; anlamı `docs/PLATFORM_FINANS_BANKA.md`'den: eşleşmedi · zayıf eşleşme, daire önseçili, yönetici onayını bekler · tahsilat yazıldı · mevcut tahsilata bağlandı, ikinci tahsilat yazılmaz · daire dışı olarak sınıflandı (gider, banka masrafı, faiz...) · yok sayıldı · geri alındı) |
| Banka yüklemesi (`bank_imports.status`) | `active` · `reverted` | — (aktif yükleme · geri alınmış yükleme) |
| Banka dosya biçimi (`bank_imports.format`) | `xlsx` · `csv` · `mt940` | — |
| **Makbuz** (`receipts.kind`, 040) | `collection` · `cancellation` | Tahsilat makbuzu · İptal makbuzu |

### D4. Gecikme, hatırlatma, gider ve sayaç

| Kayıt | Kodlar | Etiketler |
| --- | --- | --- |
| Gecikme tazminatı yöntemi (`finance_settings.late_fee_method`) | `daily_30` · `daily_actual` | Aylık oran ÷ 30 gün · Aylık oran ÷ ayın gerçek gün sayısı |
| Tazminat çalıştırması (`late_fee_runs.status`) | `active` · `voided` | — |
| Borç hatırlatma tonu (`finance_reminder_runs.tone`) | `friendly` · `standard` | Nazik hatırlatma · Resmî hatırlatma |
| Hatırlatma çalıştırması (`finance_reminder_runs.status`) | `active` · `cancelled` | — |
| Gider belge türü (`ExpenseDocumentKind`) | `none` · `invoice` · `receipt` · `contract` · `other` | Belgesiz · Fatura · Fiş / makbuz · Sözleşme · Diğer |
| Gider eki türü (`expense_documents.kind`, 040) | `invoice` · `receipt` · `photo` · `other` | Fatura · Fiş / makbuz · Fotoğraf · Diğer |
| Gider niteliği (`expense_natures.nature`) | `routine` · `unexpected` | Rutin · Beklenmedik |
| Sayaç türü (`meters.kind`) | `water` · `electricity` · `heat` · `hot_water` | Su · Elektrik · Isı · Sıcak su |
| Faturalama yöntemi (`meter_billings.method`) | `unit_price` · `invoice` · `heat` | Birim fiyat · Fatura tutarı · Isı payı (ölçüm + m²) |
| Sayaç okuma kaynağı (`meter_readings.source`) | `manual` · `file` | — (elle girilen · dosyadan aktarılan) |
| Finans raporu (`FinanceReportKind`) | `aging` · `income_expense` · `cash_position` · `statement` · `board_summary` · `expense_analysis` · `enforcement` | Gecikmiş borçlar · Aylık özet · Kasa Durumu · Daire ekstresi · Yıllık hesap · Gider Analizi · İcra dökümü |

Hukuki bayrak: tazminat ve hatırlatma ayrıca sistem bayrağı `finance.legal_ok` ister (yalnız süper açar; varsayılan KAPALI;
`server/.env.example` yorumu, `PUT /admin/finance-legal-gate`).

---

## E. Modüller ve iş akışı durumları

### E1. Modül kavramları (`server/src/modules/catalog.js`)

| Terim | Anlamı |
| --- | --- |
| **Çekirdek (temel) modül** — `core: true` | Her sitede **hep açık**, talep edilmez, **kapatılamaz** (AGENTS.md Kural 25). Katalogda 8 tane. |
| **Seçmeli modül** — `core: false` | Süper açar/kapatır; yönetici **talep eder** (`module_requests`). |
| Modül durumu (`status`) | `available` (kullanıma açık) · `coming_soon` (yakında; açılamaz, hep KAPALI) |
| Açık mı (`enabled`) | `coming_soon` ise KAPALI; çekirdekse AÇIK; aksi halde `site_modules` satırı, satır yoksa katalog varsayılanı |
| Açılıp kapatılabilir (`toggleable`) | `!core && status == 'available'` |
| Kaldırılmış kodlar | `documents` → `drive_storage`'a çevrilir (migration 084); `card_payments` → Aidat ve Finans'ın parçası, istek `400 MODULE_NOT_TOGGLEABLE` ile yanıtlanır (migration 083) |

Katalog: toplam **23 modül**, 8'i çekirdek.

| Kod | Ad | Tür | Durum | Varsayılan |
| --- | --- | --- | --- | --- |
| `door_control` | Geçiş Kontrol (SmartKeyPass) | seçmeli | kullanıma açık | KAPALI |
| `people` | Kişi ve Daire Kayıtları | çekirdek | kullanıma açık | AÇIK |
| `announcements` | Duyuru ve Bildirim | çekirdek | kullanıma açık | AÇIK |
| `finance` | Aidat ve Finans | çekirdek | kullanıma açık | AÇIK |
| `survey` | Anket ve Oylama | çekirdek | kullanıma açık | AÇIK |
| `drive_storage` | Dosya Deposu (Belgeler dahil) | çekirdek | kullanıma açık | AÇIK |
| `neighbor_board` | Komşu Panosu | çekirdek | kullanıma açık | AÇIK |
| `annual_report` | Faaliyet Raporu | çekirdek | kullanıma açık | AÇIK |
| `equipment` | Ekipman ve Bakım | çekirdek | kullanıma açık | AÇIK |
| `reservation` | Rezervasyon ve Konsiyerj | seçmeli | kullanıma açık | KAPALI |
| `work_tracking` | İş Takibi | seçmeli | kullanıma açık | KAPALI |
| `metering` | Sayaç Okuma ve Faturalandırma | seçmeli | kullanıma açık | KAPALI |
| `visitor_log` | Ziyaretçi ve Kargo | seçmeli | kullanıma açık | KAPALI |
| `card_access` | Kartlı Geçiş | seçmeli | kullanıma açık | KAPALI |
| `plate_cameras` | Kamera ve Plaka | seçmeli | kullanıma açık | KAPALI |
| `plate_recognition` | Plaka Tanıma | seçmeli | kullanıma açık | KAPALI |
| `contracts` | Firma ve Sözleşme Takibi | seçmeli | kullanıma açık | KAPALI |
| `decision_book` | Karar Defteri | seçmeli | kullanıma açık | KAPALI |
| `directory` | Rehber | seçmeli | kullanıma açık | KAPALI |
| `budget` | İşletme Projesi (Bütçe) | seçmeli | kullanıma açık | KAPALI |
| `cctv_link` | Kamera (CCTV) Bağlantısı | seçmeli | kullanıma açık | KAPALI |
| `online_payment` | Online Tahsilat ve Banka Bağlantısı | seçmeli | **yakında** | KAPALI |
| `hgs_access` | HGS Geçişi | seçmeli | **yakında** | KAPALI |

Sıra: önce Geçiş Kontrol, sonra çekirdekler, sonra seçmeliler (katalog dosyasındaki sıra değildir). Geçiş Kontrol kapalıyken telefondan kapı açma, QR ve misafir geçişi durur
(`DOOR_CONTROL_DISABLE_WARNING`).

### E2. İş akışı durumları

Etiketler istemci modellerindedir (`lib/models/`); "son" = o durumdan başka duruma geçilmez.

| Kayıt | Kodlar → Etiketler |
| --- | --- |
| **Duyuru** (`announcements.status`, 032) | `draft` Taslak · `scheduled` Zamanlanmış · `published` Yayında · `withdrawn` Geri çekildi |
| Duyuru önemi / hedefi | `normal` Normal · `urgent` Acil — `site` Tüm site · `blocks` Bloklar · `apartments` Daireler |
| Duyuru e-posta teslimi (`EmailDelivery`) | `none` E-posta istenmedi · `pending` E-posta sırada · `sent` E-posta gönderildi · `failed` E-posta gönderilemedi · `no_address` E-postası yok · `skipped_pref` E-posta tercihi kapalı · `capped` Günlük sınır aşıldı · `duplicate` Aynı adres, tekrar gönderilmedi |
| Telefon bildirimi (`push_outbox.status`, 041) | `pending` · `sent` · `failed` · `skipped` · `expired` (modelde etiket yok) |
| **İş takibi / talep** (`work_items.status`, 042) | `yeni` Yeni · `islemde` İşlemde · `beklemede` Beklemede · `cozuldu` Çözüldü · `kapandi` Kapandı (**son**) · `iptal` İptal (**son**) |
| Talep önceliği / kategorisi / yeri | `dusuk` Düşük · `normal` Normal · `acil` Acil — `ariza` Arıza · `bakim` Bakım · `sikayet_oneri` Şikayet / Öneri · `diger` Diğer — `ortak_alan` Ortak alan · `daire` Daire |
| **Rezervasyon** (`reservations.status`, 043) | `beklemede` Onay bekliyor · `onaylandi` Onaylandı · `reddedildi` Reddedildi (son) · `iptal` İptal edildi (son) · **`tamamlandi` Tamamlandı** (veritabanında yok; yanıtta `onaylandi` ve bitişi geçmişse **türetilir**) |
| Alan onay modu (`reservation_areas.approval_mode`) | `otomatik` Otomatik onay · `yonetici_onayli` Yönetici onaylı |
| **Konsiyerj talebi** (`concierge_requests.status`) | `yeni` Yeni · `hazirlaniyor` Hazırlanıyor · `tamamlandi` Tamamlandı · `iptal` İptal edildi |
| Konsiyerj kategorisi | `paket_teslim` Paket teslim · `misafir_hazirlik` Misafir hazırlığı · `temizlik` Temizlik · `tasima` Taşıma · `diger` Diğer |
| **Ziyaretçi / kargo** (`visitor_entries.status`, 045) | `bekliyor` Bekliyor · `iceride` İçeride (ikisi **açık**) · `teslim_edildi` Teslim edildi · `ayrildi` Ayrıldı · `iptal` İptal (üçü **son**); tür: `visitor` Ziyaretçi · `cargo` Kargo |
| **Anket** (`surveys.status`, 044) | `draft` Taslak · `open` Açık · `closed` Kapalı |
| **Karar defteri** (`board_decisions.status`, 050) | `taslak` Taslak · `kesin` Kesin |
| Oylama sonucu / görünürlük / toplantı | `kabul` Kabul edildi · `ret` Reddedildi · `ertelendi` Ertelendi · `bilgi` Bilgi notu — `yonetim` Yalnız yönetim · `sakinler` Sakinlere açık — `yonetim_kurulu` Yönetim Kurulu · `genel_kurul` Genel Kurul · `denetim_kurulu` Denetim Kurulu · `diger` Diğer |
| **Sözleşme** (`site_contracts.status`, 049) | veritabanında `aktif` · `feshedildi`; ekranda **türetilmiş durum** (`ContractState`): Yürürlükte · Bitişi yaklaşıyor · Süresi doldu · Feshedildi |
| Sözleşme hatırlatması (`contract_reminders.kind`) | `bitis` · `fesih_bildirim` |
| **İşletme projesi / bütçe** (`budget_projects.status`, 059) | `taslak` Taslak · `teblig` Tebliğ edildi · `kesin` Kesin |
| **Belge** (`documents.status`, 039) | `pending` Yükleniyor · `active` Yayında · `deleted` Silindi |
| Belge sürümü (`document_versions.status` / `scan_status`) | `uploading` · `ready` — `not_scanned` · `clean` · `infected` · `error` |
| Belge kategorisi | `regulation` Yönetmelik · `minutes` Toplantı Tutanağı / Karar · `contract` Sözleşme · `notice` Bilgilendirme · `other` Diğer |
| **Komşu panosu ilanı** (`neighbor_posts.status`, 064) | `pending` Onay bekliyor · `published` Yayında · `rejected` Reddedildi · `removed` Kaldırıldı · `withdrawn` Geri çekildi |
| Ekipman teklifi (`equipment_quotes.status`, 068) | `open` · `accepted` · `rejected` |
| Bakım planı aralığı (`equipment_plans.interval_months`) | 1 · 3 · 6 · 12 ay |
| Toplu yükleme türü (`ImportKind`) | `apartments` Daireler · `people` Kişiler · `vehicles` Araçlar · `all_in_one` Hepsi bir arada · `opening_balances` Devir bakiyesi |
| Beyaz etiket kapsamı (`brand_themes.scope_type`, 071) | `company` · `site` |

Diğer: **İstemci hata raporu** platformu (`client_error_reports.platform`): `android` · `ios` · `web` · `other`. Kullanıcı ve hesap işlemleri
denetim kaydında `lib/models/audit_log.dart` etiketleriyle ("Modül açıldı", "Talep onaylandı", "Hesap silindi"...) görünür.

---

## Kaynakların haritası

| Konu | Dosya |
| --- | --- |
| Veritabanı kısıtları | `server/migrations/*.sql` (ayrıca `server/src/modules/*_schema.js` aynı DDL'i taşır) |
| Hesap rolleri / giriş kapıları | `server/src/routes/auth_routes.js`, `lib/models/user_role.dart` |
| Bağ rolü, modül durumu | `server/src/modules/module_service.js`, `server/src/modules/catalog.js` |
| Etiketler | `lib/models/*.dart` (özellikle `work_tracking_models`, `reservation_models`, `visitor_log_models`, `finance`, `payment_notice`, `door_access_log_record`, `door_permission_record`, `audit_log`) |
| Kapı kaydı tetikleyicileri | `server/src/services/door_log_service.js` |
| Terim sözlüğü / terim katmanı | `lib/models/management_terms.dart`, `lib/models/finance_funds.dart` |

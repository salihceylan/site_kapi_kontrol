# Komşu Panosu (S4)

Modül kodu `neighbor_board`. TEMEL modül (2026-10-28, AGENTS.md Kural 25): `neighbor_board` her sitede hep açıktır; talep edilmez, kapatılamaz (`site_modules` satırı kurulumda yazılır, `migrations/082` mevcut siteleri doldurur). Migration 064 (`server/migrations/064_neighbor_board.sql`, `neighbor_board_schema.js` ile aynı DDL).

## Tablolar
- `neighbor_posts`: site_code, author_user_code (kullanıcı silinince NULL), title (3-120), body (3-2000), status, decision_note (en çok 300), decided_by, decided_at.
  Durum: `pending` -> `published` | `rejected`; `published` -> `removed` (yönetici) | `withdrawn` (yazar); `pending` -> `withdrawn`.
- `neighbor_post_reports`: post_id, reporter_user_code, reason (1-200); kişi başına ilan başına tek şikayet.

## Uçlar
Sakin (sitenin onaylı sakini; modül açık olmalı):
- `GET /app/neighbor-board?site_code=` yayındaki ilanlar + kendi bekleyen / reddedilen / kaldırılan ilanları
- `POST /app/neighbor-board` { site_code, title, body } -> 201, `pending`; onay bekleyen en çok 5 ilan (409 PENDING_LIMIT)
- `POST /app/neighbor-board/:id/report` { reason }; kendi ilanı 409 OWN_POST
- `POST /app/neighbor-board/:id/withdraw` yazar geri çeker

Yönetim (yönetici / süper; kurul ve görevli 403 FORBIDDEN_ROLE, başka site 403 FORBIDDEN_SITE):
- `GET /manager/sites/:siteCode/neighbor-board?status=pending|published|rejected|removed|reported`
- `POST .../:id/approve`, `POST .../:id/reject` { note zorunlu }, `POST .../:id/remove` { note zorunlu } (yalnız yayındaki)
Durum uygun değilse 409 POST_STATE. Modül kapalıysa 403 MODULE_DISABLED.

## Kurallar
- Yazar adı komşulara "Ad S." biçiminde görünür; şikayet gerekçeleri yalnız yöneticiye.
- Günlüğe başlık / metin yazılmaz. Şikayet ilanı kendiliğinden gizlemez; kaldırma yöneticinin kararıdır.
- Yeni ilan her zaman onaya düşer (otomatik yayın yok).

## Yakında
Telefon bildirimi, fotoğraf eki, yorum, süper kullanıcı için pano ekranı.

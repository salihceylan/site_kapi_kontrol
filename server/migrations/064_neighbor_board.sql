-- 064: Komsu panosu (S4): neighbor_posts, neighbor_post_reports
-- Sozlesme: docs/PLATFORM_KOMSU_PANOSU.md. db.js ensureDbSchema ile ayni DDL (src/modules/neighbor_board_schema.js; test: neighbor_board_schema).
-- Tamamen ekleyici ve idempotent. Modul varsayilan KAPALI (catalog.js neighbor_board).
-- Durum: pending (onay bekler) -> published | rejected; published -> removed (yonetici kaldirdi) ya da withdrawn (yazar geri cekti).
-- Silme politikasi: site silinince ilanlar CASCADE; kullanici silinince author_user_code SET NULL (ilan kalir, ad "Silinmis Kullanici").

CREATE TABLE IF NOT EXISTS neighbor_posts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  author_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  decision_note TEXT,
  decided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  decided_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_neighbor_posts_status CHECK (status IN ('pending', 'published', 'rejected', 'removed', 'withdrawn')),
  CONSTRAINT chk_neighbor_posts_title CHECK (char_length(title) BETWEEN 3 AND 120),
  CONSTRAINT chk_neighbor_posts_body CHECK (char_length(body) BETWEEN 3 AND 2000),
  CONSTRAINT chk_neighbor_posts_note CHECK (decision_note IS NULL OR char_length(decision_note) <= 300)
);

CREATE INDEX IF NOT EXISTS idx_neighbor_posts_site_status ON neighbor_posts (site_code, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_neighbor_posts_author ON neighbor_posts (author_user_code, id DESC) WHERE author_user_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS neighbor_post_reports (
  id BIGSERIAL PRIMARY KEY,
  post_id BIGINT NOT NULL REFERENCES neighbor_posts(id) ON DELETE CASCADE,
  reporter_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_neighbor_post_reports_reason CHECK (char_length(reason) BETWEEN 1 AND 200)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_neighbor_post_reports_once ON neighbor_post_reports (post_id, reporter_user_code) WHERE reporter_user_code IS NOT NULL;

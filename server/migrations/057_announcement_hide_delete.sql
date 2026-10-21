-- 057: Duyuru gizleme (alici kendi listesinden kaldirir) ve yumusak silme (yonetici). Ekleyici, idempotent.
-- db.js ensureDbSchema ile ayni ifadeler, ayni sira (src/modules/announcement_hide_schema.js; test: announcement_hide_schema).
-- hidden_at: alicinin kendi listesinden kaldirmasi (read_at'e dokunmaz; NULL = gorunur). deleted_at: yoneticinin yumusak silmesi (yalniz withdrawn).

ALTER TABLE announcements ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_announcements_deleted_withdrawn' AND conrelid = 'announcements'::regclass
  ) THEN
    ALTER TABLE announcements ADD CONSTRAINT chk_announcements_deleted_withdrawn CHECK (deleted_at IS NULL OR status = 'withdrawn') NOT VALID;
  END IF;
END $$;

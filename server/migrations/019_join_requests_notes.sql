-- 019: Katılım talepleri tablosuna notlar alanı ekleme
ALTER TABLE join_requests ADD COLUMN IF NOT EXISTS notes TEXT;


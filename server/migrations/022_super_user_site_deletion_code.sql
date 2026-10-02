-- 022_super_user_site_deletion_code.sql
-- Super User e-posta kodu ile doğrudan site silme desteği

ALTER TABLE sites
  ADD COLUMN IF NOT EXISTS deletion_email_code VARCHAR(10),
  ADD COLUMN IF NOT EXISTS deletion_email_code_expires_at TIMESTAMPTZ;


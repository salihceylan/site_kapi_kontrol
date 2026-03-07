ALTER TABLE users
ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE users
ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved';

ALTER TABLE users
ADD COLUMN IF NOT EXISTS email_verification_code_hash TEXT;

ALTER TABLE users
ADD COLUMN IF NOT EXISTS email_verification_expires_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_approval_status_check'
  ) THEN
    ALTER TABLE users
    ADD CONSTRAINT users_approval_status_check
    CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_users_role_approval_status
ON users(role, approval_status);

CREATE INDEX IF NOT EXISTS idx_users_role_email_verified
ON users(role, email_verified);

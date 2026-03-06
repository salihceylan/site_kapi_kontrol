CREATE OR REPLACE FUNCTION generate_unique_user_code()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  generated_code INTEGER;
BEGIN
  LOOP
    generated_code := (floor(random() * 90000) + 10000)::INTEGER;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM users WHERE user_code = generated_code
    );
  END LOOP;

  RETURN generated_code;
END;
$$;

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  user_code INTEGER NOT NULL DEFAULT generate_unique_user_code() UNIQUE CHECK (user_code BETWEEN 10000 AND 99999),
  full_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN ('super_user', 'site_manager', 'apartment_owner')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  phone_number TEXT,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_role_active ON users(role, is_active);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_user_code ON users(user_code);

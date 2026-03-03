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

ALTER TABLE users
ADD COLUMN IF NOT EXISTS user_code INTEGER;

ALTER TABLE users
ADD COLUMN IF NOT EXISTS phone_number TEXT;

UPDATE users
SET user_code = generate_unique_user_code()
WHERE user_code IS NULL;

ALTER TABLE users
ALTER COLUMN user_code SET DEFAULT generate_unique_user_code();

ALTER TABLE users
ALTER COLUMN user_code SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_user_code_five_digits_check'
  ) THEN
    ALTER TABLE users
    ADD CONSTRAINT users_user_code_five_digits_check
    CHECK (user_code BETWEEN 10000 AND 99999);
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_user_code ON users(user_code);

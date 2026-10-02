-- Migration 018: Add device claiming columns (owner_user_id and claimed_at)
ALTER TABLE devices
ADD COLUMN IF NOT EXISTS owner_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_devices_owner_user_id ON devices(owner_user_id);


-- Migration 017: Allow 'individual' role in users_role_check constraint
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('super_user', 'site_manager', 'apartment_owner', 'individual'));


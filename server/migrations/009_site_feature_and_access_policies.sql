-- 009_site_feature_and_access_policies.sql
-- Adds site-level entry policies (App remote open, QR access, local UDP, guest pass, GPS geofencing, QR rotation)

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS feature_qr_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS feature_remote_open_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS feature_local_udp_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS feature_guest_pass_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS qr_entry_active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS require_geofence BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS geofence_latitude DOUBLE PRECISION;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS geofence_longitude DOUBLE PRECISION;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER NOT NULL DEFAULT 75;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS qr_totp_secret TEXT;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS qr_rotation_seconds INTEGER NOT NULL DEFAULT 30;


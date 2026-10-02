-- Migration 021: Site Deletion Mutual Approval Workflow
-- Adds columns to track mutual confirmation between Super User and Site Manager

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS deletion_status TEXT NOT NULL DEFAULT 'none';

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS deletion_requested_by_user_code BIGINT;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS deletion_requested_by_name TEXT;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS deletion_requested_by_role TEXT;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ;


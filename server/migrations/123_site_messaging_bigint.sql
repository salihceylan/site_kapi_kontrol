-- 123: site_messaging_connections site_code ve updated_by sutunlarini BIGINT yapma (10 basamakli site kodlari integer tasma hatasini onler).
ALTER TABLE site_messaging_connections ALTER COLUMN site_code TYPE BIGINT;
ALTER TABLE site_messaging_connections ALTER COLUMN updated_by TYPE BIGINT;

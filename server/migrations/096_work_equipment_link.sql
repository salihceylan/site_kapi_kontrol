-- 096: Is kaydi <-> ekipman bagi ve fotograf once/sonra etiketi. Sozlesme: docs/PLATFORM_IS_TAKIBI.md "Ekipman bagi" / "Fotograf etiketi", docs/PLATFORM_EKIPMAN.md "Servis gecmisi"
-- db.js ensureDbSchema ile ayni DDL (src/modules/work_equipment_schema.js WORK_EQUIPMENT_STEPS; ayni sira; test: work_equipment_link). Tamamen ekleyici ve idempotent:
-- hicbir satiri DEGISTIRMEZ / SILMEZ. Yalniz iki yeni BOS sutun (work_items.equipment_id, work_item_attachments.phase), bir FK, bir kismi indeks, bir CHECK ve
-- work_item_events.chk_work_item_events_type kisitinin `equipment_changed` ile GENISLETILMESI (047 ile ayni kalip: DROP + ADD ayni DO blogunda = tek islem).
-- Eski istemciler / eski kod bozulmaz: sutunlar bos kalir, yeni olay turu yalniz yeni kod tarafindan yazilir. Geri alma icin guvenli (sutunlar nullable).
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039 / 042 / 080).
-- Silme politikasi: ekipman satiri silinirse (API silmez, pasife alir) work_items.equipment_id SET NULL; site silinince iki tablo da CASCADE gider.

ALTER TABLE work_items ADD COLUMN IF NOT EXISTS equipment_id BIGINT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_equipment_id_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_work_items_equipment ON work_items (equipment_id, id DESC) WHERE equipment_id IS NOT NULL;

ALTER TABLE work_item_attachments ADD COLUMN IF NOT EXISTS phase TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_attachments_phase' AND conrelid = 'work_item_attachments'::regclass
  ) THEN
    ALTER TABLE work_item_attachments ADD CONSTRAINT chk_work_item_attachments_phase CHECK (phase IS NULL OR phase IN ('before', 'after'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_events_type' AND conrelid = 'work_item_events'::regclass AND pg_get_constraintdef(oid) LIKE '%equipment_changed%'
  ) THEN
    ALTER TABLE work_item_events DROP CONSTRAINT IF EXISTS chk_work_item_events_type;
    ALTER TABLE work_item_events ADD CONSTRAINT chk_work_item_events_type CHECK (event_type IN ('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment', 'attachment_added', 'attachment_removed', 'equipment_changed'));
  END IF;
END $$;

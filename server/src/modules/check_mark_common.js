// Kontrol izi (110) saf yardımcıları. Hiçbir şey içe aktarmaz (gider ve dekont modülleri güvenle kullanır).

const iso = (value) => (value ? new Date(value).toISOString() : null);

/** API alanları: iz yoksa ikisi de null (kontrolsüz). `row`: checked_at + checked_by_name sütunlarını taşıyan satır (ya da null). Kullanıcı silinmişse ad null. */
export function checkMarkFields(row) {
  const at = row?.checked_at ? iso(row.checked_at) : null;
  return { checked_at: at, checked_by_name: at === null ? null : (row.checked_by_name ?? null) };
}

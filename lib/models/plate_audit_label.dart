/// Plaka Tanıma (`plate_recognition`) denetim eylemlerinin Türkçe başlığı; bilinmeyen eylemde null (zincirdeki sonraki üretici
/// dener). Denetim kaydına TAM plaka yazılmaz (sunucu maskeler: "34***23").
String? plateActionLabel(String action) {
  switch (action) {
    case 'plate.permit_created':
      return 'Misafir plakası izni verildi';
    case 'plate.permit_revoked':
      return 'Misafir plakası izni iptal edildi';
    case 'plate.blacklist_added':
      return 'Plaka kara listeye eklendi';
    case 'plate.blacklist_removed':
      return 'Plaka kara listeden çıkarıldı';
    case 'plate.settings_changed':
      return 'Plaka kapı ayarı değişti';
    case 'plate.auto_open':
      return 'Plakayla otomatik açma kaydı';
  }
  return null;
}

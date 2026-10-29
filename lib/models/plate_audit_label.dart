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
    case 'plate.gate_created':
      return 'Plaka geçiş noktası eklendi';
    case 'plate.gate_updated':
      return 'Plaka geçiş noktası değişti';
    case 'plate.gate_deleted':
      return 'Plaka geçiş noktası silindi';
    case 'plate.site_settings_changed':
      return 'Plaka misafir kuralı / durum eşikleri değişti';
    case 'plate.edge_client_created':
      return 'Plaka kenar istemcisi eklendi';
    case 'plate.edge_client_rotated':
      return 'Plaka kenar istemcisi anahtarı yenilendi';
    case 'plate.edge_client_revoked':
      return 'Plaka kenar istemcisi kaldırıldı';
    case 'plate.inside_cleared':
      return 'İçerideki araç elle düşürüldü';
  }
  return null;
}

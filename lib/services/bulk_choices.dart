// Toplu yükleme seçim listeleri (İlişki, Borç Sorumlusu, Hesap): Excel şablonundaki açılır liste ve önizleme tablosundaki açılır liste AYNI kaynaktan
// gelir. Kaynak sunucudur (`GET imports/spec` sütunundaki `choices`); eski bir sunucu göndermezse aşağıdaki yedek sözlük kullanılır.
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';

/// Sunucu `choices` göndermezse kullanılan yedek listeler (sunucudaki RELATION_CHOICES / RESPONSIBLE_CHOICES / ACCOUNT_CHOICES ile aynı).
const Map<String, List<String>> kFallbackChoices = <String, List<String>>{
  'iliski': <String>['Malik', 'Kiracı', 'Aile Üyesi', 'Sakin'],
  'sorumlu': <String>['Malik', 'Kiracı', 'İkisi'],
  'hesap': <String>['Ev sahibi', 'Kiracı'],
};

/// Kanonik değer -> listedeki etiket (sunucunun relation_words / responsible_words anahtarları).
const Map<String, String> kRelationChoiceLabels = <String, String>{
  'owner': 'Malik',
  'tenant': 'Kiracı',
  'family_member': 'Aile Üyesi',
  'resident': 'Sakin',
};
const Map<String, String> kResponsibleChoiceLabels = <String, String>{
  'owner': 'Malik',
  'tenant': 'Kiracı',
  'both': 'İkisi',
};

/// «Hesap» sütunu için eşanlamlılar (sunucunun ACCOUNT_WORDS'ü; spec'te taşınmaz).
const Map<String, List<String>> _accountSynonyms = <String, List<String>>{
  'Ev sahibi': <String>['malik', 'mal sahibi', 'ev sahibi'],
  'Kiracı': <String>['kiraci'],
};

/// Sütunun seçim listesi (enum olmayan sütunda boş). Sunucu listesi öncelikli, yoksa yedek sözlük.
List<String> choicesFor(ImportColumn column) {
  if (column.type != ImportColumnType.enumeration) return const <String>[];
  if (column.choices.isNotEmpty) return column.choices;
  return kFallbackChoices[column.key] ?? const <String>[];
}

/// Hücredeki metni listedeki seçeneğe eşler: önce etiketin kendisi (Türkçe katlamalı), sonra sunucunun kabul ettiği eşanlamlılar (Eş, Çocuk, Mal sahibi ...).
/// Eşleşme yoksa null (örn. dosyada anlaşılmaz bir değer vardı; sunucu zaten satır hatası verir).
String? matchChoice(ImportKindSpec? spec, ImportColumn column, String text) {
  final folded = foldHeader(text);
  if (folded.isEmpty) return null;
  final choices = choicesFor(column);
  for (final choice in choices) {
    if (foldHeader(choice) == folded) return choice;
  }
  Map<String, List<String>>? words;
  Map<String, String>? labels;
  switch (column.key) {
    case 'iliski':
      words = spec?.relationWords;
      labels = kRelationChoiceLabels;
    case 'sorumlu':
      words = spec?.responsibleWords;
      labels = kResponsibleChoiceLabels;
    case 'hesap':
      for (final entry in _accountSynonyms.entries) {
        if (entry.value.any((word) => foldHeader(word) == folded) && choices.contains(entry.key)) return entry.key;
      }
      return null;
  }
  if (words == null || labels == null) return null;
  for (final entry in words.entries) {
    final label = labels[entry.key];
    if (label == null || !choices.contains(label)) continue;
    if (entry.value.any((word) => foldHeader(word) == folded)) return label;
  }
  return null;
}

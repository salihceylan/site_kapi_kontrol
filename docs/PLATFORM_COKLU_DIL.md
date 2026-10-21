# Çok dil altyapısı (S6)

- Paketler: `flutter_localizations` (SDK), `intl ^0.20.2` (flutter_localizations ile uyum için yükseltildi). `flutter: generate: true` + `l10n.yaml`; çıktı `lib/l10n/gen/` (flutter gen-l10n / derleme üretir).
- Metinler: `lib/l10n/app_tr.arb` (şablon) ve `app_en.arb`. Kapsam: giriş ekranı (kimlik, şifre, şifremi unuttum, giriş) ve yan menü (mod geçişi, yardım, çıkış). Diğer metinler toplu taşınmadı; yeni metinler önce ARB'ye eklenir.
- Kullanım: `context.l10n.anahtar` (`lib/services/locale_service.dart`). Yerelleştirme kapsamı yoksa (testler) Türkçe döner.
- Dil seçimi: Profilim'de "Dil" (Türkçe / English), `LocaleService` cihazda `app_locale` anahtarıyla saklar; varsayılan Türkçe. Sunucu tarafı değişikliği yok.
- Yakında: kalan ekranların taşınması, sunucu hata iletilerinin İngilizcesi.

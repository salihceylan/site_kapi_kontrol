import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Finans ayarlarının (`GET …/finance/settings`) tek yükleyicisi (Platform Faz 4b): site değişince yeni bir
/// denetleyici kurulur. Eski / yavaş yanıt yenisini ezmez (jeton); hata durumunda eski ayar KORUNMAZ (gecikme
/// tazminatı ve hatırlatma "açık" sanılmasın diye bilinmeyen = kullanılamaz).
class FinanceSettingsController extends ChangeNotifier {
  FinanceSettingsController(this.scope);

  final PeopleScope scope;

  FinanceSettings? settings;
  bool loading = false;
  String? error;
  bool _loadedOnce = false;
  bool _disposed = false;
  int _token = 0;

  bool get loadedOnce => _loadedOnce;

  Future<void> load() async {
    if (_disposed) return;
    final token = ++_token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await scope.f4Call((api, t, site) => api.getSettings(token: t, siteCode: site));
      if (_disposed || token != _token) return;
      settings = result;
      loading = false;
      _loadedOnce = true;
      notifyListeners();
    } catch (e) {
      if (_disposed || token != _token) return;
      settings = null;
      loading = false;
      error = financeMessageOf(e, 'Ayarlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      notifyListeners();
    }
  }

  /// Ayar penceresinden dönen güncel ayarı uygular.
  void apply(FinanceSettings next) {
    if (_disposed) return;
    ++_token;
    settings = next;
    loading = false;
    error = null;
    _loadedOnce = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_token;
    super.dispose();
  }
}

/// Özelliğin (gecikme tazminatı / hatırlatma) kullanılabilirlik durumu.
enum FeatureAvailability { loading, error, legalPending, disabled, ready }

/// Gecikme tazminatı için durum (sistem bayrağı `finance.legal_ok` VE site ayarı).
FeatureAvailability lateFeeAvailability(FinanceSettingsController c) {
  final s = c.settings;
  if (s == null) return c.error != null ? FeatureAvailability.error : FeatureAvailability.loading;
  if (s.lateFee.legalOk == false) return FeatureAvailability.legalPending;
  if (!s.lateFee.enabled) return FeatureAvailability.disabled;
  return FeatureAvailability.ready;
}

/// Borç hatırlatma için durum.
FeatureAvailability reminderAvailability(FinanceSettingsController c) {
  final s = c.settings;
  if (s == null) return c.error != null ? FeatureAvailability.error : FeatureAvailability.loading;
  if (s.reminders.legalOk == false) return FeatureAvailability.legalPending;
  if (!s.reminders.enabled) return FeatureAvailability.disabled;
  return FeatureAvailability.ready;
}

/// Kullanılamayan özellik için NEDENİ açıklayan pasif kart. "Hukuk onayı bekleniyor" yalnız sistem bayrağı kapalı
/// iken yazılır; hukuki içerik iddiası YOKTUR. Kapalı özellikte yazma yetkisi olana "Ayarlar" yolu gösterilir.
class FinanceFeatureGate extends StatelessWidget {
  const FinanceFeatureGate({
    super.key,
    required this.featureName,
    required this.availability,
    this.error,
    this.canWrite = false,
    this.onRetry,
    this.onOpenSettings,
    this.compact = false,
  });

  /// "Gecikme tazminatı" / "Borç hatırlatma".
  final String featureName;
  final FeatureAvailability availability;
  final String? error;
  final bool canWrite;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  /// true: büyük boş-durum kartı yerine tek satırlık bildirim (ana listenin üstünde yer kaplamasın). Metinler ve anahtarlar aynıdır.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact && (availability == FeatureAvailability.legalPending || availability == FeatureAvailability.disabled)) {
      return _buildCompact(context);
    }
    switch (availability) {
      case FeatureAvailability.loading:
        return const ListSkeleton(rows: 1);
      case FeatureAvailability.error:
        return InlineNotice(
          key: const ValueKey<String>('finance_feature_error'),
          message: error ?? '$featureName ayarları yüklenemedi.',
          onRetry: onRetry,
        );
      case FeatureAvailability.legalPending:
        return EmptyCard(
          key: const ValueKey<String>('finance_feature_legal'),
          icon: Icons.gavel_rounded,
          tone: AppTone.warning,
          title: 'Hukuk onayı bekleniyor',
          message:
              '$featureName, hukuki doğrulama tamamlanınca kullanıma açılır. Şimdilik bu özellik kullanılamıyor.',
        );
      case FeatureAvailability.disabled:
        return EmptyCard(
          key: const ValueKey<String>('finance_feature_disabled'),
          icon: Icons.toggle_off_rounded,
          tone: AppTone.neutral,
          title: '$featureName bu sitede kapalı',
          message: canWrite
              ? 'Kullanmak için Finans Ayarları bölümünden açın. İşlem her zaman önizleme ve onayla yapılır.'
              : 'Site yönetimi ayarlardan açtığında burada görünür.',
          child: canWrite && onOpenSettings != null
              ? PrimaryActionButton(
                  key: const ValueKey<String>('finance_feature_open_settings'),
                  label: 'Finans Ayarları',
                  icon: Icons.tune_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: onOpenSettings,
                )
              : null,
        );
      case FeatureAvailability.ready:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCompact(BuildContext context) {
    if (availability == FeatureAvailability.legalPending) {
      return _CompactGateNote(
        key: const ValueKey<String>('finance_feature_legal'),
        tone: AppTone.warning,
        icon: Icons.gavel_rounded,
        message: 'Hukuk onayı bekleniyor. $featureName, hukuki doğrulama tamamlanınca kullanıma açılır.',
      );
    }
    final canOpen = canWrite && onOpenSettings != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompactGateNote(
          key: const ValueKey<String>('finance_feature_disabled'),
          tone: AppTone.neutral,
          icon: Icons.toggle_off_rounded,
          message: canWrite
              ? '$featureName bu sitede kapalı. Kullanmak için Finans Ayarları bölümünden açın.'
              : '$featureName bu sitede kapalı. Site yönetimi ayarlardan açtığında burada görünür.',
        ),
        if (canOpen)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey<String>('finance_feature_open_settings'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Finans Ayarları'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
      ],
    );
  }
}

/// Tek satırlık pasif durum notu (hata bildirimi DEĞİL: "Tekrar Dene" yok); ana listenin üstünde az yer kaplar.
class _CompactGateNote extends StatelessWidget {
  const _CompactGateNote({super.key, required this.tone, required this.icon, required this.message});

  final AppTone tone;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Semantics(
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, color: tone.ink(p), size: 22)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(message, style: th.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

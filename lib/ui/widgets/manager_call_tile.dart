import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dial_call.dart';
import 'package:site_kapi_kontrol/ui/widgets/dial_fallback.dart';

/// "Yöneticiyi ara" metinleri (testler ve ekran okuyucu etiketleri tek kaynaktan).
abstract final class ManagerCallTexts {
  static const String title = 'Yöneticiyi ara';
  static const String noPhone = 'Telefon kayıtlı değil';
  static const String noPhoneMessage =
      'Bu sitenin yöneticisi henüz telefon numarası eklememiş. Numarayı eklediğinde bu kutudan arayabilirsiniz.';
  static const String hintCall = 'Telefon uygulamasını yönetici numarasıyla açar';
  static const String hintNoPhone = 'Yönetici telefonu kayıtlı değil; dokununca bunu söyler';
  static const String hintMany = 'Siteleri listeler; aramak istediğiniz sitenin yöneticisini seçersiniz';
}

Color _cardColor(AppPalette p) => p.isDark ? p.surface : AppShowcaseColors.card;
Color _cardBorder(AppPalette p) => p.isDark ? p.border : AppShowcaseColors.cardBorder;
Color _bodyInk(AppPalette p) => p.isDark ? p.textSecondary : AppShowcaseColors.text;

/// Sakin Panel'inin "Hızlı işlemler" ızgarasında "Yöneticiyi ara" kutusu ("dokun-ara", P2-23, karar K13).
///
/// Veri [contacts] (sunucu `GET /app/manager-contact`; kendi sitesinin yöneticisi olan satırlar ÇAĞIRANDA süzülür, bkz.
/// [ManagerCallTile.callable]):
/// - Tek site, telefon kayıtlı: dokununca telefon uygulaması yönetici numarasıyla açılır (kapı / para gibi bir işlem DEĞİL;
///   uygulama aramayı kendisi başlatmaz). Açılamazsa KURU MOD: numara alt sayfada büyük gösterilir ve kopyalanır.
/// - Tek site, telefon YOK: kutu görünür kalır ("Telefon kayıtlı değil"); dokununca nedeni söyler (ölü düğme yok).
/// - Birden çok site: dokununca siteler listelenir, her sitenin yöneticisi ayrı aranır.
///
/// Görünüm [_QuickTile] ile aynı dildedir (düz beyaz kart, ince çerçeve, gölge yok). Erişilebilirlik: tek düğüm; adı görünen
/// başlıktır ("Yöneticiyi ara" + alt satır), ipucu dokununca olanı söyler; dokunma hedefi >= 56 dp. Taşma: başlık ve alt satır
/// sarar (alt satır en çok 3 satır, sonra elips).
class ManagerCallTile extends StatelessWidget {
  const ManagerCallTile({super.key, required this.contacts, this.launcher});

  /// Çağıranın kendi sitesi olmayan, en az bir satır içeren liste (boşsa kutu çizilmez).
  final List<ManagerContact> contacts;

  /// Telefon uygulamasını açan işlev (varsayılan: `url_launcher`); testlerde sahte verilir.
  final DialLauncher? launcher;

  /// Çağıranın kendisi yönetici olduğu siteler kutuda yer almaz (kendini aramaz).
  static List<ManagerContact> callable(Iterable<ManagerContact> all) => <ManagerContact>[
    for (final c in all)
      if (!c.isSelf) c,
  ];

  static String? _dialableOf(ManagerContact c) => dialableNumber(c.phone);

  String get _subtitle {
    if (contacts.length > 1) return '${contacts.length} site';
    final c = contacts.single;
    if (_dialableOf(c) == null) return ManagerCallTexts.noPhone;
    return c.managerName ?? c.siteName;
  }

  String get _hint {
    if (contacts.length > 1) return ManagerCallTexts.hintMany;
    return _dialableOf(contacts.single) == null ? ManagerCallTexts.hintNoPhone : ManagerCallTexts.hintCall;
  }

  Future<void> _onTap(BuildContext context) async {
    if (contacts.length > 1) {
      await showManagerCallSheet(context, contacts: contacts, launcher: launcher);
      return;
    }
    final contact = contacts.single;
    final dialable = _dialableOf(contact);
    if (dialable == null) {
      AppSnack.show(context, ManagerCallTexts.noPhoneMessage, kind: AppSnackKind.info);
      announcePolite(context, ManagerCallTexts.noPhoneMessage);
      return;
    }
    final outcome = await dialPhone(dialable, launcher: launcher);
    if (outcome == DialOutcome.started || !context.mounted) return;
    await showDialFallbackSheet(
      context,
      heading: ManagerCallTexts.title,
      subtitle: contact.managerName ?? contact.siteName,
      dialable: dialable,
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(contacts.isNotEmpty, 'Boş listede kutu çizilmez');
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final subtitle = _subtitle;
    return Semantics(
      container: true,
      button: true,
      label: '${ManagerCallTexts.title}. $subtitle',
      hint: _hint,
      onTap: () => unawaited(_onTap(context)),
      excludeSemantics: true,
      child: Material(
        key: const ValueKey<String>('panel_hizli_yoneticiyiAra'),
        color: _cardColor(p),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: _cardBorder(p)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(_onTap(context)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                children: [
                  const IconOrb(icon: Icons.phone_in_talk_rounded, size: 40, shape: IconOrbShape.squircle),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ManagerCallTexts.title, style: th.titleMedium),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: th.bodySmall?.copyWith(color: _bodyInk(p)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Birden çok sitesi olan sakin için alt sayfa: her sitenin yöneticisi ve "Ara" düğmesi. Telefonu olmayan satırda düğme
/// yoktur, "Telefon kayıtlı değil" yazar. Arama açılamazsa sayfanın altında kuru mod kartı (numara + kopyala) görünür.
Future<void> showManagerCallSheet(
  BuildContext context, {
  required List<ManagerContact> contacts,
  DialLauncher? launcher,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _ManagerCallSheet(contacts: contacts, launcher: launcher),
  );
}

class _ManagerCallSheet extends StatefulWidget {
  const _ManagerCallSheet({required this.contacts, this.launcher});

  final List<ManagerContact> contacts;
  final DialLauncher? launcher;

  @override
  State<_ManagerCallSheet> createState() => _ManagerCallSheetState();
}

class _ManagerCallSheetState extends State<_ManagerCallSheet> {
  String? _fallbackNumber;

  Future<void> _call(ManagerContact contact) async {
    final dialable = dialableNumber(contact.phone);
    if (dialable == null) return;
    final outcome = await dialPhone(dialable, launcher: widget.launcher);
    if (!mounted) return;
    setState(() => _fallbackNumber = outcome == DialOutcome.started ? null : dialable);
    if (outcome == DialOutcome.started) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(ManagerCallTexts.title, style: th.titleLarge)),
            const SizedBox(height: AppSpace.xs),
            Text('Aramak istediğiniz sitenin yöneticisini seçin.', style: th.bodyMedium),
            const SizedBox(height: AppSpace.md),
            for (final contact in widget.contacts) ...[
              _SheetRow(contact: contact, onCall: () => unawaited(_call(contact))),
              Divider(height: AppSpace.lg, color: p.border),
            ],
            if (_fallbackNumber != null) ...[
              DialFallbackCard(dialable: _fallbackNumber!),
              const SizedBox(height: AppSpace.sm),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.contact, required this.onCall});

  final ManagerContact contact;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final callable = dialableNumber(contact.phone) != null;
    final who = callable ? (contact.managerName ?? 'Yönetici') : ManagerCallTexts.noPhone;
    final button = callable
        ? Semantics(
            button: true,
            label: '${contact.siteName} yöneticisini ara',
            onTap: onCall,
            excludeSemantics: true,
            child: OutlinedButton.icon(
              key: ValueKey<String>('yonetici_ara_${contact.siteCode}'),
              onPressed: onCall,
              icon: const Icon(Icons.call_rounded, size: 18),
              label: const Text('Ara'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          )
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(contact.siteName, style: th.titleMedium),
                Text(who, style: th.bodyMedium?.copyWith(color: callable ? p.textSecondary : p.textMuted)),
              ],
            ),
          ),
        ),
        if (button != null) ...[const SizedBox(width: AppSpace.md), button],
      ],
    );
  }
}

/// Site yöneticisinin Panel'inde "telefon ekleyin" ipucu ("dokun-ara", P2-23): profilinde telefon yoksa sakinler onu
/// "Yöneticiyi ara" ile arayamaz. Numaranın KİMLERE görüneceği açıkça yazılır (aydınlatma); numara yazılınca ipucu kalkar.
///
/// [onOpenProfile] verilirse "Profilim'e git" düğmesi çıkar (Profilim menüde yoksa düğme de yok). Taşma: metin sarar, düğme
/// alt satıra iner; dokunma hedefi >= 48 dp.
class ManagerPhoneHint extends StatelessWidget {
  const ManagerPhoneHint({super.key, this.onOpenProfile});

  final VoidCallback? onOpenProfile;

  static const String title = 'Telefon numaranızı ekleyin';
  static const String message =
      'Sakinler sizi tek dokunuşla arayabilsin diye profilinize telefon numaranızı yazın. Numara yalnızca sitenizdeki '
      'sakinlere, kurul üyelerine ve görevlilere "Yöneticiyi ara" kutusunda görünür.';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Semantics(
        container: true,
        child: DecoratedBox(
          key: const ValueKey<String>('panel_telefon_ipucu'),
          decoration: BoxDecoration(
            color: _cardColor(p),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: _cardBorder(p)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconOrb(icon: Icons.phone_in_talk_rounded, size: 40, shape: IconOrbShape.squircle),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Semantics(header: true, child: Text(title, style: th.titleMedium)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(message, style: th.bodyMedium?.copyWith(color: _bodyInk(p))),
                if (onOpenProfile != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton(
                      key: const ValueKey<String>('panel_telefon_ipucu_profil'),
                      onPressed: onOpenProfile,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                      child: const Text("Profilim'e git"),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart' show relationTone;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_household.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Daire halkının yükleme durumu. Daire satırı açılıp kapanınca bölüm ağaçtan çıkar; veri bu denetleyicide kalır
/// (yeniden açınca sunucuya tekrar gidilmez). [load] `force` ile yenilerken eski veri ekranda kalır.
class ApartmentHouseholdController extends ChangeNotifier {
  ApartmentHouseholdController(this._loader);

  final Future<ApartmentHousehold> Function() _loader;

  ApartmentHousehold? data;
  String? error;
  bool loading = false;
  bool _disposed = false;

  Future<void> load({bool force = false}) async {
    if (loading || (data != null && !force)) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _loader();
      data = result;
    } catch (e) {
      error = crmMessageOf(e, 'Daire sakinleri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Site Yönetimi > Daireler: dairenin sakinleri. Üstte DAİRE ADMİNİ, altında "Aile üyeleri (N)" AKORDİYONU.
/// Kiracı oturan dairede malik admin değilse "Malik (oturmuyor)" ayrı satırdır.
///
/// Kurul üyesi için sunucu yalnız ad + ilişki gönderir ([ApartmentHousehold.isDetailed] false): telefon, çocuk, hesap durumu
/// ve erişim askısı çizilmez. Kişi satırına dokununca [onOpenPerson] (kişi kartı) çağrılır; dönünce liste yenilenir.
class ApartmentHouseholdSection extends StatefulWidget {
  const ApartmentHouseholdSection({
    super.key,
    required this.controller,
    this.onOpenPerson,
    this.onProvisionAccount,
    this.onResetPin,
    this.initiallyExpanded = false,
  });

  final ApartmentHouseholdController controller;

  /// Kişi kartını açar (kişi numarası olan satırlarda).
  final Future<void> Function(HouseholdPerson person)? onOpenPerson;

  /// Kişiye hesap tanımlar (kullanıcı adı ve geçici şifre).
  final Future<void> Function(HouseholdPerson person)? onProvisionAccount;

  /// Kişinin geçici şifresini / PIN'ini sıfırlar.
  final Future<void> Function(HouseholdPerson person)? onResetPin;

  /// Aile üyeleri akordiyonu ilk çizimde açık mı (varsayılan kapalı).
  final bool initiallyExpanded;

  @override
  State<ApartmentHouseholdSection> createState() => _ApartmentHouseholdSectionState();
}

class _ApartmentHouseholdSectionState extends State<ApartmentHouseholdSection> {
  late bool _familyOpen = widget.initiallyExpanded;

  ApartmentHouseholdController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    _loadAfterFrame();
  }

  /// Yükleme çizim aşamasının dışında başlar (denetleyici dinleyicileri çizim sırasında setState çağırmasın).
  void _loadAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.load();
    });
  }

  @override
  void didUpdateWidget(ApartmentHouseholdSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _loadAfterFrame();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open(HouseholdPerson person) async {
    final open = widget.onOpenPerson;
    if (open == null || person.personId == null) return;
    await open(person);
    if (mounted) await _c.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final data = _c.data;
    final Widget body;
    if (data == null) {
      body = _c.error != null
          ? InlineNotice(message: _c.error!, onRetry: () => _c.load(force: true))
          : const ListSkeleton(rows: 2, inCard: true);
    } else {
      body = _buildData(context, data);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.groups_2_rounded, size: 18, color: p.textSecondary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text('Daire sakinleri', style: th.titleSmall?.copyWith(color: p.text)),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        body,
        if (data != null && _c.error != null) ...[
          const SizedBox(height: AppSpace.sm),
          InlineNotice(message: _c.error!, onRetry: () => _c.load(force: true)),
        ],
      ],
    );
  }

  Widget _buildData(BuildContext context, ApartmentHousehold data) {
    final admin = data.admin;
    final absent = data.absentOwner;
    final members = data.members;
    final detailed = data.isDetailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _caption(context, 'Daire admini'),
        if (admin != null)
          _PersonRow(
            person: admin,
            detailed: detailed,
            isAdminRow: true,
            onTap: widget.onOpenPerson == null || admin.personId == null ? null : () => _open(admin),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Text(
              data.total == 0 ? 'Bu dairede kayıtlı kişi yok.' : 'Bu dairede daire admini görünmüyor.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTone.warning.ink(context.palette)),
            ),
          ),
        if (absent != null) ...[
          const SizedBox(height: AppSpace.sm),
          _caption(context, 'Malik (oturmuyor)'),
          _PersonRow(
            person: absent,
            detailed: detailed,
            onTap: widget.onOpenPerson == null || absent.personId == null ? null : () => _open(absent),
            onProvisionAccount: widget.onProvisionAccount == null || absent.personId == null ? null : () => widget.onProvisionAccount!(absent),
            onResetPin: widget.onResetPin == null || absent.personId == null ? null : () => widget.onResetPin!(absent),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        _buildFamily(context, members, detailed),
      ],
    );
  }

  Widget _caption(BuildContext context, String text) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: p.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// "Aile üyeleri (N)" akordiyonu: başlık 48 dp dokunma hedefi; içerik [ExpandableSection] (hareket azaltmada anında).
  Widget _buildFamily(BuildContext context, List<HouseholdPerson> members, bool detailed) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final hasMembers = members.isNotEmpty;
    final title = 'Aile üyeleri (${members.length})';
    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: th.titleSmall?.copyWith(color: p.text)),
          ),
          if (hasMembers) ExpandChevron(expanded: _familyOpen),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMembers)
            Semantics(
              button: true,
              expanded: _familyOpen,
              label: title,
              excludeSemantics: true,
              onTap: () => setState(() => _familyOpen = !_familyOpen),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => setState(() => _familyOpen = !_familyOpen),
                child: header,
              ),
            )
          else
            header,
          if (!hasMembers)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text('Aile üyesi kaydı yok.', style: th.bodyMedium?.copyWith(color: p.textSecondary)),
            )
          else
            ExpandableSection(
              expanded: _familyOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < members.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PersonRow(
                      person: members[i],
                      detailed: detailed,
                      onTap: widget.onOpenPerson == null || members[i].personId == null
                          ? null
                          : () => _open(members[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bir kişi satırı: ad, ilişki / rol çipleri, (yönetici için) telefon ve hesap durumu. Satır >= 48 dp, metin sarar.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.detailed,
    this.isAdminRow = false,
    this.onTap,
    this.onProvisionAccount,
    this.onResetPin,
  });

  final HouseholdPerson person;
  final bool detailed;
  final bool isAdminRow;
  final VoidCallback? onTap;
  final VoidCallback? onProvisionAccount;
  final VoidCallback? onResetPin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final phone = detailed ? person.phone : null;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (isAdminRow)
                        const StatusChip(
                          label: 'Admin',
                          tone: AppTone.warning,
                          icon: Icons.shield_rounded,
                        ),
                      // Kurulda çocuk ayrımı gösterilmez (yaş bilgisi yönetime özeldir): [isMinor] yalnız ayrıntılı yanıtta dolu gelir.
                      if (relationTone(person.relation) != null)
                        StatusChip(
                          label: person.relationLabel,
                          tone: relationTone(person.relation)!,
                        )
                      else
                        InfoChip(person.relationLabel),
                      if (detailed && person.accessSuspended)
                        const StatusChip(
                          label: 'Erişim askıda',
                          tone: AppTone.warning,
                          icon: Icons.lock_outline_rounded,
                        ),
                      if (detailed)
                        person.hasAccount
                            ? const StatusChip(label: 'Hesabı var', tone: AppTone.success)
                            : const InfoChip('Hesapsız'),
                    ],
                  ),
                  if (phone != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(phone, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.sm, top: AppSpace.xs),
                child: ExcludeSemantics(
                  child: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'Kişi kartını aç: ${person.name}, ${person.relationLabel}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.sm), onTap: onTap, child: content),
    );
  }
}

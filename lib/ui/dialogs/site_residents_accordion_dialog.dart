import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_residents_tree_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class SiteResidentsAccordionDialog extends StatefulWidget {
  const SiteResidentsAccordionDialog({
    super.key,
    required this.site,
    required this.authService,
  });

  final SiteRecord site;
  final AuthService authService;

  static Future<void> show(
    BuildContext context, {
    required SiteRecord site,
    required AuthService authService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SiteResidentsAccordionDialog(
        site: site,
        authService: authService,
      ),
    );
  }

  @override
  State<SiteResidentsAccordionDialog> createState() => _SiteResidentsAccordionDialogState();
}

class _SiteResidentsAccordionDialogState extends State<SiteResidentsAccordionDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  SiteResidentsTreeData? _treeData;
  String _searchQuery = '';
  // Arama süzmesi yazma durunca uygulanır: her tuş vuruşunda yüzlerce sakin kartının tamamını
  // yeniden kurmak (büyük sitelerde saniyeler) yerine hızlı yazımda tek yeniden kurma yapılır.
  static const Duration _searchDebounce = Duration(milliseconds: 220);
  Timer? _searchDebounceTimer;
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _busyMemberCodes = {};
  bool _expandAll = true;
  String _activeFilter = 'ALL'; // 'ALL', 'OCCUPIED', 'EMPTY'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (data, error) = await widget.authService.getSiteResidentsTree(widget.site.id);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (error != null) {
        _errorMessage = error;
      } else {
        _treeData = data;
      }
    });
  }

  Future<void> _toggleMemberStatus(SiteResidentApartment apt, SiteResidentMember resident) async {
    final nextStatus = !resident.isActive;
    final actionLabel = nextStatus ? 'Aktif Et' : 'Pasife Al';
    final actionTone = nextStatus ? AppTone.success : AppTone.warning;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Üyeliği $actionLabel',
        icon: nextStatus
            ? Icons.check_circle_outline_rounded
            : Icons.pause_circle_outline_rounded,
        tone: actionTone,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: actionTone.a,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
        // Burada yalnız daire üyeliği / kapı erişimi yönetilir; kullanıcının hesabını (giriş yetkisi)
        // sistem yöneticisi yönetir.
        child: Text(
          nextStatus
              ? '${resident.fullName} (${apt.unitLabel}) adlı sakinin daire üyeliğini ve kapı erişimini aktif etmek istiyor musunuz? Sakin bu dairenin kapı erişimlerini tekrar kullanabilecektir.'
              : '${resident.fullName} (${apt.unitLabel}) adlı sakinin daire üyeliğini pasife almak istiyor musunuz? Sakinin bu dairedeki kapı erişimi geçici olarak durdurulacaktır. Kullanıcının hesabı etkilenmez.',
        ),
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _busyMemberCodes.add(resident.userCode));
    final (success, msg) = await widget.authService.toggleApartmentMemberStatus(
      apartmentId: apt.id,
      targetUserCode: resident.userCode,
      isActive: nextStatus,
    );
    if (!mounted) return;
    setState(() => _busyMemberCodes.remove(resident.userCode));

    AppSnack.show(
      context,
      msg ?? (success ? 'Durum güncellendi.' : 'İşlem başarısız.'),
      kind: success ? AppSnackKind.success : AppSnackKind.error,
    );

    if (success) {
      _loadData();
    }
  }

  Future<void> _deleteMember(SiteResidentApartment apt, SiteResidentMember resident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Sakini Daireden Sil',
        icon: Icons.delete_forever_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTone.danger.a,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Daireden Sil'),
          ),
        ],
        child: Text(
          '${resident.fullName} (${apt.unitLabel}) adlı sakini bu daireden tamamen silmek istediğinize emin misiniz?\n\nBu işlem sonucunda sakinin daire üyeliği ve tüm kapı yetkileri kalıcı olarak silinecektir. Bu işlem geri alınamaz.',
        ),
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _busyMemberCodes.add(resident.userCode));
    final (success, msg) = await widget.authService.deleteApartmentMember(
      apartmentId: apt.id,
      targetUserCode: resident.userCode,
    );
    if (!mounted) return;
    setState(() => _busyMemberCodes.remove(resident.userCode));

    AppSnack.show(
      context,
      msg ?? (success ? 'Sakin silindi.' : 'İşlem başarısız.'),
      kind: success ? AppSnackKind.success : AppSnackKind.error,
    );

    if (success) {
      _loadData();
    }
  }


  Future<void> _setPrimaryAdmin(SiteResidentApartment apt, SiteResidentMember resident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Aile Reisi Yap',
        icon: Icons.star_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTone.warning.a,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Aile Reisi Yap'),
          ),
        ],
        child: Text(
          '${resident.fullName} (${apt.unitLabel}) adlı sakini dairenin yeni Aile Reisi (Daire Yöneticisi) yapmak istediğinize emin misiniz?\n\nMevcut daire yöneticisinin rolü standart aile üyesine dönüştürülecektir.',
        ),
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _busyMemberCodes.add(resident.userCode));
    final (success, msg) = await widget.authService.setApartmentPrimaryAdmin(
      apartmentId: apt.id,
      targetUserCode: resident.userCode,
    );
    if (!mounted) return;
    setState(() => _busyMemberCodes.remove(resident.userCode));

    AppSnack.show(
      context,
      msg ?? (success ? 'Aile reisi güncellendi.' : 'İşlem başarısız.'),
      kind: success ? AppSnackKind.success : AppSnackKind.error,
    );

    if (success) {
      _loadData();
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnack.show(
      context,
      '$label panoya kopyalandı: $text',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: ConstrainedBox(
        // Yükseklik üst sınırı: en az 760, büyük ekranda ekranın %96'sı (uzun sakin listeleri için).
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: math.max(760.0, MediaQuery.sizeOf(context).height * 0.96),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (başlık şeridi + sağ üstte kapatma; başlık düğmenin altına girmesin diye sağdan pay)
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 32),
                  child: AppDialogHeader(
                    title: widget.site.name,
                    icon: Icons.account_tree_rounded,
                  ),
                ),
                PositionedDirectional(
                  top: AppSpace.sm,
                  end: AppSpace.sm,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Kapat',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),

            // Kaydırılan alan: sayılar + arama + süzgeç + liste (büyük yazıda başlık sabit kalır)
            Expanded(
              child: CustomScrollView(
                slivers: _buildSlivers(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Site sayıları + yenile, arama alanı, süzgeç çipleri ve daralt/genişlet (kaydırılan alanın başı).
  Widget _buildHeadSliver() {
    final p = context.palette;
    final site = _treeData?.site;
    final totalResidents = site?.totalResidents ?? 0;
    final totalApts = site?.totalApartments ?? 0;
    final totalBlocks = site?.totalBlocks ?? 0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildStatBadge('$totalBlocks Blok', AppTone.primary),
                      _buildStatBadge('$totalApts Daire', AppTone.info),
                      _buildStatBadge('$totalResidents Sakin', AppTone.success),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Yenile',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: _isLoading ? null : _loadData,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Sakin adı, telefon, e-posta veya daire ara...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: _clearSearch,
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildFilterChip('Tümü', 'ALL'),
                  _buildFilterChip('Dolu Daireler', 'OCCUPIED'),
                  _buildFilterChip('Boş Daireler', 'EMPTY'),
                  TextButton.icon(
                    onPressed: () => setState(() => _expandAll = !_expandAll),
                    icon: Icon(
                      _expandAll ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                      size: 16,
                    ),
                    label: Text(_expandAll ? 'Daralt' : 'Genişlet'),
                    style: TextButton.styleFrom(
                      foregroundColor: p.textSecondary,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final p = context.palette;
    final isSelected = _activeFilter == value;
    final accent = AppTone.primary.ink(p);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: AppTone.primary.tint(p),
      side: BorderSide(color: isSelected ? accent : p.border),
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? accent : p.textSecondary,
      ),
      onSelected: (_) => setState(() => _activeFilter = value),
    );
  }

  Widget _buildStatBadge(String text, AppTone tone) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.tint(p),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.hue.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: tone.ink(p),
        ),
      ),
    );
  }

  /// Parça sırası: hata kutusu EN ÜSTTE (büyük yazıda kaydırmadan görünsün); yükleniyor/boş
  /// durumları sayı/arama alanının altında; liste de onun altında.
  List<Widget> _buildSlivers() {
    final th = Theme.of(context).textTheme;
    final head = _buildHeadSliver();

    if (_isLoading) {
      return [
        head,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Sakinler ve daireler yükleniyor...',
                    style: th.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (_errorMessage != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: InlineNotice(message: _errorMessage!, onRetry: _loadData),
          ),
        ),
        head,
      ];
    }

    final blocks = _treeData?.blocks ?? [];
    if (blocks.isEmpty) {
      return [
        head,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.account_tree_rounded,
              title: 'Bu sitede henüz tanımlı blok veya daire kaydı bulunmuyor.',
            ),
          ),
        ),
      ];
    }

    return [
      head,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        sliver: SliverList.builder(
          itemCount: blocks.length,
          itemBuilder: (ctx, index) {
            final block = blocks[index];
            return _buildBlockAccordion(block);
          },
        ),
      ),
    ];
  }

  Widget _buildBlockAccordion(SiteResidentBlock block) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    // Filter apartments according to search & filter chip
    final filteredApartments = block.apartments.where((apt) {
      if (_activeFilter == 'OCCUPIED' && apt.isEmpty) return false;
      if (_activeFilter == 'EMPTY' && !apt.isEmpty) return false;

      if (_searchQuery.isEmpty) return true;
      final aptMatches = apt.unitLabel.toLowerCase().contains(_searchQuery);
      final residentMatches = apt.residents.any((r) =>
          r.fullName.toLowerCase().contains(_searchQuery) ||
          (r.phoneNumber != null && r.phoneNumber!.toLowerCase().contains(_searchQuery)) ||
          (r.email != null && r.email!.toLowerCase().contains(_searchQuery)) ||
          (r.loginName != null && r.loginName!.toLowerCase().contains(_searchQuery)));

      return aptMatches || residentMatches;
    }).toList();

    if (_searchQuery.isNotEmpty && filteredApartments.isEmpty) {
      return const SizedBox.shrink();
    }

    final blockResidentsCount = filteredApartments.fold<int>(0, (sum, a) => sum + a.totalResidents);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: PageStorageKey('block_${block.id}_$_expandAll'),
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _expandAll,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTone.primary.tint(p),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.domain_rounded,
                color: AppTone.primary.ink(p),
                size: 22,
              ),
            ),
            title: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  block.blockName,
                  style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTone.success.tint(p),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$blockResidentsCount Sakin • ${filteredApartments.length} Daire',
                    style: th.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTone.success.ink(p),
                    ),
                  ),
                ),
              ],
            ),
            children: [
              if (filteredApartments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Bu blokta seçilen filtreye uygun daire bulunamadı.',
                    style: th.bodySmall,
                  ),
                )
              else
                for (final apt in filteredApartments) _buildApartmentAccordion(apt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApartmentAccordion(SiteResidentApartment apt) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final hasResidents = apt.residents.isNotEmpty;
    final aptTone = hasResidents ? AppTone.success : AppTone.warning;

    return Container(
      key: PageStorageKey('apt_${apt.id}_$_expandAll'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasResidents ? p.border : AppTone.warning.hue.withValues(alpha: 0.5),
          width: 0.9,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.transparent,
          child: ExpansionTile(
            initiallyExpanded: _expandAll && hasResidents,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            leading: Icon(
              hasResidents ? Icons.door_front_door_rounded : Icons.door_sliding_outlined,
              size: 20,
              color: hasResidents ? AppTone.primary.ink(p) : AppTone.warning.ink(p),
            ),
            title: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  apt.unitLabel,
                  style: th.titleMedium,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: aptTone.tint(p),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    hasResidents ? '${apt.residents.length} Sakin' : 'Boş Daire',
                    style: th.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: aptTone.ink(p),
                    ),
                  ),
                ),
              ],
            ),
            children: [
              if (!hasResidents)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: InlineNotice(
                    tone: AppTone.warning,
                    icon: Icons.info_outline_rounded,
                    message: 'Bu daireye henüz kayıtlı veya onaylanmış sakin bulunmuyor.',
                  ),
                )
              else
                for (final resident in apt.residents) _buildResidentCard(apt, resident),
            ],
          ),
        ),
      ),
    );
  }

  /// Telefon / e-posta satırı: dokununca panoya kopyalar (aynı işlemler kart menüsünde 48 dp'lik
  /// öğelerle de vardır; bu satır yoğun listede yer kazanmak için kompakttır).
  Widget _buildCopyRow(IconData icon, String text, String label, {required bool link}) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => _copyToClipboard(text, label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: p.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: th.bodySmall?.copyWith(
                  color: link ? AppTone.primary.ink(p) : p.textSecondary,
                  fontWeight: link ? FontWeight.w500 : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy_rounded, size: 11, color: p.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildResidentCard(
    SiteResidentApartment apt,
    SiteResidentMember resident,
  ) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isBusy = _busyMemberCodes.contains(resident.userCode);
    final inactive = !resident.isActive;
    final roleTone = inactive
        ? AppTone.neutral
        : (resident.isAdmin ? AppTone.warning : AppTone.violet);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border, width: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: roleTone.tint(p),
            child: Icon(
              inactive
                  ? Icons.person_off_rounded
                  : (resident.isAdmin ? Icons.star_rounded : Icons.person_rounded),
              size: 16,
              color: roleTone.ink(p),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      resident.fullName,
                      style: th.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: inactive ? p.textSecondary : p.text,
                        decoration: inactive ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: roleTone.tint(p),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        resident.roleLabel,
                        style: th.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: roleTone.ink(p),
                        ),
                      ),
                    ),
                    if (!resident.isActive || !resident.accountIsActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppTone.danger.tint(p),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          resident.accountIsActive ? 'İnaktif' : 'Hesap pasif (sistem yöneticisi)',
                          style: th.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTone.danger.ink(p),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                if (resident.phoneNumber != null && resident.phoneNumber!.isNotEmpty)
                  _buildCopyRow(Icons.phone_rounded, resident.phoneNumber!, 'Telefon', link: true),
                if (resident.email != null && resident.email!.isNotEmpty)
                  _buildCopyRow(Icons.email_outlined, resident.email!, 'E-posta', link: false),
              ],
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: p.textSecondary,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (action) {
                if (action == 'toggle_status') {
                  _toggleMemberStatus(apt, resident);
                } else if (action == 'set_admin') {
                  _setPrimaryAdmin(apt, resident);
                } else if (action == 'delete') {
                  _deleteMember(apt, resident);
                } else if (action == 'copy_phone' && resident.phoneNumber != null) {
                  _copyToClipboard(resident.phoneNumber!, 'Telefon');
                } else if (action == 'copy_email' && resident.email != null) {
                  _copyToClipboard(resident.email!, 'E-posta');
                }
              },
              itemBuilder: (ctx) => [
                if (!resident.accountIsActive)
                  // Hesap sistem yöneticisi tarafından pasife alınmış: üyelik işlemi giriş ve kapı
                  // erişimini açmaz, bu yüzden işlem yerine bilgi gösterilir.
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Hesap sistem yöneticisi tarafından pasife alındı. Giriş ve kapı erişimi hesap aktif edilene kadar kapalıdır.',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  PopupMenuItem<String>(
                    value: 'toggle_status',
                    child: Row(
                      children: [
                        Icon(
                          resident.isActive ? Icons.pause_circle_outline_rounded : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: resident.isActive ? AppTone.warning.ink(p) : AppTone.success.ink(p),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            resident.isActive ? 'Üyeliği Pasife Al' : 'Üyeliği Aktif Et',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: resident.isActive ? AppTone.warning.ink(p) : AppTone.success.ink(p),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!resident.isAdmin)
                  PopupMenuItem(
                    value: 'set_admin',
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, size: 16, color: AppTone.warning.ink(p)),
                        const SizedBox(width: 8),
                        const Flexible(child: Text('Aile Reisi Yap', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                if (resident.phoneNumber != null)
                  const PopupMenuItem(
                    value: 'copy_phone',
                    child: Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 16),
                        SizedBox(width: 8),
                        Flexible(child: Text('Numarayı Kopyala', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                if (resident.email != null)
                  const PopupMenuItem(
                    value: 'copy_email',
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined, size: 16),
                        SizedBox(width: 8),
                        Flexible(child: Text('E-postayı Kopyala', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever_rounded, size: 16, color: AppTone.danger.ink(p)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Daireden Sil',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTone.danger.ink(p)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

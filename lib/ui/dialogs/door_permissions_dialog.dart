import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_permission_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class DoorPermissionsDialog extends StatefulWidget {
  const DoorPermissionsDialog({
    super.key,
    required this.door,
    required this.authService,
  });

  final DoorRecord door;
  final AuthService authService;

  static Future<void> show(
    BuildContext context, {
    required DoorRecord door,
    required AuthService authService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DoorPermissionsDialog(
        door: door,
        authService: authService,
      ),
    );
  }

  @override
  State<DoorPermissionsDialog> createState() => _DoorPermissionsDialogState();
}

class _DoorPermissionsDialogState extends State<DoorPermissionsDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  DoorPermissionsData? _data;
  final Set<int> _busyUserCodes = {};
  final Set<int> _busyBlockIds = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (data, error) = await widget.authService.getDoorPermissions(widget.door.id);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (error != null) {
        _errorMessage = error;
      } else {
        _data = data;
      }
    });
  }

  /// Sakinin bu kapıda (ek izin/engel kaydı yokken) varsayılan erişimi olup olmadığı:
  /// ortak kapı tüm sakinlere, blok kapısı yalnız kendi bloğunun sakinlerine açıktır.
  bool _hasDefaultAccess(DoorResidentPermission resident) {
    final data = _data;
    if (data == null) return false;
    final door = data.door;
    if (door.isSiteCommon) return true;
    if (!door.isBlockScope || door.blockId == null) return false;
    return data.blocks.any(
      (block) =>
          block.id == door.blockId &&
          block.apartments.any(
            (apt) => apt.residents.any((r) => r.userCode == resident.userCode),
          ),
    );
  }

  Future<void> _toggleResidentAccess(DoorResidentPermission resident) async {
    setState(() => _busyUserCodes.add(resident.userCode));

    // Anahtara dokunmak görünen durumun TERSİNİ üretmelidir: ek izin/engel kaydı varsayılanla
    // aynı sonucu veriyorsa kaydı silmek anahtarı değiştirmez, bu yüzden açıkça tersi yazılır.
    bool? targetAllowed;
    if (resident.isNoAccess) {
      targetAllowed = true;
    } else if (resident.isOverrideAllowed) {
      // Varsayılan erişimi yoksa kaydı silmek erişimi kapatır; varsa açıkça engellenmelidir.
      targetAllowed = _hasDefaultAccess(resident) ? false : null;
    } else if (resident.isOverrideDenied) {
      // Varsayılan erişimi varsa kaydı silmek erişimi açar; yoksa açıkça izin verilmelidir.
      targetAllowed = _hasDefaultAccess(resident) ? null : true;
    } else {
      // It's SITE_COMMON or BLOCK_DEFAULT
      targetAllowed = false; // Deny
    }

    final (success, message) = await widget.authService.setDoorAccessOverride(
      doorId: widget.door.id,
      userCode: resident.userCode,
      isAllowed: targetAllowed,
    );

    if (!mounted) return;
    setState(() => _busyUserCodes.remove(resident.userCode));

    if (success) {
      AppSnack.show(
        context,
        message ?? 'Yetki güncellendi.',
        kind: AppSnackKind.success,
        duration: const Duration(seconds: 2),
      );
      _loadPermissions();
    } else {
      AppSnack.show(
        context,
        message ?? 'Yetki güncellenemedi.',
        kind: AppSnackKind.error,
      );
    }
  }

  Future<void> _applyBulkBlockAccess(DoorBlockPermission block, bool? isAllowed) async {
    setState(() => _busyBlockIds.add(block.id));

    final (success, message) = await widget.authService.setBulkDoorAccessOverride(
      doorId: widget.door.id,
      blockId: block.id,
      isAllowed: isAllowed,
    );

    if (!mounted) return;
    setState(() => _busyBlockIds.remove(block.id));

    if (success) {
      AppSnack.show(
        context,
        message ?? 'Toplu işlem uygulandı.',
        kind: AppSnackKind.success,
        duration: const Duration(seconds: 2),
      );
      _loadPermissions();
    } else {
      AppSnack.show(
        context,
        message ?? 'Toplu işlem başarısız.',
        kind: AppSnackKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Büyük yazıda sabit başlık küçülür: alt başlık ve kapsam rozeti kaydırılan alanın başına taşınır.
    final compactHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        // Yükseklik üst sınırı: en az 720, büyük ekranda ekranın %90'ı (uzun sakin listeleri için).
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: math.max(720.0, MediaQuery.sizeOf(context).height * 0.9),
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
                    title: widget.door.doorName,
                    subtitle: compactHeader ? null : 'Kapı Yetki Yönetimi & Toplu Yetkilendirme',
                    icon: Icons.vpn_key_rounded,
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
            if (!compactHeader) _buildScopeChipRow(),
            const Divider(height: 1),

            // Kaydırılan alan: kapsam bilgisi + arama + liste (büyük yazıda başlık sabit kalır, geri kalan kayar)
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

  /// Kapsam rozeti (kapı kapsamı etiketi): sabit başlığın altında; büyük yazıda kaydırılan alanda.
  Widget _buildScopeChipRow() {
    final blockTone = widget.door.isBlockScope ? AppTone.info : AppTone.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.md),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: StatusChip(
          label: widget.door.accessScopeLabel,
          tone: blockTone,
        ),
      ),
    );
  }

  /// Kapsam bilgisi + arama alanı + yenile düğmesi (kaydırılan alanın başı).
  Widget _buildHeadSliver() {
    final compactHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(
          children: [
            if (compactHeader) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Kapı Yetki Yönetimi & Toplu Yetkilendirme',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusChip(
                  label: widget.door.accessScopeLabel,
                  tone: widget.door.isBlockScope ? AppTone.info : AppTone.primary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            _buildScopeInfoBanner(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Sakin veya daire ara...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Yenile',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: _isLoading ? null : _loadPermissions,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeInfoBanner() {
    final door = _data?.door;
    String infoText;
    IconData icon;
    AppTone tone;

    if (door?.isSiteCommon ?? widget.door.isSiteCommon) {
      infoText = 'Ortak Kapı: Sitedeki tüm sakinler varsayılan olarak yetkilidir. Gerekirse belirli kişileri engelleyebilirsiniz.';
      icon = Icons.public_rounded;
      tone = AppTone.success;
    } else if (door?.isBlockScope ?? widget.door.isBlockScope) {
      final bName = door?.blockName ?? 'Kendi Bloğu';
      infoText = '$bName Kapısı: Yalnızca $bName sakinleri varsayılan olarak yetkilidir. Diğer bloklara ek yetki verebilirsiniz.';
      icon = Icons.domain_rounded;
      tone = AppTone.info;
    } else {
      infoText = 'Özel Yetkilendirme: Bu kapı varsayılan olarak kapalıdır. Yalnızca yetki verdiğiniz sakinler açabilir.';
      icon = Icons.lock_clock_rounded;
      tone = AppTone.warning;
    }

    return InlineNotice(tone: tone, icon: icon, message: infoText);
  }

  /// Durum parçaları sırası: hata kutusu EN ÜSTTE (büyük yazıda kaydırmadan görünsün); yükleniyor/boş
  /// durumları kapsam bilgisi + aramanın altında; liste de aramanın altında.
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
                  Text('Kapı yetkileri yükleniyor...', style: th.bodyMedium, textAlign: TextAlign.center),
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
            child: InlineNotice(message: _errorMessage!, onRetry: _loadPermissions),
          ),
        ),
        head,
      ];
    }

    final blocks = _data?.blocks ?? [];
    if (blocks.isEmpty) {
      return [
        head,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.apartment_rounded,
              title: 'Bu sitede kayıtlı blok veya sakin bulunamadı.',
            ),
          ),
        ),
      ];
    }

    return [
      head,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
        sliver: SliverList.builder(
          itemCount: blocks.length,
          itemBuilder: (ctx, index) {
            final block = blocks[index];
            return _buildBlockCard(block);
          },
        ),
      ),
    ];
  }

  Widget _buildBlockCard(DoorBlockPermission block) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isBlockBusy = _busyBlockIds.contains(block.id);

    // Filter apartments and residents based on search query
    final filteredApartments = block.apartments.where((apt) {
      if (_searchQuery.isEmpty) return true;
      final aptMatches = apt.doorNumber.toLowerCase().contains(_searchQuery);
      final resMatches = apt.residents.any((r) =>
          r.fullName.toLowerCase().contains(_searchQuery) ||
          (r.phone != null && r.phone!.toLowerCase().contains(_searchQuery)) ||
          (r.email != null && r.email!.toLowerCase().contains(_searchQuery)));
      return aptMatches || resMatches;
    }).toList();

    if (_searchQuery.isNotEmpty && filteredApartments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTone.primary.tint(p),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.domain_rounded,
              color: AppTone.primary.ink(p),
              size: 20,
            ),
          ),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                block.blockName,
                style: th.titleMedium,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTone.success.tint(p),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${block.allowedResidentsCount}/${block.totalResidents} Yetkili',
                  style: th.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTone.success.ink(p),
                  ),
                ),
              ),
            ],
          ),
          trailing: isBlockBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: p.textSecondary),
                  tooltip: 'Bloğa Toplu İşlem',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (action) {
                    if (action == 'grant_all') {
                      _applyBulkBlockAccess(block, true);
                    } else if (action == 'reset_all') {
                      _applyBulkBlockAccess(block, null);
                    } else if (action == 'deny_all') {
                      _applyBulkBlockAccess(block, false);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'grant_all',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 18, color: AppTone.success.ink(p)),
                          const SizedBox(width: 8),
                          const Flexible(child: Text('Tüm Bloğa Yetki Ver')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reset_all',
                      child: Row(
                        children: [
                          Icon(Icons.restart_alt_rounded, size: 18, color: AppTone.info.ink(p)),
                          const SizedBox(width: 8),
                          const Flexible(child: Text('Bloğun Yetkilerini Sıfırla')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'deny_all',
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded, size: 18, color: AppTone.danger.ink(p)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Tüm Bloğu Engelle',
                              style: TextStyle(color: AppTone.danger.ink(p)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          children: [
            if (filteredApartments.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Bu blokta kayıtlı daire bulunmuyor.',
                  style: th.bodySmall,
                ),
              )
            else
              for (final apt in filteredApartments) _buildApartmentSection(apt),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildApartmentSection(DoorApartmentPermission apt) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    // Filter residents by search query if applicable
    final residents = apt.residents.where((r) {
      if (_searchQuery.isEmpty) return true;
      return apt.doorNumber.toLowerCase().contains(_searchQuery) ||
          r.fullName.toLowerCase().contains(_searchQuery) ||
          (r.phone != null && r.phone!.toLowerCase().contains(_searchQuery)) ||
          (r.email != null && r.email!.toLowerCase().contains(_searchQuery));
    }).toList();

    if (residents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTone.primary.tint(p),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  apt.label,
                  style: th.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTone.primary.ink(p),
                  ),
                ),
              ),
              if (apt.floor != null)
                Text(
                  'Kat ${apt.floor}',
                  style: th.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final resident in residents) _buildResidentRow(resident),
        ],
      ),
    );
  }

  /// Sakinin yetki kaynağına göre durum tonu (başarı / bilgi / hata / nötr).
  AppTone _statusTone(DoorResidentPermission resident) {
    switch (resident.accessSource) {
      case 'SITE_COMMON':
      case 'BLOCK_DEFAULT':
        return AppTone.success;
      case 'OVERRIDE_ALLOWED':
        return AppTone.primary;
      case 'OVERRIDE_DENIED':
        return AppTone.danger;
      case 'NO_ACCESS':
      default:
        return AppTone.neutral;
    }
  }

  Widget _buildResidentRow(DoorResidentPermission resident) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isBusy = _busyUserCodes.contains(resident.userCode);
    final statusTone = _statusTone(resident);
    final avatarTone = resident.canOpen ? AppTone.success : AppTone.neutral;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: avatarTone.tint(p),
            child: Icon(
              Icons.person_rounded,
              size: 16,
              color: avatarTone.ink(p),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      resident.fullName,
                      style: th.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusTone.tint(p),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        resident.statusLabel,
                        style: th.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: statusTone.ink(p),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${resident.roleLabel}${resident.phone != null ? ' • ${resident.phone}' : ''}',
                  style: th.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 24,
              height: 24,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch.adaptive(
              value: resident.canOpen,
              activeTrackColor: AppTone.success.a,
              onChanged: (_) => _toggleResidentAccess(resident),
            ),
        ],
      ),
    );
  }
}


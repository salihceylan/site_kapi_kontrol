// FAZ 5 / A2-G4: bireysel ana görünümün "Kayıtlı Dairem" kartı.
//
// `IndividualHomeView._buildApartmentCard` ayrı widget'a çıkarıldı (üst görünüm yalnız veri/eylem
// tutar). Davranış aynıdır: daire yöneticisi, kendisi ve başka bir yönetici olmayan aile üyesi için
// "Üyeyi Çıkar" düğmesini görür; onay akışı üst görünümdedir ([onRemoveMember]).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Bir dairenin kartı: site/blok/daire başlığı, rol rozeti ve daire sakinleri listesi.
///
/// Rol vurgusu 3 dp üst şerit + tonlu başlık zeminidir (yönetici: uyarı/amber, üye: birincil/mavi).
/// Rol rozeti başlığın ALTINA iner (uzun site adı ya da büyük yazıda başlığı ezmez); üye satırında
/// rozetler adın altında `Wrap`tir. "Üyeyi Çıkar" düğmesi 44 dp'dir.
class IndividualApartmentCard extends StatelessWidget {
  const IndividualApartmentCard({
    super.key,
    required this.apartment,
    required this.onRemoveMember,
  });

  final MyApartmentRecord apartment;

  /// "Üyeyi Çıkar" düğmesine basıldığında (onay diyaloğu üst görünümde açılır).
  final ValueChanged<ApartmentMemberRecord> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final apt = apartment;
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isAdmin = apt.isApartmentAdmin;
    final tone = isAdmin ? AppTone.warning : AppTone.primary;
    final roleText = isAdmin ? '👑 Daire Yöneticisi' : '👨‍👩‍👧 Aile Üyesi';
    final unit =
        '${apt.blockName.isNotEmpty ? '${apt.blockName} • ' : ''}${apt.unitLabel}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        padding: EdgeInsets.zero,
        accentBar: tone.hue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık alanı
            ColoredBox(
              color: tone.tint(p),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.surface,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: Icon(
                            Icons.home_work_rounded,
                            size: 20,
                            color: tone.ink(p),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              apt.siteName,
                              style: th.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            unit,
                            style: th.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpace.sm),
                          StatusChip(label: roleText, tone: tone),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Üyeler bölümü
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daire Sakinleri (${apt.members.length})',
                    style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (apt.members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpace.sm,
                      ),
                      child: Text(
                        'Henüz başka sakin bulunmuyor.',
                        style: th.bodySmall,
                      ),
                    )
                  else
                    for (var i = 0; i < apt.members.length; i++) ...[
                      if (i > 0) const Divider(height: AppSpace.lg),
                      _MemberRow(
                        member: apt.members[i],
                        // Daire yöneticisi için: Aile üyesini çıkar düğmesi.
                        canRemove:
                            isAdmin &&
                            !apt.members[i].isCurrentUser &&
                            !apt.members[i].isApartmentAdmin,
                        onRemove: () => onRemoveMember(apt.members[i]),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bir daire sakini satırı: avatar, ad, e-posta, rozetler ve (yetkiliyse) çıkar düğmesi.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  final ApartmentMemberRecord member;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isMemberAdmin = member.isApartmentAdmin;
    final tone = isMemberAdmin ? AppTone.warning : AppTone.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Color.alphaBlend(tone.tint(p), p.surface),
          child: Icon(
            isMemberAdmin ? Icons.star_rounded : Icons.person_rounded,
            size: 18,
            color: tone.ink(p),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                member.fullName,
                style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (member.email.isNotEmpty)
                Text(
                  member.email,
                  style: th.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  if (member.isCurrentUser)
                    const StatusChip(
                      label: 'Siz',
                      tone: AppTone.success,
                      icon: Icons.check_circle_rounded,
                    ),
                  StatusChip(
                    label: isMemberAdmin ? 'Daire Yön.' : 'Aile Üyesi',
                    tone: tone,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (canRemove) ...[
          const SizedBox(width: AppSpace.xs),
          IconButton(
            icon: Icon(
              Icons.person_remove_rounded,
              color: AppTone.danger.ink(p),
              size: 20,
            ),
            tooltip: 'Üyeyi Çıkar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onRemove,
          ),
        ],
      ],
    );
  }
}

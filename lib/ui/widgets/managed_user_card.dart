import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class ManagedUserCard extends StatefulWidget {
  const ManagedUserCard({
    super.key,
    required this.user,
    required this.isSelf,
    required this.activationBusy,
    required this.onTap,
    required this.onActivationChanged,
    this.onDelete,
  });

  final ManagedUserAccount user;
  final bool isSelf;
  final bool activationBusy;
  final VoidCallback onTap;
  final ValueChanged<bool> onActivationChanged;
  final VoidCallback? onDelete;

  @override
  State<ManagedUserCard> createState() => _ManagedUserCardState();
}

class _ManagedUserCardState extends State<ManagedUserCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final user = widget.user;

    // Avatar rengi rol tonu (süper = mavi, yönetici = yeşil, sakin/bireysel = mor); pasif hesap nötr
    // tonlu kart (önceki sürümde pasif = gri kenar). Tek yüzey: kart AppCard'dır.
    return AppCard(
      tone: user.isActive ? null : AppTone.neutral,
      padding: listCardPadding(context),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(expanded: _expanded), // Açık/kapalı durumu ekran okuyucuya bildirir (karta birleşir).
          Row(
            children: [
              InitialAvatar(
                name: user.fullName,
                tone: user.role.tone,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: th.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      user.role.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: th.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              widget.activationBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch.adaptive(
                      value: user.isActive,
                      activeThumbColor: AppTone.primary.a,
                      onChanged: widget.isSelf
                          ? null
                          : widget.onActivationChanged,
                    ),
              ExpandChevron(expanded: _expanded),
            ],
          ),
          ExpandableSection(
            expanded: _expanded,
            child: _buildDetails(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final user = widget.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.md),
        const Divider(),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            InfoChip('Kullanıcı ID: ${user.id}'),
            InfoChip('E-posta: ${user.email}'),
            if ((user.phoneNumber ?? '').isNotEmpty)
              InfoChip('Telefon: ${user.phoneNumber}'),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        // Tonlu (pasif) kartta textMuted soluk zeminde 4,5:1'in altına düşer: ikincil metin kullanılır.
        Text(
          'Kayıt: ${formatDateTime(user.createdAt)}',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            ElevatedButton.icon(
              onPressed: widget.onTap,
              style: tonalActionStyle(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Düzenle'),
            ),
            if (!widget.isSelf && widget.onDelete != null)
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                style: dangerOutlineStyle(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Sil'),
              ),
          ],
        ),
      ],
    );
  }
}

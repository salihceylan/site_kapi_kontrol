import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

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
    final user = widget.user;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: user.isActive
                  ? AppColors.primarySoft.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      user.fullName.trim().isEmpty
                          ? '?'
                          : user.fullName.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.role.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  widget.activationBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch.adaptive(
                          value: user.isActive,
                          onChanged: widget.isSelf
                              ? null
                              : widget.onActivationChanged,
                        ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Kullanıcı ID: ${user.id}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'E-posta: ${user.email}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    if ((user.phoneNumber ?? '').isNotEmpty)
                      Text(
                        'Telefon: ${user.phoneNumber}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    Text(
                      'Kayıt: ${formatDateTime(user.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!widget.isSelf && widget.onDelete != null) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Sil'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Düzenle'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

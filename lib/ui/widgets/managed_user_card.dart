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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = widget.user;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.85)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: user.isActive
                  ? (isDark ? const Color(0x333B82F6) : const Color(0xFFBFDBFE))
                  : (isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0)),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x30000000) : const Color(0x080F172A),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                    child: Text(
                      user.fullName.trim().isEmpty
                          ? '?'
                          : user.fullName.trim()[0].toUpperCase(),
                      style: TextStyle(
                        color: isDark ? AppColors.accentLight : AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
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
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: isDark ? const Color(0xFFF8FAFC) : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.role.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
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
                          activeThumbColor: AppColors.primary,
                          onChanged: widget.isSelf
                              ? null
                              : widget.onActivationChanged,
                        ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(
                    color: isDark ? const Color(0x1FFFFFFF) : const Color(0x150F172A),
                    height: 1,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildChip(context, 'Kullanıcı ID: ${user.id}'),
                    _buildChip(context, 'E-posta: ${user.email}'),
                    if ((user.phoneNumber ?? '').isNotEmpty)
                      _buildChip(context, 'Telefon: ${user.phoneNumber}'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Kayıt: ${formatDateTime(user.createdAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Düzenle'),
                    ),
                    if (!widget.isSelf && widget.onDelete != null)
                      OutlinedButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.roseLight),
                        label: const Text('Sil', style: TextStyle(color: AppColors.roseLight)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
                        ),
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

  Widget _buildChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        ),
      ),
    );
  }
}

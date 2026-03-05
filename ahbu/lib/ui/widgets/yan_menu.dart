import 'package:flutter/material.dart';
import 'package:ahbu/styles/app_colors.dart';

class YanMenu extends StatelessWidget {
  const YanMenu({
    super.key,
    required this.fullName,
    required this.userEmail,
    required this.roleLabel,
    required this.onLogout,
  });

  final String fullName;
  final String userEmail;
  final String roleLabel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(topRight: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  userEmail,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: const Icon(
                    Icons.home_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Ana Sayfa'),
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(height: 4),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: AppColors.primary.withValues(alpha: 0.08),
                  leading: const Icon(Icons.logout, color: AppColors.primary),
                  title: const Text('Cikis Yap'),
                  onTap: () {
                    Navigator.pop(context);
                    onLogout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

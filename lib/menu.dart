import 'package:flutter/material.dart';

class YanMenu extends StatelessWidget {
  const YanMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Menü Başlığı
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.deepPurple),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40, color: Colors.deepPurple),
                ),
                SizedBox(height: 10),
                Text(
                  "Kullanıcı Adı", 
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          ),
          
          // Menü Elemanları
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text("Ana Sayfa"),
            onTap: () {
              Navigator.pop(context); // Menüyü kapatır
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("Ayarlar"),
            onTap: () {
              Navigator.pop(context);
              // Buraya Navigator.push ile ayarlar sayfası gelebilir
            },
          ),
          const Divider(), 
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text("Çıkış Yap"),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
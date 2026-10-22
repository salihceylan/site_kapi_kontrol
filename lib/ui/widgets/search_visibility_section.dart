import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// Profilde "Beni aramalarda göster" ayarı (varsayılan KAPALI). Kapalıyken kişi, daire sahibi / yöneticisinin "Sistemden ara"sında
/// yalnız e-posta adresi ya da telefonu TAM yazılarak bulunur; açıkken ad soyadla da bulunur. Sonuçlar her durumda maskelidir ve
/// daire / site / adres bilgisi içermez. Hata varsa varsayılan bir anahtar ASLA çizilmez (yanlış değeri doğruymuş gibi göstermesin).
class SearchVisibilitySection extends StatefulWidget {
  const SearchVisibilitySection({super.key, required this.authService, this.service});

  final AuthService authService;
  final ApartmentManagementService? service;

  @override
  State<SearchVisibilitySection> createState() => _SearchVisibilitySectionState();
}

class _SearchVisibilitySectionState extends State<SearchVisibilitySection> {
  late final ApartmentManagementService _service = widget.service ?? ApartmentManagementService(authService: widget.authService);
  bool? _value;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final v = await _service.getSearchVisibility();
      if (!mounted) return;
      setState(() {
        _value = v;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = crmMessageOf(e, 'Ayar yüklenemedi.'));
    }
  }

  Future<void> _set(bool next) async {
    final before = _value;
    setState(() {
      _busy = true;
      _value = next;
      _error = null;
    });
    try {
      await _service.setSearchVisibility(next);
    } catch (e) {
      if (mounted) {
        setState(() {
          _value = before;
          _error = crmMessageOf(e, 'Ayar kaydedilemedi.');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Aramalarda Görünme'),
          const SizedBox(height: AppSpace.sm),
          if (value != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: value,
              onChanged: _busy ? null : (v) => unawaited(_set(v)),
              title: const Text('Beni aramalarda göster'),
              subtitle: const Text(
                'Kapalıyken yalnızca e-posta adresinizi ya da telefonunuzu tam olarak bilen kişiler sizi daire davetleri için bulabilir. '
                'Açıkken ad soyadınızla da bulunursunuz; sonuçlarda adınız maskelenmiş görünür.',
              ),
            ),
          if (_error != null) InlineNotice(message: _error!, onRetry: value == null ? _load : null),
        ],
      ),
    );
  }
}

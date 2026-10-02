import 'package:flutter/material.dart';
import '../../models/door_record.dart';
import '../../models/site_block_record.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/app_dialog.dart';
import '../design/tokens.dart';

class DoorEditDialog extends StatefulWidget {
  const DoorEditDialog({
    super.key,
    required this.authService,
    required this.siteCode,
    this.door,
    this.blocks = const [],
    this.availableDevices = const [],
  });

  final AuthService authService;
  final int siteCode;
  final DoorRecord? door;
  final List<SiteBlockRecord> blocks;
  final List<Map<String, dynamic>> availableDevices;

  static Future<bool?> show(
    BuildContext context, {
    required AuthService authService,
    required int siteCode,
    DoorRecord? door,
    List<SiteBlockRecord> blocks = const [],
    List<Map<String, dynamic>> availableDevices = const [],
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DoorEditDialog(
        authService: authService,
        siteCode: siteCode,
        door: door,
        blocks: blocks,
        availableDevices: availableDevices,
      ),
    );
  }

  @override
  State<DoorEditDialog> createState() => _DoorEditDialogState();
}

class _DoorEditDialogState extends State<DoorEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  late String _selectedScope;
  int? _selectedBlockId;
  String? _selectedDeviceUid;

  bool _isLoading = false;
  String? _errorMessage;

  bool get _isEditing => widget.door != null;

  @override
  void initState() {
    super.initState();
    final d = widget.door;
    _nameController = TextEditingController(text: d?.doorName ?? '');
    _selectedScope = d?.accessScope ?? 'SITE_COMMON';
    _selectedBlockId = d?.blockId;

    if (_selectedBlockId == null && widget.blocks.isNotEmpty && _selectedScope == 'BLOCK') {
      _selectedBlockId = widget.blocks.first.id;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isEditing) {
        await widget.authService.updateDoor(
          doorId: widget.door!.id,
          doorName: _nameController.text.trim(),
          accessScope: _selectedScope,
          blockId: _selectedScope == 'BLOCK' ? _selectedBlockId : null,
        );
      } else {
        await widget.authService.createDoor(
          siteCode: widget.siteCode,
          doorName: _nameController.text.trim(),
          accessScope: _selectedScope,
          blockId: _selectedScope == 'BLOCK' ? _selectedBlockId : null,
          deviceUid: _selectedDeviceUid,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'İşlem sırasında bir hata oluştu: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık & İkon (+ sağ üstte kapatma düğmesi; başlık düğmenin altına girmesin diye sağdan pay)
                Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 32),
                      child: AppDialogHeader(
                        title: _isEditing ? 'Kapıyı Düzenle' : 'Yeni Kapı Ekle',
                        subtitle: _isEditing
                            ? '${widget.door!.doorName} ayarlarını güncelleyin'
                            : 'Siteye bağımsız bir geçiş noktası tanımlayın',
                        icon: Icons.meeting_room_rounded,
                      ),
                    ),
                    PositionedDirectional(
                      top: AppSpace.sm,
                      end: AppSpace.sm,
                      child: IconButton(
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xl, 18, AppSpace.xl, AppSpace.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hata Mesajı
                      if (_errorMessage != null) ...[
                        InlineNotice(message: _errorMessage!),
                        const SizedBox(height: 14),
                      ],

                      // Kapı Adı
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Kapı Adı *',
                          hintText: 'Örn: Ana Giriş Kapısı, A Blok Girişi, Otopark',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Lütfen kapı adını giriniz.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Erişim Kapsamı
                      DropdownButtonFormField<String>(
                        initialValue: _selectedScope,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Erişim Kapsamı',
                          prefixIcon: Icon(Icons.security_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'SITE_COMMON',
                            child: Text(
                              'Site Ortak Girişi (Tüm Sakinler)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'BLOCK',
                            child: Text(
                              'Blok Kapısı (Sadece İlgili Blok)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'CUSTOM',
                            child: Text(
                              'Özel Yetkili Giriş',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _selectedScope = val;
                            if (_selectedScope == 'BLOCK' && _selectedBlockId == null && widget.blocks.isNotEmpty) {
                              _selectedBlockId = widget.blocks.first.id;
                            }
                          });
                        },
                      ),

                      // Eğer Blok Kapısı Seçilmişse Blok Listesi
                      if (_selectedScope == 'BLOCK') ...[
                        const SizedBox(height: 16),
                        if (widget.blocks.isEmpty)
                          const InlineNotice(
                            tone: AppTone.warning,
                            message:
                                'Bu sitede tanımlı blok bulunamadı. Blok kapısı oluşturabilmek için önce siteye blok eklenmelidir.',
                          )
                        else
                          DropdownButtonFormField<int>(
                            initialValue: widget.blocks.any((b) => b.id == _selectedBlockId)
                                ? _selectedBlockId
                                : widget.blocks.first.id,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Bağlı Olduğu Blok *',
                              prefixIcon: Icon(Icons.apartment_rounded),
                            ),
                            items: widget.blocks.map((b) {
                              return DropdownMenuItem<int>(
                                value: b.id,
                                child: Text(
                                  b.blockName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedBlockId = val);
                            },
                          ),
                      ],

                      // Yeni kapı ekleniyorsa ve boşta cihaz varsa hızlı atama seçeneği
                      if (!_isEditing && widget.availableDevices.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedDeviceUid,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cihaz Ata (İsteğe Bağlı)',
                            prefixIcon: Icon(Icons.developer_board_rounded),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Daha sonra ata (Cihaz yok)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ...widget.availableDevices.map((dev) {
                              final uid = dev['device_uid']?.toString() ?? '';
                              final hw = dev['hardware_type']?.toString() ?? '';
                              final isWroom = hw.toLowerCase().contains('wroom');
                              return DropdownMenuItem<String?>(
                                value: uid,
                                child: Text(
                                  '$uid (${isWroom ? "WROOM" : "C3"})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedDeviceUid = val);
                          },
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Kaydet Butonu
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _submit,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(_isEditing ? Icons.check_rounded : Icons.add_rounded),
                        label: Text(
                          _isLoading
                              ? 'Kaydediliyor...'
                              : (_isEditing ? 'Değişiklikleri Kaydet' : 'Kapıyı Oluştur'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

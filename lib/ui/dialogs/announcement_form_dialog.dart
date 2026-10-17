import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart' show ApartmentSummary;
import 'package:site_kapi_kontrol/models/document_models.dart' show DocumentAttachment;
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/time_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_attachment_field.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Duyurunun ne zaman yayınlanacağı (formdaki "Yayın" seçimi).
enum AnnouncementPublishMode {
  draft('Taslak'),
  now('Şimdi yayınla'),
  schedule('Zamanla');

  const AnnouncementPublishMode(this.label);

  final String label;
}

/// Form kapanırken döner: güncel duyuru ve kullanıcıya gösterilecek kısa mesaj.
class AnnouncementFormResult {
  const AnnouncementFormResult({required this.detail, required this.message});

  final AnnouncementDetail detail;
  final String message;
}

/// Hedefte seçilmiş bir blok ya da daire (etiketiyle).
typedef _Picked = ({int id, String label});

/// Kitle önizlemesi sıfır kişi gösterdiğinde ("Şimdi yayınla") formun kendi mesajı.
const String _noRecipientsMessage =
    'Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin.';

/// Yayın / zamanlama onayı (Platform Faz 3a): yayından ÖNCE kitle önizlemesi ("N kişiye ulaşır, M kişinin
/// e-postası var") gösterilir. Onaylanırsa true, vazgeçilirse ya da kapatılırsa false döner. Çift
/// dokunuşta ikinci `pop` bir üst pencereyi kapatmaz ([popIfCurrent]).
Future<bool> confirmAnnouncementAudience(
  BuildContext context, {
  required AudiencePreview preview,
  required bool scheduled,
  required bool sendEmail,
  DateTime? publishAt,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final th = Theme.of(dialogContext).textTheme;
      final p = dialogContext.palette;
      return AppDialog(
        title: scheduled ? 'Zamanlamayı onayla' : 'Yayını onayla',
        icon: scheduled ? Icons.schedule_rounded : Icons.campaign_rounded,
        actions: [
          TextButton(
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: filledToneStyle(dialogContext),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: Text(scheduled ? 'Zamanla' : 'Yayınla'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                '${preview.people} kişiye ulaşır',
                key: const ValueKey<String>('audience_people'),
                style: th.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '${preview.apartments} daire hedefleniyor. ${preview.withAccount} kişinin '
              'uygulama hesabı var; duyuruyu uygulamada görürler.',
              style: th.bodyMedium,
            ),
            if (sendEmail) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '${preview.withEmail} kişinin e-postası var, ${preview.withoutEmail} kişinin '
                'e-postası yok. Gönderilen e-postalar geri alınamaz.',
                key: const ValueKey<String>('audience_email'),
                style: th.bodyMedium,
              ),
            ],
            if (scheduled && publishAt != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                'Yayın zamanı: ${formatIstanbulDateTime(publishAt)} (İstanbul saati). '
                'Alıcılar yayın anında belirlenir.',
                style: th.bodyMedium?.copyWith(color: p.textSecondary),
              ),
            ],
            if (preview.people == 0) ...[
              const SizedBox(height: AppSpace.md),
              const InlineNotice(
                tone: AppTone.warning,
                message: 'Şu anda bu hedefte duyuruyu alacak kimse yok.',
              ),
            ],
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// "Yeni Duyuru" ve "Düzenle" penceresi (Platform Faz 3a).
///
/// - Alanlar: başlık (en çok 120), metin (en çok 5000, sayaçlı), önem (Normal / Acil), hedef (Tüm site /
///   Bloklar / Daireler; seçiciler `crm_pickers` üzerinden), "E-posta da gönder" (Acil seçilince varsayılan
///   açık), yayın (Taslak / Şimdi yayınla / Zamanla; tarih GG.AA.YYYY + saat SS:DD, İstanbul saati).
///   SMS ve WhatsApp "Yakında…" etiketli PASİF seçeneklerdir.
/// - Yayın ya da zamanlamadan ÖNCE kitle önizlemesi alınır ve onay istenir ([confirmAnnouncementAudience]).
/// - YAYINLANMIŞ duyuruda yalnız başlık ve metin düzenlenir; diğer alanlar kilitli ve açıklamalıdır
///   (sakinlerde "düzenlendi" notu görünür, yeniden bildirim / e-posta yoktur).
/// - Çift gönderim koruması (`_submitting`), gönderim sürerken geri tuşu kapatmaz, hata pencerenin içinde
///   görünür konuma kaydırılır. Sunucu reddi Türkçe mesajla gösterilir ve pencere AÇIK kalır.
///
/// Başarıda [AnnouncementFormResult] ile kapanır; değişiklik yoksa (yalnız düzenlemede) null.
class AnnouncementFormDialog extends StatefulWidget {
  const AnnouncementFormDialog({
    super.key,
    required this.scope,
    this.announcement,
    this.now,
    this.onRefreshNeeded,
    this.documentService,
  });

  final PeopleScope scope;

  /// Düzenlenen duyuru; null ise yeni duyuru.
  final AnnouncementDetail? announcement;

  /// Duyurunun sunucudaki durumu pencere açıkken değiştiğinde (409 `INVALID_STATE`, 404
  /// `ANNOUNCEMENT_NOT_FOUND`) çağrılır: pencere sonuçsuz kapansa da çağıran ayrıntıyı / listeyi tazeleyebilsin.
  final VoidCallback? onRefreshNeeded;

  /// Belge eki alanı için servis (Faz 3b-A); verilmezse oturumdan kurulur (testlerde sahte verilir).
  final DocumentService? documentService;

  /// Şimdiki zaman (zamanlama doğrulaması; testler içindir).
  final DateTime Function()? now;

  static const int maxTitleLength = 120;
  static const int maxBodyLength = 5000;
  static const int maxTargetItems = 500;

  static Future<AnnouncementFormResult?> show(
    BuildContext context, {
    required PeopleScope scope,
    AnnouncementDetail? announcement,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
    DocumentService? documentService,
  }) {
    return showDialog<AnnouncementFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementFormDialog(
        scope: scope,
        announcement: announcement,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
        documentService: documentService,
      ),
    );
  }

  @override
  State<AnnouncementFormDialog> createState() => _AnnouncementFormDialogState();
}

class _AnnouncementFormDialogState extends State<AnnouncementFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late AnnouncementDetail? _initial = widget.announcement;
  late final TextEditingController _title = TextEditingController(
    text: widget.announcement?.title ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.announcement?.body ?? '',
  );
  final TextEditingController _date = TextEditingController();
  final TextEditingController _time = TextEditingController();

  late AnnouncementImportance _importance =
      widget.announcement?.importance ?? AnnouncementImportance.normal;
  late AnnouncementTargetType _targetType =
      widget.announcement?.target.type ?? AnnouncementTargetType.site;
  late bool _sendEmail = widget.announcement?.sendEmail ?? false;
  AnnouncementPublishMode _mode = AnnouncementPublishMode.draft;
  // Bu oturumda seçilenler (etiketleriyle). Kayıtlı duyurunun önceden seçili hedefi ise `_kept*` içindedir:
  // sunucu etiketleri kimliklerden BAĞIMSIZ sırayla (blok/daire sırasıyla) döndürür, bu yüzden tek tek
  // kimlikle eşleştirilemez; yalnız gösterilir ve toplu temizlenebilir. Blokların adları site yapısından
  // alınabilirse `_blocks`a çevrilir (tek tek çıkarılabilir).
  List<_Picked> _blocks = const <_Picked>[];
  List<_Picked> _apartments = const <_Picked>[];
  List<int> _keptBlockIds = const <int>[];
  List<String> _keptBlockLabels = const <String>[];
  List<int> _keptApartmentIds = const <int>[];
  List<String> _keptApartmentLabels = const <String>[];

  bool _submitting = false;

  // Belge ekleri (Faz 3b-A; en çok 5). Yayınlanmış duyuruda değişmez.
  late List<DocumentAttachment> _attachments =
      List<DocumentAttachment>.of(widget.announcement?.attachments ?? const <DocumentAttachment>[]);

  // Seçici pencereleri çift dokunuşta iki kez açılmasın.
  bool _picking = false;

  // Yeni duyuru gönderimi sonucu BELİRSİZ kaldı (ağ zaman aşımı, 5xx, DUPLICATE_ANNOUNCEMENT): ilk istek
  // yayınlamış olabilir; form kapanırken (Vazgeç dahil) çağıran listeyi tazelesin.
  bool _needsRefreshOnClose = false;
  final RetryLock _retry = RetryLock();
  String? _error;
  String? _targetError;
  List<SiteBlockRecord>? _blockCache;

  bool get _editing => widget.announcement != null;

  /// Yayınlanmış duyuru: yalnız başlık ve metin düzenlenir.
  bool get _locked => _initial?.status == AnnouncementStatus.published;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final initial = widget.announcement;
    if (initial == null) return;
    if (initial.target.type == AnnouncementTargetType.blocks) {
      // Sunucu `target.blocks` ([{id, name}]) gönderiyorsa kayıtlı bloklar tek tek çıkarılabilir çip olarak
      // seçili gelir; eşleşmeyen kimlikler (silinmiş blok) ve eski sunucu için kayıtlı seçim kalır.
      final known = <int>{for (final b in initial.target.blocks) b.id};
      _blocks = <_Picked>[for (final b in initial.target.blocks) (id: b.id, label: b.name)];
      _keptBlockIds = <int>[
        for (final id in initial.target.blockIds)
          if (!known.contains(id)) id,
      ];
      _keptBlockLabels = known.isEmpty ? initial.target.labels : const <String>[];
    } else if (initial.target.type == AnnouncementTargetType.apartments) {
      final known = <int>{for (final a in initial.target.apartments) a.id};
      _apartments = <_Picked>[
        for (final a in initial.target.apartments) (id: a.id, label: a.label),
      ];
      _keptApartmentIds = <int>[
        for (final id in initial.target.apartmentIds)
          if (!known.contains(id)) id,
      ];
      _keptApartmentLabels = known.isEmpty ? initial.target.labels : const <String>[];
    }
    if (initial.status == AnnouncementStatus.scheduled && initial.publishAt != null) {
      _mode = AnnouncementPublishMode.schedule;
      _date.text = formatIstanbulDate(initial.publishAt);
      _time.text = formatIstanbulTime(initial.publishAt);
    }
    if (_keptBlockIds.isNotEmpty) _resolveBlockLabels();
  }

  @override
  void dispose() {
    _retry.dispose();
    _title.dispose();
    _body.dispose();
    _date.dispose();
    _time.dispose();
    super.dispose();
  }

  /// Önceden seçili blokların adlarını site yapısından (kimlikle) alıp tek tek çıkarılabilir seçime çevirir.
  /// Alınamazsa (ya da bir blok bulunamazsa) sunucu etiketleri salt görüntü olarak kalır.
  Future<void> _resolveBlockLabels() async {
    try {
      final blocks = await _loadBlocks();
      if (!mounted) return;
      final names = <int, String>{for (final b in blocks) b.id: b.blockName.trim()};
      if (_keptBlockIds.any((id) => (names[id] ?? '').isEmpty)) return;
      setState(() {
        _blocks = <_Picked>[
          for (final id in _keptBlockIds) (id: id, label: names[id]!),
          ..._blocks,
        ];
        _keptBlockIds = const <int>[];
        _keptBlockLabels = const <String>[];
      });
    } catch (_) {
      // Sunucu etiketleriyle devam.
    }
  }

  Future<List<SiteBlockRecord>> _loadBlocks() async {
    final cached = _blockCache;
    if (cached != null) return cached;
    final (structure, error) = await widget.scope.authService.getSiteStructure(
      siteCode: widget.scope.siteCode,
    );
    if (structure == null) {
      throw ApiException(
        (error ?? '').trim().isEmpty
            ? 'Bloklar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
            : error!,
      );
    }
    return _blockCache = structure.blocks;
  }

  // --- Hedef seçimi ----------------------------------------------------------------------------

  Future<void> _pickBlock() async {
    if (_picking) return;
    _picking = true;
    SiteBlockRecord? result;
    try {
      result = await _showBlockPicker();
    } finally {
      _picking = false;
    }
    final picked = result;
    if (picked == null || !mounted) return;
    if (_blockIds.contains(picked.id)) return;
    if (_blockIds.length >= AnnouncementFormDialog.maxTargetItems) {
      setState(() => _targetError = _tooMany);
      return;
    }
    setState(() {
      _targetError = null;
      _blocks = <_Picked>[
        ..._blocks,
        (
          id: picked.id,
          label: picked.blockName.trim().isEmpty ? 'Adsız blok' : picked.blockName.trim(),
        ),
      ];
    });
  }

  Future<SiteBlockRecord?> _showBlockPicker() {
    return CrmPickerDialog.show<SiteBlockRecord>(
      context,
      CrmPickerDialog<SiteBlockRecord>(
        title: 'Blok Ekle',
        icon: Icons.domain_rounded,
        searchLabel: 'Blok ara',
        emptyTitle: 'Eklenecek blok bulunamadı.',
        fetch: (query, offset, limit) async {
          final blocks = await _loadBlocks();
          final q = query.trim().toLowerCase();
          final chosen = _blockIds.toSet();
          final rows = blocks
              .where(
                (b) =>
                    !chosen.contains(b.id) &&
                    (q.isEmpty || b.blockName.toLowerCase().contains(q)),
              )
              .toList();
          return (items: rows.skip(offset).take(limit).toList(), total: rows.length);
        },
        keyOf: (b) => b.id,
        titleOf: (b) => b.blockName.trim().isEmpty ? 'Adsız blok' : b.blockName.trim(),
      ),
    );
  }

  Future<void> _pickApartment() async {
    if (_picking) return;
    _picking = true;
    ApartmentSummary? result;
    try {
      result = await showApartmentPicker(context, widget.scope, title: 'Daire Ekle');
    } finally {
      _picking = false;
    }
    final picked = result;
    if (picked == null || !mounted) return;
    if (_apartmentIds.contains(picked.id)) return;
    if (_apartmentIds.length >= AnnouncementFormDialog.maxTargetItems) {
      setState(() => _targetError = _tooMany);
      return;
    }
    setState(() {
      _targetError = null;
      _apartments = <_Picked>[..._apartments, (id: picked.id, label: picked.fullLabel)];
    });
  }

  static const String _tooMany = 'En çok 500 öğe seçilebilir. Hedefi bölüp ayrı duyurular oluşturun.';

  /// Seçili blok / daire kimlikleri (önceden kayıtlı olanlar + bu oturumda eklenenler).
  List<int> get _blockIds => <int>[..._keptBlockIds, for (final b in _blocks) b.id];
  List<int> get _apartmentIds => <int>[..._keptApartmentIds, for (final a in _apartments) a.id];

  AnnouncementTargetInput get _targetInput => AnnouncementTargetInput(
    type: _targetType,
    blockIds: _targetType == AnnouncementTargetType.blocks ? _blockIds : const <int>[],
    apartmentIds:
        _targetType == AnnouncementTargetType.apartments ? _apartmentIds : const <int>[],
  );

  String? _validateTarget() {
    switch (_targetType) {
      case AnnouncementTargetType.site:
        return null;
      case AnnouncementTargetType.blocks:
        return _blockIds.isEmpty ? 'En az bir blok seçin.' : null;
      case AnnouncementTargetType.apartments:
        return _apartmentIds.isEmpty ? 'En az bir daire seçin.' : null;
    }
  }

  // --- Gönderim --------------------------------------------------------------------------------

  /// Seçilen yayın zamanı (İstanbul saatinden gerçek ana); geçersizse null.
  DateTime? _scheduledInstant() {
    final date = parseDateField(_date.text);
    final time = parseTimeField(_time.text);
    if (date == null || time == null) return null;
    return istanbulInstantOf(date, time.hour, time.minute);
  }

  /// Zamanlama kuralı (sözleşme): bugünden en az 1 dakika, en çok 1 yıl sonra.
  String? _scheduleProblem(DateTime instant) {
    final now = _now().toUtc();
    if (!instant.isAfter(now.add(const Duration(minutes: 1)))) {
      return 'Yayın zamanı şu andan en az 1 dakika sonra olmalı (İstanbul saati).';
    }
    // Üst sınır TAKVİM olarak 1 yıl (İstanbul): sunucudaki `setFullYear(+1)` ile aynı (29 Şubat'lı aralıkta
    // 366 gün olabilir).
    if (instant.isAfter(istanbulCalendarYearAfter(now))) {
      return 'Yayın zamanı en çok 1 yıl sonrası olabilir.';
    }
    return null;
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final set = a.toSet();
    return set.length == a.length && set.containsAll(b);
  }

  bool _targetChanged(AnnouncementDetail initial) {
    if (initial.target.type != _targetType) return true;
    switch (_targetType) {
      case AnnouncementTargetType.site:
        return false;
      case AnnouncementTargetType.blocks:
        return !_sameIds(initial.target.blockIds, _blockIds);
      case AnnouncementTargetType.apartments:
        return !_sameIds(initial.target.apartmentIds, _apartmentIds);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(_formKey)) {
      // Özet bildirimi (canlı bölge) + ilk geçersiz alana kaydırma / odak (validateForm).
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final locked = _locked;
    DateTime? instant;
    if (!locked) {
      final targetProblem = _validateTarget();
      if (targetProblem != null) {
        setState(() => _targetError = targetProblem);
        return;
      }
      if (_mode == AnnouncementPublishMode.schedule) {
        instant = _scheduledInstant();
        if (instant == null) {
          setState(() => _error = 'Yayın tarihini ve saatini girin (İstanbul saati).');
          return;
        }
        final problem = _scheduleProblem(instant);
        if (problem != null) {
          setState(() => _error = problem);
          return;
        }
      }
    }
    final initial = _initial;
    Map<String, Object?>? fields;
    if (initial != null) {
      fields = _changedFields(initial, instant);
      // Değişiklik yok: sunucuya (ve kitle onayına) gitmeden kapanır.
      if (fields.isEmpty && (locked || _mode != AnnouncementPublishMode.now)) {
        popIfCurrent<AnnouncementFormResult>(context);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _targetError = null;
    });
    try {
      final auth = widget.scope.authService;
      final siteCode = widget.scope.siteCode;
      final mode = _mode;

      // Yayın / zamanlama öncesi kitle önizlemesi + onay. Taslakta, kilitli (yayınlanmış) düzenlemede ve
      // alıcıyı / zamanı değiştirmeyen düzenlemede yoktur.
      final needsConfirm =
          !locked &&
          mode != AnnouncementPublishMode.draft &&
          (initial == null ||
              mode == AnnouncementPublishMode.now ||
              initial.status != AnnouncementStatus.scheduled ||
              fields!.containsKey('publish_at') ||
              fields.containsKey('target') ||
              fields.containsKey('send_email'));
      if (needsConfirm) {
        final preview = await auth.previewAnnouncementAudience(
          siteCode,
          _targetInput,
          sendEmail: _sendEmail,
        );
        if (!mounted) return;
        if (preview.people == 0 && mode == AnnouncementPublishMode.now) {
          setState(() {
            _submitting = false;
            _error = _noRecipientsMessage;
          });
          return;
        }
        final confirmed = await confirmAnnouncementAudience(
          context,
          preview: preview,
          scheduled: mode == AnnouncementPublishMode.schedule,
          sendEmail: _sendEmail,
          publishAt: instant,
        );
        if (!mounted) return;
        if (!confirmed) {
          setState(() => _submitting = false);
          return;
        }
      }

      final AnnouncementDetail result;
      if (initial == null) {
        result = await auth.createAnnouncement(
          siteCode,
          title: _title.text,
          body: _body.text,
          target: _targetInput,
          importance: _importance,
          sendEmail: _sendEmail,
          publish: switch (mode) {
            AnnouncementPublishMode.draft => 'draft',
            AnnouncementPublishMode.now => 'now',
            AnnouncementPublishMode.schedule => 'schedule',
          },
          publishAt: instant,
          documentIds: _attachments.isEmpty
              ? null
              : <int>[for (final a in _attachments) a.documentId],
        );
      } else {
        var current = initial;
        final publishNow = !locked && mode == AnnouncementPublishMode.now;
        if (fields!.isNotEmpty) {
          // "Şimdi yayınla": kayıt + yayın TEK istekte (`publish: 'now'`, create ile aynı anlam): sunucu ikisini
          // aynı işlemde yapar; yayın başarısız olursa (örn. NO_RECIPIENTS) düzenleme de geri alınır, yarım
          // kalmış durum olmaz ve form aynı değerlerle yeniden denenebilir.
          current = await auth.updateAnnouncement(
            siteCode,
            initial.id,
            publishNow ? <String, Object?>{...fields, 'publish': 'now'} : fields,
          );
          _initial = current;
        } else if (publishNow) {
          current = await auth.publishAnnouncement(siteCode, initial.id);
          _initial = current;
        }
        result = current;
      }
      if (!mounted) return;
      _needsRefreshOnClose = false; // sonuçla kapanır: çağıran zaten günceller
      popIfCurrent(
        context,
        AnnouncementFormResult(detail: result, message: _messageFor(result, wasPublished: locked)),
      );
    } catch (e) {
      if (e is ApiException &&
          (e.code == 'INVALID_STATE' || e.code == 'ANNOUNCEMENT_NOT_FOUND')) {
        // Duyuru başka yerden değişmiş / silinmiş: çağıran ayrıntı ve listeyi tazelesin.
        widget.onRefreshNeeded?.call();
      } else if (initial == null && _outcomeUncertain(e)) {
        // Yeni duyuru: istek sunucuya ulaşmış olabilir (zaman aşımı / 5xx / aynı içerik yinelendi). Liste
        // şimdi ve form kapanırken tazelenir; kullanıcı duyuruyu listede görebilir.
        _needsRefreshOnClose = true;
        widget.onRefreshNeeded?.call();
      }
      if (!mounted) return;
      final rateLimited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _error = rateLimited
            ? RetryLock.messageFor(e)
            : crmMessageOf(
                e,
                'Duyuru kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
        _submitting = false;
      });
    }
  }

  /// İstek sunucuya ulaşmış olabilir mi (sonuç belirsiz)? Ağ/zaman aşımı (durum kodu yok), 5xx ya da aynı
  /// içeriğin yinelenmesi (`DUPLICATE_ANNOUNCEMENT`: ilk istek yayınlamış olabilir).
  static bool _outcomeUncertain(Object error) {
    if (error is! ApiException) return true;
    return error.statusCode == null ||
        error.isServerError ||
        error.code == 'DUPLICATE_ANNOUNCEMENT';
  }

  /// Form sonuçsuz kapanırken (Vazgeç / geri tuşu) belirsiz gönderim varsa çağıranı bir kez haberdar eder.
  void _notifyRefreshOnClose() {
    if (!_needsRefreshOnClose) return;
    _needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  /// Düzenlemede yalnız değişen alanlar. Yayınlanmış duyuruda YALNIZ başlık / metin.
  Map<String, Object?> _changedFields(AnnouncementDetail initial, DateTime? instant) {
    final fields = <String, Object?>{};
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title != initial.title.trim()) fields['title'] = title;
    if (body != initial.body.trim()) fields['body'] = body;
    if (_locked) return fields;
    if (_importance != initial.importance) fields['importance'] = _importance.apiValue;
    if (_sendEmail != initial.sendEmail) fields['send_email'] = _sendEmail;
    if (_targetChanged(initial)) fields['target'] = _targetInput.toJson();
    if (!_sameIds(
      <int>[for (final a in initial.attachments) a.documentId],
      <int>[for (final a in _attachments) a.documentId],
    )) {
      // PATCH ek listesini DEĞİŞTİRİR (boş liste = tüm ekleri kaldır).
      fields['document_ids'] = <int>[for (final a in _attachments) a.documentId];
    }
    switch (_mode) {
      case AnnouncementPublishMode.draft:
        // Zamanlamayı kaldırmak: publish_at null (sunucu durumu taslağa döndürür).
        if (initial.status == AnnouncementStatus.scheduled) fields['publish_at'] = null;
      case AnnouncementPublishMode.schedule:
        final current = initial.publishAt;
        final same = initial.status == AnnouncementStatus.scheduled &&
            current != null &&
            instant != null &&
            current.toUtc().difference(instant).abs() < const Duration(seconds: 30);
        if (!same && instant != null) {
          fields['publish_at'] = instant.toUtc().toIso8601String();
        }
      case AnnouncementPublishMode.now:
        break;
    }
    return fields;
  }

  static String _messageFor(AnnouncementDetail detail, {required bool wasPublished}) {
    if (wasPublished) return 'Duyuru güncellendi.';
    switch (detail.status) {
      case AnnouncementStatus.published:
        return detail.recipientCount > 0
            ? 'Duyuru yayınlandı. ${detail.recipientCount} kişiye ulaştı.'
            : 'Duyuru yayınlandı.';
      case AnnouncementStatus.scheduled:
        return 'Duyuru ${formatIstanbulDateTime(detail.publishAt)} için zamanlandı.';
      case AnnouncementStatus.draft:
        return 'Taslak kaydedildi.';
      case AnnouncementStatus.withdrawn:
      case AnnouncementStatus.unknown:
        return 'Duyuru kaydedildi.';
    }
  }

  // --- Görünüm ---------------------------------------------------------------------------------

  String get _submitLabel {
    if (_submitting) return 'Kaydediliyor...';
    if (_locked) return 'Kaydet';
    return switch (_mode) {
      AnnouncementPublishMode.draft => 'Taslağı Kaydet',
      AnnouncementPublishMode.now => 'Yayınla',
      AnnouncementPublishMode.schedule => 'Zamanla',
    };
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final locked = _locked;
    return PopScope(
      // Gönderim sürerken geri tuşu pencereyi kapatmaz (işlem yarıda kalmış gibi görünmesin).
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _notifyRefreshOnClose();
      },
      child: AppDialog(
        title: _editing ? 'Duyuruyu Düzenle' : 'Yeni Duyuru',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: _editing ? Icons.edit_rounded : Icons.campaign_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            // Hız sınırı (429) sonrası kısa süre kilitli: art arda deneme yapılmasın.
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitLabel),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              TextFormField(
                key: const ValueKey<String>('announcement_title'),
                controller: _title,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: AnnouncementFormDialog.maxTitleLength,
                // Sayaç ve doğrulama AYNI birimi (kod noktası; sunucu da öyle sayar) kullanır; sınırı aşan
                // giriş (yapıştırma) sessizce kırpılmaz: sayaç kırmızıya döner, doğrulayıcı hata verir.
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    _counter(context, _title.text.runes.length, AnnouncementFormDialog.maxTitleLength),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (length < 1) return 'Başlık boş olamaz.';
                  if (length > AnnouncementFormDialog.maxTitleLength) {
                    return 'Başlık en çok ${AnnouncementFormDialog.maxTitleLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('announcement_body'),
                controller: _body,
                enabled: !_submitting,
                minLines: 4,
                maxLines: 10,
                maxLength: AnnouncementFormDialog.maxBodyLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    _counter(context, _body.text.runes.length, AnnouncementFormDialog.maxBodyLength),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Metin',
                  alignLabelWithHint: true,
                  helperText: 'Yalnızca düz metin; biçimlendirme ve bağlantı etiketi desteklenmez.',
                  helperMaxLines: 3,
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (length < 1) return 'Metin boş olamaz.';
                  if (length > AnnouncementFormDialog.maxBodyLength) {
                    return 'Metin en çok ${AnnouncementFormDialog.maxBodyLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              if (locked)
                _buildLockedPanel(context)
              else ...[
                DocumentAttachmentField(
                  scope: widget.scope,
                  service: widget.documentService,
                  value: _attachments,
                  enabled: !_submitting,
                  onChanged: (value) => setState(() => _attachments = value),
                ),
                _buildImportance(context),
                const SizedBox(height: AppSpace.lg),
                _buildTarget(context),
                const SizedBox(height: AppSpace.lg),
                _buildChannels(context),
                const SizedBox(height: AppSpace.lg),
                _buildPublish(context, th),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "n/120" sayacı: sınır aşılınca kırmızı + kalın; ekran okuyucu aşımı söyler.
  Widget _counter(BuildContext context, int length, int max) {
    final p = context.palette;
    final over = length > max;
    return Semantics(
      liveRegion: over,
      label: over
          ? '$length karakter; en çok $max olabilir, sınır aşıldı'
          : '$length / $max karakter',
      child: ExcludeSemantics(
        child: Text(
          '$length/$max',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: over ? AppTone.danger.ink(p) : p.textSecondary,
            fontWeight: over ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);

  Widget _buildImportance(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, 'Önem'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final importance in AnnouncementImportance.values)
              ChoiceChip(
                key: ValueKey<String>('announcement_importance_${importance.apiValue}'),
                avatar: Icon(
                  importance == AnnouncementImportance.urgent
                      ? Icons.priority_high_rounded
                      : Icons.notifications_none_rounded,
                  size: 18,
                ),
                label: Text(importance.label),
                selected: _importance == importance,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        // E-posta yalnız önem Normal -> Acil DEĞİŞİNCE kendiliğinden açılır; seçili Acil çipine
                        // yeniden dokunmak kullanıcının kapattığı tercihi ezmez.
                        if (importance == AnnouncementImportance.urgent &&
                            _importance != AnnouncementImportance.urgent) {
                          _sendEmail = true;
                        }
                        _importance = importance;
                      }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTarget(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Hedef'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final type in AnnouncementTargetType.values)
              ChoiceChip(
                key: ValueKey<String>('announcement_target_${type.apiValue}'),
                label: Text(type.label),
                selected: _targetType == type,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _targetType = type;
                        _targetError = null;
                      }),
              ),
          ],
        ),
        if (_targetType == AnnouncementTargetType.blocks)
          ..._pickerSection(
            context,
            picks: _blocks,
            keptIds: _keptBlockIds,
            keptLabels: _keptBlockLabels,
            noun: 'blok',
            addLabel: 'Blok Ekle',
            onAdd: _pickBlock,
            onRemove: (id) => setState(() => _blocks = _blocks.where((b) => b.id != id).toList()),
            onClearKept: () => setState(() {
              _keptBlockIds = const <int>[];
              _keptBlockLabels = const <String>[];
            }),
            addKey: 'announcement_add_block',
          ),
        if (_targetType == AnnouncementTargetType.apartments)
          ..._pickerSection(
            context,
            picks: _apartments,
            keptIds: _keptApartmentIds,
            keptLabels: _keptApartmentLabels,
            noun: 'daire',
            addLabel: 'Daire Ekle',
            onAdd: _pickApartment,
            onRemove: (id) =>
                setState(() => _apartments = _apartments.where((a) => a.id != id).toList()),
            onClearKept: () => setState(() {
              _keptApartmentIds = const <int>[];
              _keptApartmentLabels = const <String>[];
            }),
            addKey: 'announcement_add_apartment',
          ),
        if (_targetType == AnnouncementTargetType.site) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Sitedeki tüm aktif dairelerin güncel sakinlerine gönderilir.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
        if (_targetError != null) ...[
          const SizedBox(height: AppSpace.sm),
          CrmFormError(message: _targetError!),
        ],
      ],
    );
  }

  List<Widget> _pickerSection(
    BuildContext context, {
    required List<_Picked> picks,
    required List<int> keptIds,
    required List<String> keptLabels,
    required String noun,
    required String addLabel,
    required Future<void> Function() onAdd,
    required void Function(int id) onRemove,
    required VoidCallback onClearKept,
    required String addKey,
  }) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return [
      const SizedBox(height: AppSpace.sm),
      if (keptIds.isNotEmpty) ...[
        // Kayıtlı seçim: etiketler yalnız gösterilir (tek tek çıkarılamaz); "Seçimi temizle" ile hepsi
        // kaldırılıp yeniden seçilebilir.
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (keptLabels.length == keptIds.length)
              for (final label in keptLabels) Chip(label: Text(label))
            else
              Chip(label: Text('${keptIds.length} $noun')),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Kayıtlı seçim tek tek çıkarılamaz; yeniden seçmek için "Seçimi temizle" kullanın.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        TextButton.icon(
          key: ValueKey<String>('${addKey}_clear'),
          onPressed: _submitting ? null : onClearKept,
          icon: const Icon(Icons.layers_clear_rounded, size: 18),
          label: const Text('Seçimi temizle'),
        ),
      ],
      if (picks.isNotEmpty) ...[
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            for (final pick in picks)
              _PickedChip(
                key: ValueKey<String>('announcement_pick_${pick.id}'),
                label: pick.label,
                onRemove: _submitting ? null : () => onRemove(pick.id),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      PrimaryActionButton(
        key: ValueKey<String>(addKey),
        label: addLabel,
        icon: Icons.add_rounded,
        variant: AppButtonVariant.outline,
        onPressed: _submitting ? null : onAdd,
      ),
    ];
  }

  Widget _buildChannels(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Gönderim'),
        SwitchListTile(
          key: const ValueKey<String>('announcement_send_email'),
          contentPadding: EdgeInsets.zero,
          title: const Text('E-posta da gönder'),
          subtitle: const Text(
            'Uygulama bildirimine ek olarak e-postası olan alıcılara da gönderilir. E-posta tercihini '
            'kapatan sakine normal duyuru e-postayla gitmez; acil duyurunun e-postası bu tercihten '
            'etkilenmez. Acil seçilince bu seçenek kendiliğinden açılır.',
          ),
          value: _sendEmail,
          onChanged: _submitting ? null : (value) => setState(() => _sendEmail = value),
        ),
        const _ComingSoonOption(label: 'SMS ile gönder', icon: Icons.sms_rounded),
        const _ComingSoonOption(label: 'WhatsApp ile gönder', icon: Icons.chat_rounded),
      ],
    );
  }

  Widget _buildPublish(BuildContext context, TextTheme th) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Yayın'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final mode in AnnouncementPublishMode.values)
              ChoiceChip(
                key: ValueKey<String>('announcement_mode_${mode.name}'),
                label: Text(mode.label),
                selected: _mode == mode,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _mode = mode;
                        _error = null;
                      }),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          switch (_mode) {
            AnnouncementPublishMode.draft =>
              'Taslak sakinlere görünmez; sonra düzenleyip yayınlayabilirsiniz.',
            AnnouncementPublishMode.now =>
              'Kaydedince yayınlanır; yayından önce kaç kişiye ulaşacağı gösterilir.',
            AnnouncementPublishMode.schedule =>
              'Seçtiğiniz zamanda otomatik yayınlanır. Saat İstanbul saatidir.',
          },
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        if (_mode == AnnouncementPublishMode.schedule) ...[
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const ValueKey<String>('announcement_publish_date'),
            controller: _date,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: const [DateInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Yayın tarihi',
              hintText: 'GG.AA.YYYY',
              prefixIcon: Icon(Icons.event_rounded),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) return 'Yayın tarihini girin.';
              return validateDateField(value);
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const ValueKey<String>('announcement_publish_time'),
            controller: _time,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: const [TimeInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Yayın saati (İstanbul)',
              hintText: 'SS:DD',
              prefixIcon: Icon(Icons.access_time_rounded),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) return 'Yayın saatini girin.';
              return validateTimeField(value);
            },
          ),
        ],
      ],
    );
  }

  /// Yayınlanmış duyuruda kilitli alanlar: değerleri ve nedeni açıklanır.
  Widget _buildLockedPanel(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final initial = _initial!;
    return DialogPanel(
      key: const ValueKey<String>('announcement_locked_panel'),
      tone: AppTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(
            icon: Icons.lock_outline_rounded,
            title: 'Kilitli alanlar',
            tone: AppTone.info,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Yayınlanmış duyuruda yalnızca başlık ve metin değiştirilebilir. Diğer alanlar kilitlidir. '
            'Düzenleme sakinlerde "düzenlendi" notuyla görünür; yeniden bildirim ya da e-posta gönderilmez.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          CrmInfoLine(label: 'Önem', value: initial.importance.label),
          const SizedBox(height: AppSpace.sm),
          CrmInfoLine(label: 'Hedef', value: initial.target.summary()),
          const SizedBox(height: AppSpace.sm),
          CrmInfoLine(
            label: 'E-posta',
            value: initial.sendEmail ? 'Gönderildi / gönderilecek' : 'İstenmedi',
          ),
          const SizedBox(height: AppSpace.sm),
          CrmInfoLine(
            label: 'Yayın',
            value: 'Yayınlandı: ${formatIstanbulDateTime(initial.publishedAt)}',
          ),
        ],
      ),
    );
  }
}

/// "Yakında…" etiketli PASİF seçenek (SMS / WhatsApp, Faz 3b): anahtar kapalı ve devre dışıdır; durum
/// yalnız renkle değil "Yakında…" metniyle de verilir. Ekran okuyucuya tek ifade olarak okunur.
class _ComingSoonOption extends StatelessWidget {
  const _ComingSoonOption({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.textSecondary),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(label, style: th.bodyLarge?.copyWith(color: p.textSecondary)),
            ),
            const SizedBox(width: AppSpace.sm),
            const Flexible(
              child: StatusChip(
                label: 'Yakında…',
                tone: AppTone.neutral,
                icon: Icons.schedule_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hedefte seçili blok / daire çipi: ✕ düğmesi en az 48x48 dp dokunma hedefidir (ipucu etiketli); uzun
/// etiket sarar (kırpılmaz).
class _PickedChip extends StatelessWidget {
  const _PickedChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpace.md,
                top: AppSpace.sm,
                bottom: AppSpace.sm,
              ),
              child: Text(label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            tooltip: '$label hedeften çıkar',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

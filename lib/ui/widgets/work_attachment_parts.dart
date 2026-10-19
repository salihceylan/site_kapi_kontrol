// Talep fotoğrafı ekleri için ortak parçalar (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri"): resim önbelleği,
// küçük görsel şeridi, tam ekran görüntüleyici (yakınlaştırma), seçilen fotoğraf listesi (form), yükleme ilerlemesi
// ve liste kartındaki fotoğraf sayısı çipi.
//
// Kurallar:
// - Resim baytları belirteçli `GET` ile gelir ve pencere ömrünce bellekte tutulur ([WorkAttachmentImageCache]);
//   başarısız indirme de tutulur (yeniden çizimde istek yinelenmez; "Tekrar Dene" açıkça yeniden ister).
// - Bellek: çözülen görseller Flutter'ın `ImageCache`'inde kalmasın diye oluşturulan her sağlayıcı kaydedilir ve pencere
//   kapanınca çıkarılır ([WorkImageProviders]); görsel çözülmeden ÖNCE piksel boyutu okunur, sunucu sınırını aşan
//   (kenar 12.000 / 40 milyon piksel) görsel hiç çözülmez ([WorkGuardedImage]).
// - Gizlilik: sakin görünümünde yükleyen adı GÖSTERİLMEZ: kendi fotoğrafı "Siz", diğerleri "Yönetim" (görevli adı
//   sakine sızmaz; bkz. [workAttachmentUploader]).
// - Küçük görsel sabit 96 dp (sarar, taşmaz); dokunma hedefleri en az 48 dp; durum yalnız renkle verilmez; ham renk
//   yok. Dosya adı günlüğe yazılmaz.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:site_kapi_kontrol/models/document_models.dart' show formatDocumentSize;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_attachment_upload.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Küçük görsel kenarı (dp).
const double kWorkThumbSize = 96;

/// Bellekteki görsellerin `ImageCache` kayıtlarını izler: [of] ile oluşturulan her sağlayıcı (`MemoryImage` ve kullanılan
/// her `cacheWidth` için `ResizeImage`) [evictBytes] / [dispose] ile önbellekten çıkarılır. Pencere kapanınca çözülmüş
/// fotoğraflar bellekte kalmaz (fotoğraf başına onlarca MB olabilir).
class WorkImageProviders {
  /// (baytlar, cacheWidth) çiftleri; `Uint8List` eşitliği kimliktir (aynı bayt nesnesi = aynı önbellek anahtarı).
  final Set<(Uint8List, int?)> _used = <(Uint8List, int?)>{};

  /// Görüntü sağlayıcısı: `Image.memory(bytes, cacheWidth:)` ile AYNI önbellek anahtarını üretir.
  ImageProvider<Object> of(Uint8List bytes, {int? cacheWidth}) {
    _used.add((bytes, cacheWidth));
    return ResizeImage.resizeIfNeeded(cacheWidth, null, MemoryImage(bytes));
  }

  /// Bu baytların tüm önbellek kayıtlarını çıkarır (fotoğraf silindi / seçimden kaldırıldı).
  void evictBytes(Uint8List bytes) {
    final entries = _used.where((entry) => identical(entry.$1, bytes)).toList();
    for (final entry in entries) {
      _evict(entry);
      _used.remove(entry);
    }
  }

  /// Tüm kayıtları önbellekten çıkarır (pencere kapanırken).
  void dispose() {
    for (final entry in _used) {
      _evict(entry);
    }
    _used.clear();
  }

  static void _evict((Uint8List, int?) entry) {
    final base = MemoryImage(entry.$1);
    unawaited(base.evict());
    final width = entry.$2;
    if (width != null) unawaited(ResizeImage(base, width: width).evict());
  }
}

/// Pencere ömrünce resim baytlarını tutar: aynı fotoğraf bir kez indirilir ve aynı `Future` nesnesi döner
/// (`FutureBuilder` yeniden kurulumda titremez). Başarısız indirme de tutulur: pencere her yeniden çizildiğinde
/// (ör. yükleme ilerlemesi) istek YİNELENMEZ; yeniden deneme yalnız açıkça [evict] ile olur (görüntüleyicideki
/// "Tekrar Dene"). [dispose] çözülmüş görselleri de `ImageCache`'ten çıkarır.
class WorkAttachmentImageCache {
  WorkAttachmentImageCache(this._fetch);

  final Future<Uint8List> Function(WorkAttachment attachment) _fetch;
  final Map<int, Future<Uint8List>> _futures = <int, Future<Uint8List>>{};
  final Map<int, Uint8List> _bytes = <int, Uint8List>{};

  /// Bu önbelleğin baytlarından oluşturulan görüntü sağlayıcıları (küçük görsel ve görüntüleyici).
  final WorkImageProviders images = WorkImageProviders();

  /// Zaten inmişse baytlar (eşzamanlı çizim); yoksa null.
  Uint8List? peek(int id) => _bytes[id];

  Future<Uint8List> load(WorkAttachment attachment) {
    final id = attachment.id;
    final existing = _futures[id];
    if (existing != null) return existing;
    final future = _fetch(attachment);
    _futures[id] = future;
    unawaited(
      future.then<void>(
        (bytes) {
          // Bu arada çıkarıldıysa (silme / yeniden deneme) eski yanıt yazılmaz.
          if (identical(_futures[id], future)) _bytes[id] = bytes;
        },
        onError: (Object _) {
          // Hata tutulur (bkz. sınıf notu); işlenmemiş hata sayılmasın diye burada yakalanır.
        },
      ),
    );
    return future;
  }

  /// Fotoğrafın baytlarını / hatasını ve çözülmüş görüntüsünü bırakır (silindi ya da yeniden denenecek).
  void evict(int id) {
    final bytes = _bytes.remove(id);
    _futures.remove(id);
    if (bytes != null) images.evictBytes(bytes);
  }

  /// Pencere kapanırken: bayt önbelleği ve `ImageCache` kayıtları bırakılır.
  void dispose() {
    images.dispose();
    _futures.clear();
    _bytes.clear();
  }
}

/// Seçimi ayırır: geçerli fotoğraflar (en çok [remaining]) ve kullanıcıya gösterilecek notlar. Geçersiz seçimler yer
/// DOLDURMAZ, her biri kendi satırında nedeniyle bildirilir ("ad: neden"); yer kalmadığı için alınmayanlar tek satır
/// sınır uyarısıdır.
({List<WorkPhotoPick> valid, List<String> notes}) workSplitSelection(
  WorkPhotoSelection selection, {
  required int remaining,
}) {
  final notes = <String>[];
  final valid = <WorkPhotoPick>[];
  for (final pick in <WorkPhotoPick>[...selection.picks, ...selection.rejected]) {
    final error = pick.validationError;
    if (error == null) {
      valid.add(pick);
    } else {
      notes.add('${pick.name}: $error');
    }
  }
  var overflow = selection.droppedCount;
  final room = remaining < 0 ? 0 : remaining;
  if (valid.length > room) {
    overflow += valid.length - room;
    valid.removeRange(room, valid.length);
  }
  if (overflow > 0) notes.add(WorkAttachmentRules.limitMessage);
  return (valid: valid, notes: notes);
}

/// Liste kartındaki "n fotoğraf" çipi (`attachment_count > 0`).
class WorkPhotoCountChip extends StatelessWidget {
  const WorkPhotoCountChip(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: '$count fotoğraf',
    tone: AppTone.neutral,
    icon: Icons.photo_camera_outlined,
  );
}

/// Yükleyen etiketi. Yönetim görünümünde ([showUploader]) sunucunun verdiği ad; SAKİN görünümünde ad gösterilmez:
/// kendi eklediği "Siz", diğer her fotoğraf "Yönetim" (sunucu yanlışlıkla ad gönderse bile görevli adı sızmaz).
String workAttachmentUploader(
  WorkAttachment attachment, {
  required bool showUploader,
}) {
  if (!showUploader) return attachment.uploadedByMe ? 'Siz' : 'Yönetim';
  final name = (attachment.uploadedByName ?? '').trim();
  if (name.isNotEmpty) return name;
  if (attachment.uploadedByMe) return 'Siz';
  return attachment.uploadedByKind == 'resident' ? 'Sakin' : 'Yönetim';
}

/// Yükleyen + tarih alt metni ("Ayşe Yılmaz · 19.10.2026 09:00"; sakinde "Yönetim · ..."). Ekranda ve ekran okuyucu
/// etiketinde AYNI metin kullanılır.
String workAttachmentCaption(
  WorkAttachment attachment, {
  required bool showUploader,
}) {
  final parts = <String>[
    workAttachmentUploader(attachment, showUploader: showUploader),
    if (attachment.createdAt != null) formatIstanbulDateTime(attachment.createdAt),
  ];
  return parts.join(' · ');
}

/// Bayt nesnesi -> "sunucu sınırını aşan görsel mi" (bir kez ölçülür).
final Expando<bool> _tooLargeMemo = Expando<bool>('work_image_too_large');

Future<bool> _measureTooLarge(Uint8List bytes) async {
  final known = _tooLargeMemo[bytes];
  if (known != null) return known;
  final size = await probeImageSize(bytes);
  final tooLarge =
      size != null &&
      WorkAttachmentRules.dimensionsTooLarge(size.width, size.height);
  _tooLargeMemo[bytes] = tooLarge;
  return tooLarge;
}

/// Bellek bombası korumalı görsel: çözmeden ÖNCE piksel boyutunu okur ([probeImageSize]); kenar 12.000'i ya da toplam
/// 40 milyon pikseli aşan görsel hiç çözülmez, [tooLargeBuilder] çizilir. Boyut okunamazsa görsel denenir (çözülemezse
/// [errorBuilder]). Sağlayıcı [images] kaydına girer (pencere kapanınca `ImageCache`'ten çıkar).
class WorkGuardedImage extends StatefulWidget {
  const WorkGuardedImage({
    super.key,
    required this.bytes,
    required this.images,
    required this.errorBuilder,
    required this.tooLargeBuilder,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final WorkImageProviders images;
  final WidgetBuilder errorBuilder;
  final WidgetBuilder tooLargeBuilder;
  final int? cacheWidth;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<WorkGuardedImage> createState() => _WorkGuardedImageState();
}

class _WorkGuardedImageState extends State<WorkGuardedImage> {
  bool? _tooLarge;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(WorkGuardedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _check();
  }

  void _check() {
    final token = ++_token;
    final bytes = widget.bytes;
    _tooLarge = _tooLargeMemo[bytes];
    if (_tooLarge != null) return;
    unawaited(
      _measureTooLarge(bytes).then((tooLarge) {
        if (!mounted || token != _token) return;
        setState(() => _tooLarge = tooLarge);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tooLarge = _tooLarge;
    if (tooLarge == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    if (tooLarge) return widget.tooLargeBuilder(context);
    return Image(
      image: widget.images.of(widget.bytes, cacheWidth: widget.cacheWidth),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => widget.errorBuilder(context),
    );
  }
}

/// Tek küçük görsel: hazır ek indirilip çizilir; tamamlanmamış (`uploading`) ek yer tutar: şu an gönderilen kayıtta
/// "Yükleniyor" ([inFlight]), yarıda kalmışta "Tamamlanmadı". Hepsi dokunulabilir: yarım kaydın sahibi
/// görüntüleyiciden onu silebilir (talep başına 4 sınırını doldurmasın).
class WorkAttachmentThumbnail extends StatelessWidget {
  const WorkAttachmentThumbnail({
    super.key,
    required this.attachment,
    required this.cache,
    this.onTap,
    this.size = kWorkThumbSize,
    this.showUploader = false,
    this.inFlight = false,
  });

  final WorkAttachment attachment;
  final WorkAttachmentImageCache cache;

  /// Dokununca (görüntüleyici); null ise dokunulamaz.
  final VoidCallback? onTap;
  final double size;

  /// Yönetim görünümü: yükleyenin adı (sakinde "Siz" / "Yönetim").
  final bool showUploader;

  /// Bu tamamlanmamış kaydın içeriği şu an gönderiliyor.
  final bool inFlight;

  Widget _image(BuildContext context, Uint8List bytes) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return WorkGuardedImage(
      bytes: bytes,
      images: cache.images,
      cacheWidth: (size * dpr).round(),
      width: size,
      height: size,
      errorBuilder: (context) => _placeholder(
        context,
        icon: Icons.broken_image_outlined,
        label: 'Açılamadı',
      ),
      tooLargeBuilder: (context) => _placeholder(
        context,
        icon: Icons.image_not_supported_outlined,
        label: 'Çok büyük',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ready = attachment.isReady;
    final radius = BorderRadius.circular(AppRadius.sm);
    final cached = ready ? cache.peek(attachment.id) : null;
    final Widget inner;
    if (!ready) {
      inner = _placeholder(
        context,
        icon: inFlight ? Icons.hourglass_top_rounded : Icons.error_outline_rounded,
        label: inFlight ? 'Yükleniyor' : 'Tamamlanmadı',
      );
    } else if (cached != null) {
      inner = _image(context, cached);
    } else {
      inner = FutureBuilder<Uint8List>(
        future: cache.load(attachment),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) return _image(context, bytes);
          if (snapshot.hasError) {
            return _placeholder(
              context,
              icon: Icons.broken_image_outlined,
              label: 'Açılamadı',
            );
          }
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.textSecondary),
            ),
          );
        },
      );
    }
    final caption = workAttachmentCaption(attachment, showUploader: showUploader);
    final semantic = StringBuffer('Fotoğraf: ${attachment.label}.');
    if (!ready) {
      semantic.write(inFlight ? ' Yükleniyor.' : ' Yüklemesi tamamlanmadı.');
    }
    if (caption.isNotEmpty) semantic.write(' $caption.');
    final tap = onTap;
    return Semantics(
      button: tap != null ? true : null,
      label: semantic.toString(),
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        color: p.surfaceMuted,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: SizedBox(width: size, height: size, child: inner),
        ),
      ),
    );
  }

  Widget _placeholder(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: p.textSecondary),
          const SizedBox(height: AppSpace.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Küçük görsel şeridi: sarar (320 dp x 2,0'da iki sütun); yönetim görünümünde ([showUploader]) altında yükleyen adı.
class WorkAttachmentStrip extends StatelessWidget {
  const WorkAttachmentStrip({
    super.key,
    required this.attachments,
    required this.cache,
    required this.onOpen,
    this.showUploader = false,
    this.inFlightAttachmentId,
    this.keyPrefix = 'work_attachment',
  });

  final List<WorkAttachment> attachments;
  final WorkAttachmentImageCache cache;

  /// Bir eke dokununca sırasıyla çağrılır.
  final void Function(int index) onOpen;

  /// Yönetim görünümü: yükleyenin adı (görselin altında ve ekran okuyucu etiketinde).
  final bool showUploader;

  /// İçeriği şu an gönderilen kaydın kimliği ("Yükleniyor"); diğer tamamlanmamışlar "Tamamlanmadı".
  final int? inFlightAttachmentId;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    if (attachments.isEmpty) {
      return Text(
        'Henüz fotoğraf yok.',
        key: ValueKey<String>('${keyPrefix}_empty'),
        style: th.bodyMedium?.copyWith(color: p.textSecondary),
      );
    }
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (var i = 0; i < attachments.length; i++)
          SizedBox(
            width: kWorkThumbSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                WorkAttachmentThumbnail(
                  key: ValueKey<String>('${keyPrefix}_${attachments[i].id}'),
                  attachment: attachments[i],
                  cache: cache,
                  showUploader: showUploader,
                  inFlight: attachments[i].id == inFlightAttachmentId,
                  onTap: () => onOpen(i),
                ),
                if (showUploader)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: ExcludeSemantics(
                      child: Text(
                        workAttachmentUploader(attachments[i], showUploader: true),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tam ekran görüntüleyici: sayfa sayfa kaydırma, yakınlaştırma ([InteractiveViewer]; yakınken sayfa kaymaz, sayfa
/// değişince yakınlık sıfırlanır), önceki / sonraki düğmeleri ve ok tuşları, yükleyen / tarih alt metni ve (yetki varsa)
/// "Sil". [show] kullanıcı silmeyi ONAYLADIYSA o eki döner (silme işini çağıran yapar); aksi hâlde null.
class WorkPhotoViewer extends StatefulWidget {
  const WorkPhotoViewer({
    super.key,
    required this.attachments,
    required this.cache,
    this.initialIndex = 0,
    this.canDelete,
    this.showUploader = false,
    this.inFlightAttachmentId,
  });

  final List<WorkAttachment> attachments;
  final WorkAttachmentImageCache cache;
  final int initialIndex;

  /// Gösterilen ek silinebilir mi (kurul: null / false → düğme yok).
  final bool Function(WorkAttachment attachment)? canDelete;

  /// Yönetim görünümü: yükleyenin adı (sakinde "Siz" / "Yönetim").
  final bool showUploader;

  /// İçeriği şu an gönderilen kaydın kimliği.
  final int? inFlightAttachmentId;

  static Future<WorkAttachment?> show(
    BuildContext context, {
    required List<WorkAttachment> attachments,
    required WorkAttachmentImageCache cache,
    int initialIndex = 0,
    bool Function(WorkAttachment attachment)? canDelete,
    bool showUploader = false,
    int? inFlightAttachmentId,
  }) {
    return showDialog<WorkAttachment>(
      context: context,
      useSafeArea: false,
      builder: (_) => WorkPhotoViewer(
        attachments: attachments,
        cache: cache,
        initialIndex: initialIndex,
        canDelete: canDelete,
        showUploader: showUploader,
        inFlightAttachmentId: inFlightAttachmentId,
      ),
    );
  }

  @override
  State<WorkPhotoViewer> createState() => _WorkPhotoViewerState();
}

class _WorkPhotoViewerState extends State<WorkPhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex.clamp(0, widget.attachments.length - 1),
  );
  late int _index = widget.initialIndex.clamp(0, widget.attachments.length - 1);
  int _retryEpoch = 0;

  /// Sayfa başına yakınlaştırma denetleyicisi; yakınken ([_zoomed]) sayfa kaydırma kapalıdır.
  final Map<int, TransformationController> _zoom = <int, TransformationController>{};
  bool _zoomed = false;

  @override
  void dispose() {
    for (final controller in _zoom.values) {
      controller.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  WorkAttachment get _current => widget.attachments[_index];

  TransformationController _zoomFor(int index) => _zoom.putIfAbsent(index, () {
    final controller = TransformationController();
    controller.addListener(() {
      if (index != _index || !mounted) return;
      final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
    return controller;
  });

  void _onPageChanged(int index) {
    final previous = _index;
    setState(() {
      _index = index;
      _zoomed = false;
    });
    // Bırakılan sayfanın yakınlığı sıfırlanır (geri dönülünce tam görünüm).
    _zoom[previous]?.value = Matrix4.identity();
  }

  void _go(int target) {
    if (target < 0 || target >= widget.attachments.length || target == _index) {
      return;
    }
    _zoom[_index]?.value = Matrix4.identity();
    final duration = AppMotion.of(context, AppMotion.base);
    if (duration == Duration.zero) {
      _pages.jumpToPage(target);
    } else {
      unawaited(
        _pages.animateToPage(target, duration: duration, curve: AppMotion.standard),
      );
    }
  }

  void _previous() => _go(_index - 1);

  void _next() => _go(_index + 1);

  Future<void> _confirmDelete() async {
    final attachment = _current;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Fotoğraf silinsin mi?',
        icon: Icons.delete_outline_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            key: const ValueKey<String>('work_photo_delete_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('work_photo_delete_confirm'),
            onPressed: () => popIfCurrent(dialogContext, true),
            style: filledToneStyle(dialogContext, tone: AppTone.danger),
            child: const Text('Sil'),
          ),
        ],
        child: Text(
          '"${attachment.label}" talepten kalıcı olarak kaldırılır. Bu işlem geri alınamaz.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (go != true || !mounted) return;
    popIfCurrent<WorkAttachment>(context, attachment);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final total = widget.attachments.length;
    final current = _current;
    final canDelete = widget.canDelete?.call(current) ?? false;
    final caption = workAttachmentCaption(current, showUploader: widget.showUploader);
    const navConstraints = BoxConstraints(minWidth: 48, minHeight: 48);
    return Dialog.fullscreen(
      key: const ValueKey<String>('work_photo_viewer'),
      backgroundColor: p.surface,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
          const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: p.surfaceMuted,
            appBar: AppBar(
              leading: IconButton(
                key: const ValueKey<String>('work_photo_viewer_close'),
                tooltip: 'Kapat',
                onPressed: () => popIfCurrent<WorkAttachment>(context),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text('Fotoğraf ${_index + 1}/$total'),
              actions: [
                if (canDelete)
                  IconButton(
                    key: const ValueKey<String>('work_photo_viewer_delete'),
                    tooltip: 'Fotoğrafı sil',
                    onPressed: () => unawaited(_confirmDelete()),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey<String>('work_photo_viewer_pages'),
                    controller: _pages,
                    // Yakınken sürükleme görseli kaydırır, sayfayı değil.
                    physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                    itemCount: total,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) => _page(context, i, widget.attachments[i]),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.sm,
                      AppSpace.sm,
                      AppSpace.sm,
                      AppSpace.md,
                    ),
                    child: Row(
                      children: [
                        if (total > 1)
                          IconButton(
                            key: const ValueKey<String>('work_photo_viewer_previous'),
                            tooltip: 'Önceki fotoğraf',
                            constraints: navConstraints,
                            onPressed: _index > 0 ? _previous : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${current.label} · ${formatDocumentSize(current.sizeBytes)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (caption.isNotEmpty)
                                  Text(
                                    caption,
                                    key: const ValueKey<String>('work_photo_viewer_caption'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: th.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (total > 1)
                          IconButton(
                            key: const ValueKey<String>('work_photo_viewer_next'),
                            tooltip: 'Sonraki fotoğraf',
                            constraints: navConstraints,
                            onPressed: _index < total - 1 ? _next : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text, {Key? key}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Text(
        text,
        key: key,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );

  Widget _page(BuildContext context, int index, WorkAttachment attachment) {
    final p = context.palette;
    if (!attachment.isReady) {
      final inFlight = attachment.id == widget.inFlightAttachmentId;
      return _message(
        context,
        inFlight
            ? 'Bu fotoğraf şu an yükleniyor.'
            : 'Bu fotoğrafın yüklemesi tamamlanmadı. Yükleme yarıda kaldıysa fotoğrafı silip yeniden ekleyebilirsiniz.',
        key: const ValueKey<String>('work_photo_viewer_incomplete'),
      );
    }
    final media = MediaQuery.of(context);
    // Çözme genişliği ekran genişliği x yoğunluk x 2 ile sınırlı (yakınlaştırmaya pay; küçük görsel büyütülmez).
    final cacheWidth = (media.size.width * media.devicePixelRatio * 2).round();
    return FutureBuilder<Uint8List>(
      key: ValueKey<String>('work_photo_page_${attachment.id}_$_retryEpoch'),
      future: widget.cache.load(attachment),
      initialData: widget.cache.peek(attachment.id),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return InteractiveViewer(
            transformationController: _zoomFor(index),
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: WorkGuardedImage(
                bytes: bytes,
                images: widget.cache.images,
                cacheWidth: cacheWidth > 0 ? cacheWidth : null,
                fit: BoxFit.contain,
                errorBuilder: (context) =>
                    _message(context, 'Fotoğraf açılamadı (dosya bozuk olabilir).'),
                tooLargeBuilder: (context) => _message(
                  context,
                  'Fotoğrafın çözünürlüğü çok yüksek olduğu için gösterilemiyor.',
                  key: const ValueKey<String>('work_photo_viewer_too_large'),
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: InlineNotice(
                message:
                    'Fotoğraf alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
                onRetry: () => setState(() {
                  // Tutulan hata bırakılır: yeni FutureBuilder yeni istek başlatır.
                  widget.cache.evict(attachment.id);
                  _retryEpoch++;
                }),
              ),
            ),
          );
        }
        return Center(child: CircularProgressIndicator(color: p.textSecondary));
      },
    );
  }
}

/// Formda seçilen fotoğraflar: satır başına küçük görsel + ad + boyut + "Kaldır" (48 dp). Önizlemeler [images] kaydına
/// girer (form kapanınca / fotoğraf kaldırılınca `ImageCache`'ten çıkar).
class WorkPickedPhotoList extends StatelessWidget {
  const WorkPickedPhotoList({
    super.key,
    required this.photos,
    required this.onRemove,
    required this.images,
    this.enabled = true,
    this.keyPrefix = 'work_form_photo',
  });

  final List<WorkPhotoPick> photos;
  final void Function(int index) onRemove;
  final WorkImageProviders images;
  final bool enabled;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget icon(IconData data) => Icon(data, color: p.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < photos.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == photos.length - 1 ? 0 : AppSpace.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: p.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: photos[i].bytes.isEmpty
                            ? icon(Icons.image_not_supported_outlined)
                            : WorkGuardedImage(
                                bytes: photos[i].bytes,
                                images: images,
                                cacheWidth: (56 * dpr).round(),
                                width: 56,
                                height: 56,
                                errorBuilder: (_) => icon(Icons.broken_image_outlined),
                                tooLargeBuilder: (_) =>
                                    icon(Icons.image_not_supported_outlined),
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            photos[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodyMedium?.copyWith(color: p.text),
                          ),
                          Text(
                            formatDocumentSize(photos[i].size),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey<String>('${keyPrefix}_remove_$i'),
                      tooltip: 'Fotoğrafı kaldır',
                      onPressed: enabled ? () => onRemove(i) : null,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Yükleme ilerlemesi: "Fotoğraf 2/3 yükleniyor", çubuk, yüzde / bayt (web'de belirsiz çubuk) ve "Vazgeç".
class WorkUploadProgress extends StatelessWidget {
  const WorkUploadProgress({
    super.key,
    required this.controller,
    this.onCancel,
    this.keyPrefix = 'work_upload',
  });

  final WorkAttachmentUploadController controller;

  /// null ise iptal düğmesi yok.
  final VoidCallback? onCancel;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final phase = c.phase;
        final title = c.total > 1
            ? 'Fotoğraf ${c.index}/${c.total} yükleniyor...'
            : 'Fotoğraf yükleniyor...';
        final status = switch (phase) {
          WorkUploadPhase.preparing => 'Sunucu fotoğrafı doğruluyor...',
          WorkUploadPhase.finishing => 'Fotoğraf gönderildi, sunucu kaydediyor...',
          _ when !c.progressKnown => 'Fotoğraf gönderiliyor...',
          _ =>
            '%${c.percent} · ${formatDocumentSize(c.sentBytes)} / ${formatDocumentSize(c.totalBytes)}',
        };
        final fraction = phase == WorkUploadPhase.preparing ? null : c.fraction;
        return Semantics(
          container: true,
          liveRegion: true,
          label: '$title $status',
          child: ExcludeSemantics(
            child: Column(
              key: ValueKey<String>('${keyPrefix}_progress'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: th.titleSmall),
                const SizedBox(height: AppSpace.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                    backgroundColor: p.surfaceMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(status, style: th.bodySmall),
                if (onCancel != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: ValueKey<String>('${keyPrefix}_cancel'),
                      onPressed: onCancel,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Vazgeç'),
                      style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Seçilen fotoğraflar yüklemeden önce hazırlanıyor (küçültme, JPEG, EXIF silme; bkz. `work_photo_prepare.dart`):
/// belirsiz çubuk ve "Fotoğraf hazırlanıyor...". Ekran okuyucuya bir kez duyurulur.
class WorkPhotoPreparing extends StatelessWidget {
  const WorkPhotoPreparing({super.key, this.keyPrefix = 'work_photo'});

  static const String label = 'Fotoğraf hazırlanıyor...';

  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Column(
          key: ValueKey<String>('${keyPrefix}_preparing'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: th.titleSmall),
            const SizedBox(height: AppSpace.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(minHeight: 8, backgroundColor: p.surfaceMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fotoğraf seçicinin altındaki kural ipucu (ayrıntı penceresi ve talep formu).
const String kWorkPhotoPrepareHint = 'Fotoğraflar yüklenmeden önce küçültülür; konum bilgisi silinir.';

/// 409 `LIMIT_REACHED` sınır kilidinden ("başka fotoğraf yükleniyor olabilir") sonra ayrıntının sessizce yeniden
/// yüklenme süresi (kilit kalıcı olmasın).
const Duration kWorkLimitRecheckDelay = Duration(seconds: 30);

/// Ayrıntı penceresindeki "Fotoğraflar" bölümü: sayaç, şerit, hazırlama / yükleme ilerlemesi, hata ve "Fotoğraf Ekle".
/// Düğmeler yalnız [canAdd] iken çizilir (kurul: hiç; sakin: talep açıkken; yönetim: yazma yetkisiyle).
class WorkAttachmentSection extends StatelessWidget {
  const WorkAttachmentSection({
    super.key,
    required this.attachments,
    required this.cache,
    required this.onOpen,
    this.loading = false,
    this.canAdd = false,
    this.addLocked = false,
    this.onAdd,
    this.uploader,
    this.onCancelUpload,
    this.error,
    this.showUploader = false,
    this.preparing = false,
    this.keyPrefix = 'work_attachment',
  });

  final List<WorkAttachment> attachments;
  final WorkAttachmentImageCache cache;
  final void Function(int index) onOpen;

  /// Ayrıntı yükleniyor ve liste boş: iskelet.
  final bool loading;
  final bool canAdd;

  /// Hız sınırı kilidi (429) ya da sınır beklemesi: düğme kapalı.
  final bool addLocked;
  final VoidCallback? onAdd;

  /// Sürmekte olan yükleme (ilerleme çubuğu); yoksa null.
  final WorkAttachmentUploadController? uploader;
  final VoidCallback? onCancelUpload;

  /// Yükleme / silme / seçim hatası.
  final String? error;

  /// Yönetim görünümü: yükleyenin adı (sakinde "Siz" / "Yönetim").
  final bool showUploader;

  /// Seçilen fotoğraflar hazırlanıyor ([WorkPhotoPreparing]); düğme kapalı.
  final bool preparing;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final uploading = uploader?.busy ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text('Fotoğraflar', style: th.titleSmall),
            ),
            InfoChip('${attachments.length}/$kWorkAttachmentMax'),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (loading && attachments.isEmpty)
          const ListSkeleton(rows: 1, inCard: true)
        else
          WorkAttachmentStrip(
            attachments: attachments,
            cache: cache,
            onOpen: onOpen,
            showUploader: showUploader,
            inFlightAttachmentId: uploader?.inFlightAttachmentId,
            keyPrefix: keyPrefix,
          ),
        if (preparing && !uploading) ...[
          const SizedBox(height: AppSpace.md),
          WorkPhotoPreparing(keyPrefix: keyPrefix),
        ],
        if (uploading && uploader != null) ...[
          const SizedBox(height: AppSpace.md),
          WorkUploadProgress(
            controller: uploader!,
            onCancel: onCancelUpload,
            keyPrefix: '${keyPrefix}_upload',
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.sm),
          InlineNotice(key: ValueKey<String>('${keyPrefix}_error'), message: error!),
        ],
        if (canAdd) ...[
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            key: ValueKey<String>('${keyPrefix}_add'),
            label: 'Fotoğraf Ekle',
            icon: Icons.add_a_photo_outlined,
            variant: AppButtonVariant.tonal,
            onPressed: (uploading || preparing || addLocked) ? null : onAdd,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'En fazla $kWorkAttachmentMax fotoğraf; JPEG, PNG veya WebP. $kWorkPhotoPrepareHint',
            key: ValueKey<String>('${keyPrefix}_hint'),
            style: th.bodySmall,
          ),
        ],
      ],
    );
  }
}

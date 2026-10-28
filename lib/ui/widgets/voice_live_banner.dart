// FAZ 5 / A1b-(iii): sesli dinleme canlı banner'ı (ortak bileşen).
//
// `ResidentDoorRemoteCard` ve `AdminDoorStatusCard` içinde birebir kopya olan `_buildVoiceLiveBanner`
// (~140 satır) burada tek yerde toplandı. Metinler (emoji dahil) kopyalarla BİREBİR aynıdır ve
// davranış aynıdır: düğme dinliyorsa durdurur, değilse dinlemeyi başlatır. Renkler tasarım
// sistemine bağlandı (kopyalar koyu zemine göre yazılmıştı: açık temada açık gri metin okunmuyordu).
//
// İki katman: [VoiceLiveBanner] servise bağlanır (`AnimatedBuilder`), [VoiceLiveBannerView] yalnız
// durum + metin alır (saf görünüm; her durum servis olmadan sınanabilir).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [VoiceDoorService]'e bağlı canlı banner: servis her bildirimde (durum, tanınan sözcükler, geri
/// bildirim metni) yalnız banner yeniden kurulur.
///
/// [candidateDoors]: dinleme başlatılırken servise verilecek aday kapılar (yönetici kartı kendi kapı
/// listesini verir; sakin kartı vermez: `null` = `startListening()` ile aynı).
class VoiceLiveBanner extends StatelessWidget {
  const VoiceLiveBanner({
    super.key,
    required this.service,
    this.candidateDoors,
  });

  final VoiceDoorService service;
  final List<DoorRecord>? candidateDoors;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => VoiceLiveBannerView(
        status: service.status,
        recognizedWords: service.recognizedWords,
        feedbackText: service.feedbackText,
        onStart: () => service.startListening(candidateDoors: candidateDoors),
        onStop: service.stopListening,
      ),
    );
  }
}

/// Saf görünüm: [status] + metinler -> banner. Servise bağlı değildir.
///
/// Durumlar (ton): dinliyor (success) • komut algılanıyor (primary) • komut gönderildi (success) •
/// hata (danger) • boşta/başlatılıyor (neutral). Eylem düğmesi dinliyorsa [onStop], değilse [onStart]
/// çağırır.
///
/// Taşma: başlık en çok 2, alt başlık en çok 4 satıra sarar (sonra elips); sabit yükseklik yoktur.
/// Büyük yazı / dar ekranda (metin sütunu 7 em'den dar kalacaksa; örn. 320 dp x 2,0 ya da
/// 360 dp x 1,5 kart içinde) KOMPAKT düzen: dekoratif başlangıç simgesi atlanır (başlıktaki emoji ve
/// düğme simgesi durumu zaten söyler) ve satır sınırları 3 / 6'ya gevşer; böylece metin ezilip
/// kırpılmaz.
/// Erişilebilirlik: banner TEK anlamsal düğüm olarak okunur (başlık + alt başlık; dokunma = düğme);
/// simge dekoratiftir. Düğmenin dokunma hedefi 48 dp'dir. Yeni metin eklenmedi (düğmenin ayrı
/// ipucu/tooltip metni yok: mevcut başlık/alt başlık okunur; bu yüzden ayrı bir durum rozeti
/// ([StatusChip] etiketi) de eklenmedi: etiketi anlamsal düğüme yeni metin katardı).
/// Hareket: durum değişince renk 200 ms morph eder, simge belirir (`Pop`); hareket azaltmada anında.
///
/// Görünüm ("cam" şerit): ton zemini + sol-üstten inen statik ışık (gradyan; `saveLayer`,
/// `BackdropFilter`, ek gölge yok: kart-içinde-kart), başlangıçta cilalı ton küresi ([IconOrb];
/// dinlerken tonun glow'u). Hepsi durağandır: kararlı durumda ticker yoktur.
class VoiceLiveBannerView extends StatelessWidget {
  const VoiceLiveBannerView({
    super.key,
    required this.status,
    required this.onStart,
    required this.onStop,
    this.recognizedWords = '',
    this.feedbackText = '',
  });

  final VoiceStatus status;

  /// Servisin o an tanıdığı sözcükler ([VoiceDoorService.recognizedWords]).
  final String recognizedWords;

  /// Servisin geri bildirim metni ([VoiceDoorService.feedbackText]); yalnız hata durumunda gösterilir.
  final String feedbackText;

  /// Dinlemiyorken düğmeye basılınca.
  final VoidCallback onStart;

  /// Dinlerken düğmeye basılınca.
  final VoidCallback onStop;

  /// Başlangıç küresinin çapı (dp).
  static const double _orbSize = 38;

  /// Normal düzende metin dışı sabit genişlik: simge küresi 38 + 12 + 8 + düğme 48.
  static const double _fixedWidth = _orbSize + AppSpace.md + AppSpace.sm + 48;

  /// Zeminin üstüne binen statik "cam" ışığı: koyuda soluk beyaz (AppCard ile aynı), açıkta daha belirgin
  /// beyaz yansıma. İki uçta da beyazdır: metin kontrastını koyu temada çok az, açıkta artırarak etkiler.
  static LinearGradient _glass(AppPalette p) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Colors.white.withValues(alpha: p.isDark ? 0.07 : 0.55),
      Colors.white.withValues(alpha: 0),
    ],
    stops: const <double>[0.0, 0.65],
  );

  /// Metin sütunu bundan (1 em = 16 dp x yazı ölçeği) dar kalacaksa kompakt düzen kullanılır.
  static const double _minTextEm = 7;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final look = _VoiceBannerLook.of(status, recognizedWords, feedbackText);
    final tone = look.tone;
    final ink = tone.ink(p);
    final listening = status == VoiceStatus.listening;
    final neutral = tone == AppTone.neutral;

    return MergeSemantics(
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.standard,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: neutral ? p.surfaceMuted : tone.tint(p),
          gradient: _glass(p),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: neutral ? p.border : tone.hue.withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Büyük yazı / dar ekranda metin sütunu ezilmesin (sınırsız genişlikte kompakt olmaz).
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final textWidth = constraints.maxWidth - _fixedWidth;
            final compact = textWidth < _minTextEm * 16 * scale;
            return Row(
              children: <Widget>[
                if (!compact) ...<Widget>[
                  // Küre dekoratiftir (IconOrb anlamsal ağaçtan kendisi dışlanır).
                  Pop(
                    // Anahtar durum değil SİMGE: boşta <-> başlatılıyor aynı görünür, simge
                    // yeniden belirmez.
                    key: ValueKey<IconData>(look.icon),
                    child: IconOrb(
                      icon: look.icon,
                      tone: tone,
                      size: _orbSize,
                      // Canlı dinleme: tonun glow'u (tek katman, statik).
                      glow: listening,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        look.title,
                        maxLines: compact ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: th.titleMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        look.subtitle,
                        maxLines: compact ? 6 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: th.bodyMedium?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: tone.hue.withValues(alpha: 0.15),
                    foregroundColor: ink,
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    // Düğmenin kendi renk morph'u da hareket azaltmada kapalı: "tüm süreler
                    // AppMotion.of'tan geçer" (yoksa 200 ms'lik gizli bir ticker kalırdı).
                    animationDuration: AppMotion.of(context, AppMotion.base),
                  ),
                  onPressed: listening ? onStop : onStart,
                  icon: Icon(
                    listening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: ink,
                    size: 20,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bir durumun görünümü: ton, simge ve metinler (kopyalardaki `switch` ile birebir).
@immutable
class _VoiceBannerLook {
  const _VoiceBannerLook(this.tone, this.icon, this.title, this.subtitle);

  final AppTone tone;
  final IconData icon;
  final String title;
  final String subtitle;

  factory _VoiceBannerLook.of(
    VoiceStatus status,
    String recognizedWords,
    String feedbackText,
  ) {
    switch (status) {
      case VoiceStatus.listening:
        return _VoiceBannerLook(
          AppTone.success,
          Icons.mic_rounded,
          '🎙️ Sesli Dinleme Aktif',
          recognizedWords.isNotEmpty
              ? '"$recognizedWords"'
              : 'Dinleniyor... "Kapıyı aç" diyebilirsiniz.',
        );
      case VoiceStatus.processing:
        return _VoiceBannerLook(
          AppTone.primary,
          Icons.auto_awesome_rounded,
          '🤖 Komut Algılanıyor...',
          '"$recognizedWords"',
        );
      case VoiceStatus.success:
        return const _VoiceBannerLook(
          AppTone.success,
          Icons.lock_open_rounded,
          '🔓 Komut Gönderildi',
          'Sesli komut onaylandı, açma komutu gönderildi.',
        );
      case VoiceStatus.error:
        return _VoiceBannerLook(
          AppTone.danger,
          Icons.error_outline_rounded,
          '⚠️ Sesli Komut Hatası',
          feedbackText.isNotEmpty ? feedbackText : 'Bilinmeyen hata',
        );
      case VoiceStatus.idle:
      case VoiceStatus.initializing:
        return const _VoiceBannerLook(
          AppTone.neutral,
          Icons.mic_none_rounded,
          '🎙️ Sesli Kapı Açma',
          'Başlatmak için dokunun',
        );
    }
  }
}

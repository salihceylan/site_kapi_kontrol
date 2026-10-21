import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';

/// Finans > Grafikler'in giriş animasyonu (çubuklar alttan büyür, çizgiler soldan sağa çizilir, tutar ve yüzde 0'dan sayar).
///
/// Kurallar:
/// - Kart başına TEK `AnimationController` (kartın state'inde); aynı karttaki bütün grafikler [ChartRevealScope] ile onu okur.
///   fl_chart'ın kendi animasyonu yalnız VERİ DEĞİŞİNCE oynar (ilk kurulumda doğrudan son hali çizer), bu yüzden ilk giriş
///   ve yenileme bu ilerleme değeriyle sürülür; çizimde fl_chart animasyonu kapatılır (süre sıfır).
/// - Süre 800 ms ([kChartRevealDuration]), eğri `AppMotion.enter` (easeOutCubic), kartlar arası kademe [kChartRevealStagger].
/// - Sonsuz animasyon yoktur; animasyon sekme açılırken (veri gelince) bir kez oynar, yalnız veri değişince yeniden oynar.
/// - `MediaQuery.disableAnimations` açıkken kart denetleyicisi hiç çalışmaz: ilk karede son hal çizilir.
const Duration kChartRevealDuration = Duration(milliseconds: 800);

/// Kartlar arası giriş kademesi (kart sırası x bu süre kadar geç başlar).
const Duration kChartRevealStagger = Duration(milliseconds: 70);

/// Kartın giriş ilerlemesini (0 -> 1, eğri uygulanmış) altındaki grafiklere verir.
///
/// Kapsam yoksa ([maybeOf] null) grafik tek başına kullanılıyordur: animasyon uygulanmaz, son hal çizilir.
class ChartRevealScope extends InheritedWidget {
  const ChartRevealScope({super.key, required this.progress, required super.child});

  final Animation<double> progress;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChartRevealScope>()?.progress;

  @override
  bool updateShouldNotify(ChartRevealScope oldWidget) => !identical(progress, oldWidget.progress);
}

/// Çizgiyi soldan sağa çizer: [progress] (0..1) kadarını gösterir; sınırdaki parça iki nokta arasında ara değerlenir.
///
/// Boş (null) noktalar korunur; [progress] 1 ya da daha fazlaysa liste aynen döner.
List<FlSpot> revealSpots(List<FlSpot> spots, double progress) {
  if (progress >= 1 || spots.length < 2) return spots;
  final limit = progress.clamp(0.0, 1.0) * (spots.length - 1);
  final out = <FlSpot>[];
  for (var i = 0; i < spots.length; i++) {
    if (i <= limit) {
      out.add(spots[i]);
      continue;
    }
    final prev = spots[i - 1];
    final next = spots[i];
    if (prev.isNotNull() && next.isNotNull()) {
      out.add(FlSpot(prev.x + (next.x - prev.x) * (limit - (i - 1)), prev.y + (next.y - prev.y) * (limit - (i - 1))));
    }
    break;
  }
  return out;
}

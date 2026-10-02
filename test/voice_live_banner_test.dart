// FAZ 5 / A1b-(iii): VoiceLiveBanner / VoiceLiveBannerView widget testleri.
//
// İki kartta (sakin + yönetici) birebir kopya olan sesli dinleme banner'ının ortak bileşeni:
// her durumun metni (mevcut kopyalarla BİREBİR), tonu, eylem düğmesi; servis bağlantısı;
// taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu); hareket azaltma; pumpAndSettle'ın
// bitmesi; Semantics ve dokunma hedefi.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_live_banner.dart';

import 'design/harness.dart';

// Mevcut `_buildVoiceLiveBanner` kopyalarındaki metinler (birebir).
const String _idleTitle = '🎙️ Sesli Kapı Açma';
const String _idleSubtitle = 'Başlatmak için dokunun';
const String _listeningTitle = '🎙️ Sesli Dinleme Aktif';
const String _listeningHint = 'Dinleniyor... "Kapıyı aç" diyebilirsiniz.';
const String _processingTitle = '🤖 Komut Algılanıyor...';
const String _successTitle = '🔓 Kapı Açılıyor!';
const String _successSubtitle = 'Sesli komut onaylandı, kapı tetikleniyor...';
const String _errorTitle = '⚠️ Sesli Komut Hatası';
const String _unknownError = 'Bilinmeyen hata';

/// Bir durumun beklenen görünümü.
class _Case {
  const _Case(
    this.name,
    this.status, {
    this.words = '',
    this.feedback = '',
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.buttonIcon,
  });

  final String name;
  final VoiceStatus status;
  final String words;
  final String feedback;
  final String title;
  final String subtitle;
  final IconData icon;
  final AppTone tone;
  final IconData buttonIcon;
}

const List<_Case> _cases = <_Case>[
  _Case(
    'boşta',
    VoiceStatus.idle,
    title: _idleTitle,
    subtitle: _idleSubtitle,
    icon: Icons.mic_none_rounded,
    tone: AppTone.neutral,
    buttonIcon: Icons.mic_rounded,
  ),
  _Case(
    'başlatılıyor (boşta gibi; geri bildirim metni gösterilmez)',
    VoiceStatus.initializing,
    words: 'x',
    feedback: 'Ses motoru başlatılıyor...',
    title: _idleTitle,
    subtitle: _idleSubtitle,
    icon: Icons.mic_none_rounded,
    tone: AppTone.neutral,
    buttonIcon: Icons.mic_rounded,
  ),
  _Case(
    'dinliyor (söz yok: ipucu)',
    VoiceStatus.listening,
    title: _listeningTitle,
    subtitle: _listeningHint,
    icon: Icons.mic_rounded,
    tone: AppTone.success,
    buttonIcon: Icons.stop_rounded,
  ),
  _Case(
    'dinliyor (tanınan sözcükler tırnak içinde)',
    VoiceStatus.listening,
    words: 'ana kapıyı aç',
    title: _listeningTitle,
    subtitle: '"ana kapıyı aç"',
    icon: Icons.mic_rounded,
    tone: AppTone.success,
    buttonIcon: Icons.stop_rounded,
  ),
  _Case(
    'komut algılanıyor',
    VoiceStatus.processing,
    words: 'ana kapıyı aç',
    title: _processingTitle,
    subtitle: '"ana kapıyı aç"',
    icon: Icons.auto_awesome_rounded,
    tone: AppTone.primary,
    buttonIcon: Icons.mic_rounded,
  ),
  _Case(
    'kapı açılıyor',
    VoiceStatus.success,
    title: _successTitle,
    subtitle: _successSubtitle,
    icon: Icons.lock_open_rounded,
    tone: AppTone.success,
    buttonIcon: Icons.mic_rounded,
  ),
  _Case(
    'hata (geri bildirim metni)',
    VoiceStatus.error,
    feedback: 'Mikrofon veya ses tanıma izni alınamadı.',
    title: _errorTitle,
    subtitle: 'Mikrofon veya ses tanıma izni alınamadı.',
    icon: Icons.error_outline_rounded,
    tone: AppTone.danger,
    buttonIcon: Icons.mic_rounded,
  ),
  _Case(
    'hata (metin yok: Bilinmeyen hata)',
    VoiceStatus.error,
    title: _errorTitle,
    subtitle: _unknownError,
    icon: Icons.error_outline_rounded,
    tone: AppTone.danger,
    buttonIcon: Icons.mic_rounded,
  ),
];

Widget _view(_Case c, {VoidCallback? onStart, VoidCallback? onStop}) =>
    VoiceLiveBannerView(
      status: c.status,
      recognizedWords: c.words,
      feedbackText: c.feedback,
      onStart: onStart ?? () {},
      onStop: onStop ?? () {},
    );

/// Banner'ın (AnimatedContainer) o anki süslemesi.
BoxDecoration _decoration(WidgetTester t) {
  final f = find.descendant(
    of: find.byType(AnimatedContainer),
    matching: find.byType(DecoratedBox),
  );
  return t.widget<DecoratedBox>(f.first).decoration as BoxDecoration;
}

TextStyle _style(WidgetTester t, String text) =>
    t.widget<Text>(find.text(text)).style!;

/// Önde (leading) gösterilen durum simgesi (düğmenin içindekini sayma).
Icon _leadingIcon(WidgetTester t) {
  final f = find.descendant(
    of: find.byType(Container),
    matching: find.byType(Icon),
  );
  return t.widget<Icon>(f.first);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

DoorRecord _door(int id, String name) => DoorRecord(
  id: id,
  siteCode: 1,
  siteName: 'Gude Sitesi',
  doorIndex: id,
  doorName: name,
  isActive: true,
  assignedDeviceId: id,
  assignedDeviceUid: 'ESP_$id',
  mqttSiteId: 1,
  createdAt: null,
);

/// Durumu elle sürülen sahte servis (gerçek konuşma motoru/platform kanalı yok).
class _FakeVoice extends ChangeNotifier implements VoiceDoorService {
  VoiceStatus _status = VoiceStatus.idle;
  String _words = '';
  String _feedback = '';
  final List<List<DoorRecord>?> startCalls = <List<DoorRecord>?>[];
  int stopCalls = 0;
  int listenerCount = 0;

  void set({VoiceStatus? status, String? words, String? feedback}) {
    _status = status ?? _status;
    _words = words ?? _words;
    _feedback = feedback ?? _feedback;
    notifyListeners();
  }

  @override
  VoiceStatus get status => _status;

  @override
  String get recognizedWords => _words;

  @override
  String get feedbackText => _feedback;

  @override
  bool get isListening => _status == VoiceStatus.listening;

  @override
  Future<void> startListening({List<DoorRecord>? candidateDoors}) async {
    startCalls.add(candidateDoors);
    set(status: VoiceStatus.listening, words: '', feedback: _listeningHint);
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    set(status: VoiceStatus.idle, words: '', feedback: '');
  }

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceLiveBannerView: her durumun metni, simgesi ve tonu', () {
    for (final c in _cases) {
      testWidgets(c.name, (t) async {
        for (final dark in const [false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          await pumpAt(t, _view(c), scale: 1.0, dark: dark);

          expect(find.text(c.title), findsOneWidget);
          expect(find.text(c.subtitle), findsOneWidget);
          if (c.status == VoiceStatus.initializing) {
            expect(find.text(c.feedback), findsNothing);
          }
          expect(_leadingIcon(t).icon, c.icon, reason: 'dark=$dark');
          expect(_leadingIcon(t).color, c.tone.ink(p));
          expect(
            find.descendant(
              of: find.byType(IconButton),
              matching: find.byIcon(c.buttonIcon),
            ),
            findsOneWidget,
            reason: 'düğme simgesi',
          );

          // Renkler: başlık = ton mürekkebi (w800), alt başlık = ikincil metin.
          final title = _style(t, c.title);
          expect(title.color, c.tone.ink(p));
          expect(title.fontWeight, FontWeight.w800);
          expect(_style(t, c.subtitle).color, p.textSecondary);

          final d = _decoration(t);
          final neutral = c.tone == AppTone.neutral;
          expect(
            d.color,
            neutral ? p.surfaceMuted : c.tone.tint(p),
            reason: 'dark=$dark',
          );
          expect(
            (d.border! as Border).top.color,
            neutral ? p.border : c.tone.hue.withValues(alpha: 0.6),
          );
          expect(d.borderRadius, BorderRadius.circular(AppRadius.md));
          expect(d.boxShadow, isNull, reason: 'kart-içinde-kart: ek gölge yok');
        }
      });
    }

    testWidgets('metinler mevcut kopyalarla birebir (sabit değerler)', (
      t,
    ) async {
      expect(
        _idleTitle.codeUnits,
        '\u{1F399}\u{FE0F} Sesli Kapı Açma'.codeUnits,
      );
      expect(
        _listeningTitle.codeUnits,
        '\u{1F399}\u{FE0F} Sesli Dinleme Aktif'.codeUnits,
      );
      expect(
        _processingTitle.codeUnits,
        '\u{1F916} Komut Algılanıyor...'.codeUnits,
      );
      expect(_successTitle.codeUnits, '\u{1F513} Kapı Açılıyor!'.codeUnits);
      expect(
        _errorTitle.codeUnits,
        '\u{26A0}\u{FE0F} Sesli Komut Hatası'.codeUnits,
      );
    });

    testWidgets('başlık en çok 2, alt başlık en çok 4 satır (elips)', (
      t,
    ) async {
      await pumpAt(t, _view(_cases[3]), scale: 1.0);
      final title = t.widget<Text>(find.text(_listeningTitle));
      final sub = t.widget<Text>(find.text('"ana kapıyı aç"'));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(sub.maxLines, 4);
      expect(sub.overflow, TextOverflow.ellipsis);
    });

    testWidgets('yasaklı efektler yok (BackdropFilter, ShaderMask, ek gölge)', (
      t,
    ) async {
      await pumpAt(t, _view(_cases[2]), scale: 1.0);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    });
  });

  group('VoiceLiveBannerView: kontrast (>= 4,5:1)', () {
    // Banner'ın oturabileceği zeminler: kart yüzeyi, soluk yüzey ve sayfa zemini.
    final backgrounds = <String, List<Color>>{
      'açık': const [Color(0xFFFFFFFF), Color(0xFFF1F5F9), Color(0xFFF8FAFC)],
      'koyu': const [Color(0xFF1E293B), Color(0xFF0F172A)],
    };

    for (final c in _cases) {
      testWidgets('${c.name}: başlık ve alt başlık her zeminde okunur', (
        t,
      ) async {
        for (final dark in const [false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          final fill = c.tone == AppTone.neutral
              ? p.surfaceMuted
              : c.tone.tint(p);
          for (final behind in backgrounds[dark ? 'koyu' : 'açık']!) {
            final bg = Color.alphaBlend(fill, behind);
            expect(
              _contrast(c.tone.ink(p), bg),
              greaterThanOrEqualTo(4.5),
              reason: 'başlık ${c.tone.name} dark=$dark zemin=$behind',
            );
            expect(
              _contrast(p.textSecondary, bg),
              greaterThanOrEqualTo(4.5),
              reason: 'alt başlık ${c.tone.name} dark=$dark zemin=$behind',
            );
          }
        }
      });
    }
  });

  group('VoiceLiveBannerView: eylem düğmesi', () {
    testWidgets('dinlemiyorken dokunma onStart çağırır (onStop değil)', (
      t,
    ) async {
      var starts = 0;
      var stops = 0;
      await pumpAt(
        t,
        _view(_cases[0], onStart: () => starts++, onStop: () => stops++),
        scale: 1.0,
      );
      await t.tap(find.byType(IconButton));
      await t.pump();
      expect((starts, stops), (1, 0));
    });

    testWidgets('dinlerken dokunma onStop çağırır (onStart değil)', (t) async {
      var starts = 0;
      var stops = 0;
      await pumpAt(
        t,
        _view(_cases[2], onStart: () => starts++, onStop: () => stops++),
        scale: 1.0,
      );
      await t.tap(find.byType(IconButton));
      await t.pump();
      expect((starts, stops), (0, 1));
    });

    testWidgets(
      'işleniyor/başarılı/hata/başlatılıyor durumlarında düğme dinlemeyi BAŞLATIR',
      (t) async {
        for (final c in [_cases[1], _cases[4], _cases[5], _cases[6]]) {
          var starts = 0;
          var stops = 0;
          await pumpAt(
            t,
            _view(c, onStart: () => starts++, onStop: () => stops++),
            scale: 1.0,
          );
          await t.tap(find.byType(IconButton));
          await t.pump();
          expect((starts, stops), (1, 0), reason: c.name);
        }
      },
    );

    testWidgets(
      'yalnız düğme dokunulabilir (başlık/alt başlığa dokunmak eylem tetiklemez)',
      (t) async {
        var calls = 0;
        await pumpAt(
          t,
          _view(_cases[0], onStart: () => calls++, onStop: () => calls++),
          scale: 1.0,
        );
        await t.tap(find.text(_idleSubtitle));
        await t.pump();
        expect(calls, 0);
      },
    );

    testWidgets(
      'dokunma hedefi >= 44 dp (48 dp) her yazı ölçeğinde ve her durumda',
      (t) async {
        for (final scale in kHarnessScales) {
          for (final c in _cases) {
            await pumpAt(t, _view(c), scale: scale);
            final size = t.getSize(find.byType(IconButton));
            expect(
              size.width,
              greaterThanOrEqualTo(44),
              reason: '${c.name} x$scale',
            );
            expect(
              size.height,
              greaterThanOrEqualTo(44),
              reason: '${c.name} x$scale',
            );
          }
        }
      },
    );
  });

  group('VoiceLiveBannerView: kompakt düzen (büyük yazı / dar ekran)', () {
    // Banner kart içindeymiş gibi her yanda 32 dp boşlukla: genişlik = ekran - 64; iç genişlik =
    // ekran - 64 - 32 (iç boşluk) - 2,4 (kenar çizgisi); metin sütunu = iç genişlik - 106 =
    // ekran - 204,4. Kompakt: metin sütunu < 7 em (112 dp x yazı ölçeği).
    Widget inCard(Widget w) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: w);

    // (ekran genişliği, yazı ölçeği, kompakt mi?)
    const table = <(double, double, bool)>[
      (320, 1.0, false), // 115,6 >= 112
      (320, 1.5, true), // 115,6 < 168
      (320, 2.0, true),
      (360, 1.0, false), // 155,6 >= 112
      (360, 1.3, false), // 155,6 >= 145,6
      (360, 1.5, true), // 155,6 < 168
      (360, 2.0, true),
      (412, 1.5, false), // 207,6 >= 168
      (412, 2.0, true), // 207,6 < 224
      (820, 2.0, false),
    ];

    for (final (width, scale, compact) in table) {
      testWidgets(
        '${width.toInt()} px x$scale: ${compact ? 'kompakt (başlangıç simgesi yok)' : 'normal (başlangıç simgesi var)'}',
        (t) async {
          for (final dark in const [false, true]) {
            for (final c in _cases) {
              await pumpAt(
                t,
                inCard(_view(c)),
                width: width,
                scale: scale,
                dark: dark,
              );
              final title = t.widget<Text>(find.text(c.title));
              final sub = t.widget<Text>(find.text(c.subtitle));
              expect(
                find.byIcon(c.icon),
                // Düğme simgesi (mic/stop) başlangıç simgesiyle aynı olabilir (dinliyor: mic).
                compact
                    ? (c.icon == c.buttonIcon ? findsOneWidget : findsNothing)
                    : (c.icon == c.buttonIcon
                          ? findsNWidgets(2)
                          : findsOneWidget),
                reason: '${c.name} ${width.toInt()}px x$scale dark=$dark',
              );
              expect(title.maxLines, compact ? 3 : 2, reason: c.name);
              expect(sub.maxLines, compact ? 6 : 4, reason: c.name);
              // Her durumda: tek dokunulabilir 48 dp düğme ve ekranı aşmayan banner.
              final button = t.getSize(find.byType(IconButton));
              expect(button.width, greaterThanOrEqualTo(44));
              expect(button.height, greaterThanOrEqualTo(44));
              expect(
                t.getSize(find.byType(VoiceLiveBannerView)).width,
                width - 64,
              );
            }
          }
        },
      );
    }

    testWidgets(
      'kompakt düzende de anlamsal etiket ve dokunma aynıdır (tek düğüm)',
      (t) async {
        final handle = t.ensureSemantics();
        var starts = 0;
        await pumpAt(
          t,
          inCard(_view(_cases[2], onStart: () => starts++)),
          width: 320,
          scale: 2.0,
        );
        expect(
          find.byIcon(Icons.mic_rounded),
          findsNothing,
          reason: 'dinliyor: düğme stop; simge yok',
        );
        expect(
          t.getSemantics(find.text(_listeningTitle)),
          isSemantics(
            label: '$_listeningTitle\n$_listeningHint',
            isButton: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'yazı ölçeği çalışma anında artınca simge gider, azalınca geri gelir; hata yok',
      (t) async {
        Widget app(double scale) =>
            harnessApp(inCard(_view(_cases[0])), scale: scale);
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        await t.pumpWidget(app(1.0));
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

        await t.pumpWidget(app(2.0));
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
        expect(find.text(_idleTitle), findsOneWidget);
        expect(find.text(_idleSubtitle), findsOneWidget);

        await t.pumpWidget(app(1.0));
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'kompakt düzende standart metinler 3 / 6 satıra sığar (Ahem x 1 em bile olsa en kötü durum hatasız)',
      (t) async {
        // Ahem'de her harf 1 em: gerçek yazı tiplerinden ~2 kat geniş; yalnız taşma/hata olmaması sınanır.
        for (final c in _cases) {
          await pumpAt(t, inCard(_view(c)), width: 320, scale: 2.0);
          expect(t.takeException(), isNull, reason: c.name);
          expect(
            t.getSize(find.byType(VoiceLiveBannerView)).height.isFinite,
            isTrue,
          );
        }
      },
    );
  });

  group('VoiceLiveBanner: servis bağlantısı (sahte servis)', () {
    testWidgets(
      'servis her bildirimde banner güncellenir: durum, tanınan sözcük, geri bildirim',
      (t) async {
        final svc = _FakeVoice();
        await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
        expect(find.text(_idleTitle), findsOneWidget);
        expect(find.text(_idleSubtitle), findsOneWidget);

        svc.set(status: VoiceStatus.listening);
        await t.pumpAndSettle();
        expect(find.text(_listeningTitle), findsOneWidget);
        expect(find.text(_listeningHint), findsOneWidget);

        svc.set(words: 'ana');
        await t.pump();
        expect(find.text('"ana"'), findsOneWidget);
        svc.set(words: 'ana kapıyı aç');
        await t.pump();
        expect(find.text('"ana kapıyı aç"'), findsOneWidget);
        expect(find.text('"ana"'), findsNothing);

        svc.set(status: VoiceStatus.processing);
        await t.pumpAndSettle();
        expect(find.text(_processingTitle), findsOneWidget);
        expect(find.text('"ana kapıyı aç"'), findsOneWidget);

        svc.set(status: VoiceStatus.success);
        await t.pumpAndSettle();
        expect(find.text(_successTitle), findsOneWidget);
        expect(find.text(_successSubtitle), findsOneWidget);

        svc.set(
          status: VoiceStatus.error,
          feedback: 'Ses algılanamadı (error_no_match)',
        );
        await t.pumpAndSettle();
        expect(find.text(_errorTitle), findsOneWidget);
        expect(find.text('Ses algılanamadı (error_no_match)'), findsOneWidget);

        svc.set(status: VoiceStatus.idle);
        await t.pumpAndSettle();
        expect(find.text(_idleTitle), findsOneWidget);
        // Her geçişte tek başlık/alt başlık: eski durumun metni ağaçta KALMAZ.
        expect(find.text(_errorTitle), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'dinlemiyorken dokunma servisin startListening\'ini aday kapılarla çağırır',
      (t) async {
        final svc = _FakeVoice();
        final doors = <DoorRecord>[_door(1, 'Ana Kapı'), _door(2, 'Otopark')];
        await t.pumpWidget(
          harnessApp(VoiceLiveBanner(service: svc, candidateDoors: doors)),
        );
        await t.tap(find.byType(IconButton));
        await t.pumpAndSettle();
        expect(svc.startCalls, hasLength(1));
        expect(
          svc.startCalls.single,
          same(doors),
          reason: 'yönetici kartı kendi kapı listesini verir',
        );
        expect(
          find.text(_listeningTitle),
          findsOneWidget,
          reason: 'servis dinlemeye geçti',
        );
      },
    );

    testWidgets(
      'aday kapı verilmezse startListening() argümansız çağrılır (sakin kartı)',
      (t) async {
        final svc = _FakeVoice();
        await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
        await t.tap(find.byType(IconButton));
        await t.pumpAndSettle();
        expect(svc.startCalls, [null]);
      },
    );

    testWidgets(
      'dinlerken dokunma stopListening çağırır ve boşta durumuna döner',
      (t) async {
        final svc = _FakeVoice()..set(status: VoiceStatus.listening);
        await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
        await t.tap(find.byType(IconButton));
        await t.pumpAndSettle();
        expect(svc.stopCalls, 1);
        expect(svc.startCalls, isEmpty);
        expect(find.text(_idleTitle), findsOneWidget);
      },
    );

    testWidgets(
      'aday kapılar değişince sonraki dokunma GÜNCEL listeyi kullanır',
      (t) async {
        final svc = _FakeVoice();
        final first = <DoorRecord>[_door(1, 'Ana Kapı')];
        final second = <DoorRecord>[_door(2, 'Otopark'), _door(3, 'Garaj')];
        await t.pumpWidget(
          harnessApp(VoiceLiveBanner(service: svc, candidateDoors: first)),
        );
        await t.pumpWidget(
          harnessApp(VoiceLiveBanner(service: svc, candidateDoors: second)),
        );
        await t.tap(find.byType(IconButton));
        await t.pump();
        expect(svc.startCalls.single, same(second));
      },
    );

    testWidgets(
      'yalnız banner yeniden kurulur: servis bildirimleri üst öğeyi kurmaz',
      (t) async {
        final svc = _FakeVoice();
        var parentBuilds = 0;
        await t.pumpWidget(
          harnessApp(
            Builder(
              builder: (context) {
                parentBuilds++;
                return VoiceLiveBanner(service: svc);
              },
            ),
          ),
        );
        expect(parentBuilds, 1);
        for (var i = 0; i < 5; i++) {
          svc.set(words: 'söz $i');
          await t.pump();
        }
        expect(parentBuilds, 1);
      },
    );

    testWidgets('banner kalkınca servisten dinleyici çıkarılır (sızıntı yok)', (
      t,
    ) async {
      final svc = _FakeVoice();
      await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
      expect(svc.listenerCount, 1);
      await t.pumpWidget(harnessApp(const SizedBox()));
      expect(svc.listenerCount, 0);
      svc.set(status: VoiceStatus.error); // kalkmış banner'a bildirim: hata yok
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  group(
    'VoiceLiveBanner: gerçek VoiceDoorService (ses motoru "kullanılamıyor" diyen sahte platform)',
    () {
      setUp(() {
        SharedPreferences.setMockInitialValues(<String, Object>{});
      });

      testWidgets(
        'boşta -> dokun -> ses motoru yok: hata durumu gösterilir; aday kapılar servise ulaşır; oturum temizlenince boşta',
        (t) async {
          // Platform kanalları: konuşma tanıma "başlatılamadı" (izin yok) der; TTS sessizce kabul eder.
          final messenger = t.binding.defaultBinaryMessenger;
          const speech = MethodChannel('plugin.csdcorp.com/speech_to_text');
          const tts = MethodChannel('flutter_tts');
          messenger.setMockMethodCallHandler(
            speech,
            (call) async => call.method == 'initialize' ? false : null,
          );
          messenger.setMockMethodCallHandler(tts, (call) async => 1);
          addTearDown(() {
            messenger.setMockMethodCallHandler(speech, null);
            messenger.setMockMethodCallHandler(tts, null);
          });

          final svc = VoiceDoorService(
            authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')),
          );
          addTearDown(svc.dispose);
          final doors = <DoorRecord>[_door(7, 'Ana Kapı')];

          await t.pumpWidget(
            harnessApp(VoiceLiveBanner(service: svc, candidateDoors: doors)),
          );
          expect(find.text(_idleTitle), findsOneWidget);
          expect(find.text(_idleSubtitle), findsOneWidget);

          await t.tap(find.byType(IconButton));
          await t.pumpAndSettle();
          expect(svc.debugLastCandidateDoors, same(doors));
          expect(svc.status, VoiceStatus.error);
          expect(find.text(_errorTitle), findsOneWidget);
          expect(
            find.text('Mikrofon veya ses tanıma izni alınamadı.'),
            findsOneWidget,
          );

          svc.clearSession();
          await t.pumpAndSettle();
          expect(find.text(_idleTitle), findsOneWidget);
          expect(find.text(_errorTitle), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    },
  );

  group('VoiceLiveBannerView: hareket azaltma ve pumpAndSettle', () {
    testWidgets(
      'hareket azaltma: durum değişince TEK pump son görünümü verir, ticker yok',
      (t) async {
        final svc = _FakeVoice();
        await t.pumpWidget(
          harnessApp(VoiceLiveBanner(service: svc), reduce: true),
        );
        final p = AppPalette.light;
        expect(_decoration(t).color, p.surfaceMuted);

        svc.set(status: VoiceStatus.error, feedback: 'x');
        await t.pump();
        expect(_decoration(t).color, AppTone.danger.tint(p));
        expect(
          (_decoration(t).border! as Border).top.color,
          AppTone.danger.hue.withValues(alpha: 0.6),
        );
        expect(t.binding.transientCallbackCount, 0);
        expect(_leadingIcon(t).icon, Icons.error_outline_rounded);
      },
    );

    testWidgets(
      'hareket varken renk 200 ms morph eder (ara değer), sonra sabit; pumpAndSettle biter',
      (t) async {
        final svc = _FakeVoice();
        await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
        await t.pumpAndSettle();
        final p = AppPalette.light;
        final before = _decoration(t).color;
        expect(before, p.surfaceMuted);

        svc.set(status: VoiceStatus.listening);
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        final mid = _decoration(t).color;
        expect(mid, isNot(before), reason: 'morph başladı');
        expect(mid, isNot(AppTone.success.tint(p)), reason: 'henüz bitmedi');

        await t.pumpAndSettle();
        expect(_decoration(t).color, AppTone.success.tint(p));
        expect(
          t.binding.transientCallbackCount,
          0,
          reason: 'kararlı durumda ticker yok',
        );
      },
    );

    testWidgets(
      'boşta <-> başlatılıyor aynı görünür: simge yeniden belirmez (titreme yok); farklı simge belirir',
      (t) async {
        final svc = _FakeVoice();
        await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
        await t.pumpAndSettle();
        double iconOpacity(IconData icon) => t
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.byIcon(icon),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity;

        svc.set(
          status: VoiceStatus.initializing,
          feedback: 'Ses motoru başlatılıyor...',
        );
        await t.pump();
        expect(
          iconOpacity(Icons.mic_none_rounded),
          1,
          reason: 'aynı simge: yeniden belirme yok',
        );
        expect(t.binding.transientCallbackCount, 0);

        svc.set(status: VoiceStatus.listening);
        await t.pump();
        expect(
          iconOpacity(Icons.mic_rounded),
          0,
          reason: 'yeni simge: belirme animasyonu başlar',
        );
        await t.pumpAndSettle();
        expect(iconOpacity(Icons.mic_rounded), 1);
      },
    );

    testWidgets('tüm durumlar arasında geçiş: pumpAndSettle her adımda biter', (
      t,
    ) async {
      final svc = _FakeVoice();
      await t.pumpWidget(harnessApp(VoiceLiveBanner(service: svc)));
      for (final status in VoiceStatus.values) {
        svc.set(status: status, words: 'söz', feedback: 'geri bildirim');
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0, reason: status.name);
      }
      expect(t.takeException(), isNull);
    });
  });

  group('VoiceLiveBannerView: Semantics', () {
    testWidgets(
      'banner TEK anlamsal düğümdür: başlık + alt başlık etiketi, düğme, dokunma eylemi',
      (t) async {
        final handle = t.ensureSemantics();
        for (final c in _cases) {
          await pumpAt(t, _view(c), scale: 1.0);
          expect(
            t.getSemantics(find.text(c.title)),
            isSemantics(
              label: '${c.title}\n${c.subtitle}',
              isButton: true,
              isEnabled: true,
              hasEnabledState: true,
              hasTapAction: true,
            ),
            reason: c.name,
          );
          final tapNodes = t.semantics.simulatedAccessibilityTraversal().where(
            (n) => n.getSemanticsData().hasAction(SemanticsAction.tap),
          );
          expect(
            tapNodes,
            hasLength(1),
            reason: '${c.name}: tek dokunulabilir düğüm',
          );
        }
        handle.dispose();
      },
    );

    testWidgets(
      'anlamsal etiket yalnız mevcut metinlerdir (simge/emoji dışında yeni metin yok)',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(t, _view(_cases[0]), scale: 1.0);
        final labels = t.semantics
            .simulatedAccessibilityTraversal()
            .map((n) => n.getSemanticsData().label)
            .where((l) => l.isNotEmpty)
            .toList();
        expect(labels, ['$_idleTitle\n$_idleSubtitle']);
        handle.dispose();
      },
    );

    testWidgets(
      'dokunma eylemi anlamsal yoldan da çalışır (TalkBack/VoiceOver çift dokunma)',
      (t) async {
        final handle = t.ensureSemantics();
        var starts = 0;
        await pumpAt(t, _view(_cases[0], onStart: () => starts++), scale: 1.0);
        t.semantics.tap(find.semantics.byLabel('$_idleTitle\n$_idleSubtitle'));
        await t.pump();
        expect(starts, 1);
        handle.dispose();
      },
    );
  });

  group(
    'VoiceLiveBannerView: taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu)',
    () {
      const longWords =
          'ana kapıyı aç lütfen otopark giriş kapısını da aç ve garaj kapısını kapat sonra ana kapıyı tekrar aç';
      const longFeedback =
          'Kapı komutu gönderilemedi: cihaz çevrimdışı olduğu için işlem tamamlanamadı, lütfen biraz sonra tekrar deneyin.';

      final matrixCases = <_Case>[
        ..._cases,
        const _Case(
          'uzun tanınan sözcükler',
          VoiceStatus.listening,
          words: longWords,
          title: _listeningTitle,
          subtitle: '"$longWords"',
          icon: Icons.mic_rounded,
          tone: AppTone.success,
          buttonIcon: Icons.stop_rounded,
        ),
        const _Case(
          'uzun hata metni',
          VoiceStatus.error,
          feedback: longFeedback,
          title: _errorTitle,
          subtitle: longFeedback,
          icon: Icons.error_outline_rounded,
          tone: AppTone.danger,
          buttonIcon: Icons.mic_rounded,
        ),
      ];

      testWidgets(
        'her durum her hücrede taşmaz; banner ekranı aşmaz ve sonlu yüksekliktedir',
        (t) async {
          await forEachHarnessCell((width, scale, dark) async {
            for (final c in matrixCases) {
              await pumpAt(
                t,
                Padding(padding: const EdgeInsets.all(16), child: _view(c)),
                width: width,
                scale: scale,
                dark: dark,
              );
              final size = t.getSize(find.byType(VoiceLiveBannerView));
              expect(
                size.width,
                lessThanOrEqualTo(width),
                reason:
                    '${c.name} ${width}px x$scale ${dark ? 'koyu' : 'açık'}',
              );
              expect(size.height.isFinite, isTrue);
              expect(
                size.height,
                lessThan(640),
                reason: '${c.name} ${width}px x$scale',
              );
            }
          });
        },
      );

      testWidgets(
        'servise bağlı sürüm de uzun metinle 320 px x 2,0 yazıda taşmaz',
        (t) async {
          final svc = _FakeVoice();
          await t.pumpWidget(const SizedBox());
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            harnessApp(
              Padding(
                padding: const EdgeInsets.all(16),
                child: VoiceLiveBanner(service: svc),
              ),
              scale: 2.0,
            ),
          );
          for (final status in VoiceStatus.values) {
            svc.set(status: status, words: longWords, feedback: longFeedback);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: status.name);
          }
        },
      );
    },
  );
}

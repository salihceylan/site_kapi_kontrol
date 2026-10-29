// Komşu Panosu: sınır (uç durum) testlerinin ortak örnek verisi, sahte servisi ve düzeneği (`_test.dart` ile bitmediği
// için kendi başına test olarak çalışmaz).
//
// Sahte servis SUNUCUYU taklit eder (server/src/modules/neighbor_board_routes.js): ilanlar sunucunun JSON biçiminde
// tutulur ve görünüme `NeighborPost.fromJson` üzerinden girer; sakin yalnız yayındaki ilanları + KENDİ bekleyen /
// reddedilen / kaldırılan ilanlarını görür, yönetime özel alanlar (şikayet sayısı / gerekçeleri) ona gitmez; yönetici
// durum sekmesine göre süzer. Her çağrı kuyruktaki bir hataya ya da kapıya takılabilir.
//
// Gerçek servisi (`NeighborBoardService`) sahte HTTP istemcisiyle süren ağ düzeneği de burada ([NeighborNet]).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/neighbor_post.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/neighbor_board_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/neighbor_board_view.dart';

import '../design/harness.dart' show harnessApp;
import 'dialog_layout_harness.dart' show settleFor;

// ---------------------------------------------------------------------------------------------------------------------
// Siteler
// ---------------------------------------------------------------------------------------------------------------------

/// Sakin (yazma yetkisi yok): ilan yazar, başkasının ilanını şikayet eder, kendi ilanını geri çeker.
const List<PeopleSite> nbResidentSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];

/// Yönetici (`canWrite`): onaylar / reddeder / kaldırır.
const List<PeopleSite> nbManagerSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true)];

/// Karışık yetki: 11 numaralı sitede yönetici, 12 numaralıda sakin.
const List<PeopleSite> nbMixedSites = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
  PeopleSite(code: 12, name: 'Mavi Park'),
];

// ---------------------------------------------------------------------------------------------------------------------
// Metin üreticileri
// ---------------------------------------------------------------------------------------------------------------------

/// [unit]'i tekrarlayıp tam [length] karakterlik metin üretir (boşluksuz tek sözcük için tek harf verin).
String nbBlock(String unit, int length) => (unit * (length ~/ unit.length + 1)).substring(0, length);

/// Boşluklu, Türkçe harfli, tam [length] karakterlik metin (satır kaydırma sınanır). Boşlukla BİTMEZ: model
/// `decision_note` alanını kırptığı için sınanan metin aynen geri gelsin.
String nbWords(int length) {
  final text = nbBlock('Şirin çocuk parkı ığdır güzel ', length);
  return text.endsWith(' ') ? '${text.substring(0, length - 1)}.' : text;
}

/// Testlerde sabit "oluşturma" anı: öğlen UTC, yerel saat dilimi ne olursa olsun gün (20.10.2026) değişmez.
const String nbCreatedAt = '2026-10-20T12:00:00Z';

/// Sunucu `mapPost` biçiminde TAM ilan satırı (yönetim alanları dahil). Sahte servis bunu role göre süzer.
Map<String, dynamic> nbPost(
  int id, {
  int site = 11,
  String title = 'Bahçe düzenlemesi için gönüllü aranıyor',
  String body = 'Cumartesi sabahı bahçedeki çiçekleri birlikte dikelim.',
  String status = NeighborPostStatus.published,
  String author = 'Ayşe Y.',
  String? createdAt = nbCreatedAt,
  bool mine = false,
  String? note,
  List<String> reasons = const <String>[],
}) => <String, dynamic>{
  'id': id,
  'site_code': site,
  'title': title,
  'body': body,
  'status': status,
  'author_name': author,
  'created_at': createdAt,
  'is_mine': mine,
  'decision_note': note,
  'decided_at': note == null ? null : '2026-10-21T09:00:00Z',
  'report_count': reasons.length,
  'report_reasons': List<String>.of(reasons),
};

/// Sakin görünümü: yönetime özel alanlar çıkar, karar notu yalnız kendi ilanında kalır.
Map<String, dynamic> _residentView(Map<String, dynamic> row) {
  final out = Map<String, dynamic>.of(row)
    ..remove('report_count')
    ..remove('report_reasons');
  if (row['is_mine'] != true) {
    out
      ..remove('decision_note')
      ..remove('decided_at');
  }
  return out;
}

/// Yönetici görünümü: `is_mine` hep false (sunucu `FALSE AS is_mine`).
Map<String, dynamic> _managerView(Map<String, dynamic> row) => Map<String, dynamic>.of(row)..['is_mine'] = false;

// ---------------------------------------------------------------------------------------------------------------------
// Oturum
// ---------------------------------------------------------------------------------------------------------------------

class NeighborFakeAuth extends AuthService {
  NeighborFakeAuth({this.token = 'tok-1'}) : super(api: AuthApi(baseUrl: 'https://api.example.test///'));

  /// null: oturum yok (servis hiç istek atmadan "Oturum açmanız gerekmektedir." der).
  String? token;

  /// `refreshSession(force: true)` çağrı sayısı: 401 yanıtı oturum yenileme / kapatma sinyalidir.
  int forcedRefreshes = 0;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(
          id: 5,
          fullName: 'Ayşe Yılmaz',
          email: 'ayse@e2e.local',
          loginName: null,
          role: UserRole.apartmentOwner,
          isActive: true,
          token: token!,
        );

  @override
  bool get isLoggedIn => token != null;

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) forcedRefreshes++;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Sahte servis
// ---------------------------------------------------------------------------------------------------------------------

class FakeNeighborService extends NeighborBoardService {
  FakeNeighborService({required super.authService})
    : super(client: MockClient((_) async => throw StateError('Sahte servis ağa çıkmamalı.')));

  /// Sunucudaki tüm ilanlar ([nbPost] biçimi).
  final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

  /// Sunucu `LIST_LIMIT` (100) gibi liste üst sınırı; null = sınırsız (istemcinin 100'ün ötesini de çizdiği sınanır).
  int? listLimit;

  /// true: sunucu hatası simülasyonu — sakine yönetime özel alanları da gönderir (arayüz bunları göstermemeli).
  bool leakManagerFields = false;

  /// true: sunucu hatası simülasyonu — sakine görünürlük kuralına bakmadan sitenin TÜM ilanlarını gönderir (başkasının
  /// bekleyen / reddedilen / kaldırılan ilanı dahil); arayüz bunlara eylem düğmesi çizmemeli.
  bool ignoreVisibility = false;

  // --- Çağrı kayıtları ---
  final List<int> residentCalls = <int>[];
  final List<({int site, String status})> managedCalls = <({int site, String status})>[];
  final List<({int site, String title, String body})> createCalls = <({int site, String title, String body})>[];
  final List<({int id, String reason})> reportCalls = <({int id, String reason})>[];
  final List<int> withdrawCalls = <int>[];
  final List<({int site, int id, String action, String? note})> decideCalls =
      <({int site, int id, String action, String? note})>[];

  /// İşlem adı (`listResident`, `listManaged`, `create`, `report`, `withdraw`, `decide`) -> sıradaki hatalar.
  final Map<String, List<Object>> failures = <String, List<Object>>{};

  /// İşlem adı -> sıradaki kapılar (açılana dek yanıt gelmez; yanıt çağrı ANINDA hesaplanır).
  final Map<String, List<Completer<void>>> gates = <String, List<Completer<void>>>{};

  Future<void> _enter(String op) async {
    final gate = gates[op];
    if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
    final failure = failures[op];
    if (failure != null && failure.isNotEmpty) throw failure.removeAt(0);
  }

  static ApiException error(int status, String code, String message) =>
      ApiException(message, statusCode: status, code: code, payload: <String, dynamic>{'error': message, 'code': code});

  static ApiException forbiddenRole() => error(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
  static ApiException forbiddenSite() => error(403, 'FORBIDDEN_SITE', 'Bu site üzerinde yönetim yetkiniz bulunmuyor.');
  static ApiException moduleOff() => error(403, 'MODULE_DISABLED', 'Komşu Panosu modülü kapalı.');
  static ApiException postNotFound() => error(404, 'POST_NOT_FOUND', 'İlan bulunamadı ya da erişiminiz yok.');
  static ApiException postState() => error(409, 'POST_STATE', 'İlan bu işlem için uygun durumda değil.');

  Map<String, dynamic>? row(int id) {
    for (final r in rows) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  int _nextId() {
    var max = 1000;
    for (final r in rows) {
      if ((r['id'] as int) > max) max = r['id'] as int;
    }
    return max + 1;
  }

  List<NeighborPost> _posts(Iterable<Map<String, dynamic>> source, Map<String, dynamic> Function(Map<String, dynamic>) view) {
    final sorted = source.toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final page = listLimit == null ? sorted : sorted.take(listLimit!).toList();
    return <NeighborPost>[for (final r in page) NeighborPost.fromJson(view(r))];
  }

  @override
  Future<List<NeighborPost>> listResident(int siteCode) async {
    residentCalls.add(siteCode);
    await _enter('listResident');
    const ownVisible = <String>{'pending', 'rejected', 'removed'};
    return _posts(
      rows.where(
        (r) =>
            r['site_code'] == siteCode &&
            (ignoreVisibility ||
                r['status'] == 'published' ||
                (r['is_mine'] == true && ownVisible.contains(r['status']))),
      ),
      leakManagerFields ? (r) => Map<String, dynamic>.of(r) : _residentView,
    );
  }

  @override
  Future<List<NeighborPost>> listManaged(int siteCode, String status) async {
    managedCalls.add((site: siteCode, status: status));
    await _enter('listManaged');
    bool matches(Map<String, dynamic> r) =>
        r['site_code'] == siteCode &&
        (status == 'reported'
            ? r['status'] == 'published' && (r['report_count'] as int) > 0
            : r['status'] == status);
    return _posts(rows.where(matches), _managerView);
  }

  @override
  Future<void> create(int siteCode, String title, String body) async {
    createCalls.add((site: siteCode, title: title, body: body));
    await _enter('create');
    rows.add(nbPost(_nextId(), site: siteCode, title: title, body: body, status: 'pending', author: 'Ben B.', mine: true));
  }

  @override
  Future<void> report(int id, String reason) async {
    reportCalls.add((id: id, reason: reason));
    await _enter('report');
    final r = row(id);
    if (r == null || r['status'] != 'published') throw postNotFound();
    (r['report_reasons'] as List<String>).add(reason);
    r['report_count'] = (r['report_reasons'] as List<String>).length;
  }

  @override
  Future<void> withdraw(int id) async {
    withdrawCalls.add(id);
    await _enter('withdraw');
    final r = row(id);
    if (r == null || r['is_mine'] != true || (r['status'] != 'pending' && r['status'] != 'published')) throw postNotFound();
    r['status'] = 'withdrawn';
  }

  @override
  Future<void> decide(int siteCode, int id, String action, {String? note}) async {
    decideCalls.add((site: siteCode, id: id, action: action, note: note));
    await _enter('decide');
    final r = row(id);
    if (r == null || r['site_code'] != siteCode) throw postNotFound();
    if (r['status'] != (action == 'remove' ? 'published' : 'pending')) throw postState();
    r['status'] = switch (action) {
      'approve' => 'published',
      'reject' => 'rejected',
      _ => 'removed',
    };
    r['decision_note'] = note;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Ağ düzeneği (gerçek servis + sahte HTTP istemcisi)
// ---------------------------------------------------------------------------------------------------------------------

/// Sunucu yanıtı. [body] bir String ise olduğu gibi (HTML, bozuk JSON ...), değilse JSON olarak kodlanır; gövde HER ZAMAN
/// UTF-8 baytlarıdır ve `content-type` charset taşımaz (servis `bodyBytes`'ı kendisi UTF-8 çözmelidir).
http.Response nbResponse(int status, Object? body, {String contentType = 'application/json'}) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': contentType},
);

class NeighborNet {
  /// Servise gelen tüm istekler (sırayla).
  final List<http.Request> requests = <http.Request>[];

  /// Sıradaki isteğe verilecek yanıt; fırlatırsa ağ hatasıdır, hiç tamamlanmazsa zaman aşımıdır.
  Future<http.Response> Function(http.Request request) handler = (_) async =>
      nbResponse(200, <String, dynamic>{'items': <Object>[]});

  late final http.Client client = MockClient((request) {
    requests.add(request);
    return handler(request);
  });

  NeighborBoardService service(NeighborFakeAuth auth) => NeighborBoardService(authService: auth, client: client);
}

// ---------------------------------------------------------------------------------------------------------------------
// Düzenek
// ---------------------------------------------------------------------------------------------------------------------

/// Kısa süre ilerletir (ağ / animasyon sonrası). `pumpAndSettle` KULLANILMAZ: yüklenirken dönen çubuk bitmeyen animasyondur.
Future<void> nbSettle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

/// Görünen snackbar'ın süresini doldurur: sıradaki snackbar ancak o kapanınca görünür (aynı testte art arda iki işlem).
Future<void> nbExpireSnack(WidgetTester t) async {
  await t.pump(const Duration(seconds: 5));
  await t.pump(const Duration(seconds: 1));
}

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> kNeighborCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalıdır.
void neighborMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kNeighborCells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
        await body(t, width, height, scale, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

/// Komşu Panosu ekranını gerçek sayfa kabuğuna benzer biçimde kurar: tüm sayfa tek dış kaydırıcıdadır (ekranın kendi
/// `ListView`'ı kaydırmaz), yatay 16 dp kenar boşluğu.
class NeighborRig {
  NeighborRig({
    Iterable<Map<String, dynamic>> posts = const <Map<String, dynamic>>[],
    this.sites = nbResidentSite,
    NeighborFakeAuth? auth,
  }) : auth = auth ?? NeighborFakeAuth() {
    service = FakeNeighborService(authService: this.auth)..rows.addAll(posts);
  }

  /// Gerçek servis + sahte HTTP: ağ / oturum / yetki yanıtlarını uçtan uca sınar.
  NeighborRig.network(NeighborNet net, {this.sites = nbResidentSite, NeighborFakeAuth? auth}) : auth = auth ?? NeighborFakeAuth() {
    service = net.service(this.auth);
  }

  final NeighborFakeAuth auth;
  late final NeighborBoardService service;
  final GlobalKey<NeighborBoardViewState> key = GlobalKey<NeighborBoardViewState>();
  List<PeopleSite> sites;
  double _scale = 1.0;
  bool _dark = false;

  FakeNeighborService get fake => service as FakeNeighborService;

  NeighborBoardViewState get state => key.currentState!;

  Widget _tree() => harnessApp(
    SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NeighborBoardView(key: key, authService: auth, service: service, sites: sites),
        ),
      ),
    ),
    dark: _dark,
    scale: _scale,
  );

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<PeopleSite>? sites,
  }) async {
    if (sites != null) this.sites = sites;
    _scale = scale;
    _dark = dark;
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_tree());
    await nbSettle(t);
  }

  /// Aynı ağaçta `sites` değerini değiştirir (`didUpdateWidget`: yetki / modül değişimi).
  Future<void> rebuild(WidgetTester t, {required List<PeopleSite> sites}) async {
    this.sites = sites;
    await t.pumpWidget(_tree());
    await nbSettle(t);
  }

  /// Tüm sayfayı kaydıran DIŞ kaydırıcı (ekranın içindeki `ListView` kaydırmaz, yalnız boyutlanır).
  Finder get pageScrollable => find.byType(Scrollable).first;

  ScrollPosition position(WidgetTester t) => t.state<ScrollableState>(pageScrollable).position;
}

// ---------------------------------------------------------------------------------------------------------------------
// Pencere yardımcıları
// ---------------------------------------------------------------------------------------------------------------------

/// Açık iletişim kutusundaki [index]. metin alanı.
Finder nbDialogField(int index) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(index);

/// Metin alanının o anki değeri.
String nbFieldText(WidgetTester t, Finder field) => t.widget<TextField>(field).controller!.text;

/// Açık iletişim kutusundaki düğme / metin.
Finder nbInDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

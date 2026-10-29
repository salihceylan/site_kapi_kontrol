// Çoklu malik (104): daire kartında malik listesi + "Hesap muhatabı" rozeti + yönetici düzenlemesi (Malik ekle / Muhatap yap / Maliki çıkar).
//
// Sunucu davranışı sahte HTTP katmanıyla (ApartmentManagementApi alt sınıfı) taklit edilir; kart gerçek ApartmentManagementService ile çalışır.
// AGENTS.md kural 6: çoklu malikli kart dört hücre x açık / koyu taşmaz. Kurul üyesi (salt okunur) hiçbir yazma düğmesi görmez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_owner_dialogs.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_crm_card.dart';

import 'dialog_layout_harness.dart';
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'people_fixtures.dart';

/// Sahte sunucu: bir dairenin (301) malikleri bellekte tutulur; her yazma kartın okuduğu daire JSON'una yansır.
class _OwnersApi extends ApartmentManagementApi {
  _OwnersApi(this.auth, List<Map<String, dynamic>> initial)
    : owners = <Map<String, dynamic>>[for (final o in initial) Map<String, dynamic>.of(o)],
      super(baseUrl: 'http://localhost') {
    _sync();
  }

  final PeopleFakeAuth auth;
  final List<Map<String, dynamic>> owners;
  final List<({String method, String path, Object? body})> calls = <({String method, String path, Object? body})>[];

  /// Doluysa sıradaki YAZMA bu hatayla reddedilir.
  ApiException? failNext;
  int _nextResidency = 900;

  static Map<String, dynamic> owner(int residency, int person, String name, {bool holder = false, bool account = false}) => <String, dynamic>{
    'residency_id': residency,
    'person_id': person,
    'full_name': name,
    'is_account_holder': holder,
    'has_account': account,
    'move_in_date': '2024-03-05',
  };

  List<Map<String, dynamic>> get _ordered => <Map<String, dynamic>>[
    ...owners.where((o) => o['is_account_holder'] == true),
    ...owners.where((o) => o['is_account_holder'] != true),
  ];

  Map<String, dynamic> view() => <String, dynamic>{
    'apartment_id': 301,
    'label': 'A Blok - 5',
    'owners': _ordered,
    'account_holder_residency_id': owners.where((o) => o['is_account_holder'] == true).map((o) => o['residency_id']).firstOrNull,
    'owner_limit': 10,
  };

  void _sync() {
    final ordered = _ordered;
    final holder = ordered.isEmpty || ordered.first['is_account_holder'] != true ? null : ordered.first;
    auth.apartmentsJson[301] = <String, dynamic>{
      ...pplApartmentJson(
        301,
        'A Blok - 5',
        floor: 2,
        owner: holder == null ? null : <String, dynamic>{'person_id': holder['person_id'], 'full_name': holder['full_name']},
        current: <Map<String, dynamic>>[
          for (final o in ordered)
            <String, dynamic>{
              ...pplResidentJson(o['residency_id'] as int, o['person_id'] as int, o['full_name'] as String, ResidencyRelation.owner, account: o['has_account'] == true),
              'is_account_holder': o['is_account_holder'] == true,
            },
        ],
      ),
      'owners': ordered,
      'owner_count': ordered.length,
    };
  }

  @override
  Future<Map<String, dynamic>> call(String method, String path, {required String token, Map<String, String>? query, Object? body}) async {
    calls.add((method: method, path: path, body: body));
    final failure = failNext;
    if (method != 'GET' && failure != null) {
      failNext = null;
      throw failure;
    }
    final map = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
    if (method == 'POST' && path.endsWith('/apartments/301/owners')) {
      final makeHolder = map['make_account_holder'] == true || owners.isEmpty;
      if (makeHolder) {
        for (final o in owners) {
          o['is_account_holder'] = false;
        }
      }
      final person = map['person'] is Map ? Map<String, dynamic>.from(map['person'] as Map) : null;
      owners.add(owner(
        ++_nextResidency,
        (map['person_id'] as int?) ?? 800 + _nextResidency,
        person?['full_name'] as String? ?? auth.peopleJson[map['person_id']]?['full_name'] as String? ?? 'Seçilen Kişi',
        holder: makeHolder,
      ));
    } else if (method == 'PUT' && path.endsWith('/owners/account-holder')) {
      final target = map['residency_id'];
      for (final o in owners) {
        o['is_account_holder'] = o['residency_id'] == target;
      }
    } else if (method == 'POST' && path.endsWith('/remove')) {
      final id = int.parse(RegExp(r'/owners/(\d+)/remove').firstMatch(path)!.group(1)!);
      final target = owners.firstWhere((o) => o['residency_id'] == id);
      final others = owners.where((o) => o['residency_id'] != id).toList();
      if (target['is_account_holder'] == true) {
        final replacement = map['new_account_holder_residency_id'];
        if (replacement == null && others.length > 1) {
          throw ApiException('Bu kişi hesap muhatabı. Çıkarmadan önce yeni hesap muhatabını seçin.', statusCode: 409, code: 'ACCOUNT_HOLDER_REQUIRED');
        }
        final next = others.firstWhere((o) => replacement == null || o['residency_id'] == replacement);
        next['is_account_holder'] = true;
      }
      owners.removeWhere((o) => o['residency_id'] == id);
    }
    _sync();
    return view();
  }
}

PeopleScope _scope(PeopleFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

final List<Map<String, dynamic>> _three = <Map<String, dynamic>>[
  _OwnersApi.owner(11, 1, 'Ayşe Yılmaz', holder: true, account: true),
  _OwnersApi.owner(12, 2, 'Ali Yılmaz'),
  _OwnersApi.owner(13, 3, 'Fatma Yılmaz'),
];

/// Kartı açar. `api` doğrudan ApartmentManagementService'e verilir (kartın kendi kurduğu servis `debugApiFactory` ile bu sahteyi kullanır).
Future<({PeopleFakeAuth auth, _OwnersApi api, List<int> changed})> _openCard(
  WidgetTester t,
  List<Map<String, dynamic>> owners, {
  bool canWrite = true,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final auth = PeopleFakeAuth.seeded();
  final api = _OwnersApi(auth, owners);
  ApartmentManagementService.debugApiFactory = (_) => api;
  final changed = <int>[];
  await openDialogAt(
    t,
    (c) => ApartmentCardDialog.show(c, scope: _scope(auth, canWrite: canWrite), apartmentId: 301, initialLabel: 'A Blok - 5', onChanged: () => changed.add(1)),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return (auth: auth, api: api, changed: changed);
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _tapKey(WidgetTester t, String key) => tapFinder(t, _key(key));

void main() {
  tearDown(() => ApartmentManagementService.debugApiFactory = null);

  group('kart: malik listesi ve muhatap rozeti', () {
    testWidgets('çoklu malik (yönetici): muhatap rozeti tek, satır etiketi, açıklama, düğmeler', (t) async {
      await _openCard(t, _three);
      expect(find.text('Malik (hesap muhatabı)'), findsOneWidget);
      expect(find.text('Hesap muhatabı'), findsOneWidget, reason: 'rozet yalnız muhatapta (satır etiketi "Malik (hesap muhatabı)" farklı metin)');
      expect(find.text(kAccountHolderExplain), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsNWidgets(2), reason: 'muhatap satırı + sakin listesi');
      expect(find.text('Ali Yılmaz'), findsOneWidget);
      expect(find.text('Fatma Yılmaz'), findsOneWidget);
      expect(find.text('Muhatap yap'), findsNWidgets(2), reason: 'yalnız muhatap OLMAYAN iki malikte');
      expect(find.text('Maliki çıkar'), findsNWidgets(3));
      expect(_key('owner_make_holder_11'), findsNothing, reason: 'muhatabın kendisinde "Muhatap yap" yok');
      expect(_key('owner_make_holder_12'), findsOneWidget);
      expect(find.text('Malik ekle'), findsOneWidget);
    });

    testWidgets('kurul üyesi (salt okunur): rozet ve açıklama görünür, hiçbir yazma düğmesi yok', (t) async {
      await _openCard(t, _three, canWrite: false);
      expect(find.text('Hesap muhatabı'), findsOneWidget);
      expect(find.text(kAccountHolderExplain), findsOneWidget);
      expect(find.text('Muhatap yap'), findsNothing);
      expect(find.text('Maliki çıkar'), findsNothing);
      expect(find.text('Malik ekle'), findsNothing);
    });

    testWidgets('tek malik: rozet / açıklama / satır düğmeleri yok (eski görünüm), yönetici yine "Malik ekle" görür', (t) async {
      await _openCard(t, <Map<String, dynamic>>[_OwnersApi.owner(11, 1, 'Ayşe Yılmaz', holder: true)]);
      expect(find.text('Malik'), findsNWidgets(2), reason: 'bilgi satırı etiketi + ilişki çipi');
      expect(find.text('Malik (hesap muhatabı)'), findsNothing);
      expect(find.text('Hesap muhatabı'), findsNothing);
      expect(find.text('Muhatap yap'), findsNothing);
      expect(find.text('Maliki çıkar'), findsNothing);
      expect(find.text('Malik ekle'), findsOneWidget);
    });

    testWidgets('sınır: 10 malik varken "Malik ekle" gizlenir', (t) async {
      final many = <Map<String, dynamic>>[
        for (var i = 0; i < kApartmentOwnerLimit; i++) _OwnersApi.owner(100 + i, 50 + i, 'Malik $i', holder: i == 0),
      ];
      await _openCard(t, many, height: 3200);
      expect(find.text('Malik ekle'), findsNothing);
    });

    layoutMatrix('çoklu malikli kart (uzun adlar, rozet, iki düğme): taşma yok', (t, w, h, s, dark) async {
      await _openCard(
        t,
        <Map<String, dynamic>>[
          _OwnersApi.owner(11, 1, 'Muhammed Abdurrahman Büyükkaradeniz-Yılmazoğlu', holder: true, account: true),
          _OwnersApi.owner(12, 2, 'Fatma Zehra Şahinkanatlıoğlu-Karakaya'),
          _OwnersApi.owner(13, 3, 'Ali Veli'),
        ],
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Hesap muhatabı'), findsOneWidget);
      expect(find.text('Malik ekle'), findsOneWidget);
    });
  });

  group('daire listesi kartı', () {
    Future<void> pumpCard(WidgetTester t, Map<String, dynamic> json) async {
      await pumpList(
        t,
        ApartmentCrmCard(apartment: ApartmentSummary.fromJson(json), onTap: () {}),
        width: 360,
        height: 600,
        scale: 1.5,
        dark: false,
      );
    }

    testWidgets('birden çok malik varsa muhatabın adı + "(+N malik)"; tek malikte eski metin', (t) async {
      await pumpCard(t, pplApartmentJson(301, 'A Blok - 5', owner: <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'})
        ..['owner_count'] = 3);
      expect(find.text('Malik: Ayşe Yılmaz (+2 malik)'), findsOneWidget);
      await pumpCard(t, pplApartmentJson(301, 'A Blok - 5', owner: <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'}));
      expect(find.text('Malik: Ayşe Yılmaz'), findsOneWidget, reason: 'owner_count alanı olmayan eski yanıt: ek yok');
      expect(t.takeException(), isNull);
    });
  });

  group('Muhatap yap', () {
    testWidgets('onaydan sonra PUT gider, kart yenilenir (rozet yeni muhatapta), liste haberdar edilir, bildirim çıkar', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_make_holder_12');
      expect(find.text('Hesap muhatabını değiştir'), findsOneWidget);
      expect(find.textContaining('Borç, ekstre, makbuz ve hatırlatmalar bu kişiye döner'), findsOneWidget);
      expect(env.api.calls.where((c) => c.method == 'PUT'), isEmpty, reason: 'onay beklenir');
      await tapFinder(t, find.widgetWithText(ElevatedButton, 'Muhatap yap'));
      await settleFor(t);
      final put = env.api.calls.singleWhere((c) => c.method == 'PUT');
      expect(put.path, '/manager/sites/11/apartments/301/owners/account-holder');
      expect(put.body, <String, Object?>{'residency_id': 12});
      expect(env.changed, hasLength(1));
      expect(find.text('Hesap muhatabı değiştirildi.'), findsOneWidget);
      // kart yeni veriyle çizildi: muhatap Ali, eski muhatabın satırında artık "Muhatap yap" var
      expect(find.text('Hesap muhatabı'), findsOneWidget);
      expect(_key('owner_make_holder_11'), findsOneWidget);
      expect(_key('owner_make_holder_12'), findsNothing);
    });

    testWidgets('vazgeçilirse hiçbir istek gitmez', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_make_holder_12');
      await tapFinder(t, find.text('Vazgeç'));
      await settleFor(t);
      expect(env.api.calls.where((c) => c.method != 'GET'), isEmpty);
      expect(env.changed, isEmpty);
    });

    testWidgets('sunucu reddi kartta Türkçe gösterilir; kart değişmez, liste haberdar edilmez', (t) async {
      final env = await _openCard(t, _three);
      env.api.failNext = ApiException('Bu kişi dairenin güncel maliki değil.', statusCode: 404, code: 'OWNER_NOT_FOUND');
      await _tapKey(t, 'owner_make_holder_12');
      await tapFinder(t, find.widgetWithText(ElevatedButton, 'Muhatap yap'));
      await settleFor(t);
      expect(find.text('Bu kişi dairenin güncel maliki değil.'), findsOneWidget);
      expect(env.changed, isEmpty);
      expect(_key('owner_make_holder_12'), findsOneWidget, reason: 'kart eski halinde');
    });
  });

  group('Maliki çıkar', () {
    testWidgets('muhatap OLMAYAN malik: seçim istenmez; POST gövdesi boş; kart yenilenir', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_remove_13');
      expect(find.text('Maliki Çıkar'), findsOneWidget);
      expect(find.textContaining('Fatma Yılmaz maliklerden çıkarılacak'), findsOneWidget);
      expect(_key('owner_new_holder'), findsNothing);
      await _tapKey(t, 'owner_remove_submit');
      await settleFor(t);
      final post = env.api.calls.singleWhere((c) => c.path.endsWith('/remove'));
      expect(post.path, '/manager/sites/11/apartments/301/owners/13/remove');
      expect(post.body, <String, Object?>{});
      expect(find.text('Malik çıkarıldı.'), findsOneWidget);
      expect(find.text('Fatma Yılmaz'), findsNothing);
      expect(env.changed, hasLength(1));
    });

    testWidgets('hesabı olan malikte erişimin kapanacağı yazılır', (t) async {
      await _openCard(t, <Map<String, dynamic>>[
        _OwnersApi.owner(11, 1, 'Ayşe Yılmaz', holder: true),
        _OwnersApi.owner(12, 2, 'Ali Yılmaz', account: true),
      ]);
      await _tapKey(t, 'owner_remove_12');
      expect(find.textContaining('erişimi (kapı yetkisi) kapanır'), findsOneWidget);
    });

    testWidgets('muhatap ve ikiden çok malik: yeni muhatap SEÇİLMEDEN gönderilmez; seçince gövdede gider', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_remove_11');
      expect(find.text('Yeni hesap muhatabı *'), findsOneWidget);
      await _tapKey(t, 'owner_remove_submit');
      await settleFor(t);
      expect(find.text('Yeni hesap muhatabını seçin.'), findsWidgets);
      expect(env.api.calls.where((c) => c.path.endsWith('/remove')), isEmpty, reason: 'seçim olmadan istek yok');
      await tapFinder(t, _key('owner_new_holder'));
      await settleFor(t);
      await t.tap(find.text('Fatma Yılmaz').last);
      await settleFor(t);
      await _tapKey(t, 'owner_remove_submit');
      await settleFor(t);
      final post = env.api.calls.singleWhere((c) => c.path.endsWith('/remove'));
      expect(post.path, '/manager/sites/11/apartments/301/owners/11/remove');
      expect(post.body, <String, Object?>{'new_account_holder_residency_id': 13});
      expect(find.text('Ayşe Yılmaz'), findsNothing, reason: 'çıkarılan malik kartta yok');
      expect(find.text('Hesap muhatabı'), findsOneWidget);
    });

    testWidgets('muhatap ve TEK kalan malik: seçim yok, kimin muhatap olacağı yazılır', (t) async {
      final env = await _openCard(t, <Map<String, dynamic>>[
        _OwnersApi.owner(11, 1, 'Ayşe Yılmaz', holder: true),
        _OwnersApi.owner(12, 2, 'Ali Yılmaz'),
      ]);
      await _tapKey(t, 'owner_remove_11');
      expect(find.text('Hesap muhatabı Ali Yılmaz olacak.'), findsOneWidget);
      expect(_key('owner_new_holder'), findsNothing);
      await _tapKey(t, 'owner_remove_submit');
      await settleFor(t);
      expect(env.api.calls.singleWhere((c) => c.path.endsWith('/remove')).body, <String, Object?>{});
      expect(env.api.owners.single['full_name'], 'Ali Yılmaz');
      expect(env.api.owners.single['is_account_holder'], isTrue);
    });

    testWidgets('sunucu reddi pencerede kalır (ACCOUNT_HOLDER_REQUIRED yarışı); pencere kapanmaz', (t) async {
      final env = await _openCard(t, <Map<String, dynamic>>[
        _OwnersApi.owner(11, 1, 'Ayşe Yılmaz', holder: true),
        _OwnersApi.owner(12, 2, 'Ali Yılmaz'),
      ]);
      await _tapKey(t, 'owner_remove_12');
      env.api.failNext = ApiException('Dairenin tek maliki buradan çıkarılamaz.', statusCode: 409, code: 'LAST_OWNER');
      await _tapKey(t, 'owner_remove_submit');
      await settleFor(t);
      expect(find.text('Dairenin tek maliki buradan çıkarılamaz.'), findsOneWidget);
      expect(find.text('Maliki Çıkar'), findsOneWidget, reason: 'pencere açık');
      expect(env.changed, isEmpty);
    });
  });

  group('Malik ekle', () {
    testWidgets('kayıtlı kişi seçilmeden eklenmez; seçici kişiyi getirir; "hesap muhatabı olsun" gövdeye girer', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_add_button');
      expect(find.text('Malik Ekle'), findsOneWidget);
      expect(find.text(kAccountHolderExplain), findsWidgets);
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      expect(find.text('Malik olacak kişiyi seçin.'), findsOneWidget);
      expect(env.api.calls.where((c) => c.method == 'POST'), isEmpty);

      await _tapKey(t, 'owner_add_person');
      await settleFor(t);
      expect(find.text('Malik olacak kişi'), findsOneWidget, reason: 'seçici başlığı');
      await t.tap(find.text('Mehmet Demir').last);
      await settleFor(t);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      await _tapKey(t, 'owner_add_holder');
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      final post = env.api.calls.singleWhere((c) => c.method == 'POST');
      expect(post.path, '/manager/sites/11/apartments/301/owners');
      expect(post.body, <String, Object?>{'person_id': 2, 'make_account_holder': true});
      expect(find.text('Malik eklendi.'), findsOneWidget);
      expect(env.changed, hasLength(1));
      expect(find.text('Mehmet Demir'), findsWidgets, reason: 'kart yenilendi: yeni malik listede');
    });

    testWidgets('yeni kişi: ad zorunlu; telefon / e-posta biçimi denetlenir; yalnız dolu alanlar gider', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_add_button');
      await tapFinder(t, find.text('Yeni kişi'));
      await settleFor(t);
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      expect(find.text('Ad soyad en az 2 karakter olmalı.'), findsOneWidget);
      expect(env.api.calls.where((c) => c.method == 'POST'), isEmpty);

      await t.enterText(_key('owner_add_name'), 'Zeynep Arslan');
      await t.enterText(_key('owner_add_email'), 'gecersiz');
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);
      expect(env.api.calls.where((c) => c.method == 'POST'), isEmpty);

      await t.enterText(_key('owner_add_email'), 'Zeynep@Example.com');
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      final post = env.api.calls.singleWhere((c) => c.method == 'POST');
      expect(post.body, <String, Object?>{
        'person': <String, Object?>{'full_name': 'Zeynep Arslan', 'email': 'zeynep@example.com'},
      });
      expect(find.text('Zeynep Arslan'), findsWidgets);
    });

    testWidgets('dairede malik yokken: "hesap muhatabı olsun" seçeneği yerine bilgi notu', (t) async {
      await _openCard(t, <Map<String, dynamic>>[]);
      expect(find.text('Kayıtlı değil'), findsNWidgets(2), reason: 'malik ve kiracı yok');
      await _tapKey(t, 'owner_add_button');
      expect(_key('owner_add_holder'), findsNothing);
      expect(find.text('Dairede başka malik kayıtlı değil: eklenen kişi hesap muhatabı olur.'), findsOneWidget);
    });

    testWidgets('sunucu reddi (aynı e-posta) pencerede Türkçe kalır; pencere kapanmaz', (t) async {
      final env = await _openCard(t, _three);
      await _tapKey(t, 'owner_add_button');
      await tapFinder(t, find.text('Yeni kişi'));
      await settleFor(t);
      await t.enterText(_key('owner_add_name'), 'Zeynep Arslan');
      env.api.failNext = ApiException('Bu e-posta ile kayıtlı bir kişi zaten var. Kayıtlı kişiyi seçerek ekleyin.', statusCode: 409, code: 'PERSON_EXISTS');
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      expect(find.textContaining('Bu e-posta ile kayıtlı bir kişi zaten var'), findsOneWidget);
      expect(find.text('Malik Ekle'), findsOneWidget);
      expect(env.changed, isEmpty);
    });

    layoutMatrix('Malik ekle penceresi (yeni kişi, hata satırı): taşma yok', (t, w, h, s, dark) async {
      final env = await _openCard(t, _three, width: w, height: h, scale: s, dark: dark);
      env.api.failNext = ApiException('Bir dairede en fazla 10 malik kayıtlı olabilir.', statusCode: 409, code: 'OWNER_LIMIT');
      await _tapKey(t, 'owner_add_button');
      await tapFinder(t, find.text('Yeni kişi'));
      await settleFor(t);
      await t.enterText(_key('owner_add_name'), 'Muhammed Abdurrahman Büyükkaradeniz-Yılmazoğlu');
      await _tapKey(t, 'owner_add_submit');
      await settleFor(t);
      expect(find.text('Bir dairede en fazla 10 malik kayıtlı olabilir.'), findsOneWidget);
    });
  });
}

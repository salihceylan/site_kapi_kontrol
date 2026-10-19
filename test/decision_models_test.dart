// Karar Defteri modelleri (lib/models/decision_models.dart): savunmacı ayrıştırma, sakin görünümü, imleç türleri,
// form gövdesi ve PATCH farkı.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';

import 'screens/decision_fixtures.dart';

void main() {
  group('Decision.fromJson', () {
    test('yönetim görünümü: tüm alanlar', () {
      final d = Decision.fromJson(dcJson(
        3,
        no: 2,
        date: '2026-06-20',
        status: 'kesin',
        visibility: 'sakinler',
        supersedesId: 1,
        supersedesLabel: '2026/1',
        supersededBy: <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'number_label': '2026/5'},
        ],
      ));
      expect(d.id, 3);
      expect(d.siteCode, 11);
      expect(d.year, 2026);
      expect(d.decisionNo, 2);
      expect(d.numberLabel, '2026/2');
      expect(d.displayNumber, '2026/2');
      expect(d.meetingType, DecisionMeetingType.yonetimKurulu);
      expect(d.meetingDate, DateTime(2026, 6, 20));
      expect(d.voteResult, DecisionVoteResult.kabul);
      expect(d.voteCountsText, 'Kabul 3 · Ret 0 · Çekimser 1');
      expect(d.visibility, DecisionVisibility.sakinler);
      expect(d.isVisibleToResidents, isTrue);
      expect(d.status, DecisionStatus.kesin);
      expect(d.isFinal, isTrue);
      expect(d.isDraft, isFalse);
      expect(d.supersedes, const DecisionRef(id: 1, numberLabel: '2026/1'));
      expect(d.supersededBy, const <DecisionRef>[DecisionRef(id: 9, numberLabel: '2026/5')]);
      expect(d.supersededText, '2026/5 sayılı kararla değiştirildi');
      expect(d.createdByName, 'Mehmet Kaya');
      expect(d.finalizedByName, 'Ayşe Yılmaz');
      expect(d.finalizedAt, DateTime.utc(2026, 3, 6, 10, 30).toLocal());
      expect(d.body, contains('\n'), reason: 'satır sonları korunur');
    });

    test('sakin görünümü: status / visibility / created_by_name yok -> kesin, görünürlük null', () {
      final d = Decision.fromJson(dcResident(dcJson(1, no: 1, status: 'kesin', visibility: 'sakinler')), resident: true);
      expect(d.status, DecisionStatus.kesin);
      expect(d.isFinal, isTrue);
      expect(d.visibility, isNull);
      expect(d.isVisibleToResidents, isFalse);
      expect(d.createdByName, isNull);
      expect(d.numberLabel, '2026/1');
    });

    test('taslak: numara yok, "Taslak" gösterilir', () {
      final d = Decision.fromJson(dcJson(2));
      expect(d.isDraft, isTrue);
      expect(d.numberLabel, isNull);
      expect(d.displayNumber, 'Taslak');
    });

    test('bozuk / eksik alanlar çökmez; bilinmeyen sabitler güvenli değere düşer', () {
      final d = Decision.fromJson(<String, dynamic>{
        'id': '7',
        'meeting_type': 'olaganustu',
        'vote_result': 'oybirligi',
        'status': 'arsiv',
        'visibility': 'herkes',
        'votes_for': 'beş',
        'superseded_by': <Object?>['x', <String, dynamic>{'id': 0}, <String, dynamic>{'id': 4}],
        'meeting_date': '2026-02-31',
      });
      expect(d.id, 7);
      expect(d.meetingType, DecisionMeetingType.diger);
      expect(d.voteResult, DecisionVoteResult.unknown);
      expect(d.voteResult.label, 'Belirtilmemiş');
      expect(d.status, DecisionStatus.unknown);
      expect(d.isDraft, isFalse);
      expect(d.isFinal, isFalse);
      expect(d.visibility, DecisionVisibility.yonetim, reason: 'bilinmeyen görünürlük dar olana düşer');
      expect(d.votesFor, isNull);
      expect(d.meetingDate, isNull, reason: '31 Şubat gerçek bir gün değil');
      expect(d.supersededBy, const <DecisionRef>[DecisionRef(id: 4)]);
      expect(d.supersededText, 'Yeni bir kararla değiştirildi');
    });

    test('toplantı günü UTC damgasıyla gelse de gün kaymaz', () {
      final d = Decision.fromJson(<String, dynamic>{'id': 1, 'meeting_date': '2026-03-05T21:00:00.000Z'});
      expect(d.meetingDate, DateTime(2026, 3, 5));
      expect(d.effectiveYear, 2026, reason: '`year` yoksa toplantı yılı');
    });

    test('status yokken numara varsa kesin sayılır (eski yanıt)', () {
      final d = Decision.fromJson(<String, dynamic>{'id': 1, 'number_label': '2026/4', 'decision_no': 4});
      expect(d.isFinal, isTrue);
    });

    test('fromResponse: {decision} sarmalı ya da doğrudan nesne; id yoksa null', () {
      expect(Decision.fromResponse(<String, dynamic>{'decision': dcJson(5)})!.id, 5);
      expect(Decision.fromResponse(dcJson(6))!.id, 6);
      expect(Decision.fromResponse(<String, dynamic>{'decision': <String, dynamic>{}}), isNull);
      expect(Decision.fromResponse('x'), isNull);
    });

    test('birden çok değiştiren karar: "sayılı kararlarla değiştirildi"', () {
      expect(
        decisionSupersededText(const <DecisionRef>[DecisionRef(id: 1, numberLabel: '2026/5'), DecisionRef(id: 2, numberLabel: '2026/7')]),
        '2026/5, 2026/7 sayılı kararlarla değiştirildi',
      );
      expect(decisionSupersededText(const <DecisionRef>[]), isNull);
    });
  });

  group('DecisionPage', () {
    test('next_before_id -> before_id imleci; yıllar yinelenmesiz ve yeniden eskiye', () {
      final page = DecisionPage.fromJson(<String, dynamic>{
        'items': <Object>[dcJson(1), dcJson(2), 'bozuk', <String, dynamic>{'id': 0}],
        'next_before_id': 2,
        'years': <Object>[2024, '2026', 2026, 2025, 'x', 0],
      });
      expect(page.items.map((d) => d.id), <int>[1, 2]);
      expect(page.next, const DecisionCursor.beforeId(2));
      expect(page.next!.query, <String, String>{'before_id': '2'});
      expect(page.years, <int>[2026, 2025, 2024]);
    });

    test('next_cursor -> opak cursor imleci (öncelikli); ikisi de yoksa son sayfa', () {
      final opaque = DecisionPage.fromJson(<String, dynamic>{'items': <Object>[], 'next_cursor': 'abc', 'next_before_id': 3});
      expect(opaque.next, const DecisionCursor.opaque('abc'));
      expect(opaque.next!.query, <String, String>{'cursor': 'abc'});
      final last = DecisionPage.fromJson(<String, dynamic>{'items': <Object>[], 'next_cursor': null, 'next_before_id': null});
      expect(last.next, isNull);
      expect(last.years, isEmpty);
    });
  });

  group('DecisionInput', () {
    final input = DecisionInput(
      meetingType: DecisionMeetingType.genelKurul,
      meetingDate: DateTime(2026, 3, 5),
      title: '  Aidat  ',
      body: ' Metin ',
      attendees: '   ',
      voteResult: DecisionVoteResult.ret,
      votesFor: 2,
      visibility: DecisionVisibility.sakinler,
      supersedesId: 4,
    );

    test('toJson: sözleşme gövdesi, boş isteğe bağlı alanlar gönderilmez', () {
      expect(input.toJson(), <String, dynamic>{
        'meeting_type': 'genel_kurul',
        'meeting_date': '2026-03-05',
        'title': 'Aidat',
        'body': 'Metin',
        'vote_result': 'ret',
        'votes_for': 2,
        'visibility': 'sakinler',
        'supersedes_id': 4,
      });
    });

    test('diff: yalnız değişen alanlar; temizlenen isteğe bağlı alan null; supersedes gönderilmez', () {
      final original = Decision.fromJson(dcJson(2, type: 'genel_kurul', title: 'Aidat', body: 'Metin', vote: 'ret', votesFor: 2, votesAgainst: 0, votesAbstain: 1));
      expect(input.diff(original), <String, Object?>{
        'attendees': null,
        'votes_against': null,
        'votes_abstain': null,
        'visibility': 'sakinler',
      });
      final same = DecisionInput(
        meetingType: original.meetingType,
        meetingDate: original.meetingDate!,
        title: original.title,
        body: original.body,
        attendees: original.attendees ?? '',
        voteResult: original.voteResult,
        votesFor: original.votesFor,
        votesAgainst: original.votesAgainst,
        votesAbstain: original.votesAbstain,
      );
      expect(same.diff(original), isEmpty);
    });
  });

  test('compareDecisionsByNumber: numara sırası, numarasızlar sonda', () {
    final list = <Decision>[
      Decision.fromJson(dcJson(9)),
      Decision.fromJson(dcJson(3, no: 2, status: 'kesin')),
      Decision.fromJson(dcJson(5, no: 1, status: 'kesin')),
    ]..sort(compareDecisionsByNumber);
    expect(list.map((d) => d.id), <int>[5, 3, 9]);
  });

  test('DecisionSite: kurul yazamaz; boş adda "İsimsiz site"', () {
    expect(const DecisionSite(code: 1, name: 'A').canWrite, isTrue);
    expect(const DecisionSite(code: 1, name: 'A', access: DecisionSiteAccess.board).canWrite, isFalse);
    expect(const DecisionSite(code: 1, name: ' ').label, 'İsimsiz site');
  });

  test('denetim kaydı: Karar Defteri eylemleri Türkçe; hedef karar numarası (metin yazılmaz)', () {
    AuditLogEntry entry(String action, {Map<String, dynamic>? details}) => AuditLogEntry.fromJson(<String, dynamic>{
      'id': 1,
      'action': action,
      'target_type': 'board_decision',
      'target_id': '42',
      'details': details ?? <String, dynamic>{},
    });
    expect(entry('board_decision.created').actionLabel, 'Karar taslağı oluşturuldu');
    expect(entry('board_decision.updated').actionLabel, 'Karar taslağı düzenlendi');
    expect(entry('board_decision.deleted').actionLabel, 'Karar taslağı silindi');
    final finalized = entry('board_decision.finalized', details: <String, dynamic>{'year': 2026, 'decision_no': 3, 'number_label': '2026/3'});
    expect(finalized.actionLabel, 'Karar kesinleştirildi');
    expect(finalized.targetLabel, 'Karar 2026/3');
    expect(entry('board_decision.created').targetLabel, 'Karar #42');
  });
}

// Anket modelleri (lib/models/survey_models.dart): ayrıştırma, güvenli varsayılanlar, tamsayı yüzde, durum kuralları
// ve istek gövdesi (docs/PLATFORM_ANKET.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';

import 'screens/survey_fixtures.dart';

void main() {
  group('surveyPercent', () {
    test('tamsayı, yuvarlama yok, 0 toplamda 0', () {
      expect(surveyPercent(1, 3), 33);
      expect(surveyPercent(2, 3), 66);
      expect(surveyPercent(0, 0), 0);
      expect(surveyPercent(5, 0), 0);
      expect(surveyPercent(7, 7), 100);
      expect(surveyPercent(9, 7), 100, reason: '100 aşılmaz');
    });
  });

  group('SurveyStatus / SurveyTargetType', () {
    test('bilinmeyen durum unknown, bilinmeyen hedef site', () {
      expect(SurveyStatus.fromApi('OPEN'), SurveyStatus.open);
      expect(SurveyStatus.fromApi('x'), SurveyStatus.unknown);
      expect(SurveyStatus.fromApi(null), SurveyStatus.unknown);
      expect(SurveyTargetType.fromApi('blocks'), SurveyTargetType.blocks);
      expect(SurveyTargetType.fromApi('?'), SurveyTargetType.site);
    });
  });

  group('SurveySummary / SurveyDetail', () {
    test('alanlar ayrışır; süresi dolmuş açık anket isExpired', () {
      final d = SurveyDetail.fromJson(svSurvey(5, effectiveStatus: 'closed', createdBy: 'Ali'));
      expect(d.id, 5);
      expect(d.summary.status, SurveyStatus.open);
      expect(d.summary.effectiveStatus, SurveyStatus.closed);
      expect(d.summary.isExpired, isTrue);
      expect(d.summary.canClose, isTrue);
      expect(d.summary.canPublish, isFalse);
      expect(d.summary.canDelete, isFalse);
      expect(d.summary.totalVotes, 20);
      expect(d.summary.eligibleCount, 40);
      expect(d.summary.createdByName, 'Ali');
      expect(d.options, <String>['Evet', 'Hayır', 'Kararsızım']);
      expect(d.results.counts, <int>[12, 5, 3]);
      expect(d.results.percentAt(0), 60);
      expect(d.results.percentAt(1), 25);
      expect(d.results.percentAt(7), 0);
      expect(d.results.participationPercent, 50);
      expect(d.target.type, SurveyTargetType.site);
      expect(d.target.summary, 'Tüm site');
    });

    test('taslak: yayınla ve sil; eksik alanlar çökmez', () {
      final s = SurveySummary.fromJson(<String, dynamic>{'id': '9', 'status': 'draft'});
      expect(s.id, 9);
      expect(s.canPublish, isTrue);
      expect(s.canDelete, isTrue);
      expect(s.canClose, isFalse);
      expect(s.anonymous, isTrue);
      expect(s.effectiveStatus, SurveyStatus.draft, reason: 'effective_status yoksa status');
      expect(s.closesAt, isNull);
      expect(SurveyDetail.fromJson(<String, dynamic>{'id': 1}).results.totalVotes, 0);
      expect(SurveySummary.listFrom(<Object>[1, 'x', <String, dynamic>{'id': 0}]), isEmpty);
    });

    test('hedef özeti: etiketler ya da sayı', () {
      expect(
        SurveyTarget.fromJson(<String, dynamic>{'type': 'blocks', 'block_ids': <int>[1, 2], 'labels': <String>['A', 'B']}).summary,
        'Bloklar: A, B',
      );
      expect(SurveyTarget.fromJson(<String, dynamic>{'type': 'apartments', 'apartment_ids': <int>[1, 2, 3]}).summary, '3 daire');
    });
  });

  group('SurveyResidentItem', () {
    test('oy / sonuç görünürlüğü', () {
      final open = SurveyResidentItem.fromJson(<String, dynamic>{'id': 1, 'effective_status': 'open', 'results': null});
      expect(open.canVote, isTrue);
      expect(open.showsResults, isFalse);
      final voted = SurveyResidentItem.fromJson(<String, dynamic>{
        'id': 1,
        'effective_status': 'open',
        'my_vote': 1,
        'results': <String, dynamic>{'counts': <int>[1, 2], 'total_votes': 3},
      });
      expect(voted.canVote, isFalse);
      expect(voted.showsResults, isTrue);
      expect(voted.results!.participationPercent, isNull, reason: 'sakin görünümünde kitle gelmez');
      final closed = SurveyResidentItem.fromJson(<String, dynamic>{'id': 1, 'effective_status': 'closed', 'results': <String, dynamic>{'counts': <int>[]}});
      expect(closed.canVote, isFalse);
      expect(closed.showsResults, isTrue);
      final page = SurveyResidentPage.fromJson(<String, dynamic>{'items': <Object>[<String, dynamic>{'id': 2}], 'next_before_id': '2'});
      expect(page.items.single.id, 2);
      expect(page.nextBeforeId, 2);
    });
  });

  group('SurveyCreateRequest', () {
    test('gövde: hedef türüne göre id listesi, publish draft|now, UTC kapanış', () {
      final draft = const SurveyCreateRequest(title: ' Başlık ', question: 'Soru?', options: <String>['A ', ' B']).toJson();
      expect(draft['title'], 'Başlık');
      expect(draft['options'], <String>['A', 'B']);
      expect(draft['target'], <String, dynamic>{'type': 'site'});
      expect(draft['publish'], 'draft');
      expect(draft['anonymous'], isTrue);
      expect(draft['closes_at'], isNull);
      final now = SurveyCreateRequest(
        title: 't',
        question: 'q',
        options: const <String>['A', 'B'],
        targetType: SurveyTargetType.blocks,
        blockIds: const <int>[3],
        apartmentIds: const <int>[9],
        closesAt: DateTime.utc(2026, 12, 31, 21),
        publishNow: true,
        oneVotePerApartment: true,
      ).toJson();
      expect(now['target'], <String, dynamic>{'type': 'blocks', 'block_ids': <int>[3]});
      expect(now['publish'], 'now');
      expect(now['one_vote_per_apartment'], isTrue);
      expect(now['closes_at'], '2026-12-31T21:00:00.000Z');
    });
  });

  test('SurveyVoter: silinmiş hesap adı', () {
    final v = SurveyVoter.fromJson(<String, dynamic>{'user_code': null, 'full_name': '', 'option_index': 1});
    expect(v.displayName, 'Silinmiş hesap');
    expect(v.optionIndex, 1);
    expect(SurveyVoterPage.fromJson(<String, dynamic>{'items': null, 'total': 'x'}).total, 0);
  });
}

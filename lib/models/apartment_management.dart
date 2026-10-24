// Daire sahipliği ve yönetimi (Dairem) modelleri. Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md ve
// docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md. Alan yoksa güvenli varsayılan (eski sunucuyla çalışır).
import 'package:flutter/foundation.dart';

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
int _i(Object? v, [int fallback = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);
bool _b(Object? v) => v == true;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => v is List ? <Map<String, dynamic>>[for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Dairedeki bir kişi (ad ve hesap var mı; başka bilgi gösterilmez).
@immutable
class AptPerson {
  const AptPerson({this.personId, required this.name, this.hasAccount = false, this.derived = false});

  factory AptPerson.fromJson(Map<String, dynamic> j) => AptPerson(
    personId: j['person_id'] is num ? _i(j['person_id']) : null,
    name: _s(j['name'], 'Kayıtlı kişi'),
    hasAccount: _b(j['has_account']),
    derived: _b(j['derived']),
  );

  final int? personId;
  final String name;
  final bool hasAccount;

  /// Malik kaydı yoktu; yönetici olduğu için malik sayıldı (eski kayıt).
  final bool derived;
}

@immutable
class AptFamilyMember {
  const AptFamilyMember({
    required this.residencyId,
    required this.name,
    required this.relation,
    this.isMinor = false,
    this.hasAccount = false,
    this.canRemove = false,
  });

  factory AptFamilyMember.fromJson(Map<String, dynamic> j) => AptFamilyMember(
    residencyId: _i(j['residency_id']),
    name: _s(j['name'], 'Kayıtlı kişi'),
    relation: _s(j['relation'], 'family_member'),
    isMinor: _b(j['is_minor']),
    hasAccount: _b(j['has_account']),
    canRemove: _b(j['can_remove']),
  );

  final int residencyId;
  final String name;
  final String relation;
  final bool isMinor;
  final bool hasAccount;
  final bool canRemove;

  /// Yetişkin ve hesabı olan üyenin çıkarılması onay isteğidir (tek taraflı kesme yok).
  bool get removalNeedsConsent => hasAccount && !isMinor;
}

/// Bekleyen talep: davet (kiracı / aile üyesi), karşılıklı bağ kesme, üye çıkarma isteği.
@immutable
class AptRequest {
  const AptRequest({
    required this.id,
    required this.kind,
    required this.direction,
    this.requesterName,
    this.targetName,
    this.delegateManagement = false,
    this.expiresAt,
  });

  factory AptRequest.fromJson(Map<String, dynamic> j) => AptRequest(
    id: _i(j['id']),
    kind: _s(j['kind']),
    direction: _s(j['direction'], 'other'),
    requesterName: j['requester_name'] is String ? j['requester_name'] as String : null,
    targetName: j['target_name'] is String ? j['target_name'] as String : null,
    delegateManagement: _b(j['delegate_management']),
    expiresAt: _d(j['expires_at']),
  );

  final int id;
  final String kind;
  final String direction;
  final String? requesterName;
  final String? targetName;
  final bool delegateManagement;
  final DateTime? expiresAt;

  String get kindLabel => switch (kind) {
    'tenant_invite' => 'Kiracı daveti',
    'family_invite' => 'Aile üyesi daveti',
    'disconnect' => 'Bağlantı kesme talebi',
    'member_removal' => 'Üye çıkarma isteği',
    _ => 'Talep',
  };
}

@immutable
class AptProxy {
  const AptProxy({
    required this.id,
    required this.scope,
    required this.validFrom,
    required this.validUntil,
    this.revoked = false,
    this.active = false,
    this.proxyName,
    this.ownerName,
  });

  factory AptProxy.fromJson(Map<String, dynamic> j) => AptProxy(
    id: _i(j['id']),
    scope: _s(j['scope']),
    validFrom: _s(j['valid_from']),
    validUntil: _s(j['valid_until']),
    revoked: _b(j['revoked']),
    active: _b(j['active']),
    proxyName: j['proxy_name'] is String ? j['proxy_name'] as String : null,
    ownerName: j['owner_name'] is String ? j['owner_name'] as String : null,
  );

  final int id;
  final String scope;
  final String validFrom;
  final String validUntil;
  final bool revoked;
  final bool active;
  final String? proxyName;
  final String? ownerName;

  String get scopeLabel => scope == 'kurul_uyeligi' ? 'Kurul üyeliği' : 'Toplantı imzası';
}

@immutable
class AptCan {
  const AptCan({
    this.manageFamily = false,
    this.addTenant = false,
    this.delegateManagement = false,
    this.exit = false,
    this.requestDisconnect = false,
    this.manageProxy = false,
    this.searchPeople = false,
  });

  factory AptCan.fromJson(Map<String, dynamic> j) => AptCan(
    manageFamily: _b(j['manage_family']),
    addTenant: _b(j['add_tenant']),
    delegateManagement: _b(j['delegate_management']),
    exit: _b(j['exit']),
    requestDisconnect: _b(j['request_disconnect']),
    manageProxy: _b(j['manage_proxy']),
    searchPeople: _b(j['search_people']),
  );

  final bool manageFamily;
  final bool addTenant;
  final bool delegateManagement;
  final bool exit;
  final bool requestDisconnect;
  final bool manageProxy;
  final bool searchPeople;
}

@immutable
class MyApartment {
  const MyApartment({
    required this.apartmentId,
    required this.siteCode,
    required this.siteName,
    required this.label,
    required this.myRole,
    this.isAdmin = false,
    this.isOwner = false,
    this.adminName,
    this.adminSide = 'none',
    this.delegated = false,
    this.delegationPending = false,
    this.owner,
    this.tenant,
    this.family = const <AptFamilyMember>[],
    this.can = const AptCan(),
    this.requests = const <AptRequest>[],
    this.proxies = const <AptProxy>[],
    this.signingKind = 'none',
    this.signingName,
  });

  factory MyApartment.fromJson(Map<String, dynamic> j) {
    final mgmt = _m(j['management']);
    final signing = _m(j['signing']);
    return MyApartment(
      apartmentId: _i(j['apartment_id']),
      siteCode: _i(j['site_code']),
      siteName: _s(j['site_name']),
      label: _s(j['label'], 'Daire'),
      myRole: _s(j['my_role'], 'resident'),
      isAdmin: _b(j['is_admin']),
      isOwner: _b(j['is_owner']),
      adminName: mgmt['admin_name'] is String ? mgmt['admin_name'] as String : null,
      adminSide: _s(mgmt['admin_side'], 'none'),
      delegated: _b(mgmt['delegated']),
      delegationPending: _b(mgmt['delegation_pending']),
      owner: j['owner'] is Map ? AptPerson.fromJson(_m(j['owner'])) : null,
      tenant: j['tenant'] is Map ? AptPerson.fromJson(_m(j['tenant'])) : null,
      family: <AptFamilyMember>[for (final e in _l(j['family'])) AptFamilyMember.fromJson(e)],
      can: AptCan.fromJson(_m(j['can'])),
      requests: <AptRequest>[for (final e in _l(j['requests'])) AptRequest.fromJson(e)],
      proxies: <AptProxy>[for (final e in _l(j['proxies'])) AptProxy.fromJson(e)],
      signingKind: _s(signing['holder_kind'], 'none'),
      signingName: signing['holder_name'] is String ? signing['holder_name'] as String : null,
    );
  }

  final int apartmentId;
  final int siteCode;
  final String siteName;
  final String label;
  final String myRole;
  final bool isAdmin;
  final bool isOwner;
  final String? adminName;
  final String adminSide;
  final bool delegated;
  final bool delegationPending;
  final AptPerson? owner;
  final AptPerson? tenant;
  final List<AptFamilyMember> family;
  final AptCan can;
  final List<AptRequest> requests;
  final List<AptProxy> proxies;
  final String signingKind;
  final String? signingName;

  String get roleLabel => switch (myRole) {
    'owner' => 'Malik',
    'tenant' => 'Kiracı',
    'family_member' => 'Aile üyesi',
    _ => 'Sakin',
  };

  String get adminSideLabel => switch (adminSide) {
    'owner' => 'malik',
    'tenant' => 'kiracı',
    'other' => 'sakin',
    _ => '',
  };
}

@immutable
class IncomingAptRequest {
  const IncomingAptRequest({
    required this.id,
    required this.kind,
    required this.apartmentId,
    required this.siteName,
    required this.apartmentLabel,
    this.requesterName,
    this.delegateManagement = false,
  });

  factory IncomingAptRequest.fromJson(Map<String, dynamic> j) => IncomingAptRequest(
    id: _i(j['id']),
    kind: _s(j['kind']),
    apartmentId: _i(j['apartment_id']),
    siteName: _s(j['site_name']),
    apartmentLabel: _s(j['apartment_label']),
    requesterName: j['requester_name'] is String ? j['requester_name'] as String : null,
    delegateManagement: _b(j['delegate_management']),
  );

  final int id;
  final String kind;
  final int apartmentId;
  final String siteName;
  final String apartmentLabel;
  final String? requesterName;
  final bool delegateManagement;

  /// Kartın başlığı (kimden ne istendiği).
  String get title {
    final who = (requesterName ?? '').trim().isEmpty ? 'Bir kullanıcı' : requesterName!.trim();
    final where = '$siteName $apartmentLabel'.trim();
    return switch (kind) {
      'tenant_invite' => '$who sizi $where dairesine kiracı olarak davet etti',
      'family_invite' => '$who sizi $where dairesine aile üyesi olarak davet etti',
      'disconnect' => '$who $where dairesi için bağlantıyı kesmek istiyor',
      'member_removal' => '$who sizi $where dairesinden çıkarmak istiyor',
      _ => '$who bir talep gönderdi',
    };
  }

  String get explanation => switch (kind) {
    'tenant_invite' => delegateManagement
        ? 'Kabul ederseniz daire kiracısı olursunuz ve dairenin yönetimi size geçer. Reddedebilirsiniz.'
        : 'Kabul ederseniz daire kiracısı olursunuz. Reddedebilirsiniz.',
    'family_invite' => 'Kabul ederseniz daireyle ilgili ekranlara erişirsiniz. Borç bilgisi aile üyelerine gösterilmez. Reddedebilirsiniz.',
    'disconnect' => 'Onaylarsanız kiracılık sona erer ve yönetim malike döner. Reddedebilirsiniz; 14 gün yanıtsız kalırsa talep kapanır.',
    'member_removal' => 'Onaylarsanız bu daireyle bağınız ve kapı erişiminiz sona erer. Onaylamazsanız hiçbir şey değişmez; 7 gün yanıtsız kalırsa istek kapanır.',
    _ => '',
  };

  bool get isRemoval => kind == 'member_removal';
}

@immutable
class AptNotice {
  const AptNotice({required this.id, required this.message});

  factory AptNotice.fromJson(Map<String, dynamic> j) => AptNotice(id: _i(j['id']), message: _s(j['message']));

  final int id;
  final String message;
}

@immutable
class MyApartmentsData {
  const MyApartmentsData({
    this.apartments = const <MyApartment>[],
    this.incoming = const <IncomingAptRequest>[],
    this.notices = const <AptNotice>[],
    this.canSearch = false,
  });

  factory MyApartmentsData.fromJson(Map<String, dynamic> j) => MyApartmentsData(
    apartments: <MyApartment>[for (final e in _l(j['apartments'])) MyApartment.fromJson(e)],
    incoming: <IncomingAptRequest>[for (final e in _l(j['incoming_requests'])) IncomingAptRequest.fromJson(e)],
    notices: <AptNotice>[for (final e in _l(j['notices'])) AptNotice.fromJson(e)],
    canSearch: _b(j['can_search']),
  );

  final List<MyApartment> apartments;
  final List<IncomingAptRequest> incoming;
  final List<AptNotice> notices;
  final bool canSearch;
}

@immutable
class PersonCandidate {
  const PersonCandidate({required this.handle, required this.displayName, required this.displayEmail});

  factory PersonCandidate.fromJson(Map<String, dynamic> j) => PersonCandidate(
    handle: _s(j['handle']),
    displayName: _s(j['display_name'], '***'),
    displayEmail: _s(j['display_email'], '***'),
  );

  final String handle;
  final String displayName;
  final String displayEmail;
}

@immutable
class PersonSearchResult {
  const PersonSearchResult({this.items = const <PersonCandidate>[], this.tooMany = false});

  factory PersonSearchResult.fromJson(Map<String, dynamic> j) => PersonSearchResult(
    items: <PersonCandidate>[for (final e in _l(j['items'])) PersonCandidate.fromJson(e)],
    tooMany: _b(j['too_many']),
  );

  final List<PersonCandidate> items;
  final bool tooMany;
}

@immutable
class ExitPreview {
  const ExitPreview({this.hasDebt = false, this.totalMinor = 0, this.familyCount = 0});

  factory ExitPreview.fromJson(Map<String, dynamic> j) =>
      ExitPreview(hasDebt: _b(j['has_debt']), totalMinor: _i(j['total_minor']), familyCount: _i(j['family_count']));

  final bool hasDebt;
  final int totalMinor;
  final int familyCount;

  String get debtText {
    final lira = totalMinor ~/ 100;
    final kurus = (totalMinor % 100).toString().padLeft(2, '0');
    return '$lira,$kurus TL';
  }
}

/// Dairem ekranında yeni kişi ekleme penceresinin sonucu.
@immutable
class AddPersonInput {
  const AddPersonInput({this.candidate, this.fullName, this.phone, this.email, this.delegateManagement = true, this.isMinor = false});

  final String? candidate;
  final String? fullName;
  final String? phone;
  final String? email;
  final bool delegateManagement;
  final bool isMinor;

  Map<String, Object?> toBody({bool tenant = false}) => <String, Object?>{
    if (candidate != null) 'candidate': candidate,
    if (candidate == null)
      'person': <String, Object?>{
        'full_name': fullName,
        if ((phone ?? '').isNotEmpty) 'phone': phone,
        if ((email ?? '').isNotEmpty) 'email': email,
      },
    if (tenant) 'delegate_management': delegateManagement else 'is_minor': isMinor,
  };
}

// ---------------------------------------------------------------------------
// Karar Defteri: imza hakkı sahipleri
// ---------------------------------------------------------------------------

@immutable
class SigningRosterItem {
  const SigningRosterItem({
    required this.label,
    required this.holderKind,
    this.holderName,
    this.ownerName,
    this.boardProxyName,
    required this.labelText,
  });

  factory SigningRosterItem.fromJson(Map<String, dynamic> j) => SigningRosterItem(
    label: _s(j['label']),
    holderKind: _s(j['holder_kind'], 'none'),
    holderName: j['holder_name'] is String ? j['holder_name'] as String : null,
    ownerName: j['owner_name'] is String ? j['owner_name'] as String : null,
    boardProxyName: j['board_proxy_name'] is String ? j['board_proxy_name'] as String : null,
    labelText: _s(j['label_text']),
  );

  final String label;
  final String holderKind;
  final String? holderName;
  final String? ownerName;
  final String? boardProxyName;
  final String labelText;
}

@immutable
class SigningRoster {
  const SigningRoster({required this.date, this.items = const <SigningRosterItem>[]});

  factory SigningRoster.fromJson(Map<String, dynamic> j) =>
      SigningRoster(date: _s(j['date']), items: <SigningRosterItem>[for (final e in _l(j['items'])) SigningRosterItem.fromJson(e)]);

  final String date;
  final List<SigningRosterItem> items;
}

// ---------------------------------------------------------------------------
// Site yöneticisi: admin değiştirme, güvenlik talepleri, askıya alma
// ---------------------------------------------------------------------------

@immutable
class AdminCandidate {
  const AdminCandidate({
    this.userCode,
    this.personId,
    required this.name,
    required this.relation,
    this.isAdmin = false,
  });

  factory AdminCandidate.fromJson(Map<String, dynamic> j) => AdminCandidate(
    userCode: j['user_code'] is num ? _i(j['user_code']) : null,
    personId: j['person_id'] is num ? _i(j['person_id']) : null,
    name: _s(j['name'], 'Sakin'),
    relation: _s(j['relation'], 'resident'),
    isAdmin: _b(j['is_admin']),
  );

  final int? userCode;
  final int? personId;
  final String name;
  final String relation;
  final bool isAdmin;

  String get candidateKey => userCode != null ? 'u:$userCode' : 'p:$personId';

  String get relationLabel => switch (relation) {
    'owner' => 'Malik',
    'tenant' => 'Kiracı',
    'family_member' => 'Aile üyesi',
    _ => 'Sakin',
  };
}

@immutable
class AdminCandidates {
  const AdminCandidates({this.currentAdmin, this.items = const <AdminCandidate>[]});

  factory AdminCandidates.fromJson(Map<String, dynamic> j) => AdminCandidates(
    currentAdmin: j['current_admin'] is Map ? AdminCandidate.fromJson(_m(j['current_admin'])) : null,
    items: <AdminCandidate>[for (final e in _l(j['items'])) AdminCandidate.fromJson(e)],
  );

  final AdminCandidate? currentAdmin;
  final List<AdminCandidate> items;
}

@immutable
class SafetyRequestItem {
  const SafetyRequestItem({
    required this.id,
    required this.label,
    required this.message,
    required this.status,
    this.contactPref,
    this.requesterName,
    this.requesterPhone,
    this.requesterEmail,
    this.notes = const <String>[],
    this.createdAt,
  });

  factory SafetyRequestItem.fromJson(Map<String, dynamic> j) {
    final requester = _m(j['requester']);
    return SafetyRequestItem(
      id: _i(j['id']),
      label: _s(j['label']),
      message: _s(j['message']),
      status: _s(j['status'], 'open'),
      contactPref: j['contact_pref'] is String ? j['contact_pref'] as String : null,
      requesterName: requester['name'] is String ? requester['name'] as String : null,
      requesterPhone: requester['phone'] is String ? requester['phone'] as String : null,
      requesterEmail: requester['email'] is String ? requester['email'] as String : null,
      notes: <String>[for (final n in _l(j['notes'])) _s(n['note'])],
      createdAt: _d(j['created_at']),
    );
  }

  final int id;
  final String label;
  final String message;
  final String status;
  final String? contactPref;
  final String? requesterName;
  final String? requesterPhone;
  final String? requesterEmail;
  final List<String> notes;
  final DateTime? createdAt;

  String get statusLabel => switch (status) {
    'in_review' => 'İnceleniyor',
    'resolved' => 'Kapandı',
    _ => 'Açık',
  };

  String get contactLabel => switch (contactPref) {
    'phone' => 'Telefonla',
    'email' => 'E-postayla',
    'app' => 'Uygulama içinden',
    _ => 'Belirtilmedi',
  };
}

@immutable
class SuspensionItem {
  const SuspensionItem({required this.userCode, required this.name, required this.reasonCode, required this.note, required this.active});

  factory SuspensionItem.fromJson(Map<String, dynamic> j) => SuspensionItem(
    userCode: _i(j['user_code']),
    name: _s(j['name'], 'Sakin'),
    reasonCode: _s(j['reason_code']),
    note: _s(j['note']),
    active: _b(j['active']),
  );

  final int userCode;
  final String name;
  final String reasonCode;
  final String note;
  final bool active;

  String get reasonLabel => switch (reasonCode) {
    'court_order' => 'Mahkeme / koruma kararı',
    'safety' => 'Güvenlik',
    _ => 'Diğer',
  };
}

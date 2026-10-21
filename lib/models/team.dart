// Yönetim kadrosu, uygulamaya davet ve rehber modelleri (sunucu 058: /team, /duty, /invitation, /app/directory, /app/invitations).

/// Görev türleri (sunucudaki `duty` değerleri) ve Türkçe etiketleri.
const List<String> kTeamDuties = <String>[
  'board_member',
  'auditor',
  'doorman',
  'technical',
  'reception',
  'other',
];

const Map<String, String> kTeamDutyLabels = <String, String>{
  'board_member': 'Yönetim kurulu üyesi',
  'auditor': 'Denetçi',
  'doorman': 'Kapıcı',
  'technical': 'Teknik görevli',
  'reception': 'Danışma',
  'other': 'Diğer',
};

String teamDutyLabel(String duty) => kTeamDutyLabels[duty] ?? duty;

/// Görevin uygulama yetkisi durumu (yalnız yönetici görür).
String teamAccessText(String? access) {
  switch (access) {
    case 'granted':
      return 'Uygulama yetkisi açık';
    case 'invited':
      return 'Uygulamaya davet edildi; kabul edince yetki açılır';
    case 'internal_account':
      return 'Kişi daire hesabıyla giriş yapıyor; görev yetkisi için kendi hesabı gerekir';
    case 'manager':
      return 'Site yöneticisi olduğu için ayrıca yetki gerekmez';
    case 'needs_sync':
      return 'Hesabı var ama yetki açık değil; görevi yeniden kaydedin';
    case 'no_account':
    default:
      return 'Kişinin uygulama hesabı yok: görev kadroda görünür; yetki için uygulamaya davet edin';
  }
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class TeamDuty {
  const TeamDuty({
    required this.personId,
    required this.fullName,
    required this.duty,
    required this.showInDirectory,
    this.title,
    this.publicPhone,
    this.access,
  });

  factory TeamDuty.fromJson(Map<String, dynamic> json) => TeamDuty(
    personId: (json['person_id'] as num?)?.toInt() ?? 0,
    fullName: _text(json['full_name']) ?? 'İsimsiz',
    duty: _text(json['duty']) ?? 'other',
    title: _text(json['title']),
    publicPhone: _text(json['public_phone']),
    showInDirectory: json['show_in_directory'] != false,
    access: _text(json['access']),
  );

  final int personId;
  final String fullName;
  final String duty;
  final String? title;
  final String? publicPhone;
  final bool showInDirectory;
  final String? access;

  /// Liste başlığı: "Kapıcı" ya da "Diğer: Bahçıvan" yerine doğrudan unvan.
  String get label => duty == 'other' && title != null ? title! : teamDutyLabel(duty);
}

class LegacyStaffRole {
  const LegacyStaffRole({required this.userCode, required this.fullName, required this.role});

  factory LegacyStaffRole.fromJson(Map<String, dynamic> json) => LegacyStaffRole(
    userCode: (json['user_code'] as num?)?.toInt() ?? 0,
    fullName: _text(json['full_name']) ?? 'İsimsiz',
    role: _text(json['role']) ?? 'STAFF',
  );

  final int userCode;
  final String fullName;
  final String role;
}

class DirectoryContact {
  const DirectoryContact({
    required this.id,
    required this.label,
    required this.phone,
    required this.category,
    this.note,
  });

  factory DirectoryContact.fromJson(Map<String, dynamic> json) => DirectoryContact(
    id: (json['id'] as num?)?.toInt() ?? 0,
    label: _text(json['label']) ?? '',
    phone: _text(json['phone']) ?? '',
    category: _text(json['category']) ?? 'other',
    note: _text(json['note']),
  );

  final int id;
  final String label;
  final String phone;
  final String category;
  final String? note;
}

const Map<String, String> kContactCategoryLabels = <String, String>{
  'emergency': 'Acil',
  'utility': 'Kurum (su, elektrik, gaz)',
  'management': 'Yönetim',
  'service': 'Servis',
  'other': 'Diğer',
};

class TeamData {
  const TeamData({
    required this.managers,
    required this.duties,
    required this.legacyRoles,
    required this.contacts,
    required this.directoryEnabled,
  });

  factory TeamData.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) map) =>
        (json[key] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(map)
            .toList();
    return TeamData(
      managers: list<String>('managers', (m) => _text(m['full_name']) ?? 'İsimsiz'),
      duties: list<TeamDuty>('duties', TeamDuty.fromJson),
      legacyRoles: list<LegacyStaffRole>('legacy_roles', LegacyStaffRole.fromJson),
      contacts: list<DirectoryContact>('contacts', DirectoryContact.fromJson),
      directoryEnabled: json['directory_enabled'] == true,
    );
  }

  final List<String> managers;
  final List<TeamDuty> duties;
  final List<LegacyStaffRole> legacyRoles;
  final List<DirectoryContact> contacts;
  final bool directoryEnabled;

  TeamDuty? dutyOf(int personId) {
    for (final duty in duties) {
      if (duty.personId == personId) return duty;
    }
    return null;
  }
}

/// Kişinin davet durumu (bağlantı ASLA gelmez).
class PersonInvitationState {
  const PersonInvitationState({
    this.status,
    this.expiresAt,
    this.sendCount = 0,
    this.sent,
    this.blockReason,
  });

  factory PersonInvitationState.fromJson(Map<String, dynamic> json) {
    final invitation = json['invitation'];
    final map = invitation is Map<String, dynamic> ? invitation : const <String, dynamic>{};
    return PersonInvitationState(
      status: _text(map['status']),
      expiresAt: DateTime.tryParse(_text(map['expires_at']) ?? ''),
      sendCount: (map['send_count'] as num?)?.toInt() ?? 0,
      sent: map['sent'] is bool ? map['sent'] as bool : null,
      blockReason: _text(json['invite_block_reason']),
    );
  }

  final String? status;
  final DateTime? expiresAt;
  final int sendCount;

  /// Yalnız gönderim yanıtında: e-posta gerçekten gitti mi.
  final bool? sent;
  final String? blockReason;

  bool get isPending => status == 'pending';
}

String invitationBlockText(String? reason) {
  switch (reason) {
    case 'PERSON_NO_EMAIL':
      return 'E-postası olmayan kişi, SMS ek hizmeti açılınca telefonla girebilecek.';
    case 'PERSON_HAS_ACCOUNT':
      return 'Kişinin zaten uygulama hesabı var.';
    case 'PERSON_INTERNAL_ACCOUNT':
      return 'Kişi daire hesabıyla giriş yapıyor; davet gösterilmez.';
    case 'PERSON_INACTIVE':
      return 'Pasif kişi davet edilemez.';
    default:
      return '';
  }
}

/// Çağıran için bekleyen davet (`GET /app/invitations`).
class PendingInvitation {
  const PendingInvitation({required this.id, required this.siteName, this.duty, this.expiresAt});

  factory PendingInvitation.fromJson(Map<String, dynamic> json) => PendingInvitation(
    id: (json['id'] as num?)?.toInt() ?? 0,
    siteName: _text(json['site_name']) ?? 'Site',
    duty: _text(json['duty']),
    expiresAt: DateTime.tryParse(_text(json['expires_at']) ?? ''),
  );

  final int id;
  final String siteName;
  final String? duty;
  final DateTime? expiresAt;
}

class DirectoryPerson {
  const DirectoryPerson({required this.fullName, required this.label, this.phone});

  factory DirectoryPerson.fromJson(Map<String, dynamic> json) {
    final duty = _text(json['duty']) ?? 'other';
    final title = _text(json['title']);
    return DirectoryPerson(
      fullName: _text(json['full_name']) ?? 'İsimsiz',
      label: duty == 'other' && title != null ? title : (title != null ? '${teamDutyLabel(duty)} - $title' : teamDutyLabel(duty)),
      phone: _text(json['phone']),
    );
  }

  final String fullName;
  final String label;
  final String? phone;
}

class DirectorySite {
  const DirectorySite({
    required this.siteName,
    required this.managers,
    required this.board,
    required this.staff,
    required this.contacts,
  });

  factory DirectorySite.fromJson(Map<String, dynamic> json) {
    List<DirectoryPerson> people(String key) => (json[key] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(DirectoryPerson.fromJson)
        .toList();
    return DirectorySite(
      siteName: _text(json['site_name']) ?? 'Site',
      managers: (json['managers'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((m) => _text(m['full_name']) ?? 'İsimsiz')
          .toList(),
      board: people('board'),
      staff: people('staff'),
      contacts: (json['contacts'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DirectoryContact.fromJson)
          .toList(),
    );
  }

  final String siteName;
  final List<String> managers;
  final List<DirectoryPerson> board;
  final List<DirectoryPerson> staff;
  final List<DirectoryContact> contacts;

  bool get isEmpty => managers.isEmpty && board.isEmpty && staff.isEmpty && contacts.isEmpty;
}

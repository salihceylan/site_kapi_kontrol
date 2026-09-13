import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_join_info.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';

class AuthApi {
  AuthApi({required this.baseUrl});

  static const Duration _requestTimeout = Duration(seconds: 45);
  static const Duration _retryDelay = Duration(milliseconds: 350);

  final String baseUrl;

  Future<UserSession> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    return _authRequest(
      path: '/auth/login',
      body: {
        'email': email,
        'password': password,
        if (role != null) 'role': role.apiValue,
      },
      expectedCode: 200,
    );
  }

  String _managementPrefix(UserRole role) {
    return role == UserRole.superUser ? '/admin' : '/manager';
  }

  Future<Map<String, dynamic>> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/register-individual');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
      },
    );
    _ensureStatus(response, 201);
    return _decodePayload(response);
  }

  Future<UserSession> verifyIndividualCode({
    required String email,
    required String code,
  }) async {
    return _authRequest(
      path: '/auth/verify-code',
      body: {
        'email': email,
        'code': code,
      },
      expectedCode: 200,
    );
  }

  Future<Map<String, dynamic>> resendIndividualCode({
    required String email,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/resend-code');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: {
        'email': email,
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<UserSession> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? phoneNumber,
  }) async {
    return _authRequest(
      path: '/auth/register',
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role.apiValue,
        'phone_number': phoneNumber,
      },
      expectedCode: 201,
    );
  }

  Future<ManagedUserPage> listManagedUsers({
    required String token,
    UserRole? role,
    required int page,
    required int pageSize,
    String? search,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/users').replace(
      queryParameters: {
        if (role != null) 'role': role.apiValue,
        'page': '$page',
        'page_size': '$pageSize',
        if (search != null && search.trim().isNotEmpty)
          'search': search.trim(),
      },
    );

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);

    final payload = _decodePayload(response);
    final users = _parsePayload(
      'Kullanici listesi',
      () => (payload['users'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => ManagedUserAccount.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );

    return ManagedUserPage(
      users: users,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<void> createManagedUser({
    required String token,
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required bool isActive,
    String? phoneNumber,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/users',
      token: token,
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role.apiValue,
        'is_active': isActive,
        'phone_number': phoneNumber,
      },
    );

    _ensureStatus(response, 201);
  }

  Future<void> updateManagedUser({
    required String token,
    required int userCode,
    String? fullName,
    String? email,
    String? password,
    String? phoneNumber,
    bool? isActive,
    UserRole? role,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
      'is_active': isActive,
      if (role != null) 'role': role.apiValue,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/users/$userCode',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
  }

  Future<void> setManagedUserActivation({
    required String token,
    required int userCode,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/users/$userCode/activation',
      token: token,
      body: {'is_active': isActive},
    );

    _ensureStatus(response, 200);
  }

  Future<void> deleteManagedUser({
    required String token,
    required int userCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/admin/users/$userCode',
      token: token,
    );

    _ensureStatus(response, 204, allowEmptyBody: true);
  }

  Future<SitePage> listSites({
    required String token,
    required UserRole role,
    required int page,
    required int pageSize,
    String? approvalStatus,
  }) async {
    final uri = Uri.parse('$baseUrl${_managementPrefix(role)}/sites').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '$pageSize',
        if (role == UserRole.superUser && approvalStatus != null)
          'approval_status': approvalStatus,
      },
    );

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final sites = _parsePayload(
      'Site listesi',
      () => (payload['sites'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => SiteRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );

    return SitePage(
      sites: sites,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<void> resolveSiteApproval({
    required String token,
    required int siteCode,
    required String action,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/sites/$siteCode/approval',
      token: token,
      body: {'action': action},
    );

    _ensureStatus(response, 200);
  }

  Future<SiteRecord> createSite({
    required String token,
    required UserRole role,
    required String name,
    String? address,
    String? city,
    String? district,
    required List<int> blockApartmentCounts,
    required int doorCount,
    int? managerUserCode,
    Map<String, dynamic>? managerUser,
  }) async {
    final totalApartments = blockApartmentCounts.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/sites',
      token: token,
      body: {
        'name': name,
        'address': address,
        'city': city,
        'district': district,
        'block_count': blockApartmentCounts.length,
        'apartment_count': totalApartments,
        'block_apartment_counts': blockApartmentCounts,
        'door_count': doorCount,
        'manager_user_code': managerUserCode,
        'manager_user': managerUser,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site kaydi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateSite({
    required String token,
    required UserRole role,
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    List<int>? blockApartmentCounts,
    int? doorCount,
    int? managerUserCode,
  }) async {
    final totalApartments = blockApartmentCounts?.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'city': city,
      'district': district,
      'block_count': blockApartmentCounts?.length,
      'apartment_count': totalApartments,
      'block_apartment_counts': blockApartmentCounts,
      'door_count': doorCount,
      'manager_user_code': managerUserCode,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/sites/$siteCode',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site kaydi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateSiteFeatures({
    required String token,
    required int siteCode,
    bool? featureQrEnabled,
    bool? featureRemoteOpenEnabled,
    bool? featureLocalUdpEnabled,
    bool? featureGuestPassEnabled,
  }) async {
    final body = <String, dynamic>{
      'feature_qr_enabled': featureQrEnabled,
      'feature_remote_open_enabled': featureRemoteOpenEnabled,
      'feature_local_udp_enabled': featureLocalUdpEnabled,
      'feature_guest_pass_enabled': featureGuestPassEnabled,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/sites/$siteCode/features',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site modulleri',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateSiteSecurityPolicy({
    required String token,
    required UserRole role,
    required int siteCode,
    bool? featureRemoteOpenEnabled,
    bool? featureQrEnabled,
    bool? featureLocalUdpEnabled,
    bool? featureGuestPassEnabled,
    bool? qrEntryActive,
    bool? requireGeofence,
    double? geofenceLatitude,
    double? geofenceLongitude,
    int? geofenceRadiusMeters,
    int? qrRotationSeconds,
  }) async {
    final body = <String, dynamic>{
      'feature_remote_open_enabled': featureRemoteOpenEnabled,
      'feature_qr_enabled': featureQrEnabled,
      'feature_local_udp_enabled': featureLocalUdpEnabled,
      'feature_guest_pass_enabled': featureGuestPassEnabled,
      'qr_entry_active': qrEntryActive,
      'require_geofence': requireGeofence,
      'geofence_latitude': geofenceLatitude,
      'geofence_longitude': geofenceLongitude,
      'geofence_radius_meters': geofenceRadiusMeters,
      'qr_rotation_seconds': qrRotationSeconds,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/sites/$siteCode/security-policy',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Guvenlik politikasi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteStructureRecord> getSiteStructure({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '${_managementPrefix(role)}/sites/$siteCode/structure',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site yapisi',
      () => SiteStructureRecord.fromJson(payload),
    );
  }

  Future<ApartmentRecord> upsertApartmentResident({
    required String token,
    required UserRole role,
    required int apartmentId,
    required String fullName,
    required String loginName,
    required String password,
    String? email,
    String? phoneNumber,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/resident',
      token: token,
      body: {
        'full_name': fullName,
        'login_name': loginName,
        'password': password,
        'email': email,
        'phone_number': phoneNumber,
        'is_active': isActive,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Daire kullanicisi',
      () => ApartmentRecord.fromJson(
        payload['apartment'] as Map<String, dynamic>,
      ),
    );
  }

  Future<void> sendApartmentCredentials({
    required String token,
    required UserRole role,
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/send-credentials',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<void> deleteApartmentResident({
    required String token,
    required UserRole role,
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/resident',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<DoorAccessLogPage> listDoorAccessLogs({
    required String token,
    required UserRole role,
    int? siteCode,
    int? doorId,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 50,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (siteCode != null) 'site_code': siteCode.toString(),
      if (doorId != null) 'door_id': doorId.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
    };

    final uri = Uri.parse('$baseUrl${_managementPrefix(role)}/door-logs')
        .replace(queryParameters: query);

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi gecis loglari',
      () => DoorAccessLogPage.fromJson(payload),
    );
  }

  Future<DeviceConnectivityReport> getDeviceConnectivityLogs({
    required String token,
    required String deviceUid,
    int page = 1,
    int pageSize = 10,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    final uri = Uri.parse('$baseUrl/admin/devices/$deviceUid/connectivity-logs')
        .replace(queryParameters: query);

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz baglanti raporu',
      () => DeviceConnectivityReport.fromJson(payload),
    );
  }

  Future<int> syncDeviceLogs({
    required String deviceUid,
    required List<Map<String, dynamic>> logs,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl/device/sync-logs');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'X-Ahbu-Device-Uid': deviceUid,
      },
      body: {
        'device_uid': deviceUid,
        'logs': logs,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return (payload['synced_count'] as num?)?.toInt() ?? 0;
  }

  Future<DoorRecord> assignDoorDevice({
    required String token,
    required UserRole role,
    required int doorId,
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/doors/$doorId/device',
      token: token,
      body: {'device_uid': deviceUid},
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi kaydi',
      () => DoorRecord.fromJson(payload['door'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> deleteSite({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '${_managementPrefix(role)}/sites/$siteCode',
      token: token,
    );

    if (response.statusCode == 204 || response.body.isEmpty) {
      return {'ok': true, 'deleted': true};
    }
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> approveSiteDeletion({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/sites/$siteCode/approve-deletion',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> rejectSiteDeletion({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/sites/$siteCode/reject-deletion',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> requestSiteDeletionEmailCode({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/sites/$siteCode/request-email-deletion-code',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> confirmSiteDeletionWithEmailCode({
    required String token,
    required int siteCode,
    required String code,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/sites/$siteCode/confirm-email-deletion',
      token: token,
      body: {'code': code},
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<DeviceRecord> createDevice({
    required String token,
    required String deviceUid,
    int? assignedUserCode,
    int? siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/devices',
      token: token,
      body: {
        'device_uid': deviceUid,
        'assigned_user_code': assignedUserCode,
        'site_code': siteCode,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz kaydi',
      () => DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>),
    );
  }

  Future<DevicePage> listCompanyDevices({
    required String token,
    required UserRole role,
    required int page,
    required int pageSize,
  }) async {
    if (role == UserRole.siteManager) {
      final response = await _authorizedRequest(
        method: 'GET',
        path: '/manager/devices',
        token: token,
      );
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final devices = _parsePayload(
        'Cihazlar',
        () => (payload['devices'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
      return DevicePage(
        devices: devices,
        total: devices.length,
        page: 1,
        pageSize: devices.length,
      );
    }

    final uri = Uri.parse('$baseUrl/admin/devices').replace(
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
    );

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final devices = _parsePayload(
      'Cihazlar',
      () => (payload['devices'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return DevicePage(
      devices: devices,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<DeviceRecord> updateDevice({
    required String token,
    required UserRole role,
    required int deviceId,
    int? assignedUserCode,
    int? siteCode,
    String? gateName,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: role == UserRole.superUser
          ? '/admin/devices/$deviceId'
          : '/manager/devices/$deviceId/assignment',
      token: token,
      body: {
        'assigned_user_code': assignedUserCode,
        'site_code': siteCode,
        'gate_name': gateName,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz kaydi',
      () => DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>),
    );
  }

  Future<void> deleteDevice({
    required String token,
    required UserRole role,
    required int deviceId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: role == UserRole.superUser
          ? '/admin/devices/$deviceId'
          : '/manager/devices/$deviceId',
      token: token,
    );

    _ensureStatus(response, 204, allowEmptyBody: true);
  }

  Future<Map<String, dynamic>> broadcastOtaCheck({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/devices/ota-check',
      token: token,
    );

    _ensureStatus(response, 202);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> getDeviceMqttCredentials({
    required String token,
    required UserRole role,
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: role == UserRole.superUser
          ? '/admin/devices/mqtt-credentials'
          : '/manager/devices/mqtt-credentials',
      token: token,
      body: {'device_uid': deviceUid},
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'MQTT cihaz kimligi',
      () => payload['mqtt'] as Map<String, dynamic>,
    );
  }

  Future<DoorRuntimeStatus> getDoorRuntimeStatus({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/doors/$doorId/status',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi durumu',
      () => DoorRuntimeStatus.fromJson(payload),
    );
  }

  Future<DoorRuntimeStatus> openDoor({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/open',
      token: token,
    );

    _ensureStatus(response, 202);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi komutu',
      () => DoorRuntimeStatus.fromJson(payload),
    );
  }

  Future<void> notifyLocalDoorOpened({
    required String token,
    required int doorId,
    String? localIp,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/local-open-notify',
      token: token,
      body: {
        if (localIp != null && localIp.trim().isNotEmpty)
          'local_ip': localIp.trim(),
      },
    );
    _ensureStatus(response, 200);
  }

  Future<Map<String, dynamic>> requestDoorQrToken({
    required String token,
    required int doorId,
    Map<String, dynamic>? location,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/qr-token',
      token: token,
      body: location != null ? {'location': location} : null,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> revokeMyDoorQr({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/revoke-my-qr',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> getDoorQrStatus({
    required String token,
    required String qrToken,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/doors/qr-status?token=${Uri.encodeComponent(qrToken)}',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }


  Future<List<DoorRecord>> listMyDoors({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/my-doors',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapilar',
      () => (payload['doors'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => DoorRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<SubscriptionRequestPage> listSubscriptionRequests({
    required String token,
    required int page,
    required int pageSize,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/subscription-requests',
    ).replace(queryParameters: {'page': '$page', 'page_size': '$pageSize'});

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final requests = _parsePayload(
      'Abonelik talepleri',
      () => (payload['requests'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => SubscriptionRequest.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );

    return SubscriptionRequestPage(
      requests: requests,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<void> resolveSubscriptionRequest({
    required String token,
    required int userCode,
    required String action,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/subscription-requests/$userCode',
      token: token,
      body: {'action': action},
    );

    _ensureStatus(response, 200);
  }

  Future<UserSession> updateMyProfile({
    required String token,
    required int id,
    required UserRole role,
    required bool isActive,
    String? fullName,
    String? email,
    String? password,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/me',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Profil bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return _toUserSession(
        user: user,
        token: token,
        fallbackId: id,
        fallbackRole: role,
        fallbackIsActive: isActive,
      );
    });
  }

  Future<UserSession> _authRequest({
    required String path,
    required Map<String, dynamic> body,
    required int expectedCode,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );

    _ensureStatus(response, expectedCode);
    final payload = _decodePayload(response);
    return _parsePayload('Oturum bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return _toUserSession(
        user: user,
        token: payload['token'] as String,
        fallbackId: user['id'] as int,
        fallbackRole: UserRole.fromApi(user['role'] as String),
        fallbackIsActive: user['is_active'] as bool? ?? true,
      );
    });
  }

  Future<http.Response> _authorizedRequest({
    required String method,
    required String path,
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    switch (method) {
      case 'GET':
        return _sendRequest(method: 'GET', uri: uri, headers: headers);
      case 'DELETE':
        return _sendRequest(method: 'DELETE', uri: uri, headers: headers);
      case 'PATCH':
        return _sendRequest(
          method: 'PATCH',
          uri: uri,
          headers: headers,
          body: body,
        );
      case 'POST':
        return _sendRequest(
          method: 'POST',
          uri: uri,
          headers: headers,
          body: body,
        );
      default:
        throw ArgumentError('Desteklenmeyen method: $method');
    }
  }

  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
    bool retryOnTransportError = true,
  }) async {
    Future<http.Response> execute() {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'DELETE':
          return http.delete(uri, headers: headers);
        case 'PATCH':
          return http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'POST':
          return http.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        default:
          throw ArgumentError('Desteklenmeyen method: $method');
      }
    }

    try {
      return await execute().timeout(_requestTimeout);
    } on TimeoutException {
      if (retryOnTransportError) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          retryOnTransportError: false,
        );
      }
      throw ApiException('Sunucu zaman asimina ugradi. Tekrar deneyin.');
    } on http.ClientException catch (error) {
      if (retryOnTransportError) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          retryOnTransportError: false,
        );
      }
      throw ApiException(_mapClientError(error));
    }
  }

  void _ensureStatus(
    http.Response response,
    int expectedCode, {
    bool allowEmptyBody = false,
  }) {
    if (response.statusCode == expectedCode) {
      return;
    }

    if (allowEmptyBody && response.body.trim().isEmpty) {
      return;
    }

    final payload = _decodePayload(response);
    final errorMsg = payload['error'] as String?;

    if (response.statusCode == 401) {
      final lower = (errorMsg ?? '').toLowerCase();
      if (lower.contains('token') ||
          lower.contains('yetkisiz') ||
          lower.contains('oturum') ||
          lower.contains('unauthorized') ||
          lower.contains('expired')) {
        throw SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.');
      }
      throw ApiException(errorMsg ?? 'Yetkisiz erişim (401)', statusCode: 401);
    }

    throw ApiException(
      errorMsg ?? 'İşlem başarısız (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic> _decodePayload(http.Response response) {
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final raw = jsonDecode(response.body);
      return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } on FormatException {
      final bodyLower = response.body.toLowerCase();
      if (bodyLower.contains('<html') ||
          bodyLower.contains('<!doctype') ||
          bodyLower.contains('router') ||
          bodyLower.contains('modem') ||
          bodyLower.contains('gateway')) {
        throw ApiException(
          'İnternet bağlantısı yok (Modem internete bağlı değil).',
          statusCode: response.statusCode,
        );
      }
      throw ApiException(
        'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
        statusCode: response.statusCode,
      );
    }
  }

  String _mapClientError(http.ClientException error) {
    final message = error.message.toLowerCase();
    if (message.contains('certificate') ||
        message.contains('handshake') ||
        message.contains('tls')) {
      return 'SSL baglantisi kurulurken hata olustu.';
    }
    if (message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('failed host lookup') ||
        message.contains('socket')) {
      return 'Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin.';
    }
    return 'Sunucu baglantisinda istemci hatasi olustu.';
  }

  T _parsePayload<T>(String label, T Function() parser) {
    try {
      return parser();
    } on FormatException {
      throw ApiException('$label verisi islenemedi.');
    } on TypeError {
      throw ApiException('$label verisi beklenen formatta degil.');
    }
  }

  Future<GuestPassRecord> createGuestPass({
    required String token,
    required int doorId,
    required String title,
    required String passType,
    int? durationMinutes,
    int? maxUses,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/guest-passes',
      token: token,
      body: {
        'door_id': doorId,
        'title': title,
        'pass_type': passType,
        'duration_minutes': durationMinutes,
        'max_uses': maxUses,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Gecis kaydi',
      () => GuestPassRecord.fromJson(
        payload['guest_pass'] as Map<String, dynamic>,
      ),
    );
  }

  Future<List<GuestPassRecord>> listGuestPasses({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/guest-passes',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Gecisler',
      () => (payload['passes'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => GuestPassRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Future<void> revokeGuestPass({
    required String token,
    required int passId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/app/guest-passes/$passId',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<Map<String, dynamic>> claimDevice({
    required String token,
    required String deviceInput,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/claim-device',
      token: token,
      body: {
        'deviceInput': deviceInput,
      },
    );

    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMyClaimedDevices({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/my-devices',
      token: token,
    );

    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> setupSite({
    required String token,
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    int doorCount = 1,
    String? deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/setup-site',
      token: token,
      body: {
        'name': name,
        if (city != null && city.isNotEmpty) 'city': city,
        if (district != null && district.isNotEmpty) 'district': district,
        if (address != null && address.isNotEmpty) 'address': address,
        'blocks': blocks,
        'doorCount': doorCount,
        if (deviceUid != null && deviceUid.isNotEmpty) 'deviceUid': deviceUid,
      },
    );

    _ensureStatus(response, 201);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createDoor({
    required String token,
    required int siteCode,
    required String doorName,
    String accessScope = 'SITE_COMMON',
    int? blockId,
    String? deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites/$siteCode/doors',
      token: token,
      body: {
        'door_name': doorName,
        'access_scope': accessScope,
        'block_id': ?blockId,
        if (deviceUid != null && deviceUid.isNotEmpty) 'device_uid': deviceUid,
      },
    );
    _ensureStatus(response, 201);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateDoor({
    required String token,
    required int doorId,
    String? doorName,
    String? accessScope,
    int? blockId,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (doorName != null) body['door_name'] = doorName;
    if (accessScope != null) body['access_scope'] = accessScope;
    if (blockId != null) body['block_id'] = blockId;
    if (isActive != null) body['is_active'] = isActive;

    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/manager/doors/$doorId',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteDoor({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/doors/$doorId',
      token: token,
    );
    _ensureStatus(response, 200);
  }

  Future<Map<String, dynamic>> unassignDoorDevice({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/doors/$doorId/unassign-device',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> replaceDoorDevice({
    required String token,
    required int doorId,
    String? deviceInput,
    int? deviceId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/doors/$doorId/replace-device',
      token: token,
      body: {
        if (deviceInput != null && deviceInput.trim().isNotEmpty)
          'device_input': deviceInput.trim(),
        'device_id': ?deviceId,
      },
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getAssignableDevices({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/assignable-devices',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<SiteJoinTokenRecord> getSiteJoinToken({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/join-token',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SiteJoinTokenRecord.fromJson(data['token'] as Map<String, dynamic>);
  }

  Future<SiteJoinTokenRecord> rotateSiteJoinToken({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites/$siteCode/join-token/rotate',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SiteJoinTokenRecord.fromJson(data['token'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getSiteJoinInfo({
    required String token,
    required String joinToken,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/join-info/$joinToken',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<SiteJoinInfo> fetchSiteJoinInfo({
    required String token,
    required String joinToken,
  }) async {
    final cleanToken = joinToken.replaceFirst('SITE_JOIN:', '').trim();
    final data = await getSiteJoinInfo(token: token, joinToken: cleanToken);
    return SiteJoinInfo.fromJson(data);
  }

  Future<Map<String, dynamic>> submitJoinRequest({
    required String token,
    required String joinToken,
    int? blockId,
    required int apartmentId,
    String? notes,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/join-request',
      token: token,
      body: {
        'token': joinToken,
        // ignore: use_null_aware_elements
        if (blockId != null) 'blockId': blockId,
        'apartmentId': apartmentId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    _ensureStatus(response, 201);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<JoinRequestRecord>> getMyJoinRequests({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/my-join-requests',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['requests'] as List<dynamic>? ?? [];
    return list.map((item) => JoinRequestRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<JoinRequestRecord>> getSiteJoinRequests({
    required String token,
    required int siteCode,
    String? status,
  }) async {
    final query = status != null ? '?status=$status' : '';
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/join-requests$query',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['requests'] as List<dynamic>? ?? [];
    return list.map((item) => JoinRequestRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> approveJoinRequest({
    required String token,
    required int requestId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/join-requests/$requestId/approve',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectJoinRequest({
    required String token,
    required int requestId,
    String? reason,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/join-requests/$requestId/reject',
      token: token,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<MyApartmentRecord>> getMyApartments({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/my-apartments',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['apartments'] as List<dynamic>? ?? [];
    return list.map((item) => MyApartmentRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> removeApartmentMember({
    required String token,
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/remove',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDoorPermissions({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/doors/$doorId/permissions',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setDoorAccessOverride({
    required String token,
    required int doorId,
    required int userCode,
    bool? isAllowed,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'userCode': userCode,
      'isAllowed': isAllowed,
    };
    if (notes != null) {
      body['notes'] = notes;
    }
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/doors/$doorId/permissions',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setBulkDoorAccessOverride({
    required String token,
    required int doorId,
    int? blockId,
    int? apartmentId,
    List<int>? userCodes,
    bool? isAllowed,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'isAllowed': isAllowed,
    };
    if (blockId != null) body['blockId'] = blockId;
    if (apartmentId != null) body['apartmentId'] = apartmentId;
    if (userCodes != null) body['userCodes'] = userCodes;
    if (notes != null) body['notes'] = notes;

    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/doors/$doorId/permissions/bulk',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSiteResidentsTree({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/sites/$siteCode/residents-tree',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> toggleApartmentMemberStatus({
    required String token,
    required int apartmentId,
    required int targetUserCode,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/status',
      token: token,
      body: {'is_active': isActive},
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteApartmentMember({
    required String token,
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> changeApartmentMemberPassword({
    required String token,
    required int apartmentId,
    required int targetUserCode,
    required String newPassword,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/change-password',
      token: token,
      body: {'new_password': newPassword},
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setApartmentPrimaryAdmin({
    required String token,
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/set-primary-admin',
      token: token,
    );
    _ensureStatus(response, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  UserSession _toUserSession({
    required Map<String, dynamic> user,
    required String token,
    required int fallbackId,
    required UserRole fallbackRole,
    required bool fallbackIsActive,
  }) {
    return UserSession(
      id: user['id'] as int? ?? fallbackId,
      fullName: user['full_name'] as String,
      email: user['email'] as String,
      loginName: user['login_name'] as String?,
      role: user['role'] == null
          ? fallbackRole
          : UserRole.fromApi(user['role'] as String),
      isActive: user['is_active'] as bool? ?? fallbackIsActive,
      token: token,
      phoneNumber: user['phone_number'] as String?,
      createdAt: user['created_at'] == null
          ? null
          : DateTime.tryParse(user['created_at'] as String),
    );
  }
}

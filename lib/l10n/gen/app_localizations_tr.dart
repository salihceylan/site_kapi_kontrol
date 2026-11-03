// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get loginIdentifierLabel => 'E-posta veya Kullanıcı Adı';

  @override
  String get loginPasswordLabel => 'Şifre';

  @override
  String get loginForgotPassword => 'Şifremi Unuttum?';

  @override
  String get loginSubmit => 'Giriş Yap';

  @override
  String get menuSwitchToAdmin => 'Yönetici Paneline Geç';

  @override
  String get menuSwitchToResident => 'Sakin Moduna Geç';

  @override
  String get menuHelp => 'Yardım ve Destek';

  @override
  String get menuLogout => 'Çıkış Yap';

  @override
  String get languageTitle => 'Dil';

  @override
  String get languageSystem => 'Cihaz dili';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTooltip => 'Ayarlar';

  @override
  String get refreshTooltip => 'Yenile';

  @override
  String get residentMode => 'Sakin Modu';

  @override
  String get roleSuperUser => 'Süper Kullanıcı';

  @override
  String get roleSiteManager => 'Site Yöneticisi';

  @override
  String get roleApartmentOwner => 'Daire Sakini';

  @override
  String get roleIndividual => 'Bireysel Kullanıcı';

  @override
  String get profileTitle => 'Profilim';

  @override
  String get profileEditTitle => 'Kendi Bilgilerini Düzenle';

  @override
  String get profileFullName => 'Ad Soyad';

  @override
  String get profileFullNameMinLength => 'Ad Soyad en az 3 karakter olmalı.';

  @override
  String get profileEmailReadOnly => 'E-posta (Değiştirilemez)';

  @override
  String get profileEmailHelper =>
      'E-posta adresi güvenlik nedeniyle değiştirilemez';

  @override
  String get profilePhone => 'Telefon (opsiyonel)';

  @override
  String get profilePhoneHelperSiteManager =>
      'Cep telefonu: +90 5XX XXX XX XX. Bu numara sitenizdeki sakinlere, kurul üyelerine ve görevlilere \"Yöneticiyi ara\" kutusunda görünür.';

  @override
  String get profilePhoneHelperNormal => 'Cep telefonu: +90 5XX XXX XX XX';

  @override
  String get profileCurrentPassword => 'Mevcut Şifre';

  @override
  String get profileCurrentPasswordHelper =>
      'Şifrenizi değiştirmek için zorunludur';

  @override
  String get profileCurrentPasswordRequired =>
      'Şifre değiştirmek için mevcut şifrenizi girin.';

  @override
  String get profileNewPassword => 'Yeni Şifre (opsiyonel)';

  @override
  String get profileSaveButton => 'Profili Kaydet';

  @override
  String get profileSaving => 'Kaydediliyor...';

  @override
  String get profileUpdatedSuccess => 'Profil başarıyla güncellendi.';

  @override
  String get accountDetailsTitle => 'Hesap Bilgilerim';

  @override
  String get accountUsername => 'Kullanıcı Adı';

  @override
  String get accountType => 'Hesap Türü';

  @override
  String get residentManagedByManagerNote =>
      'Daire sakini bilgileriniz site yöneticiniz tarafından yönetilir. Değişiklik için yöneticinizle iletişime geçin.';

  @override
  String get changePasswordTitle => 'Şifremi Değiştir';

  @override
  String get currentPasswordOrPin => 'Mevcut Şifre / PIN';

  @override
  String get newPassword => 'Yeni Şifre';

  @override
  String get newPasswordConfirm => 'Yeni Şifre (Tekrar)';

  @override
  String get newPasswordMismatch => 'Yeni şifreler eşleşmiyor.';

  @override
  String get passwordUpdateSuccess => 'Şifreniz başarıyla değiştirildi.';

  @override
  String get passwordUpdateButton => 'Şifremi Güncelle';

  @override
  String get sectionMyRecords => 'Kayıtlarım';

  @override
  String get sectionMyRecordsSubtitle =>
      'Bu bilgiler site yöneticiniz tarafından tutulur. Değişiklik için yöneticinizle iletişime geçin.';

  @override
  String get sectionSearchVisibility => 'Aramalarda Görünme';

  @override
  String get showInSearch => 'Beni aramalarda göster';

  @override
  String get sectionNotificationPrefs => 'Bildirim Tercihleri';

  @override
  String get receiveEmailAnnouncements => 'E-posta ile duyuru al';

  @override
  String get receiveEmailFinance => 'Borç hatırlatma e-postaları';

  @override
  String get sectionAccountPrivacy => 'Gizlilik ve Veri';

  @override
  String get downloadData => 'Verilerimi İndir';

  @override
  String get tabSummary => 'Özet';

  @override
  String get tabAnnouncement => 'Duyuru';

  @override
  String get tabRequest => 'Arıza';

  @override
  String get tabDoor => 'Kapı';

  @override
  String get tabDocuments => 'Dosyalar';

  @override
  String get groupHome => 'Ana sayfa';

  @override
  String get groupApartments => 'Daireler';

  @override
  String get groupDues => 'Borçlar';

  @override
  String get groupCollections => 'Tahsilat';

  @override
  String get groupExpenses => 'Giderler';

  @override
  String get groupCommunication => 'İletişim';

  @override
  String get groupReports => 'Raporlar';

  @override
  String get groupSiteServices => 'Site hizmetleri';

  @override
  String get groupSettings => 'Ayarlar';

  @override
  String get menuFeedback => 'Geri bildirim';

  @override
  String get menuAllActions => 'Tüm işlemler';

  @override
  String get menuDashboard => 'Panel';

  @override
  String get menuMyProfile => 'Profilim';

  @override
  String get menuHandsFree => 'Eller Serbest & Kestirmeler';

  @override
  String get menuSubscriptionRequests => 'Yeni Abonelik Talepleri';

  @override
  String get menuSiteApprovalRequests => 'Site Onay Talepleri';

  @override
  String get menuUserManagement => 'Kullanıcı Yönetimi';

  @override
  String get menuSuperUserManagement => 'Süper Kullanıcı Yönetimi';

  @override
  String get menuSiteManagersManagement => 'Site Yöneticileri Yönetimi';

  @override
  String get menuApartmentResidents => 'Daire Sakinleri';

  @override
  String get menuSiteManagement => 'Site Yönetimi';

  @override
  String get menuJoinApartment => 'Daireye Katıl';

  @override
  String get menuAddDevice => 'Cihaz Kaydet';

  @override
  String get menuAddDeviceIndividual => 'Cihaz Ekle';

  @override
  String get menuAddDeviceCompany => 'Şirket Cihazı Kaydet';

  @override
  String get menuRegisteredDevices => 'Kayıtlı Cihazlar';

  @override
  String get menuCompanyInventory => 'Şirket Cihaz Envanteri';

  @override
  String get menuBluetoothWifiSetup => 'Bluetooth ile Wi-Fi Kur';

  @override
  String get menuModules => 'Modüller';

  @override
  String get menuAuditLog => 'Denetim Kaydı';

  @override
  String get menuOperationLogs => 'İşlem Kayıtları';

  @override
  String get menuModuleRequests => 'Modül Talepleri';

  @override
  String get menuPeople => 'Kişiler';

  @override
  String get menuAnnouncements => 'Duyurular';

  @override
  String get menuSiteApplications => 'Site Başvuruları';

  @override
  String get menuFinance => 'Finans';

  @override
  String get menuMyDues => 'Borcum';

  @override
  String get menuDocuments => 'Dosya Deposu';

  @override
  String get menuRequests => 'Talepler';

  @override
  String get menuMyRequests => 'Taleplerim';

  @override
  String get menuReservations => 'Rezervasyonlar';

  @override
  String get menuReservation => 'Rezervasyon';

  @override
  String get menuPlatformSettings => 'Platform Ayarları';

  @override
  String get menuClientErrors => 'İstemci Hataları';

  @override
  String get menuSurveys => 'Anket ve Oylama';

  @override
  String get menuSurveyList => 'Anketler';

  @override
  String get menuVisitorDelivery => 'Ziyaretçi ve Kargo';

  @override
  String get menuMyVisitors => 'Ziyaretçilerim';

  @override
  String get menuContracts => 'Sözleşmeler';

  @override
  String get menuUtilityMeters => 'Sayaçlar';

  @override
  String get menuDecisionBook => 'Karar Defteri';

  @override
  String get menuDecisions => 'Kararlar';

  @override
  String get menuDirectory => 'Rehber';

  @override
  String get menuOperatingProject => 'İşletme Projesi';

  @override
  String get menuNeighborBoard => 'Komşu Panosu';

  @override
  String get menuAnnualReport => 'Faaliyet Raporu';

  @override
  String get menuPlateRecognition => 'Plaka Tanıma & Kameralar';

  @override
  String get menuEquipmentMaintenance => 'Ekipman ve Bakım';

  @override
  String get menuDoors => 'Kapılar';

  @override
  String get menuMyApartment => 'Dairem';

  @override
  String get menuEmergency => 'Acil durum';

  @override
  String get menuCreateNewSite => 'Yeni Site Oluştur';
}

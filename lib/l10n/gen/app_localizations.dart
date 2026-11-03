import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @loginIdentifierLabel.
  ///
  /// In tr, this message translates to:
  /// **'E-posta veya Kullanıcı Adı'**
  String get loginIdentifierLabel;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get loginPasswordLabel;

  /// No description provided for @loginForgotPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi Unuttum?'**
  String get loginForgotPassword;

  /// No description provided for @loginSubmit.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get loginSubmit;

  /// No description provided for @menuSwitchToAdmin.
  ///
  /// In tr, this message translates to:
  /// **'Yönetici Paneline Geç'**
  String get menuSwitchToAdmin;

  /// No description provided for @menuSwitchToResident.
  ///
  /// In tr, this message translates to:
  /// **'Sakin Moduna Geç'**
  String get menuSwitchToResident;

  /// No description provided for @menuHelp.
  ///
  /// In tr, this message translates to:
  /// **'Yardım ve Destek'**
  String get menuHelp;

  /// No description provided for @menuLogout.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış Yap'**
  String get menuLogout;

  /// No description provided for @languageTitle.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get languageTitle;

  /// No description provided for @languageSystem.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz dili'**
  String get languageSystem;

  /// No description provided for @languageTurkish.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe'**
  String get languageTurkish;

  /// No description provided for @languageEnglish.
  ///
  /// In tr, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @settingsTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settingsTooltip;

  /// No description provided for @refreshTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Yenile'**
  String get refreshTooltip;

  /// No description provided for @residentMode.
  ///
  /// In tr, this message translates to:
  /// **'Sakin Modu'**
  String get residentMode;

  /// No description provided for @roleSuperUser.
  ///
  /// In tr, this message translates to:
  /// **'Süper Kullanıcı'**
  String get roleSuperUser;

  /// No description provided for @roleSiteManager.
  ///
  /// In tr, this message translates to:
  /// **'Site Yöneticisi'**
  String get roleSiteManager;

  /// No description provided for @roleApartmentOwner.
  ///
  /// In tr, this message translates to:
  /// **'Daire Sakini'**
  String get roleApartmentOwner;

  /// No description provided for @roleIndividual.
  ///
  /// In tr, this message translates to:
  /// **'Bireysel Kullanıcı'**
  String get roleIndividual;

  /// No description provided for @profileTitle.
  ///
  /// In tr, this message translates to:
  /// **'Profilim'**
  String get profileTitle;

  /// No description provided for @profileEditTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kendi Bilgilerini Düzenle'**
  String get profileEditTitle;

  /// No description provided for @profileFullName.
  ///
  /// In tr, this message translates to:
  /// **'Ad Soyad'**
  String get profileFullName;

  /// No description provided for @profileFullNameMinLength.
  ///
  /// In tr, this message translates to:
  /// **'Ad Soyad en az 3 karakter olmalı.'**
  String get profileFullNameMinLength;

  /// No description provided for @profileEmailReadOnly.
  ///
  /// In tr, this message translates to:
  /// **'E-posta (Değiştirilemez)'**
  String get profileEmailReadOnly;

  /// No description provided for @profileEmailHelper.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresi güvenlik nedeniyle değiştirilemez'**
  String get profileEmailHelper;

  /// No description provided for @profilePhone.
  ///
  /// In tr, this message translates to:
  /// **'Telefon (opsiyonel)'**
  String get profilePhone;

  /// No description provided for @profilePhoneHelperSiteManager.
  ///
  /// In tr, this message translates to:
  /// **'Cep telefonu: +90 5XX XXX XX XX. Bu numara sitenizdeki sakinlere, kurul üyelerine ve görevlilere \"Yöneticiyi ara\" kutusunda görünür.'**
  String get profilePhoneHelperSiteManager;

  /// No description provided for @profilePhoneHelperNormal.
  ///
  /// In tr, this message translates to:
  /// **'Cep telefonu: +90 5XX XXX XX XX'**
  String get profilePhoneHelperNormal;

  /// No description provided for @profileCurrentPassword.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Şifre'**
  String get profileCurrentPassword;

  /// No description provided for @profileCurrentPasswordHelper.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenizi değiştirmek için zorunludur'**
  String get profileCurrentPasswordHelper;

  /// No description provided for @profileCurrentPasswordRequired.
  ///
  /// In tr, this message translates to:
  /// **'Şifre değiştirmek için mevcut şifrenizi girin.'**
  String get profileCurrentPasswordRequired;

  /// No description provided for @profileNewPassword.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre (opsiyonel)'**
  String get profileNewPassword;

  /// No description provided for @profileSaveButton.
  ///
  /// In tr, this message translates to:
  /// **'Profili Kaydet'**
  String get profileSaveButton;

  /// No description provided for @profileSaving.
  ///
  /// In tr, this message translates to:
  /// **'Kaydediliyor...'**
  String get profileSaving;

  /// No description provided for @profileUpdatedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Profil başarıyla güncellendi.'**
  String get profileUpdatedSuccess;

  /// No description provided for @accountDetailsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Bilgilerim'**
  String get accountDetailsTitle;

  /// No description provided for @accountUsername.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Adı'**
  String get accountUsername;

  /// No description provided for @accountType.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Türü'**
  String get accountType;

  /// No description provided for @residentManagedByManagerNote.
  ///
  /// In tr, this message translates to:
  /// **'Daire sakini bilgileriniz site yöneticiniz tarafından yönetilir. Değişiklik için yöneticinizle iletişime geçin.'**
  String get residentManagedByManagerNote;

  /// No description provided for @changePasswordTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi Değiştir'**
  String get changePasswordTitle;

  /// No description provided for @currentPasswordOrPin.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Şifre / PIN'**
  String get currentPasswordOrPin;

  /// No description provided for @newPassword.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre'**
  String get newPassword;

  /// No description provided for @newPasswordConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre (Tekrar)'**
  String get newPasswordConfirm;

  /// No description provided for @newPasswordMismatch.
  ///
  /// In tr, this message translates to:
  /// **'Yeni şifreler eşleşmiyor.'**
  String get newPasswordMismatch;

  /// No description provided for @passwordUpdateSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Şifreniz başarıyla değiştirildi.'**
  String get passwordUpdateSuccess;

  /// No description provided for @passwordUpdateButton.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi Güncelle'**
  String get passwordUpdateButton;

  /// No description provided for @sectionMyRecords.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlarım'**
  String get sectionMyRecords;

  /// No description provided for @sectionMyRecordsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu bilgiler site yöneticiniz tarafından tutulur. Değişiklik için yöneticinizle iletişime geçin.'**
  String get sectionMyRecordsSubtitle;

  /// No description provided for @sectionSearchVisibility.
  ///
  /// In tr, this message translates to:
  /// **'Aramalarda Görünme'**
  String get sectionSearchVisibility;

  /// No description provided for @showInSearch.
  ///
  /// In tr, this message translates to:
  /// **'Beni aramalarda göster'**
  String get showInSearch;

  /// No description provided for @sectionNotificationPrefs.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Tercihleri'**
  String get sectionNotificationPrefs;

  /// No description provided for @receiveEmailAnnouncements.
  ///
  /// In tr, this message translates to:
  /// **'E-posta ile duyuru al'**
  String get receiveEmailAnnouncements;

  /// No description provided for @receiveEmailFinance.
  ///
  /// In tr, this message translates to:
  /// **'Borç hatırlatma e-postaları'**
  String get receiveEmailFinance;

  /// No description provided for @sectionAccountPrivacy.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik ve Veri'**
  String get sectionAccountPrivacy;

  /// No description provided for @downloadData.
  ///
  /// In tr, this message translates to:
  /// **'Verilerimi İndir'**
  String get downloadData;

  /// No description provided for @tabSummary.
  ///
  /// In tr, this message translates to:
  /// **'Özet'**
  String get tabSummary;

  /// No description provided for @tabAnnouncement.
  ///
  /// In tr, this message translates to:
  /// **'Duyuru'**
  String get tabAnnouncement;

  /// No description provided for @tabRequest.
  ///
  /// In tr, this message translates to:
  /// **'Arıza'**
  String get tabRequest;

  /// No description provided for @tabDoor.
  ///
  /// In tr, this message translates to:
  /// **'Kapı'**
  String get tabDoor;

  /// No description provided for @tabDocuments.
  ///
  /// In tr, this message translates to:
  /// **'Dosyalar'**
  String get tabDocuments;

  /// No description provided for @groupHome.
  ///
  /// In tr, this message translates to:
  /// **'Ana sayfa'**
  String get groupHome;

  /// No description provided for @groupApartments.
  ///
  /// In tr, this message translates to:
  /// **'Daireler'**
  String get groupApartments;

  /// No description provided for @groupDues.
  ///
  /// In tr, this message translates to:
  /// **'Borçlar'**
  String get groupDues;

  /// No description provided for @groupCollections.
  ///
  /// In tr, this message translates to:
  /// **'Tahsilat'**
  String get groupCollections;

  /// No description provided for @groupExpenses.
  ///
  /// In tr, this message translates to:
  /// **'Giderler'**
  String get groupExpenses;

  /// No description provided for @groupCommunication.
  ///
  /// In tr, this message translates to:
  /// **'İletişim'**
  String get groupCommunication;

  /// No description provided for @groupReports.
  ///
  /// In tr, this message translates to:
  /// **'Raporlar'**
  String get groupReports;

  /// No description provided for @groupSiteServices.
  ///
  /// In tr, this message translates to:
  /// **'Site hizmetleri'**
  String get groupSiteServices;

  /// No description provided for @groupSettings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get groupSettings;

  /// No description provided for @menuFeedback.
  ///
  /// In tr, this message translates to:
  /// **'Geri bildirim'**
  String get menuFeedback;

  /// No description provided for @menuAllActions.
  ///
  /// In tr, this message translates to:
  /// **'Tüm işlemler'**
  String get menuAllActions;

  /// No description provided for @menuDashboard.
  ///
  /// In tr, this message translates to:
  /// **'Panel'**
  String get menuDashboard;

  /// No description provided for @menuMyProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilim'**
  String get menuMyProfile;

  /// No description provided for @menuHandsFree.
  ///
  /// In tr, this message translates to:
  /// **'Eller Serbest & Kestirmeler'**
  String get menuHandsFree;

  /// No description provided for @menuSubscriptionRequests.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Abonelik Talepleri'**
  String get menuSubscriptionRequests;

  /// No description provided for @menuSiteApprovalRequests.
  ///
  /// In tr, this message translates to:
  /// **'Site Onay Talepleri'**
  String get menuSiteApprovalRequests;

  /// No description provided for @menuUserManagement.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Yönetimi'**
  String get menuUserManagement;

  /// No description provided for @menuSuperUserManagement.
  ///
  /// In tr, this message translates to:
  /// **'Süper Kullanıcı Yönetimi'**
  String get menuSuperUserManagement;

  /// No description provided for @menuSiteManagersManagement.
  ///
  /// In tr, this message translates to:
  /// **'Site Yöneticileri Yönetimi'**
  String get menuSiteManagersManagement;

  /// No description provided for @menuApartmentResidents.
  ///
  /// In tr, this message translates to:
  /// **'Daire Sakinleri'**
  String get menuApartmentResidents;

  /// No description provided for @menuSiteManagement.
  ///
  /// In tr, this message translates to:
  /// **'Site Yönetimi'**
  String get menuSiteManagement;

  /// No description provided for @menuJoinApartment.
  ///
  /// In tr, this message translates to:
  /// **'Daireye Katıl'**
  String get menuJoinApartment;

  /// No description provided for @menuAddDevice.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz Kaydet'**
  String get menuAddDevice;

  /// No description provided for @menuAddDeviceIndividual.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz Ekle'**
  String get menuAddDeviceIndividual;

  /// No description provided for @menuAddDeviceCompany.
  ///
  /// In tr, this message translates to:
  /// **'Şirket Cihazı Kaydet'**
  String get menuAddDeviceCompany;

  /// No description provided for @menuRegisteredDevices.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı Cihazlar'**
  String get menuRegisteredDevices;

  /// No description provided for @menuCompanyInventory.
  ///
  /// In tr, this message translates to:
  /// **'Şirket Cihaz Envanteri'**
  String get menuCompanyInventory;

  /// No description provided for @menuBluetoothWifiSetup.
  ///
  /// In tr, this message translates to:
  /// **'Bluetooth ile Wi-Fi Kur'**
  String get menuBluetoothWifiSetup;

  /// No description provided for @menuModules.
  ///
  /// In tr, this message translates to:
  /// **'Modüller'**
  String get menuModules;

  /// No description provided for @menuAuditLog.
  ///
  /// In tr, this message translates to:
  /// **'Denetim Kaydı'**
  String get menuAuditLog;

  /// No description provided for @menuOperationLogs.
  ///
  /// In tr, this message translates to:
  /// **'İşlem Kayıtları'**
  String get menuOperationLogs;

  /// No description provided for @menuModuleRequests.
  ///
  /// In tr, this message translates to:
  /// **'Modül Talepleri'**
  String get menuModuleRequests;

  /// No description provided for @menuPeople.
  ///
  /// In tr, this message translates to:
  /// **'Kişiler'**
  String get menuPeople;

  /// No description provided for @menuAnnouncements.
  ///
  /// In tr, this message translates to:
  /// **'Duyurular'**
  String get menuAnnouncements;

  /// No description provided for @menuSiteApplications.
  ///
  /// In tr, this message translates to:
  /// **'Site Başvuruları'**
  String get menuSiteApplications;

  /// No description provided for @menuFinance.
  ///
  /// In tr, this message translates to:
  /// **'Finans'**
  String get menuFinance;

  /// No description provided for @menuMyDues.
  ///
  /// In tr, this message translates to:
  /// **'Borcum'**
  String get menuMyDues;

  /// No description provided for @menuDocuments.
  ///
  /// In tr, this message translates to:
  /// **'Dosya Deposu'**
  String get menuDocuments;

  /// No description provided for @menuRequests.
  ///
  /// In tr, this message translates to:
  /// **'Talepler'**
  String get menuRequests;

  /// No description provided for @menuMyRequests.
  ///
  /// In tr, this message translates to:
  /// **'Taleplerim'**
  String get menuMyRequests;

  /// No description provided for @menuReservations.
  ///
  /// In tr, this message translates to:
  /// **'Rezervasyonlar'**
  String get menuReservations;

  /// No description provided for @menuReservation.
  ///
  /// In tr, this message translates to:
  /// **'Rezervasyon'**
  String get menuReservation;

  /// No description provided for @menuPlatformSettings.
  ///
  /// In tr, this message translates to:
  /// **'Platform Ayarları'**
  String get menuPlatformSettings;

  /// No description provided for @menuClientErrors.
  ///
  /// In tr, this message translates to:
  /// **'İstemci Hataları'**
  String get menuClientErrors;

  /// No description provided for @menuSurveys.
  ///
  /// In tr, this message translates to:
  /// **'Anket ve Oylama'**
  String get menuSurveys;

  /// No description provided for @menuSurveyList.
  ///
  /// In tr, this message translates to:
  /// **'Anketler'**
  String get menuSurveyList;

  /// No description provided for @menuVisitorDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Ziyaretçi ve Kargo'**
  String get menuVisitorDelivery;

  /// No description provided for @menuMyVisitors.
  ///
  /// In tr, this message translates to:
  /// **'Ziyaretçilerim'**
  String get menuMyVisitors;

  /// No description provided for @menuContracts.
  ///
  /// In tr, this message translates to:
  /// **'Sözleşmeler'**
  String get menuContracts;

  /// No description provided for @menuUtilityMeters.
  ///
  /// In tr, this message translates to:
  /// **'Sayaçlar'**
  String get menuUtilityMeters;

  /// No description provided for @menuDecisionBook.
  ///
  /// In tr, this message translates to:
  /// **'Karar Defteri'**
  String get menuDecisionBook;

  /// No description provided for @menuDecisions.
  ///
  /// In tr, this message translates to:
  /// **'Kararlar'**
  String get menuDecisions;

  /// No description provided for @menuDirectory.
  ///
  /// In tr, this message translates to:
  /// **'Rehber'**
  String get menuDirectory;

  /// No description provided for @menuOperatingProject.
  ///
  /// In tr, this message translates to:
  /// **'İşletme Projesi'**
  String get menuOperatingProject;

  /// No description provided for @menuNeighborBoard.
  ///
  /// In tr, this message translates to:
  /// **'Komşu Panosu'**
  String get menuNeighborBoard;

  /// No description provided for @menuAnnualReport.
  ///
  /// In tr, this message translates to:
  /// **'Faaliyet Raporu'**
  String get menuAnnualReport;

  /// No description provided for @menuPlateRecognition.
  ///
  /// In tr, this message translates to:
  /// **'Plaka Tanıma & Kameralar'**
  String get menuPlateRecognition;

  /// No description provided for @menuEquipmentMaintenance.
  ///
  /// In tr, this message translates to:
  /// **'Ekipman ve Bakım'**
  String get menuEquipmentMaintenance;

  /// No description provided for @menuDoors.
  ///
  /// In tr, this message translates to:
  /// **'Kapılar'**
  String get menuDoors;

  /// No description provided for @menuMyApartment.
  ///
  /// In tr, this message translates to:
  /// **'Dairem'**
  String get menuMyApartment;

  /// No description provided for @menuEmergency.
  ///
  /// In tr, this message translates to:
  /// **'Acil durum'**
  String get menuEmergency;

  /// No description provided for @menuCreateNewSite.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Site Oluştur'**
  String get menuCreateNewSite;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

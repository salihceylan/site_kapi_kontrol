// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginIdentifierLabel => 'Email or username';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String get menuSwitchToAdmin => 'Switch to admin panel';

  @override
  String get menuSwitchToResident => 'Switch to resident mode';

  @override
  String get menuHelp => 'Help and support';

  @override
  String get menuLogout => 'Sign out';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'Device language';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get residentMode => 'Resident Mode';

  @override
  String get roleSuperUser => 'Super User';

  @override
  String get roleSiteManager => 'Site Manager';

  @override
  String get roleApartmentOwner => 'Apartment Resident';

  @override
  String get roleIndividual => 'Individual User';

  @override
  String get profileTitle => 'My Profile';

  @override
  String get profileEditTitle => 'Edit Personal Information';

  @override
  String get profileFullName => 'Full Name';

  @override
  String get profileFullNameMinLength =>
      'Full name must be at least 3 characters.';

  @override
  String get profileEmailReadOnly => 'Email (Cannot be changed)';

  @override
  String get profileEmailHelper =>
      'Email address cannot be changed for security reasons';

  @override
  String get profilePhone => 'Phone (optional)';

  @override
  String get profilePhoneHelperSiteManager =>
      'Mobile phone: +90 5XX XXX XX XX. This number is displayed to residents, board members, and staff in the \"Call Manager\" box.';

  @override
  String get profilePhoneHelperNormal => 'Mobile phone: +90 5XX XXX XX XX';

  @override
  String get profileCurrentPassword => 'Current Password';

  @override
  String get profileCurrentPasswordHelper => 'Required to change password';

  @override
  String get profileCurrentPasswordRequired =>
      'Please enter your current password to change password.';

  @override
  String get profileNewPassword => 'New Password (optional)';

  @override
  String get profileSaveButton => 'Save Profile';

  @override
  String get profileSaving => 'Saving...';

  @override
  String get profileUpdatedSuccess => 'Profile updated successfully.';

  @override
  String get accountDetailsTitle => 'My Account Details';

  @override
  String get accountUsername => 'Username';

  @override
  String get accountType => 'Account Type';

  @override
  String get residentManagedByManagerNote =>
      'Your resident information is managed by your site manager. Please contact your manager for changes.';

  @override
  String get changePasswordTitle => 'Change My Password';

  @override
  String get currentPasswordOrPin => 'Current Password / PIN';

  @override
  String get newPassword => 'New Password';

  @override
  String get newPasswordConfirm => 'Confirm New Password';

  @override
  String get newPasswordMismatch => 'New passwords do not match.';

  @override
  String get passwordUpdateSuccess => 'Password updated successfully.';

  @override
  String get passwordUpdateButton => 'Update Password';

  @override
  String get sectionMyRecords => 'My Records';

  @override
  String get sectionMyRecordsSubtitle =>
      'This information is maintained by your site manager. Please contact management for changes.';

  @override
  String get sectionSearchVisibility => 'Search Visibility';

  @override
  String get showInSearch => 'Show me in searches';

  @override
  String get sectionNotificationPrefs => 'Notification Preferences';

  @override
  String get receiveEmailAnnouncements => 'Receive announcements via email';

  @override
  String get receiveEmailFinance => 'Dues reminder emails';

  @override
  String get sectionAccountPrivacy => 'Privacy & Data';

  @override
  String get downloadData => 'Download My Data';

  @override
  String get tabSummary => 'Summary';

  @override
  String get tabAnnouncement => 'Announcement';

  @override
  String get tabRequest => 'Request';

  @override
  String get tabDoor => 'Door';

  @override
  String get tabDocuments => 'Files';

  @override
  String get groupHome => 'Home';

  @override
  String get groupApartments => 'Apartments';

  @override
  String get groupDues => 'Dues & Debts';

  @override
  String get groupCollections => 'Collections';

  @override
  String get groupExpenses => 'Expenses';

  @override
  String get groupCommunication => 'Communication';

  @override
  String get groupReports => 'Reports';

  @override
  String get groupSiteServices => 'Site Services';

  @override
  String get groupSettings => 'Settings';

  @override
  String get menuFeedback => 'Feedback';

  @override
  String get menuAllActions => 'All actions';

  @override
  String get menuDashboard => 'Dashboard';

  @override
  String get menuMyProfile => 'My Profile';

  @override
  String get menuHandsFree => 'Hands-Free & Shortcuts';

  @override
  String get menuSubscriptionRequests => 'Subscription Requests';

  @override
  String get menuSiteApprovalRequests => 'Site Approval Requests';

  @override
  String get menuUserManagement => 'User Management';

  @override
  String get menuSuperUserManagement => 'Super User Management';

  @override
  String get menuSiteManagersManagement => 'Site Managers Management';

  @override
  String get menuApartmentResidents => 'Apartment Residents';

  @override
  String get menuSiteManagement => 'Site Management';

  @override
  String get menuJoinApartment => 'Join Apartment';

  @override
  String get menuAddDevice => 'Register Device';

  @override
  String get menuAddDeviceIndividual => 'Add Device';

  @override
  String get menuAddDeviceCompany => 'Register Company Device';

  @override
  String get menuRegisteredDevices => 'Registered Devices';

  @override
  String get menuCompanyInventory => 'Company Device Inventory';

  @override
  String get menuBluetoothWifiSetup => 'Setup Wi-Fi via Bluetooth';

  @override
  String get menuModules => 'Modules';

  @override
  String get menuAuditLog => 'Audit Log';

  @override
  String get menuOperationLogs => 'Operation Logs';

  @override
  String get menuModuleRequests => 'Module Requests';

  @override
  String get menuPeople => 'People';

  @override
  String get menuAnnouncements => 'Announcements';

  @override
  String get menuSiteApplications => 'Site Applications';

  @override
  String get menuFinance => 'Finance';

  @override
  String get menuMyDues => 'My Dues';

  @override
  String get menuDocuments => 'Document Vault';

  @override
  String get menuRequests => 'Requests';

  @override
  String get menuMyRequests => 'My Requests';

  @override
  String get menuReservations => 'Reservations';

  @override
  String get menuReservation => 'Reservation';

  @override
  String get menuPlatformSettings => 'Platform Settings';

  @override
  String get menuClientErrors => 'Client Errors';

  @override
  String get menuSurveys => 'Surveys & Polls';

  @override
  String get menuSurveyList => 'Surveys';

  @override
  String get menuVisitorDelivery => 'Visitors & Delivery';

  @override
  String get menuMyVisitors => 'My Visitors';

  @override
  String get menuContracts => 'Contracts';

  @override
  String get menuUtilityMeters => 'Utility Meters';

  @override
  String get menuDecisionBook => 'Decision Book';

  @override
  String get menuDecisions => 'Decisions';

  @override
  String get menuDirectory => 'Directory';

  @override
  String get menuOperatingProject => 'Operating Budget Project';

  @override
  String get menuNeighborBoard => 'Community Board';

  @override
  String get menuAnnualReport => 'Annual Activity Report';

  @override
  String get menuPlateRecognition => 'Plate Recognition & Cameras';

  @override
  String get menuEquipmentMaintenance => 'Equipment & Maintenance';

  @override
  String get menuDoors => 'Doors';

  @override
  String get menuMyApartment => 'My Apartment';

  @override
  String get menuEmergency => 'Emergency';

  @override
  String get menuCreateNewSite => 'Create New Site';
}

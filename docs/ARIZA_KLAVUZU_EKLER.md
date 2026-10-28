# Arıza Klavuzu — Ekler (otomatik)

> Bu ekler koddan otomatik üretilir (elle yazılmaz). Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).

## Ek A — Sunucu uç noktaları

Kaynak: `server/src/routes/*.js` ve `server/src/server.js`. Sütunlar: yöntem, yol, o satırdaki ara katmanlar (yetki/hız sınırı).

| Yöntem | Yol | Ara katmanlar | Dosya:satır |
| --- | --- | --- | --- |
| GET | `/admin/users` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:219](../server/src/routes/admin_routes.js#L219) |
| POST | `/admin/users` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:328](../server/src/routes/admin_routes.js#L328) |
| PATCH | `/admin/users/:id` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:381](../server/src/routes/admin_routes.js#L381) |
| DELETE | `/admin/users/:id` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:544](../server/src/routes/admin_routes.js#L544) |
| GET | `/admin/sites` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:823](../server/src/routes/admin_routes.js#L823) |
| POST | `/admin/sites` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:855](../server/src/routes/admin_routes.js#L855) |
| PATCH | `/admin/sites/:id/approval` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:946](../server/src/routes/admin_routes.js#L946) |
| PATCH | `/admin/sites/:id` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1020](../server/src/routes/admin_routes.js#L1020) |
| PATCH | `/admin/sites/:id/features` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1175](../server/src/routes/admin_routes.js#L1175) |
| GET | `/admin/sites/:id/structure` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1226](../server/src/routes/admin_routes.js#L1226) |
| DELETE | `/admin/sites/:id` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1244](../server/src/routes/admin_routes.js#L1244) |
| POST | `/admin/sites/:id/approve-deletion` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1259](../server/src/routes/admin_routes.js#L1259) |
| POST | `/admin/sites/:id/reject-deletion` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1274](../server/src/routes/admin_routes.js#L1274) |
| POST | `/admin/sites/:id/request-email-deletion-code` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1289](../server/src/routes/admin_routes.js#L1289) |
| POST | `/admin/sites/:id/confirm-email-deletion` | authRequired, requireSuperUser, adminSensitiveLimiter | [server/src/routes/admin_routes.js:1304](../server/src/routes/admin_routes.js#L1304) |
| PATCH | `/admin/apartments/:id/resident` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1324](../server/src/routes/admin_routes.js#L1324) |
| POST | `/admin/apartments/:id/reset-pin` | authRequired, requireSuperUser, apartmentPinResetLimiter | [server/src/routes/admin_routes.js:1391](../server/src/routes/admin_routes.js#L1391) |
| DELETE | `/admin/apartments/:id/resident` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1419](../server/src/routes/admin_routes.js#L1419) |
| POST | `/admin/apartments/:id/send-credentials` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1446](../server/src/routes/admin_routes.js#L1446) |
| PATCH | `/admin/doors/:id/device` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1474](../server/src/routes/admin_routes.js#L1474) |
| GET | `/admin/devices` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1508](../server/src/routes/admin_routes.js#L1508) |
| GET | `/admin/devices/:deviceUid/connectivity-logs` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1526](../server/src/routes/admin_routes.js#L1526) |
| POST | `/admin/devices/mqtt-credentials` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1552](../server/src/routes/admin_routes.js#L1552) |
| POST | `/admin/devices/ota-check` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1581](../server/src/routes/admin_routes.js#L1581) |
| PATCH | `/admin/devices/:id` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1623](../server/src/routes/admin_routes.js#L1623) |
| DELETE | `/admin/devices/:id` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1696](../server/src/routes/admin_routes.js#L1696) |
| POST | `/admin/devices` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1721](../server/src/routes/admin_routes.js#L1721) |
| PATCH | `/admin/devices/:id/defect` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1782](../server/src/routes/admin_routes.js#L1782) |
| POST | `/admin/devices/:id/release-ownership` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1815](../server/src/routes/admin_routes.js#L1815) |
| GET | `/admin/maintenance/health` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1837](../server/src/routes/admin_routes.js#L1837) |
| POST | `/admin/maintenance/cleanup` | authRequired, requireSuperUser | [server/src/routes/admin_routes.js:1849](../server/src/routes/admin_routes.js#L1849) |
| GET | `/app/my-doors` | authRequired | [server/src/routes/app_doors_routes.js:109](../server/src/routes/app_doors_routes.js#L109) |
| GET | `/app/doors/:id/status` | authRequired | [server/src/routes/app_doors_routes.js:121](../server/src/routes/app_doors_routes.js#L121) |
| POST | `/app/doors/:id/open` | authRequired, doorCommandRateLimiter | [server/src/routes/app_doors_routes.js:161](../server/src/routes/app_doors_routes.js#L161) |
| POST | `/app/doors/scan-qr-open` | authRequired, doorCommandRateLimiter | [server/src/routes/app_doors_routes.js:262](../server/src/routes/app_doors_routes.js#L262) |
| POST | `/app/doors/:id/local-open-notify` | authRequired, doorCommandRateLimiter | [server/src/routes/app_doors_routes.js:419](../server/src/routes/app_doors_routes.js#L419) |
| POST | `/app/doors/:id/qr-token` | authRequired, qrTokenRateLimiter | [server/src/routes/app_doors_routes.js:475](../server/src/routes/app_doors_routes.js#L475) |
| POST | `/app/doors/:id/revoke-my-qr` | authRequired | [server/src/routes/app_doors_routes.js:510](../server/src/routes/app_doors_routes.js#L510) |
| GET | `/app/doors/qr-status` | authRequired | [server/src/routes/app_doors_routes.js:532](../server/src/routes/app_doors_routes.js#L532) |
| POST | `/auth/register-individual` | registerLimiter | [server/src/routes/auth_routes.js:55](../server/src/routes/auth_routes.js#L55) |
| POST | `/auth/verify-code` | verifyCodeLimiter | [server/src/routes/auth_routes.js:92](../server/src/routes/auth_routes.js#L92) |
| POST | `/auth/resend-code` | resendCodeLimiter | [server/src/routes/auth_routes.js:119](../server/src/routes/auth_routes.js#L119) |
| POST | `/auth/forgot-password` | forgotPasswordLimiter | [server/src/routes/auth_routes.js:387](../server/src/routes/auth_routes.js#L387) |
| GET | `/auth/reset-password` | resetPasswordLimiter | [server/src/routes/auth_routes.js:421](../server/src/routes/auth_routes.js#L421) |
| POST | `/auth/reset-password` | resetPasswordLimiter | [server/src/routes/auth_routes.js:479](../server/src/routes/auth_routes.js#L479) |
| POST | `/auth/register` |  | [server/src/routes/auth_routes.js:574](../server/src/routes/auth_routes.js#L574) |
| POST | `/auth/site-manager/register` |  | [server/src/routes/auth_routes.js:617](../server/src/routes/auth_routes.js#L617) |
| POST | `/auth/site-manager/verify-email` |  | [server/src/routes/auth_routes.js:719](../server/src/routes/auth_routes.js#L719) |
| POST | `/auth/site-manager/resend-code` |  | [server/src/routes/auth_routes.js:726](../server/src/routes/auth_routes.js#L726) |
| POST | `/auth/login` | loginRateLimiter | [server/src/routes/auth_routes.js:765](../server/src/routes/auth_routes.js#L765) |
| GET | `/me` | authRequired | [server/src/routes/auth_routes.js:907](../server/src/routes/auth_routes.js#L907) |
| PATCH | `/me` | authRequired, profileUpdateLimiter | [server/src/routes/auth_routes.js:914](../server/src/routes/auth_routes.js#L914) |
| GET | `/qrcodes/:file` | (req, res) => { | [server/src/routes/company_routes.js:277](../server/src/routes/company_routes.js#L277) |
| GET | `/api/company/labeled-devices` |  | [server/src/routes/company_routes.js:298](../server/src/routes/company_routes.js#L298) |
| POST | `/api/company/labeled-devices` |  | [server/src/routes/company_routes.js:313](../server/src/routes/company_routes.js#L313) |
| DELETE | `/api/company/labeled-devices/:deviceUid` |  | [server/src/routes/company_routes.js:407](../server/src/routes/company_routes.js#L407) |
| GET | `/api/company/devices/:deviceUid/runtime` |  | [server/src/routes/company_routes.js:478](../server/src/routes/company_routes.js#L478) |
| GET | `/admin/door-logs` | authRequired, requireSuperUser | [server/src/routes/door_log_routes.js:27](../server/src/routes/door_log_routes.js#L27) |
| GET | `/manager/door-logs` | authRequired, requireSiteManager | [server/src/routes/door_log_routes.js:106](../server/src/routes/door_log_routes.js#L106) |
| POST | `/device/sync-logs` | authRequired, syncDeviceLogsHandler); | [server/src/routes/door_log_routes.js:271](../server/src/routes/door_log_routes.js#L271) |
| GET | `/health` |  | [server/src/routes/firmware_routes.js:95](../server/src/routes/firmware_routes.js#L95) |
| GET | `/firmware/:target/manifest.json` |  | [server/src/routes/firmware_routes.js:111](../server/src/routes/firmware_routes.js#L111) |
| GET | `/firmware/:target/:file` | (req, res) => { | [server/src/routes/firmware_routes.js:226](../server/src/routes/firmware_routes.js#L226) |
| POST | `/app/guest-passes` | authRequired | [server/src/routes/guest_passes_routes.js:54](../server/src/routes/guest_passes_routes.js#L54) |
| GET | `/app/guest-passes` | authRequired | [server/src/routes/guest_passes_routes.js:149](../server/src/routes/guest_passes_routes.js#L149) |
| DELETE | `/app/guest-passes/:id` | authRequired | [server/src/routes/guest_passes_routes.js:193](../server/src/routes/guest_passes_routes.js#L193) |
| POST | `/public/guest-pass/:token/open` | doorCommandRateLimiter | [server/src/routes/guest_passes_routes.js:221](../server/src/routes/guest_passes_routes.js#L221) |
| GET | `/guest/:token` |  | [server/src/routes/guest_passes_routes.js:477](../server/src/routes/guest_passes_routes.js#L477) |
| PATCH | `/manager/sites/:id/security-policy` | authRequired, requireSiteManager, handleSecurityPolicyPatch); | [server/src/routes/manager_routes.js:264](../server/src/routes/manager_routes.js#L264) |
| PATCH | `/admin/sites/:id/security-policy` | authRequired, requireSuperUser, handleSecurityPolicyPatch); | [server/src/routes/manager_routes.js:267](../server/src/routes/manager_routes.js#L267) |
| GET | `/manager/sites` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:274](../server/src/routes/manager_routes.js#L274) |
| POST | `/manager/sites` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:296](../server/src/routes/manager_routes.js#L296) |
| PATCH | `/manager/sites/:id` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:357](../server/src/routes/manager_routes.js#L357) |
| DELETE | `/manager/sites/:id` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:482](../server/src/routes/manager_routes.js#L482) |
| POST | `/manager/sites/:id/approve-deletion` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:497](../server/src/routes/manager_routes.js#L497) |
| POST | `/manager/sites/:id/reject-deletion` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:512](../server/src/routes/manager_routes.js#L512) |
| GET | `/manager/sites/:id/structure` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:527](../server/src/routes/manager_routes.js#L527) |
| GET | `/manager/sites/:id/join-token` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:549](../server/src/routes/manager_routes.js#L549) |
| POST | `/manager/sites/:id/join-token/rotate` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:574](../server/src/routes/manager_routes.js#L574) |
| GET | `/manager/devices/lookup` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:607](../server/src/routes/manager_routes.js#L607) |
| GET | `/manager/devices` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:629](../server/src/routes/manager_routes.js#L629) |
| POST | `/manager/devices/mqtt-credentials` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:641](../server/src/routes/manager_routes.js#L641) |
| PATCH | `/manager/apartments/:id/resident` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:685](../server/src/routes/manager_routes.js#L685) |
| DELETE | `/manager/apartments/:id/resident` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:754](../server/src/routes/manager_routes.js#L754) |
| POST | `/manager/apartments/:id/send-credentials` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:784](../server/src/routes/manager_routes.js#L784) |
| POST | `/manager/apartments/:id/reset-pin` | authRequired, requireSiteManager, apartmentPinResetLimiter | [server/src/routes/manager_routes.js:817](../server/src/routes/manager_routes.js#L817) |
| PATCH | `/manager/doors/:id/device` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:857](../server/src/routes/manager_routes.js#L857) |
| POST | `/manager/doors/:id/unassign-device` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:901](../server/src/routes/manager_routes.js#L901) |
| POST | `/manager/doors/:id/replace-device` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:930](../server/src/routes/manager_routes.js#L930) |
| POST | `/manager/sites/:siteCode/doors` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:981](../server/src/routes/manager_routes.js#L981) |
| PUT | `/manager/doors/:id` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1020](../server/src/routes/manager_routes.js#L1020) |
| DELETE | `/manager/doors/:id` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1066](../server/src/routes/manager_routes.js#L1066) |
| POST | `/manager/doors/:id/revoke-active-qrs` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1093](../server/src/routes/manager_routes.js#L1093) |
| DELETE | `/manager/devices/:id` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1217](../server/src/routes/manager_routes.js#L1217) |
| GET | `/manager/sites/:id/join-requests` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1260](../server/src/routes/manager_routes.js#L1260) |
| POST | `/manager/join-requests/:requestId/approve` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1282](../server/src/routes/manager_routes.js#L1282) |
| POST | `/manager/join-requests/:requestId/reject` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1303](../server/src/routes/manager_routes.js#L1303) |
| GET | `/manager/sites/:siteCode/managers` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1330](../server/src/routes/manager_routes.js#L1330) |
| POST | `/manager/sites/:siteCode/managers/invite` | authRequired, requireSiteManager, inviteLimiter | [server/src/routes/manager_routes.js:1353](../server/src/routes/manager_routes.js#L1353) |
| DELETE | `/manager/sites/:siteCode/managers/:userCode` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1383](../server/src/routes/manager_routes.js#L1383) |
| DELETE | `/manager/sites/:siteCode/invitations/:invitationId` | authRequired, requireSiteManager | [server/src/routes/manager_routes.js:1410](../server/src/routes/manager_routes.js#L1410) |
| POST | `/membership/claim-device` | authRequired, claimDeviceLimiter | [server/src/routes/membership_routes.js:80](../server/src/routes/membership_routes.js#L80) |
| GET | `/membership/my-devices` | authRequired | [server/src/routes/membership_routes.js:100](../server/src/routes/membership_routes.js#L100) |
| POST | `/membership/setup-site` | authRequired, setupSiteLimiter | [server/src/routes/membership_routes.js:113](../server/src/routes/membership_routes.js#L113) |
| GET | `/membership/join-info/:token` | authRequired | [server/src/routes/membership_routes.js:143](../server/src/routes/membership_routes.js#L143) |
| POST | `/membership/join-request` | authRequired | [server/src/routes/membership_routes.js:163](../server/src/routes/membership_routes.js#L163) |
| GET | `/membership/my-join-requests` | authRequired | [server/src/routes/membership_routes.js:185](../server/src/routes/membership_routes.js#L185) |
| GET | `/membership/my-apartments` | authRequired | [server/src/routes/membership_routes.js:198](../server/src/routes/membership_routes.js#L198) |
| GET | `/membership/doors/:id/permissions` | authRequired | [server/src/routes/membership_routes.js:333](../server/src/routes/membership_routes.js#L333) |
| POST | `/membership/doors/:id/permissions` | authRequired | [server/src/routes/membership_routes.js:353](../server/src/routes/membership_routes.js#L353) |
| POST | `/membership/doors/:id/permissions/bulk` | authRequired | [server/src/routes/membership_routes.js:381](../server/src/routes/membership_routes.js#L381) |
| GET | `/membership/sites/:id/residents-tree` | authRequired | [server/src/routes/membership_routes.js:408](../server/src/routes/membership_routes.js#L408) |
| POST | `/api/company/labeled-devices` | companyAccessLimiter, requireCompanyAccess, express.json({ limit: '5m… | [server/src/server.js:124](../server/src/server.js#L124) |
| POST | `/public/client-errors` | clientErrorBodyParser); | [server/src/server.js:126](../server/src/server.js#L126) |
| GET | `*` | (req, res, next) => { | [server/src/server.js:245](../server/src/server.js#L245) |

## Ek B — Uygulama → sunucu çağrıları

Kaynak: `lib/services/*.dart`. Hangi uygulama metodunun hangi yola istek attığı (yol parametreleri `$` ile gösterilir).

| Yol | Uygulama metodu | Dosya:satır |
| --- | --- | --- |
| `/auth/login` | `login` | [lib/services/auth_api.dart:105](../lib/services/auth_api.dart#L105) |
| `/auth/register-individual` | `registerIndividual` | [lib/services/auth_api.dart:128](../lib/services/auth_api.dart#L128) |
| `/auth/verify-code` | `verifyIndividualCode` | [lib/services/auth_api.dart:150](../lib/services/auth_api.dart#L150) |
| `/auth/resend-code` | `resendIndividualCode` | [lib/services/auth_api.dart:162](../lib/services/auth_api.dart#L162) |
| `/auth/forgot-password` | `forgotPassword` | [lib/services/auth_api.dart:178](../lib/services/auth_api.dart#L178) |
| `/auth/sms/status` | `smsLoginEnabled` | [lib/services/auth_api.dart:196](../lib/services/auth_api.dart#L196) |
| `/auth/sms/request` | `requestSmsCode` | [lib/services/auth_api.dart:210](../lib/services/auth_api.dart#L210) |
| `/auth/oauth/status` | `oauthStatus` | [lib/services/auth_api.dart:223](../lib/services/auth_api.dart#L223) |
| `/auth/oauth/$cleanProvider` | `loginWithOAuth` | [lib/services/auth_api.dart:251](../lib/services/auth_api.dart#L251) |
| `/auth/oauth/$cleanProvider/request-code` | `requestOAuthEmailCode` | [lib/services/auth_api.dart:277](../lib/services/auth_api.dart#L277) |
| `/auth/oauth/$cleanProvider/verify-code` | `verifyOAuthEmailCode` | [lib/services/auth_api.dart:305](../lib/services/auth_api.dart#L305) |
| `/auth/oauth/$cleanProvider/start` | `startOAuthWebSession` | [lib/services/auth_api.dart:329](../lib/services/auth_api.dart#L329) |
| `/auth/oauth/session/$sessionId` | `pollOAuthWebSession` | [lib/services/auth_api.dart:353](../lib/services/auth_api.dart#L353) |
| `/auth/sms/verify` | `verifySmsCode` | [lib/services/auth_api.dart:363](../lib/services/auth_api.dart#L363) |
| `/auth/register` | `register` | [lib/services/auth_api.dart:377](../lib/services/auth_api.dart#L377) |
| `/admin/users` | `listManagedUsers` | [lib/services/auth_api.dart:408](../lib/services/auth_api.dart#L408) |
| `/admin/users` | `createManagedUser` | [lib/services/auth_api.dart:459](../lib/services/auth_api.dart#L459) |
| `/admin/users/$userCode` | `updateManagedUser` | [lib/services/auth_api.dart:498](../lib/services/auth_api.dart#L498) |
| `/admin/users/$userCode/activation` | `setManagedUserActivation` | [lib/services/auth_api.dart:513](../lib/services/auth_api.dart#L513) |
| `/admin/users/$userCode` | `deleteManagedUser` | [lib/services/auth_api.dart:527](../lib/services/auth_api.dart#L527) |
| `/admin/maintenance/health` | `getDatabaseHealth` | [lib/services/auth_api.dart:539](../lib/services/auth_api.dart#L539) |
| `/admin/maintenance/cleanup` | `runDatabaseCleanup` | [lib/services/auth_api.dart:552](../lib/services/auth_api.dart#L552) |
| `/admin/sites/$siteCode/approval` | `resolveSiteApproval` | [lib/services/auth_api.dart:609](../lib/services/auth_api.dart#L609) |
| `/admin/sites/$siteCode/features` | `updateSiteFeatures` | [lib/services/auth_api.dart:723](../lib/services/auth_api.dart#L723) |
| `/app/modules/catalog` | `getModuleCatalog` | [lib/services/auth_api.dart:806](../lib/services/auth_api.dart#L806) |
| `/app/my-modules` | `getMyModules` | [lib/services/auth_api.dart:822](../lib/services/auth_api.dart#L822) |
| `/app/management-types` | `getManagementTypes` | [lib/services/auth_api.dart:836](../lib/services/auth_api.dart#L836) |
| `/manager/sites/$siteCode/modules` | `getSiteModules` | [lib/services/auth_api.dart:857](../lib/services/auth_api.dart#L857) |
| `/manager/sites/$siteCode/modules/$moduleCode` | `setSiteModule` | [lib/services/auth_api.dart:879](../lib/services/auth_api.dart#L879) |
| `/admin/audit-log` | `listAuditLog` | [lib/services/auth_api.dart:906](../lib/services/auth_api.dart#L906) |
| `/manager/sites/$siteCode/staff-roles` | `listStaffRoles` | [lib/services/auth_api.dart:923](../lib/services/auth_api.dart#L923) |
| `/manager/sites/$siteCode/staff-roles` | `assignStaffRole` | [lib/services/auth_api.dart:945](../lib/services/auth_api.dart#L945) |
| `/manager/sites/$siteCode/staff-roles/$userCode` | `removeStaffRole` | [lib/services/auth_api.dart:964](../lib/services/auth_api.dart#L964) |
| `/manager/sites/$siteCode/module-requests` | `createModuleRequest` | [lib/services/auth_api.dart:1225](../lib/services/auth_api.dart#L1225) |
| `/manager/sites/$siteCode/module-requests` | `listModuleRequests` | [lib/services/auth_api.dart:1247](../lib/services/auth_api.dart#L1247) |
| `/manager/sites/$siteCode/module-requests/$requestId` | `cancelModuleRequest` | [lib/services/auth_api.dart:1268](../lib/services/auth_api.dart#L1268) |
| `/admin/module-requests` | `listAdminModuleRequests` | [lib/services/auth_api.dart:1292](../lib/services/auth_api.dart#L1292) |
| `/admin/module-requests/$requestId` | `decideModuleRequest` | [lib/services/auth_api.dart:1309](../lib/services/auth_api.dart#L1309) |
| `/membership/site-applications` | `createSiteApplication` | [lib/services/auth_api.dart:1399](../lib/services/auth_api.dart#L1399) |
| `/membership/site-applications/mine` | `getMySiteApplications` | [lib/services/auth_api.dart:1432](../lib/services/auth_api.dart#L1432) |
| `/membership/site-applications/$applicationId/cancel` | `cancelSiteApplication` | [lib/services/auth_api.dart:1456](../lib/services/auth_api.dart#L1456) |
| `/admin/site-applications` | `listAdminSiteApplications` | [lib/services/auth_api.dart:1484](../lib/services/auth_api.dart#L1484) |
| `/admin/site-applications/summary` | `getAdminSiteApplicationsPendingCount` | [lib/services/auth_api.dart:1499](../lib/services/auth_api.dart#L1499) |
| `/admin/site-applications/$applicationId` | `getAdminSiteApplication` | [lib/services/auth_api.dart:1522](../lib/services/auth_api.dart#L1522) |
| `/admin/site-applications/$applicationId/approve` | `approveSiteApplication` | [lib/services/auth_api.dart:1547](../lib/services/auth_api.dart#L1547) |
| `/admin/site-applications/$applicationId/reject` | `rejectSiteApplication` | [lib/services/auth_api.dart:1568](../lib/services/auth_api.dart#L1568) |
| `/app/my-records` | `getMyRecords` | [lib/services/auth_api.dart:1913](../lib/services/auth_api.dart#L1913) |
| `/app/announcements` | `listMyAnnouncements` | [lib/services/auth_api.dart:2139](../lib/services/auth_api.dart#L2139) |
| `/app/announcements/$announcementId` | `getMyAnnouncement` | [lib/services/auth_api.dart:2154](../lib/services/auth_api.dart#L2154) |
| `/app/announcements/$announcementId/read` | `markAnnouncementRead` | [lib/services/auth_api.dart:2169](../lib/services/auth_api.dart#L2169) |
| `/app/announcements/$announcementId` | `hideAnnouncement` | [lib/services/auth_api.dart:2182](../lib/services/auth_api.dart#L2182) |
| `/app/announcements/$announcementId/restore` | `restoreAnnouncement` | [lib/services/auth_api.dart:2192](../lib/services/auth_api.dart#L2192) |
| `/app/announcements/read-all` | `markAllAnnouncementsRead` | [lib/services/auth_api.dart:2203](../lib/services/auth_api.dart#L2203) |
| `/app/notifications/summary` | `getNotificationSummary` | [lib/services/auth_api.dart:2216](../lib/services/auth_api.dart#L2216) |
| `/app/notification-preferences` | `getNotificationPreferences` | [lib/services/auth_api.dart:2227](../lib/services/auth_api.dart#L2227) |
| `/app/notification-preferences` | `setNotificationPreferences` | [lib/services/auth_api.dart:2248](../lib/services/auth_api.dart#L2248) |
| `/app/my-finance` | `getMyFinance` | [lib/services/auth_api.dart:2688](../lib/services/auth_api.dart#L2688) |
| `/admin/devices/$deviceUid/connectivity-logs` | `getDeviceConnectivityLogs` | [lib/services/auth_api.dart:2839](../lib/services/auth_api.dart#L2839) |
| `/device/sync-logs` | `syncDeviceLogs` | [lib/services/auth_api.dart:2864](../lib/services/auth_api.dart#L2864) |
| `/admin/sites/$siteCode/request-email-deletion-code` | `requestSiteDeletionEmailCode` | [lib/services/auth_api.dart:2963](../lib/services/auth_api.dart#L2963) |
| `/admin/sites/$siteCode/confirm-email-deletion` | `confirmSiteDeletionWithEmailCode` | [lib/services/auth_api.dart:2978](../lib/services/auth_api.dart#L2978) |
| `/admin/devices` | `createDevice` | [lib/services/auth_api.dart:2995](../lib/services/auth_api.dart#L2995) |
| `/manager/devices` | `listCompanyDevices` | [lib/services/auth_api.dart:3021](../lib/services/auth_api.dart#L3021) |
| `/admin/devices` | `listCompanyDevices` | [lib/services/auth_api.dart:3040](../lib/services/auth_api.dart#L3040) |
| `/admin/devices/ota-check` | `broadcastOtaCheck` | [lib/services/auth_api.dart:3119](../lib/services/auth_api.dart#L3119) |
| `/app/doors/$doorId/status` | `getDoorRuntimeStatus` | [lib/services/auth_api.dart:3155](../lib/services/auth_api.dart#L3155) |
| `/app/doors/$doorId/open` | `openDoor` | [lib/services/auth_api.dart:3175](../lib/services/auth_api.dart#L3175) |
| `/app/doors/scan-qr-open` | `openDoorWithScannedQr` | [lib/services/auth_api.dart:3198](../lib/services/auth_api.dart#L3198) |
| `/app/doors/$doorId/local-open-notify` | `notifyLocalDoorOpened` | [lib/services/auth_api.dart:3222](../lib/services/auth_api.dart#L3222) |
| `/app/doors/$doorId/qr-token` | `requestDoorQrToken` | [lib/services/auth_api.dart:3239](../lib/services/auth_api.dart#L3239) |
| `/app/doors/$doorId/revoke-my-qr` | `revokeMyDoorQr` | [lib/services/auth_api.dart:3254](../lib/services/auth_api.dart#L3254) |
| `/app/doors/qr-status` | `getDoorQrStatus` | [lib/services/auth_api.dart:3268](../lib/services/auth_api.dart#L3268) |
| `/app/my-doors` | `listMyDoors` | [lib/services/auth_api.dart:3280](../lib/services/auth_api.dart#L3280) |
| `/admin/subscription-requests` | `listSubscriptionRequests` | [lib/services/auth_api.dart:3300](../lib/services/auth_api.dart#L3300) |
| `/admin/subscription-requests/$userCode` | `resolveSubscriptionRequest` | [lib/services/auth_api.dart:3338](../lib/services/auth_api.dart#L3338) |
| `/me` | `updateMyProfile` | [lib/services/auth_api.dart:3370](../lib/services/auth_api.dart#L3370) |
| `/me` | `fetchMe` | [lib/services/auth_api.dart:3408](../lib/services/auth_api.dart#L3408) |
| `/app/guest-passes` | `createGuestPass` | [lib/services/auth_api.dart:4244](../lib/services/auth_api.dart#L4244) |
| `/app/guest-passes` | `listGuestPasses` | [lib/services/auth_api.dart:4270](../lib/services/auth_api.dart#L4270) |
| `/app/guest-passes/$passId` | `revokeGuestPass` | [lib/services/auth_api.dart:4292](../lib/services/auth_api.dart#L4292) |
| `/membership/claim-device` | `claimDevice` | [lib/services/auth_api.dart:4305](../lib/services/auth_api.dart#L4305) |
| `/membership/my-devices` | `getMyClaimedDevices` | [lib/services/auth_api.dart:4321](../lib/services/auth_api.dart#L4321) |
| `/membership/setup-site` | `setupSite` | [lib/services/auth_api.dart:4345](../lib/services/auth_api.dart#L4345) |
| `/manager/sites/$siteCode/doors` | `createDoor` | [lib/services/auth_api.dart:4376](../lib/services/auth_api.dart#L4376) |
| `/manager/doors/$doorId` | `updateDoor` | [lib/services/auth_api.dart:4405](../lib/services/auth_api.dart#L4405) |
| `/manager/doors/$doorId` | `deleteDoor` | [lib/services/auth_api.dart:4419](../lib/services/auth_api.dart#L4419) |
| `/manager/doors/$doorId/unassign-device` | `unassignDoorDevice` | [lib/services/auth_api.dart:4431](../lib/services/auth_api.dart#L4431) |
| `/manager/doors/$doorId/replace-device` | `replaceDoorDevice` | [lib/services/auth_api.dart:4446](../lib/services/auth_api.dart#L4446) |
| `/manager/sites/$siteCode/assignable-devices` | `getAssignableDevices` | [lib/services/auth_api.dart:4464](../lib/services/auth_api.dart#L4464) |
| `/manager/sites/$siteCode/join-token` | `getSiteJoinToken` | [lib/services/auth_api.dart:4479](../lib/services/auth_api.dart#L4479) |
| `/manager/sites/$siteCode/join-token/rotate` | `rotateSiteJoinToken` | [lib/services/auth_api.dart:4493](../lib/services/auth_api.dart#L4493) |
| `/membership/join-info/$joinToken` | `getSiteJoinInfo` | [lib/services/auth_api.dart:4507](../lib/services/auth_api.dart#L4507) |
| `/membership/join-request` | `submitJoinRequest` | [lib/services/auth_api.dart:4532](../lib/services/auth_api.dart#L4532) |
| `/membership/my-join-requests` | `getMyJoinRequests` | [lib/services/auth_api.dart:4551](../lib/services/auth_api.dart#L4551) |
| `/manager/sites/$siteCode/join-requests$query` | `getSiteJoinRequests` | [lib/services/auth_api.dart:4570](../lib/services/auth_api.dart#L4570) |
| `/manager/join-requests/$requestId/approve` | `approveJoinRequest` | [lib/services/auth_api.dart:4585](../lib/services/auth_api.dart#L4585) |
| `/manager/join-requests/$requestId/reject` | `rejectJoinRequest` | [lib/services/auth_api.dart:4599](../lib/services/auth_api.dart#L4599) |
| `/membership/my-apartments` | `getMyApartments` | [lib/services/auth_api.dart:4614](../lib/services/auth_api.dart#L4614) |
| `/membership/apartments/$apartmentId/members/$targetUserCode/remove` | `removeApartmentMember` | [lib/services/auth_api.dart:4630](../lib/services/auth_api.dart#L4630) |
| `/membership/doors/$doorId/permissions` | `getDoorPermissions` | [lib/services/auth_api.dart:4643](../lib/services/auth_api.dart#L4643) |
| `/membership/doors/$doorId/permissions` | `setDoorAccessOverride` | [lib/services/auth_api.dart:4666](../lib/services/auth_api.dart#L4666) |
| `/membership/doors/$doorId/permissions/bulk` | `setBulkDoorAccessOverride` | [lib/services/auth_api.dart:4693](../lib/services/auth_api.dart#L4693) |
| `/membership/sites/$siteCode/residents-tree` | `getSiteResidentsTree` | [lib/services/auth_api.dart:4707](../lib/services/auth_api.dart#L4707) |
| `/membership/apartments/$apartmentId/members/$targetUserCode/status` | `toggleApartmentMemberStatus` | [lib/services/auth_api.dart:4722](../lib/services/auth_api.dart#L4722) |
| `/membership/apartments/$apartmentId/members/$targetUserCode` | `deleteApartmentMember` | [lib/services/auth_api.dart:4737](../lib/services/auth_api.dart#L4737) |
| `/membership/apartments/$apartmentId/members/$targetUserCode/change-password` | `changeApartmentMemberPassword` | [lib/services/auth_api.dart:4757](../lib/services/auth_api.dart#L4757) |
| `/membership/apartments/$apartmentId/members/$targetUserCode/set-primary-admin` | `setApartmentPrimaryAdmin` | [lib/services/auth_api.dart:4778](../lib/services/auth_api.dart#L4778) |
| `/manager/sites/$siteCode/managers` | `getSiteManagers` | [lib/services/auth_api.dart:4791](../lib/services/auth_api.dart#L4791) |
| `/manager/sites/$siteCode/managers/invite` | `inviteSiteManager` | [lib/services/auth_api.dart:4807](../lib/services/auth_api.dart#L4807) |
| `/manager/sites/$siteCode/managers/$userCode` | `removeSiteManager` | [lib/services/auth_api.dart:4826](../lib/services/auth_api.dart#L4826) |
| `/manager/sites/$siteCode/invitations/$invitationId` | `revokeSiteManagerInvitation` | [lib/services/auth_api.dart:4840](../lib/services/auth_api.dart#L4840) |
| `/admin/devices/$deviceId/defect` | `setDeviceDefectStatus` | [lib/services/auth_api.dart:4855](../lib/services/auth_api.dart#L4855) |
| `/admin/devices/$deviceId/release-ownership` | `releaseDeviceOwnership` | [lib/services/auth_api.dart:4874](../lib/services/auth_api.dart#L4874) |
| `/app/documents/$documentId/download` | `downloadMine` | [lib/services/document_api.dart:554](../lib/services/document_api.dart#L554) |

## Ek C — Sunucu ortam değişkenleri

Kaynak: `process.env.*` kullanımları (`server/src`, `server/scripts`). Değerler `server/.env` içindedir (canlıda `/var/www/site_kapi_kontrol/server/.env`); sır içerdiği için belgeye yazılmaz. Şablon: [server/.env.example](../server/.env.example).

| Değişken | İlk kullanımlar |
| --- | --- |
| `ALLOW_DEV_SCRIPTS` | [server/scripts/_dev_guard.js:3](../server/scripts/_dev_guard.js#L3) |
| `ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_ADDRESS` | [server/scripts/qa_platform_pg.mjs:2798](../server/scripts/qa_platform_pg.mjs#L2798) |
| `ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE` | [server/scripts/qa_platform_pg.mjs:2795](../server/scripts/qa_platform_pg.mjs#L2795) |
| `ANNOUNCEMENT_EMAIL_PUBLISH_MAX_PER_HOUR_PER_USER` | [server/scripts/qa_platform_pg.mjs:2802](../server/scripts/qa_platform_pg.mjs#L2802) |
| `ANNOUNCEMENT_EMAIL_SECRET` | [server/scripts/qa_platform_pg.mjs:5089](../server/scripts/qa_platform_pg.mjs#L5089) |
| `ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS` | [server/scripts/qa_platform_pg.mjs:5090](../server/scripts/qa_platform_pg.mjs#L5090) |
| `ANNOUNCEMENT_INBOX_RETENTION_DAYS` | [server/scripts/qa_platform_pg.mjs:4364](../server/scripts/qa_platform_pg.mjs#L4364) |
| `ANNOUNCEMENT_MAX_PER_DAY_PER_SITE` | [server/scripts/qa_platform_pg.mjs:2800](../server/scripts/qa_platform_pg.mjs#L2800) |
| `ANNOUNCEMENT_SCHEDULER_DISABLED` | [server/scripts/qa_platform_pg.mjs:2794](../server/scripts/qa_platform_pg.mjs#L2794) |
| `ANNOUNCEMENT_URGENT_EMAIL_MAX_PER_DAY_PER_SITE` | [server/scripts/qa_platform_pg.mjs:2801](../server/scripts/qa_platform_pg.mjs#L2801) |
| `BULK_IMPORT_DISABLED` | [server/scripts/qa_bulk_import.mjs:1409](../server/scripts/qa_bulk_import.mjs#L1409) |
| `CAMERA_SECRET_KEY` | [server/src/modules/device_integrations_service.js:35](../server/src/modules/device_integrations_service.js#L35) |
| `CLIENT_ERROR_MAX_ROWS` | [server/scripts/qa_platform_pg.mjs:9232](../server/scripts/qa_platform_pg.mjs#L9232) |
| `CONCIERGE_MAX_OPEN_PER_SITE` | [server/scripts/qa_reservation_section.mjs:622](../server/scripts/qa_reservation_section.mjs#L622) |
| `CONCIERGE_MAX_OPEN_PER_USER` | [server/scripts/qa_reservation_section.mjs:611](../server/scripts/qa_reservation_section.mjs#L611) |
| `CONCIERGE_MAX_PER_USER_PER_HOUR` | [server/scripts/qa_reservation_section.mjs:616](../server/scripts/qa_reservation_section.mjs#L616) |
| `DB_CONNECT_TIMEOUT_MS` | [server/src/db.js:63](../server/src/db.js#L63) |
| `DB_HOST` | [server/src/db.js:66](../server/src/db.js#L66)<br>[server/scripts/apply_017.js:15](../server/scripts/apply_017.js#L15)<br>[server/scripts/apply_018.js:15](../server/scripts/apply_018.js#L15) |
| `DB_NAME` | [server/src/db.js:68](../server/src/db.js#L68)<br>[server/scripts/apply_017.js:17](../server/scripts/apply_017.js#L17)<br>[server/scripts/apply_018.js:17](../server/scripts/apply_018.js#L17) |
| `DB_PASSWORD` | [server/src/db.js:70](../server/src/db.js#L70)<br>[server/scripts/apply_017.js:19](../server/scripts/apply_017.js#L19)<br>[server/scripts/apply_018.js:19](../server/scripts/apply_018.js#L19) |
| `DB_POOL_MAX` | [server/src/db.js:61](../server/src/db.js#L61) |
| `DB_PORT` | [server/src/db.js:67](../server/src/db.js#L67)<br>[server/scripts/apply_017.js:16](../server/scripts/apply_017.js#L16)<br>[server/scripts/apply_018.js:16](../server/scripts/apply_018.js#L16) |
| `DB_STATEMENT_TIMEOUT_MS` | [server/src/db.js:62](../server/src/db.js#L62)<br>[server/scripts/qa_bulk_import.mjs:72](../server/scripts/qa_bulk_import.mjs#L72)<br>[server/scripts/qa_documents_section.mjs:34](../server/scripts/qa_documents_section.mjs#L34) |
| `DB_USER` | [server/src/db.js:69](../server/src/db.js#L69)<br>[server/scripts/apply_017.js:18](../server/scripts/apply_017.js#L18)<br>[server/scripts/apply_018.js:18](../server/scripts/apply_018.js#L18) |
| `DOCUMENTS_DIR` | [server/scripts/qa_work_tracking_section.mjs:600](../server/scripts/qa_work_tracking_section.mjs#L600) |
| `DOCUMENTS_MAX_PER_SITE` | [server/scripts/qa_documents_section.mjs:718](../server/scripts/qa_documents_section.mjs#L718) |
| `DOCUMENTS_MIN_FREE_BYTES` | [server/scripts/qa_work_tracking_section.mjs:601](../server/scripts/qa_work_tracking_section.mjs#L601) |
| `DOCUMENTS_SITE_QUOTA_BYTES` | [server/scripts/qa_documents_section.mjs:696](../server/scripts/qa_documents_section.mjs#L696)<br>[server/scripts/qa_finance4b_expenses.mjs:282](../server/scripts/qa_finance4b_expenses.mjs#L282) |
| `DRIVE_PENDING_DIR` | [server/src/modules/drive_service.js:51](../server/src/modules/drive_service.js#L51) |
| `FINANCE_RECEIPT_SECRET` | [server/scripts/qa_finance4b.mjs:14](../server/scripts/qa_finance4b.mjs#L14)<br>[server/scripts/qa_finance4b_receipts.mjs:21](../server/scripts/qa_finance4b_receipts.mjs#L21) |
| `FINANCE_REMINDER_MAX_PER_DAY_PER_SITE` | [server/scripts/qa_finance4b_reminders.mjs:288](../server/scripts/qa_finance4b_reminders.mjs#L288) |
| `FIRMWARE_DIR` | [server/src/routes/firmware_routes.js:25](../server/src/routes/firmware_routes.js#L25) |
| `JWT_SECRET` | [server/src/jwt.js:31](../server/src/jwt.js#L31)<br>[server/src/modules/apartment_mgmt_service.js:91](../server/src/modules/apartment_mgmt_service.js#L91)<br>[server/src/modules/device_integrations_service.js:35](../server/src/modules/device_integrations_service.js#L35) |
| `LEGAL_DIR` | [server/scripts/qa_platform_pg.mjs:9231](../server/scripts/qa_platform_pg.mjs#L9231) |
| `LISTEN_HOST` | [server/src/server.js:357](../server/src/server.js#L357) |
| `MIGRATE_LOCK_TIMEOUT_MS` | [server/scripts/migrate.js:371](../server/scripts/migrate.js#L371) |
| `MOSQUITTO_PASSWD_BIN` | [server/scripts/sync_mqtt_acl.js:11](../server/scripts/sync_mqtt_acl.js#L11) |
| `MQTT_ACL_FILE` | [server/scripts/sync_mqtt_acl.js:10](../server/scripts/sync_mqtt_acl.js#L10) |
| `MQTT_ALLOW_INSECURE_TLS` | [server/scripts/trigger_ota.js:42](../server/scripts/trigger_ota.js#L42) |
| `MQTT_HOST` | [server/src/utils/helpers.js:341](../server/src/utils/helpers.js#L341)<br>[server/scripts/trigger_ota.js:19](../server/scripts/trigger_ota.js#L19) |
| `MQTT_LEGACY_USERS` | [server/scripts/sync_mqtt_acl.js:12](../server/scripts/sync_mqtt_acl.js#L12) |
| `MQTT_PASSWD_FILE` | [server/scripts/sync_mqtt_acl.js:9](../server/scripts/sync_mqtt_acl.js#L9) |
| `MQTT_PASSWORD` | [server/src/mqtt_bridge.js:68](../server/src/mqtt_bridge.js#L68)<br>[server/scripts/trigger_ota.js:36](../server/scripts/trigger_ota.js#L36) |
| `MQTT_PORT` | [server/src/utils/helpers.js:342](../server/src/utils/helpers.js#L342)<br>[server/scripts/trigger_ota.js:23](../server/scripts/trigger_ota.js#L23) |
| `MQTT_SYNC_ARGS` | [server/src/mqtt_acl_sync.js:173](../server/src/mqtt_acl_sync.js#L173) |
| `MQTT_SYNC_COMMAND` | [server/src/mqtt_acl_sync.js:158](../server/src/mqtt_acl_sync.js#L158) |
| `MQTT_SYNC_SHOW_LOG` | [server/scripts/sync_mqtt_acl.js:96](../server/scripts/sync_mqtt_acl.js#L96) |
| `MQTT_SYNC_TIMEOUT_MS` | [server/src/mqtt_acl_sync.js:174](../server/src/mqtt_acl_sync.js#L174) |
| `MQTT_URL` | [server/scripts/trigger_ota.js:15](../server/scripts/trigger_ota.js#L15) |
| `MQTT_USER` | [server/src/mqtt_bridge.js:67](../server/src/mqtt_bridge.js#L67)<br>[server/scripts/trigger_ota.js:35](../server/scripts/trigger_ota.js#L35) |
| `NODE_ENV` | [server/scripts/qa_platform_pg.mjs:548](../server/scripts/qa_platform_pg.mjs#L548) |
| `PEOPLE_SYNC_MIN_INTERVAL_MS` | [server/src/modules/people_sync.js:19](../server/src/modules/people_sync.js#L19)<br>[server/scripts/qa_platform_pg.mjs:550](../server/scripts/qa_platform_pg.mjs#L550) |
| `PORT` | [server/src/server.js:107](../server/src/server.js#L107) |
| `PUBLIC_APP_URL` | [server/src/modules/person_invite_service.js:64](../server/src/modules/person_invite_service.js#L64)<br>[server/src/routes/auth_routes.js:371](../server/src/routes/auth_routes.js#L371)<br>[server/src/routes/guest_passes_routes.js:40](../server/src/routes/guest_passes_routes.js#L40) |
| `PUBLIC_BASE_URL` | [server/src/modules/person_invite_service.js:64](../server/src/modules/person_invite_service.js#L64)<br>[server/src/routes/auth_routes.js:372](../server/src/routes/auth_routes.js#L372)<br>[server/src/routes/guest_passes_routes.js:41](../server/src/routes/guest_passes_routes.js#L41) |
| `QA_ADMIN_DB` | [server/scripts/qa_finance4b.mjs:162](../server/scripts/qa_finance4b.mjs#L162)<br>[server/scripts/qa_finance4b_upgrade.mjs:75](../server/scripts/qa_finance4b_upgrade.mjs#L75)<br>[server/scripts/qa_finance_funds_section.mjs:653](../server/scripts/qa_finance_funds_section.mjs#L653) |
| `QA_ANNOUNCEMENT_LOCK_ROUNDS` | [server/scripts/qa_platform_pg.mjs:3805](../server/scripts/qa_platform_pg.mjs#L3805) |
| `QA_ANNOUNCEMENT_ROUNDS` | [server/scripts/qa_platform_pg.mjs:3218](../server/scripts/qa_platform_pg.mjs#L3218) |
| `QA_CONFIRM_DISPOSABLE_DB` | [server/scripts/qa_device_scope_pg.mjs:21](../server/scripts/qa_device_scope_pg.mjs#L21)<br>[server/scripts/qa_finance4b_upgrade.mjs:35](../server/scripts/qa_finance4b_upgrade.mjs#L35)<br>[server/scripts/qa_pending_registration_pg.mjs:21](../server/scripts/qa_pending_registration_pg.mjs#L21) |
| `QA_DB_PREFIX` | [server/scripts/qa_finance4b_upgrade.mjs:43](../server/scripts/qa_finance4b_upgrade.mjs#L43)<br>[server/scripts/qa_platform_pg.mjs:382](../server/scripts/qa_platform_pg.mjs#L382) |
| `QA_FINANCE_DIR` | [server/scripts/qa_platform_pg.mjs:9083](../server/scripts/qa_platform_pg.mjs#L9083) |
| `QA_KEEP_DBS` | [server/scripts/qa_platform_pg.mjs:525](../server/scripts/qa_platform_pg.mjs#L525) |
| `QA_LOCK_ROUNDS` | [server/scripts/qa_finance4b_locks.mjs:10](../server/scripts/qa_finance4b_locks.mjs#L10)<br>[server/scripts/qa_platform_pg.mjs:1396](../server/scripts/qa_platform_pg.mjs#L1396) |
| `QA_ONLY` | [server/scripts/qa_platform_pg.mjs:383](../server/scripts/qa_platform_pg.mjs#L383) |
| `QA_PART` | [server/scripts/qa_finance4b.mjs:283](../server/scripts/qa_finance4b.mjs#L283) |
| `QA_PG_URL` | [server/scripts/qa_auth_attempt_limits_pg.mjs:17](../server/scripts/qa_auth_attempt_limits_pg.mjs#L17) |
| `QA_SCENARIO` | [server/scripts/qa_platform_pg.mjs:576](../server/scripts/qa_platform_pg.mjs#L576) |
| `QA_SECTION` | [server/scripts/qa_platform_pg.mjs:154](../server/scripts/qa_platform_pg.mjs#L154) |
| `QA_UPGRADE_TRIALS` | [server/scripts/qa_finance4b_upgrade.mjs:42](../server/scripts/qa_finance4b_upgrade.mjs#L42)<br>[server/scripts/qa_platform_pg.mjs:8952](../server/scripts/qa_platform_pg.mjs#L8952) |
| `RESERVATIONS_MAX_ACTIVE_PER_SITE` | [server/scripts/qa_reservation_section.mjs:420](../server/scripts/qa_reservation_section.mjs#L420) |
| `RESERVATIONS_MAX_ACTIVE_PER_USER` | [server/scripts/qa_reservation_section.mjs:414](../server/scripts/qa_reservation_section.mjs#L414) |
| `RESERVATIONS_MAX_PER_USER_PER_HOUR` | [server/scripts/qa_reservation_section.mjs:425](../server/scripts/qa_reservation_section.mjs#L425) |
| `SMS_CODE_PEPPER` | [server/src/modules/sms_login.js:29](../server/src/modules/sms_login.js#L29) |
| `SMTP_FROM` | [server/src/mailer.js:95](../server/src/mailer.js#L95) |
| `SMTP_HOST` | [server/scripts/qa_contracts_section.mjs:516](../server/scripts/qa_contracts_section.mjs#L516)<br>[server/scripts/qa_finance4b_reminders.mjs:113](../server/scripts/qa_finance4b_reminders.mjs#L113)<br>[server/scripts/qa_platform_pg.mjs:3568](../server/scripts/qa_platform_pg.mjs#L3568) |
| `SMTP_PORT` | [server/src/mailer.js:13](../server/src/mailer.js#L13)<br>[server/scripts/qa_platform_pg.mjs:558](../server/scripts/qa_platform_pg.mjs#L558) |
| `SMTP_USER` | [server/src/mailer.js:95](../server/src/mailer.js#L95) |
| `TZ` | [server/src/db.js:1](../server/src/db.js#L1)<br>[server/src/mqtt_bridge.js:1](../server/src/mqtt_bridge.js#L1)<br>[server/src/server.js:4](../server/src/server.js#L4) |
| `WORK_ATTACHMENTS_SITE_QUOTA_MB` | [server/scripts/qa_work_tracking_section.mjs:931](../server/scripts/qa_work_tracking_section.mjs#L931) |
| `WORK_ATTACHMENTS_USER_QUOTA_MB` | [server/scripts/qa_work_tracking_section.mjs:915](../server/scripts/qa_work_tracking_section.mjs#L915) |
| `WORK_ITEMS_MAX_OPEN_PER_SITE` | [server/scripts/qa_work_tracking_section.mjs:287](../server/scripts/qa_work_tracking_section.mjs#L287) |
| `WORK_ITEMS_MAX_OPEN_PER_USER` | [server/scripts/qa_work_tracking_section.mjs:494](../server/scripts/qa_work_tracking_section.mjs#L494) |
| `WORK_ITEMS_MAX_PER_USER_PER_HOUR` | [server/scripts/qa_work_tracking_section.mjs:277](../server/scripts/qa_work_tracking_section.mjs#L277) |

## Ek D — Veritabanı tabloları

Şema iki yerde tanımlanır: açılışta çalışan `server/src/db.js` (`ensureDbSchema`, ekleyici) ve numaralı `server/migrations/*.sql`.

| Tablo | db.js | İlk migration |
| --- | --- | --- |
| `access_cards` | — | [server/migrations/046_access_cards.sql:10](../server/migrations/046_access_cards.sql#L10) |
| `account_data_exports` | [server/src/db.js:141](../server/src/db.js#L141) | [server/migrations/036_account_deletion.sql:27](../server/migrations/036_account_deletion.sql#L27) |
| `account_movements` | — | [server/migrations/040_finance_4b.sql:358](../server/migrations/040_finance_4b.sql#L358) |
| `account_reconciliations` | — | [server/migrations/040_finance_4b.sql:410](../server/migrations/040_finance_4b.sql#L410) |
| `account_transfers` | — | [server/migrations/040_finance_4b.sql:335](../server/migrations/040_finance_4b.sql#L335) |
| `announcement_attachments` | — | [server/migrations/039_documents.sql:143](../server/migrations/039_documents.sql#L143) |
| `announcement_email_suppressions` | [server/src/db.js:1497](../server/src/db.js#L1497) | [server/migrations/032_announcements.sql:115](../server/migrations/032_announcements.sql#L115) |
| `announcement_recipients` | [server/src/db.js:1459](../server/src/db.js#L1459) | [server/migrations/032_announcements.sql:77](../server/migrations/032_announcements.sql#L77) |
| `announcements` | [server/src/db.js:1393](../server/src/db.js#L1393) | [server/migrations/032_announcements.sql:11](../server/migrations/032_announcements.sql#L11) |
| `annual_reports` | — | [server/migrations/069_annual_report.sql:6](../server/migrations/069_annual_report.sql#L6) |
| `apartment_access_suspensions` | — | [server/migrations/074_apartment_management.sql:87](../server/migrations/074_apartment_management.sql#L87) |
| `apartment_admin_delegations` | — | [server/migrations/074_apartment_management.sql:8](../server/migrations/074_apartment_management.sql#L8) |
| `apartment_link_requests` | — | [server/migrations/074_apartment_management.sql:27](../server/migrations/074_apartment_management.sql#L27) |
| `apartment_memberships` | [server/src/db.js:1035](../server/src/db.js#L1035) | [server/migrations/016_membership_v2_schema.sql:35](../server/migrations/016_membership_v2_schema.sql#L35) |
| `apartment_notices` | — | [server/migrations/074_apartment_management.sql:46](../server/migrations/074_apartment_management.sql#L46) |
| `apartment_proxies` | — | [server/migrations/074_apartment_management.sql:104](../server/migrations/074_apartment_management.sql#L104) |
| `apartment_residencies` | [server/src/db.js:1235](../server/src/db.js#L1235) | [server/migrations/031_people_and_apartments.sql:30](../server/migrations/031_people_and_apartments.sql#L30) |
| `apartment_residency_log` | — | [server/migrations/075_residency_log.sql:11](../server/migrations/075_residency_log.sql#L11) |
| `apartment_safety_notes` | — | [server/migrations/074_apartment_management.sql:77](../server/migrations/074_apartment_management.sql#L77) |
| `apartment_safety_requests` | — | [server/migrations/074_apartment_management.sql:59](../server/migrations/074_apartment_management.sql#L59) |
| `apartments` | [server/src/db.js:761](../server/src/db.js#L761) | [server/migrations/006_site_structure_and_access.sql:66](../server/migrations/006_site_structure_and_access.sql#L66) |
| `app_maintenance_runs` | [server/src/db.js:221](../server/src/db.js#L221) | — |
| `audit_log` | [server/src/db.js:1152](../server/src/db.js#L1152) | [server/migrations/029_platform_modules.sql:34](../server/migrations/029_platform_modules.sql#L34) |
| `auth_attempt_limits` | — | [server/migrations/085_auth_attempt_limits.sql:6](../server/migrations/085_auth_attempt_limits.sql#L6) |
| `bank_import_profiles` | — | [server/migrations/067_bank_imports.sql:2](../server/migrations/067_bank_imports.sql#L2) |
| `bank_imports` | — | [server/migrations/067_bank_imports.sql:15](../server/migrations/067_bank_imports.sql#L15) |
| `bank_payer_ibans` | — | [server/migrations/067_bank_imports.sql:87](../server/migrations/067_bank_imports.sql#L87) |
| `bank_statement_lines` | — | [server/migrations/067_bank_imports.sql:47](../server/migrations/067_bank_imports.sql#L47) |
| `board_decisions` | — | [server/migrations/050_decision_book.sql:14](../server/migrations/050_decision_book.sql#L14) |
| `brand_themes` | — | [server/migrations/071_brand_themes.sql:4](../server/migrations/071_brand_themes.sql#L4) |
| `budget_items` | — | [server/migrations/059_budget_projects.sql:68](../server/migrations/059_budget_projects.sql#L68) |
| `budget_projects` | — | [server/migrations/059_budget_projects.sql:6](../server/migrations/059_budget_projects.sql#L6) |
| `bulk_import_runs` | — | [server/migrations/038_bulk_imports.sql:13](../server/migrations/038_bulk_imports.sql#L13) |
| `camera_devices` | — | [server/migrations/065_device_integrations.sql:23](../server/migrations/065_device_integrations.sql#L23) |
| `cargo_notify_log` | — | [server/migrations/063_notify_channels.sql:25](../server/migrations/063_notify_channels.sql#L25) |
| `cctv_camera_doors` | — | [server/migrations/072_cctv_link.sql:30](../server/migrations/072_cctv_link.sql#L30) |
| `cctv_cameras` | — | [server/migrations/072_cctv_link.sql:6](../server/migrations/072_cctv_link.sql#L6) |
| `client_error_reports` | [server/src/db.js:1879](../server/src/db.js#L1879) | [server/migrations/035_platform_services.sql:26](../server/migrations/035_platform_services.sql#L26) |
| `concierge_requests` | — | [server/migrations/043_reservation.sql:151](../server/migrations/043_reservation.sql#L151) |
| `contract_reminders` | — | [server/migrations/049_contracts.sql:131](../server/migrations/049_contracts.sql#L131) |
| `contract_vendors` | — | [server/migrations/049_contracts.sql:14](../server/migrations/049_contracts.sql#L14) |
| `device_connectivity_logs` | [server/src/db.js:914](../server/src/db.js#L914) | [server/migrations/010_device_connectivity_logs.sql:4](../server/migrations/010_device_connectivity_logs.sql#L4) |
| `device_runtime_status` | [server/src/db.js:640](../server/src/db.js#L640) | [server/migrations/008_guest_passes_and_door_logs.sql:18](../server/migrations/008_guest_passes_and_door_logs.sql#L18) |
| `devices` | [server/src/db.js:546](../server/src/db.js#L546) | [server/migrations/003_sites_devices.sql:30](../server/migrations/003_sites_devices.sql#L30) |
| `document_versions` | — | [server/migrations/039_documents.sql:85](../server/migrations/039_documents.sql#L85) |
| `documents` | — | [server/migrations/039_documents.sql:13](../server/migrations/039_documents.sql#L13) |
| `door_access_logs` | [server/src/db.js:884](../server/src/db.js#L884) | [server/migrations/008_guest_passes_and_door_logs.sql:68](../server/migrations/008_guest_passes_and_door_logs.sql#L68) |
| `door_access_overrides` | [server/src/db.js:1097](../server/src/db.js#L1097) | [server/migrations/016_membership_v2_schema.sql:100](../server/migrations/016_membership_v2_schema.sql#L100) |
| `drive_files` | — | [server/migrations/060_drive_storage.sql:29](../server/migrations/060_drive_storage.sql#L29) |
| `drive_oauth_states` | — | [server/migrations/060_drive_storage.sql:22](../server/migrations/060_drive_storage.sql#L22) |
| `drive_pending_uploads` | — | [server/migrations/060_drive_storage.sql:48](../server/migrations/060_drive_storage.sql#L48) |
| `email_verifications` | [server/src/db.js:993](../server/src/db.js#L993) | [server/migrations/016_membership_v2_schema.sql:7](../server/migrations/016_membership_v2_schema.sql#L7) |
| `equipment_expense_links` | — | [server/migrations/068_equipment.sql:59](../server/migrations/068_equipment.sql#L59) |
| `equipment_items` | — | [server/migrations/068_equipment.sql:5](../server/migrations/068_equipment.sql#L5) |
| `equipment_maintenance_logs` | — | [server/migrations/068_equipment.sql:42](../server/migrations/068_equipment.sql#L42) |
| `equipment_plans` | — | [server/migrations/068_equipment.sql:26](../server/migrations/068_equipment.sql#L26) |
| `equipment_quotes` | — | [server/migrations/068_equipment.sql:67](../server/migrations/068_equipment.sql#L67) |
| `expense_categories` | — | [server/migrations/040_finance_4b.sql:207](../server/migrations/040_finance_4b.sql#L207) |
| `expense_documents` | — | [server/migrations/040_finance_4b.sql:298](../server/migrations/040_finance_4b.sql#L298) |
| `expense_natures` | — | [server/migrations/056_expense_natures.sql:5](../server/migrations/056_expense_natures.sql#L5) |
| `expense_voids` | — | [server/migrations/040_finance_4b.sql:285](../server/migrations/040_finance_4b.sql#L285) |
| `expenses` | — | [server/migrations/040_finance_4b.sql:239](../server/migrations/040_finance_4b.sql#L239) |
| `fee_definitions` | [server/src/db.js:1607](../server/src/db.js#L1607) | [server/migrations/034_finance.sql:10](../server/migrations/034_finance.sql#L10) |
| `fee_runs` | [server/src/db.js:1659](../server/src/db.js#L1659) | [server/migrations/034_finance.sql:62](../server/migrations/034_finance.sql#L62) |
| `feedback_attachments` | — | [server/migrations/103_feedback.sql:30](../server/migrations/103_feedback.sql#L30) |
| `feedback_reports` | — | [server/migrations/103_feedback.sql:11](../server/migrations/103_feedback.sql#L11) |
| `finance_account_bank_details` | — | [server/migrations/054_finance_payment_info.sql:38](../server/migrations/054_finance_payment_info.sql#L38) |
| `finance_accounts` | — | [server/migrations/040_finance_4b.sql:183](../server/migrations/040_finance_4b.sql#L183) |
| `finance_apartment_ref_codes` | — | [server/migrations/054_finance_payment_info.sql:29](../server/migrations/054_finance_payment_info.sql#L29) |
| `finance_fund_transfers` | — | [server/migrations/080_finance_funds.sql:43](../server/migrations/080_finance_funds.sql#L43) |
| `finance_opening_reverts` | — | [server/migrations/055_opening_balances.sql:16](../server/migrations/055_opening_balances.sql#L16) |
| `finance_payment_settings` | — | [server/migrations/054_finance_payment_info.sql:9](../server/migrations/054_finance_payment_info.sql#L9) |
| `finance_period_closures` | [server/src/db.js:1742](../server/src/db.js#L1742) | [server/migrations/034_finance.sql:145](../server/migrations/034_finance.sql#L145) |
| `finance_reminder_apartments` | — | [server/migrations/040_finance_4b.sql:500](../server/migrations/040_finance_4b.sql#L500) |
| `finance_reminder_exclusions` | — | [server/migrations/040_finance_4b.sql:432](../server/migrations/040_finance_4b.sql#L432) |
| `finance_reminder_items` | — | [server/migrations/040_finance_4b.sql:476](../server/migrations/040_finance_4b.sql#L476) |
| `finance_reminder_runs` | — | [server/migrations/040_finance_4b.sql:444](../server/migrations/040_finance_4b.sql#L444) |
| `finance_settings` | — | [server/migrations/040_finance_4b.sql:7](../server/migrations/040_finance_4b.sql#L7) |
| `finance_site_ref_prefixes` | — | [server/migrations/054_finance_payment_info.sql:19](../server/migrations/054_finance_payment_info.sql#L19) |
| `finance_suppliers` | — | [server/migrations/040_finance_4b.sql:220](../server/migrations/040_finance_4b.sql#L220) |
| `guest_passes` | [server/src/db.js:821](../server/src/db.js#L821) | [server/migrations/008_guest_passes_and_door_logs.sql:49](../server/migrations/008_guest_passes_and_door_logs.sql#L49) |
| `i` | — | [server/migrations/032_announcements.sql:45](../server/migrations/032_announcements.sql#L45) |
| `join_requests` | [server/src/db.js:1061](../server/src/db.js#L1061) | [server/migrations/016_membership_v2_schema.sql:63](../server/migrations/016_membership_v2_schema.sql#L63) |
| `late_fee_run_lines` | — | [server/migrations/040_finance_4b.sql:97](../server/migrations/040_finance_4b.sql#L97) |
| `late_fee_runs` | — | [server/migrations/040_finance_4b.sql:38](../server/migrations/040_finance_4b.sql#L38) |
| `ledger_entries` | [server/src/db.js:1689](../server/src/db.js#L1689) | [server/migrations/034_finance.sql:92](../server/migrations/034_finance.sql#L92) |
| `management_companies` | — | [server/migrations/062_management_companies.sql:6](../server/migrations/062_management_companies.sql#L6) |
| `management_company_members` | — | [server/migrations/062_management_companies.sql:17](../server/migrations/062_management_companies.sql#L17) |
| `management_company_sites` | — | [server/migrations/062_management_companies.sql:27](../server/migrations/062_management_companies.sql#L27) |
| `meter_billing_lines` | — | [server/migrations/061_metering.sql:138](../server/migrations/061_metering.sql#L138) |
| `meter_billings` | — | [server/migrations/061_metering.sql:95](../server/migrations/061_metering.sql#L95) |
| `meter_reading_photos` | — | [server/migrations/070_meter_reading_photos.sql:4](../server/migrations/070_meter_reading_photos.sql#L4) |
| `meter_readings` | — | [server/migrations/061_metering.sql:53](../server/migrations/061_metering.sql#L53) |
| `meters` | — | [server/migrations/061_metering.sql:9](../server/migrations/061_metering.sql#L9) |
| `module_requests` | [server/src/db.js:1192](../server/src/db.js#L1192) | [server/migrations/030_module_requests.sql:6](../server/migrations/030_module_requests.sql#L6) |
| `neighbor_post_reports` | — | [server/migrations/064_neighbor_board.sql:28](../server/migrations/064_neighbor_board.sql#L28) |
| `neighbor_posts` | — | [server/migrations/064_neighbor_board.sql:7](../server/migrations/064_neighbor_board.sql#L7) |
| `notification_preferences` | [server/src/db.js:1488](../server/src/db.js#L1488) | [server/migrations/032_announcements.sql:106](../server/migrations/032_announcements.sql#L106) |
| `ota_update_job_devices` | [server/src/db.js:696](../server/src/db.js#L696) | — |
| `ota_update_jobs` | [server/src/db.js:681](../server/src/db.js#L681) | — |
| `payment_notices` | — | [server/migrations/066_payment_notices.sql:5](../server/migrations/066_payment_notices.sql#L5) |
| `payment_provider_settings` | — | [server/migrations/065_device_integrations.sql:4](../server/migrations/065_device_integrations.sql#L4) |
| `pending_registrations` | [server/src/db.js:1008](../server/src/db.js#L1008) | [server/migrations/028_pending_registrations.sql:6](../server/migrations/028_pending_registrations.sql#L6) |
| `person_invitations` | — | [server/migrations/058_team_and_invitations.sql:94](../server/migrations/058_team_and_invitations.sql#L94) |
| `plate_blacklist` | — | [server/migrations/073_plate_recognition.sql:35](../server/migrations/073_plate_recognition.sql#L35) |
| `plate_decisions` | — | [server/migrations/073_plate_recognition.sql:81](../server/migrations/073_plate_recognition.sql#L81) |
| `plate_events` | — | [server/migrations/065_device_integrations.sql:52](../server/migrations/065_device_integrations.sql#L52) |
| `plate_gate_settings` | — | [server/migrations/073_plate_recognition.sql:57](../server/migrations/073_plate_recognition.sql#L57) |
| `plate_guest_permits` | — | [server/migrations/073_plate_recognition.sql:5](../server/migrations/073_plate_recognition.sql#L5) |
| `platform_backfills` | [server/src/db.js:1326](../server/src/db.js#L1326) | [server/migrations/031_people_and_apartments.sql:122](../server/migrations/031_people_and_apartments.sql#L122) |
| `platform_rule_values` | — | [server/migrations/053_platform_rules.sql:13](../server/migrations/053_platform_rules.sql#L13) |
| `platform_settings` | [server/src/db.js:1540](../server/src/db.js#L1540) | [server/migrations/033_site_applications.sql:44](../server/migrations/033_site_applications.sql#L44) |
| `push_devices` | — | [server/migrations/041_push.sql:13](../server/migrations/041_push.sql#L13) |
| `push_outbox` | — | [server/migrations/041_push.sql:41](../server/migrations/041_push.sql#L41) |
| `qr_access_tokens` | [server/src/db.js:851](../server/src/db.js#L851) | [server/migrations/011_qr_access_tokens.sql:7](../server/migrations/011_qr_access_tokens.sql#L7) |
| `receipt_counters` | — | [server/migrations/040_finance_4b.sql:115](../server/migrations/040_finance_4b.sql#L115) |
| `receipt_print_events` | — | [server/migrations/040_finance_4b.sql:167](../server/migrations/040_finance_4b.sql#L167) |
| `receipts` | — | [server/migrations/040_finance_4b.sql:124](../server/migrations/040_finance_4b.sql#L124) |
| `reservation_areas` | — | [server/migrations/043_reservation.sql:12](../server/migrations/043_reservation.sql#L12) |
| `reservations` | — | [server/migrations/043_reservation.sql:65](../server/migrations/043_reservation.sql#L65) |
| `site_applications` | [server/src/db.js:1553](../server/src/db.js#L1553) | [server/migrations/033_site_applications.sql:57](../server/migrations/033_site_applications.sql#L57) |
| `site_blocks` | [server/src/db.js:750](../server/src/db.js#L750) | [server/migrations/006_site_structure_and_access.sql:56](../server/migrations/006_site_structure_and_access.sql#L56) |
| `site_contracts` | — | [server/migrations/049_contracts.sql:57](../server/migrations/049_contracts.sql#L57) |
| `site_directory_contacts` | — | [server/migrations/058_team_and_invitations.sql:57](../server/migrations/058_team_and_invitations.sql#L57) |
| `site_doors` | [server/src/db.js:793](../server/src/db.js#L793) | [server/migrations/006_site_structure_and_access.sql:85](../server/migrations/006_site_structure_and_access.sql#L85) |
| `site_drive_connections` | — | [server/migrations/060_drive_storage.sql:7](../server/migrations/060_drive_storage.sql#L7) |
| `site_join_tokens` | [server/src/db.js:1049](../server/src/db.js#L1049) | [server/migrations/016_membership_v2_schema.sql:50](../server/migrations/016_membership_v2_schema.sql#L50) |
| `site_manager_invitations` | [server/src/db.js:1112](../server/src/db.js#L1112) | [server/migrations/023_site_manager_invitations.sql:4](../server/migrations/023_site_manager_invitations.sql#L4) |
| `site_manager_sites` | [server/src/db.js:738](../server/src/db.js#L738) | [server/migrations/006_site_structure_and_access.sql:46](../server/migrations/006_site_structure_and_access.sql#L46) |
| `site_memberships` | [server/src/db.js:1021](../server/src/db.js#L1021) | [server/migrations/016_membership_v2_schema.sql:20](../server/migrations/016_membership_v2_schema.sql#L20) |
| `site_menu_layouts` | — | [server/migrations/102_site_menu_layout.sql:8](../server/migrations/102_site_menu_layout.sql#L8) |
| `site_modules` | [server/src/db.js:1142](../server/src/db.js#L1142) | [server/migrations/029_platform_modules.sql:23](../server/migrations/029_platform_modules.sql#L23) |
| `site_people` | [server/src/db.js:1214](../server/src/db.js#L1214) | [server/migrations/031_people_and_apartments.sql:9](../server/migrations/031_people_and_apartments.sql#L9) |
| `site_subscriptions` | [server/src/db.js:1524](../server/src/db.js#L1524) | [server/migrations/033_site_applications.sql:28](../server/migrations/033_site_applications.sql#L28) |
| `site_team_duties` | — | [server/migrations/058_team_and_invitations.sql:8](../server/migrations/058_team_and_invitations.sql#L8) |
| `sites` | [server/src/db.js:366](../server/src/db.js#L366) | [server/migrations/003_sites_devices.sql:17](../server/migrations/003_sites_devices.sql#L17) |
| `sms_login_codes` | — | [server/migrations/063_notify_channels.sql:2](../server/migrations/063_notify_channels.sql#L2) |
| `subscription_plans` | [server/src/db.js:1505](../server/src/db.js#L1505) | [server/migrations/033_site_applications.sql:9](../server/migrations/033_site_applications.sql#L9) |
| `survey_votes` | — | [server/migrations/044_survey.sql:60](../server/migrations/044_survey.sql#L60) |
| `surveys` | — | [server/migrations/044_survey.sql:12](../server/migrations/044_survey.sql#L12) |
| `user_consents` | [server/src/db.js:1865](../server/src/db.js#L1865) | [server/migrations/035_platform_services.sql:10](../server/migrations/035_platform_services.sql#L10) |
| `user_oauth_identities` | — | [server/migrations/076_oauth_identities.sql:2](../server/migrations/076_oauth_identities.sql#L2) |
| `users` | — | [server/migrations/001_init.sql:19](../server/migrations/001_init.sql#L19) |
| `vehicles` | [server/src/db.js:1310](../server/src/db.js#L1310) | [server/migrations/031_people_and_apartments.sql:106](../server/migrations/031_people_and_apartments.sql#L106) |
| `visitor_entries` | — | [server/migrations/045_visitor_log.sql:11](../server/migrations/045_visitor_log.sql#L11) |
| `web_push_subscriptions` | — | [server/migrations/063_notify_channels.sql:13](../server/migrations/063_notify_channels.sql#L13) |
| `work_item_attachments` | — | [server/migrations/047_work_attachments.sql:14](../server/migrations/047_work_attachments.sql#L14) |
| `work_item_events` | — | [server/migrations/042_work_tracking.sql:103](../server/migrations/042_work_tracking.sql#L103) |
| `work_items` | — | [server/migrations/042_work_tracking.sql:12](../server/migrations/042_work_tracking.sql#L12) |

## Ek E — Kaynak dosya kapsamı

1068 kaynak dosyanın **244**'i en az bir arıza girişine bağlı, **1**'i yalnız dosya haritasında, **823**'i klavuzda hiç geçmiyor. Bir dosya hiç geçmiyorsa onunla ilgili arızayı `--where` ile arayın.

| Dosya | Satır | Bağlı girişler | Dosya haritası |
| --- | --- | --- | --- |
| [cihaz_dene/app.py](../cihaz_dene/app.py) | 320 | [arac-cihaz-dene-durum-bos](ariza-klavuzu/50-arac-test-ve-surec.md#arac-cihaz-dene-durum-bos), [arac-cihaz-dene-baglanti](ariza-klavuzu/50-arac-test-ve-surec.md#arac-cihaz-dene-baglanti) | 40-cihaz-yazilimi, 50-arac-test-ve-surec |
| [cihaz_kontrol/include/admin_pin.h](../cihaz_kontrol/include/admin_pin.h) | 216 | [cihaz-admin-pin-tanimsiz-reddedildi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-admin-pin-tanimsiz-reddedildi), [cihaz-admin-pin-kilitli](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-admin-pin-kilitli), [ekran-pin-hatali-kilitli-nopin](ariza-klavuzu/41-ekran-yazilimi.md#ekran-pin-hatali-kilitli-nopin) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/device_konfig.h](../cihaz_kontrol/include/device_konfig.h) | 79 | [cihaz-led-hizli-yanip-sonuyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-led-hizli-yanip-sonuyor), [cihaz-wifi-sifirlama-butonu](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-wifi-sifirlama-butonu), [cihaz-saat-ntp-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-saat-ntp-yok), [cihaz-gm60-baglanti-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-gm60-baglanti-yok), [cihaz-yerel-udp-cevap-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-udp-cevap-yok) +1 | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/display_protocol.h](../cihaz_kontrol/include/display_protocol.h) | 53 | [cihaz-ekran-bos-baglanti](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ekran-bos-baglanti), [ekran-uart-protokol-uyusmazligi](ariza-klavuzu/41-ekran-yazilimi.md#ekran-uart-protokol-uyusmazligi) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/display_uart.h](../cihaz_kontrol/include/display_uart.h) | 34 | [cihaz-ekran-bos-baglanti](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ekran-bos-baglanti), [ekran-uart-protokol-uyusmazligi](ariza-klavuzu/41-ekran-yazilimi.md#ekran-uart-protokol-uyusmazligi) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/gm60_scanner.h](../cihaz_kontrol/include/gm60_scanner.h) | 346 | [cihaz-gm60-baglanti-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-gm60-baglanti-yok), [cihaz-qr-okundu-kapi-acilmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-qr-okundu-kapi-acilmiyor), [cihaz-qr-offline-acilmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-qr-offline-acilmiyor), [akis-dinamik-qr-gm60](ariza-klavuzu/60-akislar.md#akis-dinamik-qr-gm60) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/mqtt_baglanti.h](../cihaz_kontrol/include/mqtt_baglanti.h) | 644 | [cihaz-saat-ntp-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-saat-ntp-yok), [cihaz-mqtt-rc-hatasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-rc-hatasi), [cihaz-mqtt-tls-hatasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-tls-hatasi), [cihaz-mqtt-kimlik-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-kimlik-yok), [cihaz-mqtt-yayin-basarisiz](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-yayin-basarisiz) +27 | 40-cihaz-yazilimi, 60-akislar |
| [cihaz_kontrol/include/offline_log.h](../cihaz_kontrol/include/offline_log.h) | 459 | [cihaz-mqtt-yayin-basarisiz](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-yayin-basarisiz), [cihaz-offline-log-senkronize-olmuyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-offline-log-senkronize-olmuyor), [cihaz-offline-log-dosya-sorunu](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-offline-log-dosya-sorunu), [akis-cevrimdisi-kapi-gunlukleri](ariza-klavuzu/60-akislar.md#akis-cevrimdisi-kapi-gunlukleri), [akis-pdf-ciktilari](ariza-klavuzu/61-akislar-devam.md#akis-pdf-ciktilari) | 40-cihaz-yazilimi, 60-akislar |
| [cihaz_kontrol/include/ota_guncelleme.h](../cihaz_kontrol/include/ota_guncelleme.h) | 711 | [cihaz-saat-ntp-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-saat-ntp-yok), [cihaz-mqtt-tls-hatasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-tls-hatasi), [cihaz-ota-guncelleme-baslamiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-guncelleme-baslamiyor), [cihaz-ota-manifest-hatasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-manifest-hatasi), [cihaz-ota-hedef-uyusmazligi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-hedef-uyusmazligi) +10 | 40-cihaz-yazilimi, 60-akislar |
| [cihaz_kontrol/include/ota_is_kimligi.h](../cihaz_kontrol/include/ota_is_kimligi.h) | 93 | [cihaz-ota-is-kimligi-yansimiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-is-kimligi-yansimiyor) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/qr_dogrulama.h](../cihaz_kontrol/include/qr_dogrulama.h) | 53 | [cihaz-qr-offline-acilmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-qr-offline-acilmiyor) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/role_kontrol.h](../cihaz_kontrol/include/role_kontrol.h) | 184 | [cihaz-role-acmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-role-acmiyor), [cihaz-role-acilista-tiklamasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-role-acilista-tiklamasi), [cihaz-seri-atolye-komutlari](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-seri-atolye-komutlari), [akis-bulut-kapi-acma](ariza-klavuzu/60-akislar.md#akis-bulut-kapi-acma) | 40-cihaz-yazilimi, 60-akislar |
| [cihaz_kontrol/include/tls_kok_sertifika.h](../cihaz_kontrol/include/tls_kok_sertifika.h) | 39 | [cihaz-mqtt-tls-hatasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-tls-hatasi), [cihaz-ota-manifest-hatasi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-manifest-hatasi), [cihaz-kok-sertifika-suresi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-kok-sertifika-suresi) | 40-cihaz-yazilimi |
| [cihaz_kontrol/include/wifi_baglanti.h](../cihaz_kontrol/include/wifi_baglanti.h) | 766 | [cekirdek-ble-izin-ve-tarama](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-izin-ve-tarama), [cekirdek-ble-baglanti-ve-wifi-listesi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-baglanti-ve-wifi-listesi), [cekirdek-ble-wifi-yazma-basarisiz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-wifi-yazma-basarisiz), [cihaz-wifi-baglanmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-wifi-baglanmiyor), [cihaz-led-hizli-yanip-sonuyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-led-hizli-yanip-sonuyor) +8 | 40-cihaz-yazilimi, 60-akislar, 61-akislar-devam |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h](../cihaz_kontrol/include/yerel_kapi_kontrol.h) | 578 | [cihaz-qr-offline-acilmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-qr-offline-acilmiyor), [cihaz-yerel-udp-cevap-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-udp-cevap-yok), [cihaz-yerel-udp-imza-reddi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-udp-imza-reddi), [cihaz-yerel-ozdeneme-basarisiz](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-ozdeneme-basarisiz), [cihaz-yerel-beacon-gelmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-beacon-gelmiyor) +2 | 40-cihaz-yazilimi, 60-akislar |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h](../cihaz_kontrol/include/yerel_kontrol_cekirdek.h) | 269 | [cihaz-yerel-udp-imza-reddi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-udp-imza-reddi), [cihaz-yerel-ozdeneme-basarisiz](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-yerel-ozdeneme-basarisiz) | 40-cihaz-yazilimi |
| [cihaz_kontrol/src/display_uart.cpp](../cihaz_kontrol/src/display_uart.cpp) | 245 | [cihaz-admin-pin-tanimsiz-reddedildi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-admin-pin-tanimsiz-reddedildi), [cihaz-admin-pin-kilitli](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-admin-pin-kilitli), [cihaz-ekran-bos-baglanti](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ekran-bos-baglanti), [cihaz-ekran-qr-yenilenmiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ekran-qr-yenilenmiyor), [ekran-pin-ekrani-tus-yanit-yok](ariza-klavuzu/41-ekran-yazilimi.md#ekran-pin-ekrani-tus-yanit-yok) +6 | 40-cihaz-yazilimi |
| [cihaz_kontrol/src/main.cpp](../cihaz_kontrol/src/main.cpp) | 530 | [cihaz-mqtt-kimlik-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-mqtt-kimlik-yok), [cihaz-ota-guncelleme-baslamiyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-guncelleme-baslamiyor), [cihaz-ota-sonrasi-geri-aldi](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ota-sonrasi-geri-aldi), [cihaz-watchdog-yeniden-basliyor](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-watchdog-yeniden-basliyor), [cihaz-gm60-baglanti-yok](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-gm60-baglanti-yok) +13 | 40-cihaz-yazilimi |
| [company_qr_tool/app.py](../company_qr_tool/app.py) | 4187 | [ekran-surum-derleme-yukleme](ariza-klavuzu/41-ekran-yazilimi.md#ekran-surum-derleme-yukleme), [ekran-surum-uyusmazligi](ariza-klavuzu/41-ekran-yazilimi.md#ekran-surum-uyusmazligi), [arac-sunucu-401](ariza-klavuzu/50-arac-test-ve-surec.md#arac-sunucu-401), [arac-anahtar-tanimli-degil](ariza-klavuzu/50-arac-test-ve-surec.md#arac-anahtar-tanimli-degil), [arac-http-anahtar-gonderilmiyor](ariza-klavuzu/50-arac-test-ve-surec.md#arac-http-anahtar-gonderilmiyor) +16 | 50-arac-test-ve-surec |
| [company_qr_tool/ui_kit.py](../company_qr_tool/ui_kit.py) | 1549 | — | — |
| [deploy/remote_audit.sh](../deploy/remote_audit.sh) | 24 | [altyapi-komut-rehberi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-komut-rehberi), [altyapi-deploy-dogrulama-sonuclari](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-deploy-dogrulama-sonuclari), [altyapi-disk-dolu-yedekler](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-disk-dolu-yedekler) | 20-sunucu-altyapi-ve-yayin |
| [deploy/remote_deploy.sh](../deploy/remote_deploy.sh) | 170 | [altyapi-geri-alma-ve-yedek](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-geri-alma-ve-yedek), [altyapi-deploy-prepare-basarisiz](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-deploy-prepare-basarisiz), [altyapi-deploy-activate-geri-alma](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-deploy-activate-geri-alma), [altyapi-company-api-key-uretildi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-company-api-key-uretildi), [altyapi-disk-dolu-yedekler](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-disk-dolu-yedekler) +2 | 20-sunucu-altyapi-ve-yayin |
| [deploy/remote_rehearse_schema.sh](../deploy/remote_rehearse_schema.sh) | 202 | — | — |
| [deploy/remote_verify.sh](../deploy/remote_verify.sh) | 114 | [altyapi-komut-rehberi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-komut-rehberi), [altyapi-deploy-dogrulama-sonuclari](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-deploy-dogrulama-sonuclari), [altyapi-company-api-key-uretildi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-company-api-key-uretildi) | 20-sunucu-altyapi-ve-yayin |
| [ekran_yazilimi/include/config.h](../ekran_yazilimi/include/config.h) | 54 | [ekran-siyah-bos](ariza-klavuzu/41-ekran-yazilimi.md#ekran-siyah-bos), [ekran-dokunmatik-yok](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunmatik-yok), [ekran-uart-protokol-uyusmazligi](ariza-klavuzu/41-ekran-yazilimi.md#ekran-uart-protokol-uyusmazligi), [ekran-surum-uyusmazligi](ariza-klavuzu/41-ekran-yazilimi.md#ekran-surum-uyusmazligi) | 40-cihaz-yazilimi, 41-ekran-yazilimi |
| [ekran_yazilimi/include/cst816d_touch.h](../ekran_yazilimi/include/cst816d_touch.h) | 94 | [ekran-dokunmatik-yok](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunmatik-yok), [ekran-dokunma-yanlis-koordinat](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunma-yanlis-koordinat), [ekran-dokunma-tekrar-tetikleme](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunma-tekrar-tetikleme) | 40-cihaz-yazilimi, 41-ekran-yazilimi |
| [ekran_yazilimi/include/display_protocol.h](../ekran_yazilimi/include/display_protocol.h) | 53 | [ekran-uart-protokol-uyusmazligi](ariza-klavuzu/41-ekran-yazilimi.md#ekran-uart-protokol-uyusmazligi) | 41-ekran-yazilimi |
| [ekran_yazilimi/include/ScreenManager.h](../ekran_yazilimi/include/ScreenManager.h) | 174 | [cihaz-ekran-bos-baglanti](ariza-klavuzu/40-cihaz-yazilimi.md#cihaz-ekran-bos-baglanti), [ekran-yonetici-oturum-20sn](ariza-klavuzu/41-ekran-yazilimi.md#ekran-yonetici-oturum-20sn), [ekran-qr-gorunmuyor](ariza-klavuzu/41-ekran-yazilimi.md#ekran-qr-gorunmuyor), [ekran-ana-kart-sessiz](ariza-klavuzu/41-ekran-yazilimi.md#ekran-ana-kart-sessiz) | 40-cihaz-yazilimi, 41-ekran-yazilimi |
| [ekran_yazilimi/src/main.cpp](../ekran_yazilimi/src/main.cpp) | 248 | [ekran-yeniden-baslama-dongusu](ariza-klavuzu/41-ekran-yazilimi.md#ekran-yeniden-baslama-dongusu), [ekran-dokunmatik-yok](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunmatik-yok), [ekran-dokunma-yanlis-koordinat](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunma-yanlis-koordinat), [ekran-dokunma-tekrar-tetikleme](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunma-tekrar-tetikleme), [ekran-fiziksel-dugme-kapi-acmaz](ariza-klavuzu/41-ekran-yazilimi.md#ekran-fiziksel-dugme-kapi-acmaz) +5 | 40-cihaz-yazilimi, 41-ekran-yazilimi |
| [ekran_yazilimi/src/ScreenManager.cpp](../ekran_yazilimi/src/ScreenManager.cpp) | 1164 | [ekran-siyah-bos](ariza-klavuzu/41-ekran-yazilimi.md#ekran-siyah-bos), [ekran-dokunma-yanlis-koordinat](ariza-klavuzu/41-ekran-yazilimi.md#ekran-dokunma-yanlis-koordinat), [ekran-pin-ekrani-tus-yanit-yok](ariza-klavuzu/41-ekran-yazilimi.md#ekran-pin-ekrani-tus-yanit-yok), [ekran-pin-hatali-kilitli-nopin](ariza-klavuzu/41-ekran-yazilimi.md#ekran-pin-hatali-kilitli-nopin), [ekran-yonetici-oturum-20sn](ariza-klavuzu/41-ekran-yazilimi.md#ekran-yonetici-oturum-20sn) +10 | 40-cihaz-yazilimi, 41-ekran-yazilimi |
| [lib/app.dart](../lib/app.dart) | 702 | [cekirdek-api-adresi-yanlis](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-api-adresi-yanlis), [cekirdek-internet-yok-ekrani](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-internet-yok-ekrani), [cekirdek-acilis-splash-takili](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-acilis-splash-takili), [cekirdek-giris-sonrasi-ekran-bos](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-giris-sonrasi-ekran-bos), [cekirdek-yanlis-rol-menu](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yanlis-rol-menu) +11 | 30-uygulama-cekirdek |
| [lib/brand/brand_scope.dart](../lib/brand/brand_scope.dart) | 47 | — | — |
| [lib/brand/brand_theme.dart](../lib/brand/brand_theme.dart) | 178 | — | — |
| [lib/brand/gude_logo_animated.dart](../lib/brand/gude_logo_animated.dart) | 425 | — | — |
| [lib/brand/gude_logo_data.dart](../lib/brand/gude_logo_data.dart) | 98 | — | — |
| [lib/brand/gude_logo.dart](../lib/brand/gude_logo.dart) | 200 | — | — |
| [lib/brand/logo_model.dart](../lib/brand/logo_model.dart) | 75 | — | — |
| [lib/brand/logo_palette.dart](../lib/brand/logo_palette.dart) | 74 | — | — |
| [lib/config/app_config.dart](../lib/config/app_config.dart) | 21 | [cekirdek-api-adresi-yanlis](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-api-adresi-yanlis), [surec-surum-gosterimi](ariza-klavuzu/50-arac-test-ve-surec.md#surec-surum-gosterimi) | 30-uygulama-cekirdek, 50-arac-test-ve-surec |
| [lib/data/turkey_cities_districts.dart](../lib/data/turkey_cities_districts.dart) | 1151 | [cekirdek-il-ilce-listesi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-il-ilce-listesi) | 30-uygulama-cekirdek |
| [lib/l10n/gen/app_localizations_en.dart](../lib/l10n/gen/app_localizations_en.dart) | 47 | — | — |
| [lib/l10n/gen/app_localizations_tr.dart](../lib/l10n/gen/app_localizations_tr.dart) | 47 | — | — |
| [lib/l10n/gen/app_localizations.dart](../lib/l10n/gen/app_localizations.dart) | 207 | — | — |
| [lib/main.dart](../lib/main.dart) | 54 | [cekirdek-tema-tercihi-kaydedilmiyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-tema-tercihi-kaydedilmiyor), [cekirdek-uygulama-baslangic-yon-kilidi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-uygulama-baslangic-yon-kilidi) | 30-uygulama-cekirdek |
| [lib/menu.dart](../lib/menu.dart) | 2 | [ui-menu-yanlis-rol](ariza-klavuzu/31-uygulama-arayuz.md#ui-menu-yanlis-rol), [bilesen-yan-menu-ogeleri](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-yan-menu-ogeleri) | 31-uygulama-arayuz, 32-uygulama-bilesenler |
| [lib/models/access_audit_label.dart](../lib/models/access_audit_label.dart) | 79 | — | — |
| [lib/models/account_client_error.dart](../lib/models/account_client_error.dart) | 118 | — | — |
| [lib/models/account_data_export.dart](../lib/models/account_data_export.dart) | 79 | — | — |
| [lib/models/account_deletion.dart](../lib/models/account_deletion.dart) | 132 | — | — |
| [lib/models/account_platform_config.dart](../lib/models/account_platform_config.dart) | 325 | — | — |
| [lib/models/announcement.dart](../lib/models/announcement.dart) | 870 | — | — |
| [lib/models/annual_report.dart](../lib/models/annual_report.dart) | 178 | — | — |
| [lib/models/apartment_crm.dart](../lib/models/apartment_crm.dart) | 269 | — | — |
| [lib/models/apartment_household.dart](../lib/models/apartment_household.dart) | 119 | — | — |
| [lib/models/apartment_management.dart](../lib/models/apartment_management.dart) | 577 | — | — |
| [lib/models/apartment_member_record.dart](../lib/models/apartment_member_record.dart) | 96 | [model-kimlik-id-user-code-site-code](ariza-klavuzu/33-uygulama-modeller.md#model-kimlik-id-user-code-site-code), [model-daire-uyelik-ve-site-yapisi](ariza-klavuzu/33-uygulama-modeller.md#model-daire-uyelik-ve-site-yapisi) | 33-uygulama-modeller |
| [lib/models/apartment_pin_issue.dart](../lib/models/apartment_pin_issue.dart) | 49 | — | — |
| [lib/models/apartment_record.dart](../lib/models/apartment_record.dart) | 84 | [model-tip-hatasi-beklenen-formatta-degil](ariza-klavuzu/33-uygulama-modeller.md#model-tip-hatasi-beklenen-formatta-degil), [model-daire-uyelik-ve-site-yapisi](ariza-klavuzu/33-uygulama-modeller.md#model-daire-uyelik-ve-site-yapisi) | 33-uygulama-modeller |
| [lib/models/apartment_vehicles.dart](../lib/models/apartment_vehicles.dart) | 60 | — | — |
| [lib/models/app_config.dart](../lib/models/app_config.dart) | 99 | — | — |
| [lib/models/audit_log.dart](../lib/models/audit_log.dart) | 375 | — | — |
| [lib/models/bank_import.dart](../lib/models/bank_import.dart) | 201 | — | — |
| [lib/models/budget_models.dart](../lib/models/budget_models.dart) | 170 | — | — |
| [lib/models/bulk_import.dart](../lib/models/bulk_import.dart) | 1044 | — | — |
| [lib/models/cash_models.dart](../lib/models/cash_models.dart) | 497 | — | — |
| [lib/models/contract_models.dart](../lib/models/contract_models.dart) | 654 | — | — |
| [lib/models/decision_models.dart](../lib/models/decision_models.dart) | 541 | — | — |
| [lib/models/device_connectivity_log.dart](../lib/models/device_connectivity_log.dart) | 105 | [model-tarih-saat-yanlis](ariza-klavuzu/33-uygulama-modeller.md#model-tarih-saat-yanlis), [model-baglanti-gunlugu-sure-ve-sebep](ariza-klavuzu/33-uygulama-modeller.md#model-baglanti-gunlugu-sure-ve-sebep) | 33-uygulama-modeller |
| [lib/models/device_page.dart](../lib/models/device_page.dart) | 23 | [model-sayfali-liste-bos-yarim](ariza-klavuzu/33-uygulama-modeller.md#model-sayfali-liste-bos-yarim) | 33-uygulama-modeller |
| [lib/models/device_record.dart](../lib/models/device_record.dart) | 158 | [model-kimlik-id-user-code-site-code](ariza-klavuzu/33-uygulama-modeller.md#model-kimlik-id-user-code-site-code), [model-cihaz-kaydi-donanim-ve-ota](ariza-klavuzu/33-uygulama-modeller.md#model-cihaz-kaydi-donanim-ve-ota) | 33-uygulama-modeller |
| [lib/models/document_models.dart](../lib/models/document_models.dart) | 843 | — | — |
| [lib/models/document_upload_models.dart](../lib/models/document_upload_models.dart) | 261 | — | — |
| [lib/models/door_access_log_record.dart](../lib/models/door_access_log_record.dart) | 161 | [model-tarih-saat-yanlis](ariza-klavuzu/33-uygulama-modeller.md#model-tarih-saat-yanlis), [model-gecis-gunlugu-etiketleri](ariza-klavuzu/33-uygulama-modeller.md#model-gecis-gunlugu-etiketleri) | 33-uygulama-modeller |
| [lib/models/door_permission_record.dart](../lib/models/door_permission_record.dart) | 270 | [model-kimlik-id-user-code-site-code](ariza-klavuzu/33-uygulama-modeller.md#model-kimlik-id-user-code-site-code), [model-kapi-izin-matrisi-hatali](ariza-klavuzu/33-uygulama-modeller.md#model-kapi-izin-matrisi-hatali) | 33-uygulama-modeller |
| [lib/models/door_record.dart](../lib/models/door_record.dart) | 220 | [cekirdek-kapi-ac-istemci-reddi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kapi-ac-istemci-reddi), [cekirdek-kapi-ac-konum-zorunlu](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kapi-ac-konum-zorunlu), [cekirdek-konum-mesafe-disi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-konum-mesafe-disi), [cekirdek-karekod-ile-kapi-acilmiyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-karekod-ile-kapi-acilmiyor), [cekirdek-json-ayristirma-hatasi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-json-ayristirma-hatasi) +2 | 30-uygulama-cekirdek, 33-uygulama-modeller |
| [lib/models/door_runtime_status.dart](../lib/models/door_runtime_status.dart) | 146 | [cekirdek-yerel-token-yok](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yerel-token-yok), [cekirdek-kapi-durumu-cevrimdisi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kapi-durumu-cevrimdisi), [model-kapi-anlik-durum-komut-verilemiyor](ariza-klavuzu/33-uygulama-modeller.md#model-kapi-anlik-durum-komut-verilemiyor) | 30-uygulama-cekirdek, 33-uygulama-modeller |
| [lib/models/enforcement_models.dart](../lib/models/enforcement_models.dart) | 99 | — | — |
| [lib/models/expense_analysis.dart](../lib/models/expense_analysis.dart) | 237 | — | — |
| [lib/models/expense_models.dart](../lib/models/expense_models.dart) | 470 | — | — |
| [lib/models/feedback_models.dart](../lib/models/feedback_models.dart) | 293 | — | — |
| [lib/models/finance_4b.dart](../lib/models/finance_4b.dart) | 261 | — | — |
| [lib/models/finance_charts.dart](../lib/models/finance_charts.dart) | 193 | — | — |
| [lib/models/finance_funds.dart](../lib/models/finance_funds.dart) | 183 | — | — |
| [lib/models/finance_home.dart](../lib/models/finance_home.dart) | 139 | — | — |
| [lib/models/finance_opening.dart](../lib/models/finance_opening.dart) | 68 | — | — |
| [lib/models/finance.dart](../lib/models/finance.dart) | 1690 | — | — |
| [lib/models/fund_models.dart](../lib/models/fund_models.dart) | 325 | — | — |
| [lib/models/guest_pass.dart](../lib/models/guest_pass.dart) | 49 | [model-tarih-saat-yanlis](ariza-klavuzu/33-uygulama-modeller.md#model-tarih-saat-yanlis), [model-misafir-linki-gecersiz](ariza-klavuzu/33-uygulama-modeller.md#model-misafir-linki-gecersiz) | 33-uygulama-modeller |
| [lib/models/history_item.dart](../lib/models/history_item.dart) | 212 | — | — |
| [lib/models/join_request_record.dart](../lib/models/join_request_record.dart) | 112 | [model-katilim-istegi-ve-qr-bilgisi](ariza-klavuzu/33-uygulama-modeller.md#model-katilim-istegi-ve-qr-bilgisi) | 33-uygulama-modeller |
| [lib/models/late_fee_models.dart](../lib/models/late_fee_models.dart) | 405 | — | — |
| [lib/models/legal_document.dart](../lib/models/legal_document.dart) | 252 | — | — |
| [lib/models/local_door_access.dart](../lib/models/local_door_access.dart) | 63 | [cekirdek-yerel-token-yok](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yerel-token-yok), [model-tarih-saat-yanlis](ariza-klavuzu/33-uygulama-modeller.md#model-tarih-saat-yanlis), [model-yerel-kapi-onbellek-kullanilmiyor](ariza-klavuzu/33-uygulama-modeller.md#model-yerel-kapi-onbellek-kullanilmiyor) | 30-uygulama-cekirdek, 33-uygulama-modeller |
| [lib/models/managed_user_account.dart](../lib/models/managed_user_account.dart) | 71 | [model-tip-hatasi-beklenen-formatta-degil](ariza-klavuzu/33-uygulama-modeller.md#model-tip-hatasi-beklenen-formatta-degil), [model-rol-yanlis-gorunuyor](ariza-klavuzu/33-uygulama-modeller.md#model-rol-yanlis-gorunuyor), [model-sakin-pasif-gorunuyor](ariza-klavuzu/33-uygulama-modeller.md#model-sakin-pasif-gorunuyor), [model-kullanici-hesabi-onay-ve-dogrulama](ariza-klavuzu/33-uygulama-modeller.md#model-kullanici-hesabi-onay-ve-dogrulama) | 33-uygulama-modeller |
| [lib/models/managed_user_page.dart](../lib/models/managed_user_page.dart) | 37 | [model-sayfali-liste-bos-yarim](ariza-klavuzu/33-uygulama-modeller.md#model-sayfali-liste-bos-yarim) | 33-uygulama-modeller |
| [lib/models/management_terms.dart](../lib/models/management_terms.dart) | 266 | — | — |
| [lib/models/management_type.dart](../lib/models/management_type.dart) | 35 | — | — |
| [lib/models/manager_contact.dart](../lib/models/manager_contact.dart) | 53 | — | — |
| [lib/models/menu_layout.dart](../lib/models/menu_layout.dart) | 138 | — | — |
| [lib/models/meter_field_models.dart](../lib/models/meter_field_models.dart) | 165 | — | — |
| [lib/models/meter_models.dart](../lib/models/meter_models.dart) | 310 | — | — |
| [lib/models/module_request.dart](../lib/models/module_request.dart) | 138 | — | — |
| [lib/models/neighbor_post.dart](../lib/models/neighbor_post.dart) | 67 | — | — |
| [lib/models/payment_info.dart](../lib/models/payment_info.dart) | 182 | — | — |
| [lib/models/payment_notice.dart](../lib/models/payment_notice.dart) | 303 | — | — |
| [lib/models/person_record.dart](../lib/models/person_record.dart) | 272 | — | — |
| [lib/models/plate_audit_label.dart](../lib/models/plate_audit_label.dart) | 20 | — | — |
| [lib/models/platform_module.dart](../lib/models/platform_module.dart) | 407 | — | — |
| [lib/models/platform_rule.dart](../lib/models/platform_rule.dart) | 436 | — | — |
| [lib/models/push_models.dart](../lib/models/push_models.dart) | 295 | — | — |
| [lib/models/receipt_models.dart](../lib/models/receipt_models.dart) | 348 | — | — |
| [lib/models/reminder_models.dart](../lib/models/reminder_models.dart) | 326 | — | — |
| [lib/models/report_models.dart](../lib/models/report_models.dart) | 711 | — | — |
| [lib/models/reservation_models.dart](../lib/models/reservation_models.dart) | 1023 | — | — |
| [lib/models/residency_log.dart](../lib/models/residency_log.dart) | 99 | — | — |
| [lib/models/residency_relation.dart](../lib/models/residency_relation.dart) | 61 | — | — |
| [lib/models/site_application.dart](../lib/models/site_application.dart) | 392 | — | — |
| [lib/models/site_block_record.dart](../lib/models/site_block_record.dart) | 28 | [model-daire-uyelik-ve-site-yapisi](ariza-klavuzu/33-uygulama-modeller.md#model-daire-uyelik-ve-site-yapisi) | 33-uygulama-modeller |
| [lib/models/site_join_info.dart](../lib/models/site_join_info.dart) | 89 | [model-katilim-istegi-ve-qr-bilgisi](ariza-klavuzu/33-uygulama-modeller.md#model-katilim-istegi-ve-qr-bilgisi) | 33-uygulama-modeller |
| [lib/models/site_join_token_record.dart](../lib/models/site_join_token_record.dart) | 48 | [model-katilim-istegi-ve-qr-bilgisi](ariza-klavuzu/33-uygulama-modeller.md#model-katilim-istegi-ve-qr-bilgisi) | 33-uygulama-modeller |
| [lib/models/site_manager_record.dart](../lib/models/site_manager_record.dart) | 106 | [model-yonetici-listesi-ve-davetler](ariza-klavuzu/33-uygulama-modeller.md#model-yonetici-listesi-ve-davetler) | 33-uygulama-modeller |
| [lib/models/site_page.dart](../lib/models/site_page.dart) | 37 | [model-sayfali-liste-bos-yarim](ariza-klavuzu/33-uygulama-modeller.md#model-sayfali-liste-bos-yarim) | 33-uygulama-modeller |
| [lib/models/site_record.dart](../lib/models/site_record.dart) | 248 | [model-tarih-saat-yanlis](ariza-klavuzu/33-uygulama-modeller.md#model-tarih-saat-yanlis), [model-site-alan-varsayilanlari](ariza-klavuzu/33-uygulama-modeller.md#model-site-alan-varsayilanlari), [model-site-silme-durumu-etiketi](ariza-klavuzu/33-uygulama-modeller.md#model-site-silme-durumu-etiketi), [model-kimlik-id-user-code-site-code](ariza-klavuzu/33-uygulama-modeller.md#model-kimlik-id-user-code-site-code) | 33-uygulama-modeller |
| [lib/models/site_residents_tree_record.dart](../lib/models/site_residents_tree_record.dart) | 186 | [model-kimlik-id-user-code-site-code](ariza-klavuzu/33-uygulama-modeller.md#model-kimlik-id-user-code-site-code), [model-sakinler-agaci-yarim](ariza-klavuzu/33-uygulama-modeller.md#model-sakinler-agaci-yarim), [model-sakin-pasif-gorunuyor](ariza-klavuzu/33-uygulama-modeller.md#model-sakin-pasif-gorunuyor) | 33-uygulama-modeller |
| [lib/models/site_structure_record.dart](../lib/models/site_structure_record.dart) | 34 | [model-tip-hatasi-beklenen-formatta-degil](ariza-klavuzu/33-uygulama-modeller.md#model-tip-hatasi-beklenen-formatta-degil), [model-daire-uyelik-ve-site-yapisi](ariza-klavuzu/33-uygulama-modeller.md#model-daire-uyelik-ve-site-yapisi) | 33-uygulama-modeller |
| [lib/models/staff_role_record.dart](../lib/models/staff_role_record.dart) | 64 | — | — |
| [lib/models/subscription_request_page.dart](../lib/models/subscription_request_page.dart) | 23 | [model-sayfali-liste-bos-yarim](ariza-klavuzu/33-uygulama-modeller.md#model-sayfali-liste-bos-yarim) | 33-uygulama-modeller |
| [lib/models/subscription_request.dart](../lib/models/subscription_request.dart) | 28 | [model-kullanici-hesabi-onay-ve-dogrulama](ariza-klavuzu/33-uygulama-modeller.md#model-kullanici-hesabi-onay-ve-dogrulama) | 33-uygulama-modeller |
| [lib/models/super_user_account.dart](../lib/models/super_user_account.dart) | 28 | [model-kullanici-hesabi-onay-ve-dogrulama](ariza-klavuzu/33-uygulama-modeller.md#model-kullanici-hesabi-onay-ve-dogrulama) | 33-uygulama-modeller |
| [lib/models/survey_models.dart](../lib/models/survey_models.dart) | 501 | — | — |
| [lib/models/team.dart](../lib/models/team.dart) | 286 | — | — |
| [lib/models/user_role.dart](../lib/models/user_role.dart) | 19 | [cekirdek-yanlis-rol-menu](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yanlis-rol-menu), [model-rol-yanlis-gorunuyor](ariza-klavuzu/33-uygulama-modeller.md#model-rol-yanlis-gorunuyor) | 33-uygulama-modeller |
| [lib/models/user_session.dart](../lib/models/user_session.dart) | 87 | [cekirdek-acilista-oturum-yok](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-acilista-oturum-yok), [cekirdek-json-ayristirma-hatasi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-json-ayristirma-hatasi), [model-rol-yanlis-gorunuyor](ariza-klavuzu/33-uygulama-modeller.md#model-rol-yanlis-gorunuyor), [model-oturum-yerel-kopya-bozuk](ariza-klavuzu/33-uygulama-modeller.md#model-oturum-yerel-kopya-bozuk) | 30-uygulama-cekirdek, 33-uygulama-modeller |
| [lib/models/vehicle_record.dart](../lib/models/vehicle_record.dart) | 165 | — | — |
| [lib/models/visitor_log_models.dart](../lib/models/visitor_log_models.dart) | 346 | — | — |
| [lib/models/work_tracking_models.dart](../lib/models/work_tracking_models.dart) | 1234 | — | — |
| [lib/services/account_api.dart](../lib/services/account_api.dart) | 553 | — | — |
| [lib/services/account_export_share.dart](../lib/services/account_export_share.dart) | 194 | — | — |
| [lib/services/account_local_wipe.dart](../lib/services/account_local_wipe.dart) | 148 | — | — |
| [lib/services/adaptive_poller.dart](../lib/services/adaptive_poller.dart) | 141 | [cekirdek-kapi-durumu-cevrimdisi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kapi-durumu-cevrimdisi), [cekirdek-buyuk-yanit-yavas-arayuz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-buyuk-yanit-yavas-arayuz) | 30-uygulama-cekirdek |
| [lib/services/announcement_notifier.dart](../lib/services/announcement_notifier.dart) | 395 | — | — |
| [lib/services/annual_report_api.dart](../lib/services/annual_report_api.dart) | 64 | — | — |
| [lib/services/apartment_management_api.dart](../lib/services/apartment_management_api.dart) | 379 | — | — |
| [lib/services/api_exception.dart](../lib/services/api_exception.dart) | 60 | [cekirdek-oturum-kendiliginden-dusuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-hesap-pasif-oturum-kapandi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-hesap-pasif-oturum-kapandi), [cekirdek-hiz-siniri-cok-fazla-deneme](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-hiz-siniri-cok-fazla-deneme), [cekirdek-proxy-html-modem-mesaji](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-proxy-html-modem-mesaji) | 30-uygulama-cekirdek |
| [lib/services/app_config_service.dart](../lib/services/app_config_service.dart) | 103 | — | — |
| [lib/services/app_gate_state.dart](../lib/services/app_gate_state.dart) | 39 | — | — |
| [lib/services/app_version.dart](../lib/services/app_version.dart) | 207 | — | — |
| [lib/services/auth_api.dart](../lib/services/auth_api.dart) | 4910 | [cekirdek-sunucuya-baglanilamadi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-sunucuya-baglanilamadi), [cekirdek-api-adresi-yanlis](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-api-adresi-yanlis), [cekirdek-giris-sonrasi-ekran-bos](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-giris-sonrasi-ekran-bos), [cekirdek-oturum-kendiliginden-dusuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-sifre-degisince-oturum-kapandi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-sifre-degisince-oturum-kapandi) +37 | 30-uygulama-cekirdek, 60-akislar |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) | 4325 | [cekirdek-sunucuya-baglanilamadi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-sunucuya-baglanilamadi), [cekirdek-acilis-splash-takili](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-acilis-splash-takili), [cekirdek-giris-sonrasi-ekran-bos](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-giris-sonrasi-ekran-bos), [cekirdek-oturum-kendiliginden-dusuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-sifre-degisince-oturum-kapandi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-sifre-degisince-oturum-kapandi) +31 | 30-uygulama-cekirdek, 60-akislar |
| [lib/services/background_work.dart](../lib/services/background_work.dart) | 47 | [cekirdek-json-ayristirma-hatasi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-json-ayristirma-hatasi), [cekirdek-buyuk-yanit-yavas-arayuz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-buyuk-yanit-yavas-arayuz) | 30-uygulama-cekirdek |
| [lib/services/bank_amount.dart](../lib/services/bank_amount.dart) | 87 | — | — |
| [lib/services/bank_import_api.dart](../lib/services/bank_import_api.dart) | 307 | — | — |
| [lib/services/bank_statement_reader.dart](../lib/services/bank_statement_reader.dart) | 463 | — | — |
| [lib/services/ble_wifi_provision_service.dart](../lib/services/ble_wifi_provision_service.dart) | 539 | [cekirdek-ble-izin-ve-tarama](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-izin-ve-tarama), [cekirdek-ble-baglanti-ve-wifi-listesi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-baglanti-ve-wifi-listesi), [cekirdek-ble-wifi-yazma-basarisiz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-wifi-yazma-basarisiz), [akis-cihaz-sahiplenme-wifi-kurulum](ariza-klavuzu/61-akislar-devam.md#akis-cihaz-sahiplenme-wifi-kurulum) | 30-uygulama-cekirdek, 61-akislar-devam |
| [lib/services/brand_theme_api.dart](../lib/services/brand_theme_api.dart) | 77 | — | — |
| [lib/services/budget_api.dart](../lib/services/budget_api.dart) | 143 | — | — |
| [lib/services/bulk_api.dart](../lib/services/bulk_api.dart) | 678 | — | — |
| [lib/services/bulk_cell_safety.dart](../lib/services/bulk_cell_safety.dart) | 130 | — | — |
| [lib/services/bulk_choices.dart](../lib/services/bulk_choices.dart) | 71 | — | — |
| [lib/services/bulk_csv_codec.dart](../lib/services/bulk_csv_codec.dart) | 278 | — | — |
| [lib/services/bulk_export_renderer.dart](../lib/services/bulk_export_renderer.dart) | 192 | — | — |
| [lib/services/bulk_file_delivery.dart](../lib/services/bulk_file_delivery.dart) | 221 | — | — |
| [lib/services/bulk_file_parser.dart](../lib/services/bulk_file_parser.dart) | 202 | — | — |
| [lib/services/bulk_file_picker.dart](../lib/services/bulk_file_picker.dart) | 46 | — | — |
| [lib/services/bulk_formatting.dart](../lib/services/bulk_formatting.dart) | 92 | — | — |
| [lib/services/bulk_header_mapper.dart](../lib/services/bulk_header_mapper.dart) | 373 | — | — |
| [lib/services/bulk_login_name.dart](../lib/services/bulk_login_name.dart) | 99 | — | — |
| [lib/services/bulk_sheet_types.dart](../lib/services/bulk_sheet_types.dart) | 122 | — | — |
| [lib/services/bulk_template.dart](../lib/services/bulk_template.dart) | 385 | — | — |
| [lib/services/bulk_text_decoder.dart](../lib/services/bulk_text_decoder.dart) | 142 | — | — |
| [lib/services/bulk_xlsx_reader.dart](../lib/services/bulk_xlsx_reader.dart) | 764 | — | — |
| [lib/services/bulk_xlsx_writer.dart](../lib/services/bulk_xlsx_writer.dart) | 452 | — | — |
| [lib/services/cctv_api.dart](../lib/services/cctv_api.dart) | 334 | — | — |
| [lib/services/contract_api.dart](../lib/services/contract_api.dart) | 632 | — | — |
| [lib/services/crash_reporter.dart](../lib/services/crash_reporter.dart) | 660 | — | — |
| [lib/services/decision_book_api.dart](../lib/services/decision_book_api.dart) | 509 | — | — |
| [lib/services/deep_link_service.dart](../lib/services/deep_link_service.dart) | 362 | [cekirdek-kullanici-degisince-eski-veri](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kullanici-degisince-eski-veri), [cekirdek-deep-link-kisayol-calismiyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-deep-link-kisayol-calismiyor) | 30-uygulama-cekirdek |
| [lib/services/device_integrations_api.dart](../lib/services/device_integrations_api.dart) | 286 | — | — |
| [lib/services/document_api.dart](../lib/services/document_api.dart) | 1280 | — | — |
| [lib/services/document_download.dart](../lib/services/document_download.dart) | 294 | — | — |
| [lib/services/document_file_share.dart](../lib/services/document_file_share.dart) | 181 | — | — |
| [lib/services/document_picker.dart](../lib/services/document_picker.dart) | 113 | — | — |
| [lib/services/document_upload.dart](../lib/services/document_upload.dart) | 291 | — | — |
| [lib/services/door_module_gate.dart](../lib/services/door_module_gate.dart) | 42 | — | — |
| [lib/services/door_panel_requests.dart](../lib/services/door_panel_requests.dart) | 34 | — | — |
| [lib/services/door_widget_service.dart](../lib/services/door_widget_service.dart) | 623 | [cekirdek-api-adresi-yanlis](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-api-adresi-yanlis), [cekirdek-widget-bos-ya-da-giris-yapin](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-widget-bos-ya-da-giris-yapin), [cekirdek-widget-acma-sonuc-mesajlari](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-widget-acma-sonuc-mesajlari), [cekirdek-widget-kapi-gecisi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-widget-kapi-gecisi), [akis-ana-ekran-widget-kapi-acma](ariza-klavuzu/61-akislar-devam.md#akis-ana-ekran-widget-kapi-acma) | 30-uygulama-cekirdek |
| [lib/services/easy_view_service.dart](../lib/services/easy_view_service.dart) | 56 | — | — |
| [lib/services/equipment_api.dart](../lib/services/equipment_api.dart) | 432 | — | — |
| [lib/services/expense_attachments.dart](../lib/services/expense_attachments.dart) | 136 | — | — |
| [lib/services/feedback_api.dart](../lib/services/feedback_api.dart) | 391 | — | — |
| [lib/services/finance_4b_api.dart](../lib/services/finance_4b_api.dart) | 1697 | — | — |
| [lib/services/finance_4b_errors.dart](../lib/services/finance_4b_errors.dart) | 149 | — | — |
| [lib/services/finance_payment_api.dart](../lib/services/finance_payment_api.dart) | 188 | — | — |
| [lib/services/geofence_service.dart](../lib/services/geofence_service.dart) | 261 | [cekirdek-kapi-ac-konum-zorunlu](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kapi-ac-konum-zorunlu), [cekirdek-konum-izni-gps-hatasi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-konum-izni-gps-hatasi), [cekirdek-konum-mesafe-disi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-konum-mesafe-disi) | 30-uygulama-cekirdek |
| [lib/services/legal_api.dart](../lib/services/legal_api.dart) | 244 | — | — |
| [lib/services/local_cache_purge.dart](../lib/services/local_cache_purge.dart) | 49 | — | — |
| [lib/services/local_door_service.dart](../lib/services/local_door_service.dart) | 948 | [cekirdek-yerel-kapi-bulunmuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yerel-kapi-bulunmuyor), [cekirdek-yerel-udp-acma-basarisiz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yerel-udp-acma-basarisiz), [cekirdek-yerel-beacon-alinmiyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yerel-beacon-alinmiyor), [cekirdek-yerel-token-yok](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yerel-token-yok), [cekirdek-yasam-dongusu-dinleyici](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yasam-dongusu-dinleyici) +1 | 30-uygulama-cekirdek, 60-akislar |
| [lib/services/locale_service.dart](../lib/services/locale_service.dart) | 59 | — | — |
| [lib/services/login_device_token_store.dart](../lib/services/login_device_token_store.dart) | 117 | — | — |
| [lib/services/management_company_api.dart](../lib/services/management_company_api.dart) | 92 | — | — |
| [lib/services/menu_layout_api.dart](../lib/services/menu_layout_api.dart) | 72 | — | — |
| [lib/services/meter_api.dart](../lib/services/meter_api.dart) | 274 | — | — |
| [lib/services/meter_field_queue.dart](../lib/services/meter_field_queue.dart) | 205 | — | — |
| [lib/services/meter_file_reader.dart](../lib/services/meter_file_reader.dart) | 112 | — | — |
| [lib/services/meter_ocr.dart](../lib/services/meter_ocr.dart) | 67 | — | — |
| [lib/services/module_access.dart](../lib/services/module_access.dart) | 302 | — | — |
| [lib/services/mqtt_door_service_io.dart](../lib/services/mqtt_door_service_io.dart) | 250 | [cekirdek-mqtt-dogrudan-baglanti](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-mqtt-dogrudan-baglanti) | — |
| [lib/services/mqtt_door_service_stub.dart](../lib/services/mqtt_door_service_stub.dart) | 44 | [cekirdek-mqtt-dogrudan-baglanti](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-mqtt-dogrudan-baglanti) | — |
| [lib/services/mqtt_door_service.dart](../lib/services/mqtt_door_service.dart) | 3 | [cekirdek-mqtt-dogrudan-baglanti](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-mqtt-dogrudan-baglanti) | — |
| [lib/services/mt940_parser.dart](../lib/services/mt940_parser.dart) | 149 | — | — |
| [lib/services/neighbor_board_api.dart](../lib/services/neighbor_board_api.dart) | 95 | — | — |
| [lib/services/network_service.dart](../lib/services/network_service.dart) | 121 | [cekirdek-api-adresi-yanlis](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-api-adresi-yanlis), [cekirdek-internet-yok-ekrani](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-internet-yok-ekrani) | 30-uygulama-cekirdek |
| [lib/services/panel_return_requests.dart](../lib/services/panel_return_requests.dart) | 30 | [ui-ana-sayfa-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-ana-sayfa-dugmesi) | — |
| [lib/services/payment_notice_api.dart](../lib/services/payment_notice_api.dart) | 252 | — | — |
| [lib/services/payment_notice_file.dart](../lib/services/payment_notice_file.dart) | 77 | — | — |
| [lib/services/pdf_annual_report_service.dart](../lib/services/pdf_annual_report_service.dart) | 67 | — | — |
| [lib/services/pdf_budget_service.dart](../lib/services/pdf_budget_service.dart) | 106 | — | — |
| [lib/services/pdf_credentials_service.dart](../lib/services/pdf_credentials_service.dart) | 496 | [cekirdek-pdf-giris-bilgileri-raporu](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-pdf-giris-bilgileri-raporu), [akis-pdf-giris-bilgileri-ve-surum-raporu](ariza-klavuzu/61-akislar-devam.md#akis-pdf-giris-bilgileri-ve-surum-raporu) | 30-uygulama-cekirdek |
| [lib/services/pdf_decision_service.dart](../lib/services/pdf_decision_service.dart) | 311 | — | — |
| [lib/services/pdf_device_firmware_service.dart](../lib/services/pdf_device_firmware_service.dart) | 617 | [cekirdek-pdf-firmware-raporu](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-pdf-firmware-raporu), [akis-pdf-giris-bilgileri-ve-surum-raporu](ariza-klavuzu/61-akislar-devam.md#akis-pdf-giris-bilgileri-ve-surum-raporu) | 30-uygulama-cekirdek |
| [lib/services/pdf_finance_service.dart](../lib/services/pdf_finance_service.dart) | 1168 | — | — |
| [lib/services/pdf_font_set.dart](../lib/services/pdf_font_set.dart) | 80 | [cekirdek-pdf-turkce-karakter-font](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-pdf-turkce-karakter-font) | 30-uygulama-cekirdek |
| [lib/services/pdf_logs_service.dart](../lib/services/pdf_logs_service.dart) | 540 | [cekirdek-pdf-turkce-karakter-font](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-pdf-turkce-karakter-font), [cekirdek-pdf-gecis-raporu-bos](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-pdf-gecis-raporu-bos), [cekirdek-buyuk-yanit-yavas-arayuz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-buyuk-yanit-yavas-arayuz), [akis-pdf-ciktilari](ariza-klavuzu/61-akislar-devam.md#akis-pdf-ciktilari) | 30-uygulama-cekirdek |
| [lib/services/plate_recognition_api.dart](../lib/services/plate_recognition_api.dart) | 482 | — | — |
| [lib/services/platform_rules_api.dart](../lib/services/platform_rules_api.dart) | 292 | — | — |
| [lib/services/push_api.dart](../lib/services/push_api.dart) | 367 | — | — |
| [lib/services/push_firebase_gateway.dart](../lib/services/push_firebase_gateway.dart) | 263 | — | — |
| [lib/services/push_gateway.dart](../lib/services/push_gateway.dart) | 51 | — | — |
| [lib/services/push_service.dart](../lib/services/push_service.dart) | 933 | — | — |
| [lib/services/push_store.dart](../lib/services/push_store.dart) | 243 | — | — |
| [lib/services/quick_actions_service.dart](../lib/services/quick_actions_service.dart) | 77 | [cekirdek-kisayol-gorunmuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kisayol-gorunmuyor), [akis-sesle-kapi-acma-widget-kisayol](ariza-klavuzu/61-akislar-devam.md#akis-sesle-kapi-acma-widget-kisayol) | 30-uygulama-cekirdek |
| [lib/services/reservation_api.dart](../lib/services/reservation_api.dart) | 1031 | — | — |
| [lib/services/share_inbox.dart](../lib/services/share_inbox.dart) | 64 | — | — |
| [lib/services/site_application_tracker.dart](../lib/services/site_application_tracker.dart) | 367 | — | — |
| [lib/services/stored_session_probe.dart](../lib/services/stored_session_probe.dart) | 55 | — | — |
| [lib/services/survey_api.dart](../lib/services/survey_api.dart) | 473 | — | — |
| [lib/services/theme_service.dart](../lib/services/theme_service.dart) | 77 | [cekirdek-tema-tercihi-kaydedilmiyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-tema-tercihi-kaydedilmiyor) | 30-uygulama-cekirdek |
| [lib/services/view_mode_service.dart](../lib/services/view_mode_service.dart) | 114 | — | — |
| [lib/services/visitor_log_api.dart](../lib/services/visitor_log_api.dart) | 560 | — | — |
| [lib/services/voice_door_service.dart](../lib/services/voice_door_service.dart) | 857 | [cekirdek-kullanici-degisince-eski-veri](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kullanici-degisince-eski-veri), [cekirdek-sesli-komut-anlasilmadi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-sesli-komut-anlasilmadi), [cekirdek-sesli-komut-mikrofon-hatasi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-sesli-komut-mikrofon-hatasi), [akis-sesle-kapi-acma-widget-kisayol](ariza-klavuzu/61-akislar-devam.md#akis-sesle-kapi-acma-widget-kisayol) | 30-uygulama-cekirdek |
| [lib/services/web_push_client_stub.dart](../lib/services/web_push_client_stub.dart) | 9 | — | — |
| [lib/services/web_push_client_web.dart](../lib/services/web_push_client_web.dart) | 29 | — | — |
| [lib/services/web_push_client.dart](../lib/services/web_push_client.dart) | 2 | — | — |
| [lib/services/work_attachment_picker.dart](../lib/services/work_attachment_picker.dart) | 222 | — | — |
| [lib/services/work_attachment_upload.dart](../lib/services/work_attachment_upload.dart) | 509 | — | — |
| [lib/services/work_photo_prepare.dart](../lib/services/work_photo_prepare.dart) | 631 | — | — |
| [lib/services/work_tracking_api.dart](../lib/services/work_tracking_api.dart) | 1243 | — | — |
| [lib/styles/app_colors.dart](../lib/styles/app_colors.dart) | 79 | [bilesen-eski-renkler](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-eski-renkler) | — |
| [lib/styles/app_decorations.dart](../lib/styles/app_decorations.dart) | 55 | [bilesen-sayfa-zemini](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-sayfa-zemini) | — |
| [lib/styles/app_theme.dart](../lib/styles/app_theme.dart) | 511 | [cekirdek-giris-sonrasi-ekran-bos](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-giris-sonrasi-ekran-bos), [cekirdek-tema-tercihi-kaydedilmiyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-tema-tercihi-kaydedilmiyor), [ui-koyu-tema-okunmuyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor), [bilesen-snackbar-okunmuyor](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-snackbar-okunmuyor) | 30-uygulama-cekirdek, 31-uygulama-arayuz |
| [lib/styles/easy_view_theme.dart](../lib/styles/easy_view_theme.dart) | 105 | — | — |
| [lib/styles/role_theme.dart](../lib/styles/role_theme.dart) | 55 | [ui-koyu-tema-okunmuyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor), [bilesen-rol-rengi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-rol-rengi) | 31-uygulama-arayuz, 32-uygulama-bilesenler |
| [lib/ui/design/action_bar.dart](../lib/ui/design/action_bar.dart) | 182 | — | — |
| [lib/ui/design/app_card.dart](../lib/ui/design/app_card.dart) | 518 | [bilesen-kart-tasma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-kart-tasma), [bilesen-bolum-basligi-tasma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-bolum-basligi-tasma), [bilesen-satir-ici-bildirim](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-satir-ici-bildirim) | — |
| [lib/ui/design/app_dialog.dart](../lib/ui/design/app_dialog.dart) | 161 | [bilesen-diyalog-sablonu](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-diyalog-sablonu) | 31-uygulama-arayuz |
| [lib/ui/design/app_snack.dart](../lib/ui/design/app_snack.dart) | 137 | [bilesen-snackbar-gorunmuyor](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-snackbar-gorunmuyor), [bilesen-snackbar-okunmuyor](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-snackbar-okunmuyor) | 31-uygulama-arayuz, 32-uygulama-bilesenler |
| [lib/ui/design/buttons.dart](../lib/ui/design/buttons.dart) | 248 | [bilesen-birincil-dugme](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-birincil-dugme), [bilesen-basma-olcegi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-basma-olcegi) | 31-uygulama-arayuz |
| [lib/ui/design/countdown_ring.dart](../lib/ui/design/countdown_ring.dart) | 228 | [bilesen-geri-sayim-halka](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-geri-sayim-halka), [bilesen-geri-sayim-saniye](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-geri-sayim-saniye) | 32-uygulama-bilesenler |
| [lib/ui/design/door_open_button.dart](../lib/ui/design/door_open_button.dart) | 795 | [ui-kapi-ac-yonetici](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-ac-yonetici), [ui-kapi-ac-basari-tiki](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-ac-basari-tiki), [bilesen-kapi-ac-dugmesi-durum](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-kapi-ac-dugmesi-durum) | 31-uygulama-arayuz |
| [lib/ui/design/easy_view_switch.dart](../lib/ui/design/easy_view_switch.dart) | 61 | — | — |
| [lib/ui/design/empty_state.dart](../lib/ui/design/empty_state.dart) | 184 | [bilesen-bos-durum](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-bos-durum) | — |
| [lib/ui/design/gloss.dart](../lib/ui/design/gloss.dart) | 313 | — | — |
| [lib/ui/design/icon_orb.dart](../lib/ui/design/icon_orb.dart) | 83 | — | — |
| [lib/ui/design/license_plate.dart](../lib/ui/design/license_plate.dart) | 102 | — | — |
| [lib/ui/design/login_hero.dart](../lib/ui/design/login_hero.dart) | 90 | [bilesen-giris-logosu](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-giris-logosu) | — |
| [lib/ui/design/module_art.dart](../lib/ui/design/module_art.dart) | 1061 | — | — |
| [lib/ui/design/motion_widgets.dart](../lib/ui/design/motion_widgets.dart) | 175 | [bilesen-hareket-azaltma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-hareket-azaltma), [bilesen-sayi-akisi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-sayi-akisi), [bilesen-liste-girisi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-liste-girisi), [bilesen-pop-belirme](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-pop-belirme) | 32-uygulama-bilesenler |
| [lib/ui/design/page_transitions.dart](../lib/ui/design/page_transitions.dart) | 158 | [bilesen-sayfa-gecisi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-sayfa-gecisi) | 32-uygulama-bilesenler |
| [lib/ui/design/skeleton.dart](../lib/ui/design/skeleton.dart) | 190 | [bilesen-iskelet-bitmiyor](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-iskelet-bitmiyor), [bilesen-iskelet-tasma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-iskelet-tasma) | 32-uygulama-bilesenler |
| [lib/ui/design/status_chip.dart](../lib/ui/design/status_chip.dart) | 197 | [bilesen-durum-rozeti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-durum-rozeti), [bilesen-nabiz-ticker](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-nabiz-ticker) | 32-uygulama-bilesenler |
| [lib/ui/design/status_dot.dart](../lib/ui/design/status_dot.dart) | 100 | — | — |
| [lib/ui/design/theme_toggle_button.dart](../lib/ui/design/theme_toggle_button.dart) | 54 | [ui-ust-cubuk-tasma](ariza-klavuzu/31-uygulama-arayuz.md#ui-ust-cubuk-tasma), [ui-tema-gecisi](ariza-klavuzu/31-uygulama-arayuz.md#ui-tema-gecisi) | 31-uygulama-arayuz |
| [lib/ui/design/tokens.dart](../lib/ui/design/tokens.dart) | 514 | [ui-koyu-tema-okunmuyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor), [bilesen-hareket-azaltma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-hareket-azaltma), [bilesen-durum-rozeti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-durum-rozeti), [bilesen-rol-rengi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-rol-rengi), [bilesen-eski-renkler](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-eski-renkler) | 31-uygulama-arayuz, 32-uygulama-bilesenler |
| [lib/ui/design/view_mode_toggle.dart](../lib/ui/design/view_mode_toggle.dart) | 77 | — | — |
| [lib/ui/dialogs/announcement_form_dialog.dart](../lib/ui/dialogs/announcement_form_dialog.dart) | 1255 | — | — |
| [lib/ui/dialogs/announcement_manage_dialog.dart](../lib/ui/dialogs/announcement_manage_dialog.dart) | 690 | — | — |
| [lib/ui/dialogs/announcement_read_dialog.dart](../lib/ui/dialogs/announcement_read_dialog.dart) | 275 | — | — |
| [lib/ui/dialogs/apartment_admin_dialogs.dart](../lib/ui/dialogs/apartment_admin_dialogs.dart) | 474 | — | — |
| [lib/ui/dialogs/apartment_card_dialog.dart](../lib/ui/dialogs/apartment_card_dialog.dart) | 366 | — | — |
| [lib/ui/dialogs/apartment_edit_dialog.dart](../lib/ui/dialogs/apartment_edit_dialog.dart) | 428 | — | — |
| [lib/ui/dialogs/apartment_info_section.dart](../lib/ui/dialogs/apartment_info_section.dart) | 208 | — | — |
| [lib/ui/dialogs/apartment_mgmt_dialogs.dart](../lib/ui/dialogs/apartment_mgmt_dialogs.dart) | 443 | — | — |
| [lib/ui/dialogs/apartment_pin_dialogs.dart](../lib/ui/dialogs/apartment_pin_dialogs.dart) | 176 | — | — |
| [lib/ui/dialogs/apartment_resident_dialog.dart](../lib/ui/dialogs/apartment_resident_dialog.dart) | 260 | [ui-daire-sakini-diyalogu](ariza-klavuzu/31-uygulama-arayuz.md#ui-daire-sakini-diyalogu) | — |
| [lib/ui/dialogs/apartment_vehicle_dialog.dart](../lib/ui/dialogs/apartment_vehicle_dialog.dart) | 204 | — | — |
| [lib/ui/dialogs/bank_line_assign_dialog.dart](../lib/ui/dialogs/bank_line_assign_dialog.dart) | 134 | — | — |
| [lib/ui/dialogs/bank_line_classify_dialog.dart](../lib/ui/dialogs/bank_line_classify_dialog.dart) | 183 | — | — |
| [lib/ui/dialogs/bank_mapping_dialog.dart](../lib/ui/dialogs/bank_mapping_dialog.dart) | 106 | — | — |
| [lib/ui/dialogs/concierge_manage_dialog.dart](../lib/ui/dialogs/concierge_manage_dialog.dart) | 338 | — | — |
| [lib/ui/dialogs/concierge_request_form_dialog.dart](../lib/ui/dialogs/concierge_request_form_dialog.dart) | 453 | — | — |
| [lib/ui/dialogs/concierge_resident_detail_dialog.dart](../lib/ui/dialogs/concierge_resident_detail_dialog.dart) | 178 | — | — |
| [lib/ui/dialogs/contract_detail_dialog.dart](../lib/ui/dialogs/contract_detail_dialog.dart) | 303 | — | — |
| [lib/ui/dialogs/contract_form_dialog.dart](../lib/ui/dialogs/contract_form_dialog.dart) | 637 | — | — |
| [lib/ui/dialogs/contract_vendor_form_dialog.dart](../lib/ui/dialogs/contract_vendor_form_dialog.dart) | 389 | — | — |
| [lib/ui/dialogs/create_guest_pass_dialog.dart](../lib/ui/dialogs/create_guest_pass_dialog.dart) | 413 | [ui-misafir-gecis-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-misafir-gecis-dugmesi), [akis-misafir-gecis](ariza-klavuzu/60-akislar.md#akis-misafir-gecis) | — |
| [lib/ui/dialogs/crm_confirm_dialog.dart](../lib/ui/dialogs/crm_confirm_dialog.dart) | 47 | — | — |
| [lib/ui/dialogs/crm_pickers.dart](../lib/ui/dialogs/crm_pickers.dart) | 299 | — | — |
| [lib/ui/dialogs/decision_detail_dialog.dart](../lib/ui/dialogs/decision_detail_dialog.dart) | 470 | — | — |
| [lib/ui/dialogs/decision_form_dialog.dart](../lib/ui/dialogs/decision_form_dialog.dart) | 575 | — | — |
| [lib/ui/dialogs/device_dialog.dart](../lib/ui/dialogs/device_dialog.dart) | 361 | [ui-cihaz-kayit-formu](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-kayit-formu) | — |
| [lib/ui/dialogs/dialog_parts.dart](../lib/ui/dialogs/dialog_parts.dart) | 175 | — | — |
| [lib/ui/dialogs/document_attach_picker_dialog.dart](../lib/ui/dialogs/document_attach_picker_dialog.dart) | 251 | — | — |
| [lib/ui/dialogs/document_detail_dialog.dart](../lib/ui/dialogs/document_detail_dialog.dart) | 630 | — | — |
| [lib/ui/dialogs/document_download_dialog.dart](../lib/ui/dialogs/document_download_dialog.dart) | 259 | — | — |
| [lib/ui/dialogs/document_edit_dialog.dart](../lib/ui/dialogs/document_edit_dialog.dart) | 466 | — | — |
| [lib/ui/dialogs/document_upload_dialog.dart](../lib/ui/dialogs/document_upload_dialog.dart) | 941 | — | — |
| [lib/ui/dialogs/door_device_dialog.dart](../lib/ui/dialogs/door_device_dialog.dart) | 487 | [ui-kapi-cihaz-ata](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-cihaz-ata) | — |
| [lib/ui/dialogs/door_edit_dialog.dart](../lib/ui/dialogs/door_edit_dialog.dart) | 361 | [ui-kapi-yonet-yenilenmiyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-yonet-yenilenmiyor) | — |
| [lib/ui/dialogs/door_permissions_dialog.dart](../lib/ui/dialogs/door_permissions_dialog.dart) | 672 | [ui-kapi-yetkileri](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-yetkileri), [ui-yazi-olcegi-tasma](ariza-klavuzu/31-uygulama-arayuz.md#ui-yazi-olcegi-tasma), [akis-kapi-yetkileri-izinler](ariza-klavuzu/61-akislar-devam.md#akis-kapi-yetkileri-izinler) | — |
| [lib/ui/dialogs/duty_dialog.dart](../lib/ui/dialogs/duty_dialog.dart) | 140 | — | — |
| [lib/ui/dialogs/end_residency_dialog.dart](../lib/ui/dialogs/end_residency_dialog.dart) | 186 | — | — |
| [lib/ui/dialogs/export_sheet.dart](../lib/ui/dialogs/export_sheet.dart) | 4 | — | — |
| [lib/ui/dialogs/feedback_dialog.dart](../lib/ui/dialogs/feedback_dialog.dart) | 703 | — | — |
| [lib/ui/dialogs/finance_account_dialog.dart](../lib/ui/dialogs/finance_account_dialog.dart) | 552 | — | — |
| [lib/ui/dialogs/finance_adjust_dialog.dart](../lib/ui/dialogs/finance_adjust_dialog.dart) | 346 | — | — |
| [lib/ui/dialogs/finance_assign_dialog.dart](../lib/ui/dialogs/finance_assign_dialog.dart) | 396 | — | — |
| [lib/ui/dialogs/finance_bank_details_dialog.dart](../lib/ui/dialogs/finance_bank_details_dialog.dart) | 145 | — | — |
| [lib/ui/dialogs/finance_card_payments_dialog.dart](../lib/ui/dialogs/finance_card_payments_dialog.dart) | 239 | — | — |
| [lib/ui/dialogs/finance_cash_account_dialog.dart](../lib/ui/dialogs/finance_cash_account_dialog.dart) | 361 | — | — |
| [lib/ui/dialogs/finance_catalog_dialog.dart](../lib/ui/dialogs/finance_catalog_dialog.dart) | 608 | — | — |
| [lib/ui/dialogs/finance_definition_form_dialog.dart](../lib/ui/dialogs/finance_definition_form_dialog.dart) | 579 | — | — |
| [lib/ui/dialogs/finance_expense_detail_dialog.dart](../lib/ui/dialogs/finance_expense_detail_dialog.dart) | 402 | — | — |
| [lib/ui/dialogs/finance_expense_dialog.dart](../lib/ui/dialogs/finance_expense_dialog.dart) | 876 | — | — |
| [lib/ui/dialogs/finance_fund_transfer_dialog.dart](../lib/ui/dialogs/finance_fund_transfer_dialog.dart) | 535 | — | — |
| [lib/ui/dialogs/finance_late_fee_dialog.dart](../lib/ui/dialogs/finance_late_fee_dialog.dart) | 794 | — | — |
| [lib/ui/dialogs/finance_late_fee_explain_dialog.dart](../lib/ui/dialogs/finance_late_fee_explain_dialog.dart) | 156 | — | — |
| [lib/ui/dialogs/finance_late_fee_lines_dialog.dart](../lib/ui/dialogs/finance_late_fee_lines_dialog.dart) | 170 | — | — |
| [lib/ui/dialogs/finance_movements_dialog.dart](../lib/ui/dialogs/finance_movements_dialog.dart) | 157 | — | — |
| [lib/ui/dialogs/finance_opening_dialog.dart](../lib/ui/dialogs/finance_opening_dialog.dart) | 295 | — | — |
| [lib/ui/dialogs/finance_payment_dialog.dart](../lib/ui/dialogs/finance_payment_dialog.dart) | 979 | — | — |
| [lib/ui/dialogs/finance_payment_settings_dialog.dart](../lib/ui/dialogs/finance_payment_settings_dialog.dart) | 221 | — | — |
| [lib/ui/dialogs/finance_reason_dialog.dart](../lib/ui/dialogs/finance_reason_dialog.dart) | 213 | — | — |
| [lib/ui/dialogs/finance_receipt_dialog.dart](../lib/ui/dialogs/finance_receipt_dialog.dart) | 588 | — | — |
| [lib/ui/dialogs/finance_receipt_flow.dart](../lib/ui/dialogs/finance_receipt_flow.dart) | 26 | — | — |
| [lib/ui/dialogs/finance_receipt_list_dialog.dart](../lib/ui/dialogs/finance_receipt_list_dialog.dart) | 533 | — | — |
| [lib/ui/dialogs/finance_reconcile_dialog.dart](../lib/ui/dialogs/finance_reconcile_dialog.dart) | 536 | — | — |
| [lib/ui/dialogs/finance_reminder_dialog.dart](../lib/ui/dialogs/finance_reminder_dialog.dart) | 600 | — | — |
| [lib/ui/dialogs/finance_reminder_exempt_dialog.dart](../lib/ui/dialogs/finance_reminder_exempt_dialog.dart) | 259 | — | — |
| [lib/ui/dialogs/finance_reminder_runs_dialog.dart](../lib/ui/dialogs/finance_reminder_runs_dialog.dart) | 529 | — | — |
| [lib/ui/dialogs/finance_reverse_dialog.dart](../lib/ui/dialogs/finance_reverse_dialog.dart) | 297 | — | — |
| [lib/ui/dialogs/finance_run_dialog.dart](../lib/ui/dialogs/finance_run_dialog.dart) | 1025 | — | — |
| [lib/ui/dialogs/finance_settings_dialog.dart](../lib/ui/dialogs/finance_settings_dialog.dart) | 550 | — | — |
| [lib/ui/dialogs/finance_supplier_dialog.dart](../lib/ui/dialogs/finance_supplier_dialog.dart) | 426 | — | — |
| [lib/ui/dialogs/finance_transfer_dialog.dart](../lib/ui/dialogs/finance_transfer_dialog.dart) | 524 | — | — |
| [lib/ui/dialogs/force_change_password_dialog.dart](../lib/ui/dialogs/force_change_password_dialog.dart) | 313 | — | — |
| [lib/ui/dialogs/history_dialog.dart](../lib/ui/dialogs/history_dialog.dart) | 258 | — | — |
| [lib/ui/dialogs/invite_site_manager_dialog.dart](../lib/ui/dialogs/invite_site_manager_dialog.dart) | 175 | [ui-yonetici-daveti](ariza-klavuzu/31-uygulama-arayuz.md#ui-yonetici-daveti) | — |
| [lib/ui/dialogs/large_dialog_parts.dart](../lib/ui/dialogs/large_dialog_parts.dart) | 279 | — | — |
| [lib/ui/dialogs/logout_confirm_dialog.dart](../lib/ui/dialogs/logout_confirm_dialog.dart) | 16 | — | — |
| [lib/ui/dialogs/manage_join_requests_dialog.dart](../lib/ui/dialogs/manage_join_requests_dialog.dart) | 472 | [ui-katilim-talepleri-yonet](ariza-klavuzu/31-uygulama-arayuz.md#ui-katilim-talepleri-yonet) | — |
| [lib/ui/dialogs/managed_user_dialog.dart](../lib/ui/dialogs/managed_user_dialog.dart) | 303 | [ui-kullanici-diyalogu-kaydet](ariza-klavuzu/31-uygulama-arayuz.md#ui-kullanici-diyalogu-kaydet) | — |
| [lib/ui/dialogs/module_request_dialog.dart](../lib/ui/dialogs/module_request_dialog.dart) | 149 | — | — |
| [lib/ui/dialogs/payment_notice_dialog.dart](../lib/ui/dialogs/payment_notice_dialog.dart) | 333 | — | — |
| [lib/ui/dialogs/payment_notice_manual_dialog.dart](../lib/ui/dialogs/payment_notice_manual_dialog.dart) | 202 | — | — |
| [lib/ui/dialogs/payment_notice_review_dialog.dart](../lib/ui/dialogs/payment_notice_review_dialog.dart) | 352 | — | — |
| [lib/ui/dialogs/person_account_dialog.dart](../lib/ui/dialogs/person_account_dialog.dart) | 407 | — | — |
| [lib/ui/dialogs/person_card_dialog.dart](../lib/ui/dialogs/person_card_dialog.dart) | 662 | — | — |
| [lib/ui/dialogs/person_form_dialog.dart](../lib/ui/dialogs/person_form_dialog.dart) | 904 | — | — |
| [lib/ui/dialogs/platform_rule_dialog.dart](../lib/ui/dialogs/platform_rule_dialog.dart) | 362 | — | — |
| [lib/ui/dialogs/replace_device_dialog.dart](../lib/ui/dialogs/replace_device_dialog.dart) | 322 | [ui-cihaz-degistir](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-degistir) | — |
| [lib/ui/dialogs/reservation_area_form_dialog.dart](../lib/ui/dialogs/reservation_area_form_dialog.dart) | 719 | — | — |
| [lib/ui/dialogs/reservation_booking_dialog.dart](../lib/ui/dialogs/reservation_booking_dialog.dart) | 387 | — | — |
| [lib/ui/dialogs/reservation_decision_dialog.dart](../lib/ui/dialogs/reservation_decision_dialog.dart) | 237 | — | — |
| [lib/ui/dialogs/reservation_resident_detail_dialog.dart](../lib/ui/dialogs/reservation_resident_detail_dialog.dart) | 183 | — | — |
| [lib/ui/dialogs/residency_dialog.dart](../lib/ui/dialogs/residency_dialog.dart) | 252 | — | — |
| [lib/ui/dialogs/setup_site_dialog.dart](../lib/ui/dialogs/setup_site_dialog.dart) | 1221 | [cekirdek-il-ilce-listesi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-il-ilce-listesi), [ui-kurulum-sihirbazi](ariza-klavuzu/31-uygulama-arayuz.md#ui-kurulum-sihirbazi), [akis-site-kurulum-davet-sakin-katilim](ariza-klavuzu/61-akislar-devam.md#akis-site-kurulum-davet-sakin-katilim) | — |
| [lib/ui/dialogs/signing_roster_dialog.dart](../lib/ui/dialogs/signing_roster_dialog.dart) | 93 | — | — |
| [lib/ui/dialogs/site_application_detail_dialog.dart](../lib/ui/dialogs/site_application_detail_dialog.dart) | 673 | — | — |
| [lib/ui/dialogs/site_dialog.dart](../lib/ui/dialogs/site_dialog.dart) | 668 | [cekirdek-il-ilce-listesi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-il-ilce-listesi), [ui-site-yoneticisi-secici](ariza-klavuzu/31-uygulama-arayuz.md#ui-site-yoneticisi-secici), [ui-site-duzenle-dialogu](ariza-klavuzu/31-uygulama-arayuz.md#ui-site-duzenle-dialogu) | — |
| [lib/ui/dialogs/site_join_qr_dialog.dart](../lib/ui/dialogs/site_join_qr_dialog.dart) | 537 | [ui-katilim-qr-diyalogu](ariza-klavuzu/31-uygulama-arayuz.md#ui-katilim-qr-diyalogu) | — |
| [lib/ui/dialogs/site_residents_accordion_dialog.dart](../lib/ui/dialogs/site_residents_accordion_dialog.dart) | 883 | [ui-sakin-listesi-akordiyon](ariza-klavuzu/31-uygulama-arayuz.md#ui-sakin-listesi-akordiyon) | — |
| [lib/ui/dialogs/staff_role_dialog.dart](../lib/ui/dialogs/staff_role_dialog.dart) | 192 | — | — |
| [lib/ui/dialogs/submit_join_request_dialog.dart](../lib/ui/dialogs/submit_join_request_dialog.dart) | 440 | [ui-qr-tarama-sayfasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-tarama-sayfasi), [ui-katilim-basvurusu-gonder](ariza-klavuzu/31-uygulama-arayuz.md#ui-katilim-basvurusu-gonder) | — |
| [lib/ui/dialogs/survey_form_dialog.dart](../lib/ui/dialogs/survey_form_dialog.dart) | 485 | — | — |
| [lib/ui/dialogs/vehicle_dialog.dart](../lib/ui/dialogs/vehicle_dialog.dart) | 196 | — | — |
| [lib/ui/dialogs/visitor_entry_form_dialog.dart](../lib/ui/dialogs/visitor_entry_form_dialog.dart) | 364 | — | — |
| [lib/ui/dialogs/work_item_form_dialog.dart](../lib/ui/dialogs/work_item_form_dialog.dart) | 926 | — | — |
| [lib/ui/dialogs/work_manager_detail_dialog.dart](../lib/ui/dialogs/work_manager_detail_dialog.dart) | 815 | — | — |
| [lib/ui/dialogs/work_resident_detail_dialog.dart](../lib/ui/dialogs/work_resident_detail_dialog.dart) | 503 | — | — |
| [lib/ui/helpers/a11y_announce.dart](../lib/ui/helpers/a11y_announce.dart) | 18 | — | — |
| [lib/ui/helpers/connectivity_error.dart](../lib/ui/helpers/connectivity_error.dart) | 55 | — | — |
| [lib/ui/helpers/contract_validation.dart](../lib/ui/helpers/contract_validation.dart) | 140 | — | — |
| [lib/ui/helpers/cursor_loader.dart](../lib/ui/helpers/cursor_loader.dart) | 178 | — | — |
| [lib/ui/helpers/date_input.dart](../lib/ui/helpers/date_input.dart) | 147 | — | — |
| [lib/ui/helpers/decision_loader.dart](../lib/ui/helpers/decision_loader.dart) | 119 | — | — |
| [lib/ui/helpers/device_add_gate.dart](../lib/ui/helpers/device_add_gate.dart) | 12 | — | — |
| [lib/ui/helpers/dial_call.dart](../lib/ui/helpers/dial_call.dart) | 74 | — | — |
| [lib/ui/helpers/dialog_guard.dart](../lib/ui/helpers/dialog_guard.dart) | 11 | — | — |
| [lib/ui/helpers/finance_4b_access.dart](../lib/ui/helpers/finance_4b_access.dart) | 107 | — | — |
| [lib/ui/helpers/finance_errors.dart](../lib/ui/helpers/finance_errors.dart) | 64 | — | — |
| [lib/ui/helpers/finance_export_sources.dart](../lib/ui/helpers/finance_export_sources.dart) | 43 | — | — |
| [lib/ui/helpers/finance_write_mixin.dart](../lib/ui/helpers/finance_write_mixin.dart) | 149 | — | — |
| [lib/ui/helpers/focus_helpers.dart](../lib/ui/helpers/focus_helpers.dart) | 15 | — | — |
| [lib/ui/helpers/form_validation.dart](../lib/ui/helpers/form_validation.dart) | 84 | — | — |
| [lib/ui/helpers/fund_text.dart](../lib/ui/helpers/fund_text.dart) | 22 | — | — |
| [lib/ui/helpers/home_shortcut.dart](../lib/ui/helpers/home_shortcut.dart) | 31 | [ui-ana-sayfa-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-ana-sayfa-dugmesi) | 31-uygulama-arayuz |
| [lib/ui/helpers/idempotency.dart](../lib/ui/helpers/idempotency.dart) | 65 | — | — |
| [lib/ui/helpers/istanbul_time.dart](../lib/ui/helpers/istanbul_time.dart) | 47 | — | — |
| [lib/ui/helpers/last_updated.dart](../lib/ui/helpers/last_updated.dart) | 14 | — | — |
| [lib/ui/helpers/list_export.dart](../lib/ui/helpers/list_export.dart) | 71 | — | — |
| [lib/ui/helpers/menu_layout.dart](../lib/ui/helpers/menu_layout.dart) | 173 | — | — |
| [lib/ui/helpers/module_menu.dart](../lib/ui/helpers/module_menu.dart) | 47 | — | — |
| [lib/ui/helpers/module_showcase.dart](../lib/ui/helpers/module_showcase.dart) | 440 | — | — |
| [lib/ui/helpers/money.dart](../lib/ui/helpers/money.dart) | 316 | — | — |
| [lib/ui/helpers/paged_loader.dart](../lib/ui/helpers/paged_loader.dart) | 181 | — | — |
| [lib/ui/helpers/password_policy_data.dart](../lib/ui/helpers/password_policy_data.dart) | 53 | — | — |
| [lib/ui/helpers/password_policy.dart](../lib/ui/helpers/password_policy.dart) | 266 | — | — |
| [lib/ui/helpers/people_scope.dart](../lib/ui/helpers/people_scope.dart) | 63 | — | — |
| [lib/ui/helpers/phone_input.dart](../lib/ui/helpers/phone_input.dart) | 324 | — | — |
| [lib/ui/helpers/plate_input.dart](../lib/ui/helpers/plate_input.dart) | 296 | — | — |
| [lib/ui/helpers/refresh_status.dart](../lib/ui/helpers/refresh_status.dart) | 62 | — | — |
| [lib/ui/helpers/resident_tabs.dart](../lib/ui/helpers/resident_tabs.dart) | 54 | [ui-sakin-alt-cubuk](ariza-klavuzu/31-uygulama-arayuz.md#ui-sakin-alt-cubuk) | 31-uygulama-arayuz |
| [lib/ui/helpers/retry_lock.dart](../lib/ui/helpers/retry_lock.dart) | 50 | — | — |
| [lib/ui/helpers/site_application_flow.dart](../lib/ui/helpers/site_application_flow.dart) | 130 | — | — |
| [lib/ui/helpers/text_length.dart](../lib/ui/helpers/text_length.dart) | 38 | — | — |
| [lib/ui/helpers/time_input.dart](../lib/ui/helpers/time_input.dart) | 126 | — | — |
| [lib/ui/helpers/ui_helpers.dart](../lib/ui/helpers/ui_helpers.dart) | 38 | [bilesen-dialog-genisligi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-dialog-genisligi), [model-tarih-saat-yanlis](ariza-klavuzu/33-uygulama-modeller.md#model-tarih-saat-yanlis) | 32-uygulama-bilesenler |
| [lib/ui/pages/home_page.dart](../lib/ui/pages/home_page.dart) | 7824 | [cekirdek-oturum-kendiliginden-dusuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-oturum-kendiliginden-dusuyor), [cekirdek-kapi-durumu-cevrimdisi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kapi-durumu-cevrimdisi), [cekirdek-yasam-dongusu-dinleyici](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-yasam-dongusu-dinleyici), [cekirdek-kisayol-gorunmuyor](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-kisayol-gorunmuyor), [cekirdek-pdf-gecis-raporu-bos](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-pdf-gecis-raporu-bos) +44 | 31-uygulama-arayuz |
| [lib/ui/pages/login_page.dart](../lib/ui/pages/login_page.dart) | 452 | [ui-giris-hata](ariza-klavuzu/31-uygulama-arayuz.md#ui-giris-hata), [ui-giris-beni-hatirla](ariza-klavuzu/31-uygulama-arayuz.md#ui-giris-beni-hatirla), [ui-sifremi-unuttum](ariza-klavuzu/31-uygulama-arayuz.md#ui-sifremi-unuttum), [ui-oturum-sonu-bildirimi](ariza-klavuzu/31-uygulama-arayuz.md#ui-oturum-sonu-bildirimi), [ui-dogrulama-sonrasi-yonlendirme](ariza-klavuzu/31-uygulama-arayuz.md#ui-dogrulama-sonrasi-yonlendirme) +3 | 31-uygulama-arayuz |
| [lib/ui/pages/no_internet_page.dart](../lib/ui/pages/no_internet_page.dart) | 89 | [ui-internet-yok](ariza-klavuzu/31-uygulama-arayuz.md#ui-internet-yok) | 31-uygulama-arayuz |
| [lib/ui/pages/qr_scan_page.dart](../lib/ui/pages/qr_scan_page.dart) | 350 | [ui-qr-tarama-sayfasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-tarama-sayfasi) | 31-uygulama-arayuz |
| [lib/ui/pages/register_individual_page.dart](../lib/ui/pages/register_individual_page.dart) | 394 | [ui-kayit-formu](ariza-klavuzu/31-uygulama-arayuz.md#ui-kayit-formu), [ui-tema-gecisi](ariza-klavuzu/31-uygulama-arayuz.md#ui-tema-gecisi), [akis-kayit-eposta-dogrulama](ariza-klavuzu/60-akislar.md#akis-kayit-eposta-dogrulama) | 31-uygulama-arayuz |
| [lib/ui/pages/site_manager_picker_page.dart](../lib/ui/pages/site_manager_picker_page.dart) | 320 | [ui-site-yoneticisi-secici](ariza-klavuzu/31-uygulama-arayuz.md#ui-site-yoneticisi-secici) | 31-uygulama-arayuz |
| [lib/ui/pages/sms_login_page.dart](../lib/ui/pages/sms_login_page.dart) | 167 | — | — |
| [lib/ui/pages/verify_email_code_page.dart](../lib/ui/pages/verify_email_code_page.dart) | 365 | [ui-dogrulama-kodu](ariza-klavuzu/31-uygulama-arayuz.md#ui-dogrulama-kodu), [ui-dogrulama-sonrasi-yonlendirme](ariza-klavuzu/31-uygulama-arayuz.md#ui-dogrulama-sonrasi-yonlendirme), [akis-kayit-eposta-dogrulama](ariza-klavuzu/60-akislar.md#akis-kayit-eposta-dogrulama) | 31-uygulama-arayuz |
| [lib/ui/pages/wifi_provision_page.dart](../lib/ui/pages/wifi_provision_page.dart) | 930 | [cekirdek-ble-baglanti-ve-wifi-listesi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-baglanti-ve-wifi-listesi), [cekirdek-ble-wifi-yazma-basarisiz](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-ble-wifi-yazma-basarisiz), [ui-qr-tarama-sayfasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-tarama-sayfasi), [ui-wifi-kurulum](ariza-klavuzu/31-uygulama-arayuz.md#ui-wifi-kurulum), [ui-wifi-karekod](ariza-klavuzu/31-uygulama-arayuz.md#ui-wifi-karekod) +1 | 31-uygulama-arayuz |
| [lib/ui/views/account_deletion_view.dart](../lib/ui/views/account_deletion_view.dart) | 395 | — | — |
| [lib/ui/views/all_actions_view.dart](../lib/ui/views/all_actions_view.dart) | 357 | — | — |
| [lib/ui/views/all_users_view.dart](../lib/ui/views/all_users_view.dart) | 944 | [ui-hesap-listesi-arama](ariza-klavuzu/31-uygulama-arayuz.md#ui-hesap-listesi-arama), [ui-veritabani-bakim-diyalogu](ariza-klavuzu/31-uygulama-arayuz.md#ui-veritabani-bakim-diyalogu), [akis-bakim-temizlik-health](ariza-klavuzu/60-akislar.md#akis-bakim-temizlik-health) | 31-uygulama-arayuz |
| [lib/ui/views/announcements_admin_list.dart](../lib/ui/views/announcements_admin_list.dart) | 242 | — | — |
| [lib/ui/views/announcements_admin_view.dart](../lib/ui/views/announcements_admin_view.dart) | 253 | — | — |
| [lib/ui/views/announcements_inbox_view.dart](../lib/ui/views/announcements_inbox_view.dart) | 385 | — | — |
| [lib/ui/views/announcements_view.dart](../lib/ui/views/announcements_view.dart) | 210 | — | — |
| [lib/ui/views/annual_report_view.dart](../lib/ui/views/annual_report_view.dart) | 257 | — | — |
| [lib/ui/views/app_gate_view.dart](../lib/ui/views/app_gate_view.dart) | 620 | — | — |
| [lib/ui/views/audit_log_view.dart](../lib/ui/views/audit_log_view.dart) | 432 | — | — |
| [lib/ui/views/bank_import_view.dart](../lib/ui/views/bank_import_view.dart) | 447 | — | — |
| [lib/ui/views/bank_lines_view.dart](../lib/ui/views/bank_lines_view.dart) | 219 | — | — |
| [lib/ui/views/bluetooth_wifi_view.dart](../lib/ui/views/bluetooth_wifi_view.dart) | 71 | [ui-wifi-kurulum](ariza-klavuzu/31-uygulama-arayuz.md#ui-wifi-kurulum) | 31-uygulama-arayuz |
| [lib/ui/views/brand_theme_view.dart](../lib/ui/views/brand_theme_view.dart) | 379 | — | — |
| [lib/ui/views/budget_view.dart](../lib/ui/views/budget_view.dart) | 624 | [ui-ana-sayfa-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-ana-sayfa-dugmesi) | — |
| [lib/ui/views/bulk_import_controller.dart](../lib/ui/views/bulk_import_controller.dart) | 1215 | — | — |
| [lib/ui/views/bulk_import_view.dart](../lib/ui/views/bulk_import_view.dart) | 281 | — | — |
| [lib/ui/views/cctv_view.dart](../lib/ui/views/cctv_view.dart) | 587 | — | — |
| [lib/ui/views/client_errors_view.dart](../lib/ui/views/client_errors_view.dart) | 344 | — | — |
| [lib/ui/views/company_devices_view.dart](../lib/ui/views/company_devices_view.dart) | 243 | [ui-yazi-olcegi-tasma](ariza-klavuzu/31-uygulama-arayuz.md#ui-yazi-olcegi-tasma), [ui-cihaz-envanteri](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-envanteri) | 31-uygulama-arayuz |
| [lib/ui/views/concierge_manager_tab.dart](../lib/ui/views/concierge_manager_tab.dart) | 241 | — | — |
| [lib/ui/views/concierge_resident_tab.dart](../lib/ui/views/concierge_resident_tab.dart) | 335 | — | — |
| [lib/ui/views/contract_vendors_tab.dart](../lib/ui/views/contract_vendors_tab.dart) | 389 | — | — |
| [lib/ui/views/contracts_view.dart](../lib/ui/views/contracts_view.dart) | 737 | — | — |
| [lib/ui/views/dashboard_view.dart](../lib/ui/views/dashboard_view.dart) | 132 | [ui-kapi-ac-sakin](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-ac-sakin) | 31-uygulama-arayuz |
| [lib/ui/views/decision_manager_view.dart](../lib/ui/views/decision_manager_view.dart) | 581 | — | — |
| [lib/ui/views/decision_resident_view.dart](../lib/ui/views/decision_resident_view.dart) | 221 | — | — |
| [lib/ui/views/device_add_view.dart](../lib/ui/views/device_add_view.dart) | 90 | [ui-cihaz-kayit-formu](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-kayit-formu) | — |
| [lib/ui/views/device_integrations_view.dart](../lib/ui/views/device_integrations_view.dart) | 273 | — | — |
| [lib/ui/views/directory_view.dart](../lib/ui/views/directory_view.dart) | 143 | — | — |
| [lib/ui/views/document_admin_list.dart](../lib/ui/views/document_admin_list.dart) | 380 | — | — |
| [lib/ui/views/document_admin_view.dart](../lib/ui/views/document_admin_view.dart) | 307 | — | — |
| [lib/ui/views/document_resident_view.dart](../lib/ui/views/document_resident_view.dart) | 321 | — | — |
| [lib/ui/views/document_view.dart](../lib/ui/views/document_view.dart) | 198 | — | — |
| [lib/ui/views/equipment_view.dart](../lib/ui/views/equipment_view.dart) | 685 | — | — |
| [lib/ui/views/feedback_inbox_view.dart](../lib/ui/views/feedback_inbox_view.dart) | 355 | — | — |
| [lib/ui/views/finance_balances_tab.dart](../lib/ui/views/finance_balances_tab.dart) | 228 | — | — |
| [lib/ui/views/finance_cash_tab.dart](../lib/ui/views/finance_cash_tab.dart) | 462 | — | — |
| [lib/ui/views/finance_charts_tab.dart](../lib/ui/views/finance_charts_tab.dart) | 308 | — | — |
| [lib/ui/views/finance_definitions_tab.dart](../lib/ui/views/finance_definitions_tab.dart) | 363 | — | — |
| [lib/ui/views/finance_enforcement_view.dart](../lib/ui/views/finance_enforcement_view.dart) | 228 | — | — |
| [lib/ui/views/finance_expenses_tab.dart](../lib/ui/views/finance_expenses_tab.dart) | 480 | — | — |
| [lib/ui/views/finance_funds_section.dart](../lib/ui/views/finance_funds_section.dart) | 509 | — | — |
| [lib/ui/views/finance_late_fee_section.dart](../lib/ui/views/finance_late_fee_section.dart) | 409 | — | — |
| [lib/ui/views/finance_periods_tab.dart](../lib/ui/views/finance_periods_tab.dart) | 427 | — | — |
| [lib/ui/views/finance_reminder_card.dart](../lib/ui/views/finance_reminder_card.dart) | 163 | — | — |
| [lib/ui/views/finance_reports_tab.dart](../lib/ui/views/finance_reports_tab.dart) | 1918 | — | — |
| [lib/ui/views/finance_view.dart](../lib/ui/views/finance_view.dart) | 817 | — | — |
| [lib/ui/views/help_content.dart](../lib/ui/views/help_content.dart) | 972 | — | — |
| [lib/ui/views/help_view.dart](../lib/ui/views/help_view.dart) | 750 | — | — |
| [lib/ui/views/individual_home_view.dart](../lib/ui/views/individual_home_view.dart) | 1333 | [cekirdek-konum-mesafe-disi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-konum-mesafe-disi), [ui-kapi-ac-basari-tiki](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-ac-basari-tiki), [ui-bireysel-ana-ekran-kapilar](ariza-klavuzu/31-uygulama-arayuz.md#ui-bireysel-ana-ekran-kapilar), [ui-qr-konum-hatasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-konum-hatasi), [ui-ekran-qr-oku](ariza-klavuzu/31-uygulama-arayuz.md#ui-ekran-qr-oku) +2 | 31-uygulama-arayuz |
| [lib/ui/views/join_and_setup_view.dart](../lib/ui/views/join_and_setup_view.dart) | 285 | — | 31-uygulama-arayuz |
| [lib/ui/views/legal_consent_controller.dart](../lib/ui/views/legal_consent_controller.dart) | 144 | — | — |
| [lib/ui/views/legal_consent_field.dart](../lib/ui/views/legal_consent_field.dart) | 241 | — | — |
| [lib/ui/views/legal_consent_gate.dart](../lib/ui/views/legal_consent_gate.dart) | 253 | — | — |
| [lib/ui/views/legal_consent_page.dart](../lib/ui/views/legal_consent_page.dart) | 375 | — | — |
| [lib/ui/views/legal_document_view.dart](../lib/ui/views/legal_document_view.dart) | 262 | — | — |
| [lib/ui/views/legal_footer_links.dart](../lib/ui/views/legal_footer_links.dart) | 96 | — | — |
| [lib/ui/views/legal_markdown.dart](../lib/ui/views/legal_markdown.dart) | 856 | — | — |
| [lib/ui/views/legal_parts.dart](../lib/ui/views/legal_parts.dart) | 89 | — | — |
| [lib/ui/views/maintenance_view.dart](../lib/ui/views/maintenance_view.dart) | 176 | — | — |
| [lib/ui/views/managed_users_view.dart](../lib/ui/views/managed_users_view.dart) | 135 | [ui-kullanici-diyalogu-kaydet](ariza-klavuzu/31-uygulama-arayuz.md#ui-kullanici-diyalogu-kaydet) | 31-uygulama-arayuz |
| [lib/ui/views/management_company_view.dart](../lib/ui/views/management_company_view.dart) | 482 | — | — |
| [lib/ui/views/menu_layout_view.dart](../lib/ui/views/menu_layout_view.dart) | 566 | — | — |
| [lib/ui/views/meter_field_view.dart](../lib/ui/views/meter_field_view.dart) | 446 | — | — |
| [lib/ui/views/meters_view.dart](../lib/ui/views/meters_view.dart) | 778 | — | — |
| [lib/ui/views/module_requests_view.dart](../lib/ui/views/module_requests_view.dart) | 415 | — | — |
| [lib/ui/views/module_showcase_view.dart](../lib/ui/views/module_showcase_view.dart) | 1484 | — | — |
| [lib/ui/views/modules_view.dart](../lib/ui/views/modules_view.dart) | 620 | — | — |
| [lib/ui/views/my_apartment_vehicles.dart](../lib/ui/views/my_apartment_vehicles.dart) | 215 | — | — |
| [lib/ui/views/my_apartment_view.dart](../lib/ui/views/my_apartment_view.dart) | 575 | — | — |
| [lib/ui/views/my_finance_view.dart](../lib/ui/views/my_finance_view.dart) | 630 | — | — |
| [lib/ui/views/neighbor_board_view.dart](../lib/ui/views/neighbor_board_view.dart) | 318 | — | — |
| [lib/ui/views/onboarding_tour.dart](../lib/ui/views/onboarding_tour.dart) | 383 | — | — |
| [lib/ui/views/payment_notices_view.dart](../lib/ui/views/payment_notices_view.dart) | 376 | — | — |
| [lib/ui/views/pending_site_approvals_view.dart](../lib/ui/views/pending_site_approvals_view.dart) | 90 | [ui-abonelik-site-onay-menude-yok](ariza-klavuzu/31-uygulama-arayuz.md#ui-abonelik-site-onay-menude-yok) | 31-uygulama-arayuz |
| [lib/ui/views/people_apartments_tab.dart](../lib/ui/views/people_apartments_tab.dart) | 254 | — | — |
| [lib/ui/views/people_persons_tab.dart](../lib/ui/views/people_persons_tab.dart) | 763 | — | — |
| [lib/ui/views/people_team_tab.dart](../lib/ui/views/people_team_tab.dart) | 357 | — | — |
| [lib/ui/views/people_vehicles_tab.dart](../lib/ui/views/people_vehicles_tab.dart) | 219 | — | — |
| [lib/ui/views/people_view.dart](../lib/ui/views/people_view.dart) | 474 | — | — |
| [lib/ui/views/plate_recognition_view.dart](../lib/ui/views/plate_recognition_view.dart) | 824 | — | — |
| [lib/ui/views/platform_rules_view.dart](../lib/ui/views/platform_rules_view.dart) | 332 | — | — |
| [lib/ui/views/platform_settings_view.dart](../lib/ui/views/platform_settings_view.dart) | 889 | — | — |
| [lib/ui/views/profile_view.dart](../lib/ui/views/profile_view.dart) | 530 | [ui-profil-kaydet](ariza-klavuzu/31-uygulama-arayuz.md#ui-profil-kaydet) | 31-uygulama-arayuz |
| [lib/ui/views/reservation_areas_tab.dart](../lib/ui/views/reservation_areas_tab.dart) | 264 | — | — |
| [lib/ui/views/reservation_controllers.dart](../lib/ui/views/reservation_controllers.dart) | 722 | — | — |
| [lib/ui/views/reservation_manager_view.dart](../lib/ui/views/reservation_manager_view.dart) | 655 | — | — |
| [lib/ui/views/reservation_resident_view.dart](../lib/ui/views/reservation_resident_view.dart) | 665 | — | — |
| [lib/ui/views/site_applications_view.dart](../lib/ui/views/site_applications_view.dart) | 263 | — | — |
| [lib/ui/views/sites_view.dart](../lib/ui/views/sites_view.dart) | 714 | [ui-site-silme-akisi](ariza-klavuzu/31-uygulama-arayuz.md#ui-site-silme-akisi), [ui-site-listesi-yenilenmiyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-site-listesi-yenilenmiyor), [ui-katilim-qr-diyalogu](ariza-klavuzu/31-uygulama-arayuz.md#ui-katilim-qr-diyalogu), [ui-siteler-yetkisiz-dugme](ariza-klavuzu/31-uygulama-arayuz.md#ui-siteler-yetkisiz-dugme) | 31-uygulama-arayuz |
| [lib/ui/views/subscription_requests_view.dart](../lib/ui/views/subscription_requests_view.dart) | 90 | [ui-abonelik-site-onay-menude-yok](ariza-klavuzu/31-uygulama-arayuz.md#ui-abonelik-site-onay-menude-yok) | 31-uygulama-arayuz |
| [lib/ui/views/survey_manager_view.dart](../lib/ui/views/survey_manager_view.dart) | 659 | — | — |
| [lib/ui/views/survey_resident_view.dart](../lib/ui/views/survey_resident_view.dart) | 241 | — | — |
| [lib/ui/views/update_required_view.dart](../lib/ui/views/update_required_view.dart) | 277 | — | — |
| [lib/ui/views/visitor_manager_view.dart](../lib/ui/views/visitor_manager_view.dart) | 626 | — | — |
| [lib/ui/views/visitor_resident_view.dart](../lib/ui/views/visitor_resident_view.dart) | 359 | — | — |
| [lib/ui/views/work_detail_controllers.dart](../lib/ui/views/work_detail_controllers.dart) | 529 | — | — |
| [lib/ui/views/work_manager_view.dart](../lib/ui/views/work_manager_view.dart) | 645 | — | — |
| [lib/ui/views/work_report_tab.dart](../lib/ui/views/work_report_tab.dart) | 620 | — | — |
| [lib/ui/views/work_resident_view.dart](../lib/ui/views/work_resident_view.dart) | 351 | — | — |
| [lib/ui/views/yeni_site_view.dart](../lib/ui/views/yeni_site_view.dart) | 165 | — | — |
| [lib/ui/widgets/account_password_dialog.dart](../lib/ui/widgets/account_password_dialog.dart) | 295 | — | — |
| [lib/ui/widgets/account_privacy_section.dart](../lib/ui/widgets/account_privacy_section.dart) | 381 | — | — |
| [lib/ui/widgets/admin_door_status_card.dart](../lib/ui/widgets/admin_door_status_card.dart) | 519 | [ui-kapi-ac-yonetici](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-ac-yonetici), [ui-misafir-gecis-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-misafir-gecis-dugmesi) | 31-uygulama-arayuz |
| [lib/ui/widgets/announcement_parts.dart](../lib/ui/widgets/announcement_parts.dart) | 403 | — | — |
| [lib/ui/widgets/announcement_recipients_panel.dart](../lib/ui/widgets/announcement_recipients_panel.dart) | 221 | — | — |
| [lib/ui/widgets/apartment_card.dart](../lib/ui/widgets/apartment_card.dart) | 311 | [bilesen-daire-karti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-daire-karti) | — |
| [lib/ui/widgets/apartment_crm_card.dart](../lib/ui/widgets/apartment_crm_card.dart) | 137 | — | — |
| [lib/ui/widgets/apartment_household_section.dart](../lib/ui/widgets/apartment_household_section.dart) | 376 | — | — |
| [lib/ui/widgets/audit_log_card.dart](../lib/ui/widgets/audit_log_card.dart) | 192 | — | — |
| [lib/ui/widgets/bulk_confirm_dialog.dart](../lib/ui/widgets/bulk_confirm_dialog.dart) | 196 | — | — |
| [lib/ui/widgets/bulk_editable_table.dart](../lib/ui/widgets/bulk_editable_table.dart) | 1243 | — | — |
| [lib/ui/widgets/bulk_entry_buttons.dart](../lib/ui/widgets/bulk_entry_buttons.dart) | 35 | — | — |
| [lib/ui/widgets/bulk_error_notice.dart](../lib/ui/widgets/bulk_error_notice.dart) | 67 | — | — |
| [lib/ui/widgets/bulk_export_sheet.dart](../lib/ui/widgets/bulk_export_sheet.dart) | 334 | — | — |
| [lib/ui/widgets/bulk_export_sources.dart](../lib/ui/widgets/bulk_export_sources.dart) | 57 | — | — |
| [lib/ui/widgets/bulk_file_step.dart](../lib/ui/widgets/bulk_file_step.dart) | 211 | — | — |
| [lib/ui/widgets/bulk_kind_step.dart](../lib/ui/widgets/bulk_kind_step.dart) | 266 | — | — |
| [lib/ui/widgets/bulk_mapping_step.dart](../lib/ui/widgets/bulk_mapping_step.dart) | 296 | — | — |
| [lib/ui/widgets/bulk_preview_step.dart](../lib/ui/widgets/bulk_preview_step.dart) | 685 | — | — |
| [lib/ui/widgets/bulk_result_step.dart](../lib/ui/widgets/bulk_result_step.dart) | 271 | — | — |
| [lib/ui/widgets/bulk_step_header.dart](../lib/ui/widgets/bulk_step_header.dart) | 67 | — | — |
| [lib/ui/widgets/claim_device_dialog.dart](../lib/ui/widgets/claim_device_dialog.dart) | 245 | [ui-cihaz-sahiplen](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-sahiplen), [akis-cihaz-sahiplenme-wifi-kurulum](ariza-klavuzu/61-akislar-devam.md#akis-cihaz-sahiplenme-wifi-kurulum) | 31-uygulama-arayuz |
| [lib/ui/widgets/company_device_card.dart](../lib/ui/widgets/company_device_card.dart) | 342 | [ui-cihaz-envanteri](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-envanteri), [bilesen-cihaz-karti-durum](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-cihaz-karti-durum), [bilesen-cihaz-karti-ayrinti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-cihaz-karti-ayrinti) | 31-uygulama-arayuz |
| [lib/ui/widgets/context_strip.dart](../lib/ui/widgets/context_strip.dart) | 410 | — | — |
| [lib/ui/widgets/contract_parts.dart](../lib/ui/widgets/contract_parts.dart) | 577 | — | — |
| [lib/ui/widgets/crm_parts.dart](../lib/ui/widgets/crm_parts.dart) | 279 | — | — |
| [lib/ui/widgets/cursor_list_body.dart](../lib/ui/widgets/cursor_list_body.dart) | 105 | — | — |
| [lib/ui/widgets/decision_parts.dart](../lib/ui/widgets/decision_parts.dart) | 418 | — | — |
| [lib/ui/widgets/device_action_tile.dart](../lib/ui/widgets/device_action_tile.dart) | 54 | [bilesen-cihaz-eylem-karti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-cihaz-eylem-karti) | — |
| [lib/ui/widgets/device_connectivity_logs_accordion.dart](../lib/ui/widgets/device_connectivity_logs_accordion.dart) | 632 | [ui-koyu-tema-okunmuyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-koyu-tema-okunmuyor), [akis-cihaz-baglanti-gunlukleri](ariza-klavuzu/60-akislar.md#akis-cihaz-baglanti-gunlukleri) | 31-uygulama-arayuz |
| [lib/ui/widgets/dial_fallback.dart](../lib/ui/widgets/dial_fallback.dart) | 147 | — | — |
| [lib/ui/widgets/digital_clock_widget.dart](../lib/ui/widgets/digital_clock_widget.dart) | 353 | [bilesen-saat-donuyor](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-saat-donuyor), [bilesen-saat-tasma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-saat-tasma) | — |
| [lib/ui/widgets/document_attachment_field.dart](../lib/ui/widgets/document_attachment_field.dart) | 257 | — | — |
| [lib/ui/widgets/document_attachments_list.dart](../lib/ui/widgets/document_attachments_list.dart) | 187 | — | — |
| [lib/ui/widgets/document_form_fields.dart](../lib/ui/widgets/document_form_fields.dart) | 189 | — | — |
| [lib/ui/widgets/document_parts.dart](../lib/ui/widgets/document_parts.dart) | 495 | — | — |
| [lib/ui/widgets/document_target_section.dart](../lib/ui/widgets/document_target_section.dart) | 397 | — | — |
| [lib/ui/widgets/door_card.dart](../lib/ui/widgets/door_card.dart) | 264 | [ui-kapi-cihaz-ata](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-cihaz-ata), [ui-cihaz-degistir](ariza-klavuzu/31-uygulama-arayuz.md#ui-cihaz-degistir), [ui-kapi-yonet-yenilenmiyor](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-yonet-yenilenmiyor) | — |
| [lib/ui/widgets/door_control_disabled_card.dart](../lib/ui/widgets/door_control_disabled_card.dart) | 60 | — | — |
| [lib/ui/widgets/door_logs_accordion.dart](../lib/ui/widgets/door_logs_accordion.dart) | 662 | [bilesen-kapi-gecis-gecmisi](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-kapi-gecis-gecmisi), [akis-cevrimdisi-kapi-gunlukleri](ariza-klavuzu/60-akislar.md#akis-cevrimdisi-kapi-gunlukleri) | 31-uygulama-arayuz |
| [lib/ui/widgets/drive_storage_card.dart](../lib/ui/widgets/drive_storage_card.dart) | 263 | — | — |
| [lib/ui/widgets/dynamic_qr_pass_modal.dart](../lib/ui/widgets/dynamic_qr_pass_modal.dart) | 909 | [ui-qr-modal-sure](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-modal-sure), [ui-qr-modal-ret](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-modal-ret), [ui-qr-konum-hatasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-konum-hatasi), [akis-dinamik-qr-gm60](ariza-klavuzu/60-akislar.md#akis-dinamik-qr-gm60) | 31-uygulama-arayuz |
| [lib/ui/widgets/emergency_call_button.dart](../lib/ui/widgets/emergency_call_button.dart) | 133 | — | — |
| [lib/ui/widgets/expense_analysis_chart.dart](../lib/ui/widgets/expense_analysis_chart.dart) | 147 | — | — |
| [lib/ui/widgets/fee_spec_form.dart](../lib/ui/widgets/fee_spec_form.dart) | 404 | — | — |
| [lib/ui/widgets/finance_4b_parts.dart](../lib/ui/widgets/finance_4b_parts.dart) | 606 | — | — |
| [lib/ui/widgets/finance_account_parts.dart](../lib/ui/widgets/finance_account_parts.dart) | 119 | — | — |
| [lib/ui/widgets/finance_chart_reveal.dart](../lib/ui/widgets/finance_chart_reveal.dart) | 54 | — | — |
| [lib/ui/widgets/finance_charts_parts.dart](../lib/ui/widgets/finance_charts_parts.dart) | 670 | — | — |
| [lib/ui/widgets/finance_fund_parts.dart](../lib/ui/widgets/finance_fund_parts.dart) | 400 | — | — |
| [lib/ui/widgets/finance_parts.dart](../lib/ui/widgets/finance_parts.dart) | 937 | — | — |
| [lib/ui/widgets/finance_settings_controller.dart](../lib/ui/widgets/finance_settings_controller.dart) | 230 | — | — |
| [lib/ui/widgets/finance_target_picker.dart](../lib/ui/widgets/finance_target_picker.dart) | 437 | — | — |
| [lib/ui/widgets/hands_free_settings_dialog.dart](../lib/ui/widgets/hands_free_settings_dialog.dart) | 263 | [bilesen-eller-serbest-ayar](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-eller-serbest-ayar) | 31-uygulama-arayuz |
| [lib/ui/widgets/home_shortcut_button.dart](../lib/ui/widgets/home_shortcut_button.dart) | 45 | [ui-ana-sayfa-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-ana-sayfa-dugmesi) | 31-uygulama-arayuz |
| [lib/ui/widgets/individual_apartment_card.dart](../lib/ui/widgets/individual_apartment_card.dart) | 231 | [bilesen-bireysel-daire-karti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-bireysel-daire-karti) | — |
| [lib/ui/widgets/individual_door_card.dart](../lib/ui/widgets/individual_door_card.dart) | 436 | [ui-bireysel-kapi-karti-dugmeleri](ariza-klavuzu/31-uygulama-arayuz.md#ui-bireysel-kapi-karti-dugmeleri) | 31-uygulama-arayuz |
| [lib/ui/widgets/join_request_card.dart](../lib/ui/widgets/join_request_card.dart) | 92 | [bilesen-kurulum-secenek-karti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-kurulum-secenek-karti) | — |
| [lib/ui/widgets/language_picker.dart](../lib/ui/widgets/language_picker.dart) | 39 | — | — |
| [lib/ui/widgets/list_parts.dart](../lib/ui/widgets/list_parts.dart) | 516 | [ui-yazi-olcegi-tasma](ariza-klavuzu/31-uygulama-arayuz.md#ui-yazi-olcegi-tasma), [bilesen-liste-ortak-parcalar](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-liste-ortak-parcalar), [bilesen-genisleyen-kart](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-genisleyen-kart), [bilesen-liste-iskeleti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-liste-iskeleti), [bilesen-eylem-dugme-stilleri](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-eylem-dugme-stilleri) | 31-uygulama-arayuz |
| [lib/ui/widgets/managed_user_card.dart](../lib/ui/widgets/managed_user_card.dart) | 255 | [bilesen-genisleyen-kart](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-genisleyen-kart), [bilesen-yonetilen-kullanici-karti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-yonetilen-kullanici-karti) | — |
| [lib/ui/widgets/management_type_selector.dart](../lib/ui/widgets/management_type_selector.dart) | 205 | — | — |
| [lib/ui/widgets/manager_attention_bar.dart](../lib/ui/widgets/manager_attention_bar.dart) | 243 | — | — |
| [lib/ui/widgets/manager_call_tile.dart](../lib/ui/widgets/manager_call_tile.dart) | 344 | — | — |
| [lib/ui/widgets/module_card.dart](../lib/ui/widgets/module_card.dart) | 247 | — | — |
| [lib/ui/widgets/module_request_card.dart](../lib/ui/widgets/module_request_card.dart) | 149 | — | — |
| [lib/ui/widgets/money_field.dart](../lib/ui/widgets/money_field.dart) | 110 | — | — |
| [lib/ui/widgets/my_finance_4b_parts.dart](../lib/ui/widgets/my_finance_4b_parts.dart) | 164 | — | — |
| [lib/ui/widgets/my_records_section.dart](../lib/ui/widgets/my_records_section.dart) | 193 | — | — |
| [lib/ui/widgets/notification_prefs_section.dart](../lib/ui/widgets/notification_prefs_section.dart) | 280 | — | — |
| [lib/ui/widgets/panel_site_creation_card.dart](../lib/ui/widgets/panel_site_creation_card.dart) | 151 | — | — |
| [lib/ui/widgets/pay_sheet.dart](../lib/ui/widgets/pay_sheet.dart) | 332 | — | — |
| [lib/ui/widgets/payment_notice_status.dart](../lib/ui/widgets/payment_notice_status.dart) | 106 | — | — |
| [lib/ui/widgets/pending_invitations_card.dart](../lib/ui/widgets/pending_invitations_card.dart) | 111 | — | — |
| [lib/ui/widgets/person_card.dart](../lib/ui/widgets/person_card.dart) | 442 | — | — |
| [lib/ui/widgets/person_roles_panel.dart](../lib/ui/widgets/person_roles_panel.dart) | 536 | — | — |
| [lib/ui/widgets/platform_rules_entry_card.dart](../lib/ui/widgets/platform_rules_entry_card.dart) | 61 | — | — |
| [lib/ui/widgets/push_prefs_panel.dart](../lib/ui/widgets/push_prefs_panel.dart) | 785 | — | — |
| [lib/ui/widgets/push_soft_prompt_card.dart](../lib/ui/widgets/push_soft_prompt_card.dart) | 239 | — | — |
| [lib/ui/widgets/receipt_file_preview.dart](../lib/ui/widgets/receipt_file_preview.dart) | 101 | — | — |
| [lib/ui/widgets/refresh_action_button.dart](../lib/ui/widgets/refresh_action_button.dart) | 69 | — | — |
| [lib/ui/widgets/reservation_parts.dart](../lib/ui/widgets/reservation_parts.dart) | 704 | — | — |
| [lib/ui/widgets/residency_log_section.dart](../lib/ui/widgets/residency_log_section.dart) | 348 | — | — |
| [lib/ui/widgets/resident_bottom_bar.dart](../lib/ui/widgets/resident_bottom_bar.dart) | 99 | [ui-sakin-alt-cubuk](ariza-klavuzu/31-uygulama-arayuz.md#ui-sakin-alt-cubuk) | 31-uygulama-arayuz |
| [lib/ui/widgets/resident_door_actions.dart](../lib/ui/widgets/resident_door_actions.dart) | 184 | [cekirdek-konum-mesafe-disi](ariza-klavuzu/30-uygulama-cekirdek.md#cekirdek-konum-mesafe-disi), [ui-qr-konum-hatasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-qr-konum-hatasi), [ui-ekran-qr-oku](ariza-klavuzu/31-uygulama-arayuz.md#ui-ekran-qr-oku) | — |
| [lib/ui/widgets/resident_door_remote_card.dart](../lib/ui/widgets/resident_door_remote_card.dart) | 532 | [ui-kapi-ac-sakin](ariza-klavuzu/31-uygulama-arayuz.md#ui-kapi-ac-sakin), [ui-ekran-qr-oku](ariza-klavuzu/31-uygulama-arayuz.md#ui-ekran-qr-oku), [ui-misafir-gecis-dugmesi](ariza-klavuzu/31-uygulama-arayuz.md#ui-misafir-gecis-dugmesi) | 31-uygulama-arayuz |
| [lib/ui/widgets/search_visibility_section.dart](../lib/ui/widgets/search_visibility_section.dart) | 96 | — | — |
| [lib/ui/widgets/setup_option_card.dart](../lib/ui/widgets/setup_option_card.dart) | 98 | [bilesen-kurulum-secenek-karti](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-kurulum-secenek-karti) | — |
| [lib/ui/widgets/showcase_layouts.dart](../lib/ui/widgets/showcase_layouts.dart) | 266 | — | — |
| [lib/ui/widgets/site_application_parts.dart](../lib/ui/widgets/site_application_parts.dart) | 207 | — | — |
| [lib/ui/widgets/site_application_status_card.dart](../lib/ui/widgets/site_application_status_card.dart) | 467 | — | — |
| [lib/ui/widgets/site_approval_request_card.dart](../lib/ui/widgets/site_approval_request_card.dart) | 136 | [bilesen-onay-bekleyen-kartlar](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-onay-bekleyen-kartlar) | — |
| [lib/ui/widgets/site_card.dart](../lib/ui/widgets/site_card.dart) | 358 | [ui-site-silme-akisi](ariza-klavuzu/31-uygulama-arayuz.md#ui-site-silme-akisi), [ui-siteler-yetkisiz-dugme](ariza-klavuzu/31-uygulama-arayuz.md#ui-siteler-yetkisiz-dugme) | 31-uygulama-arayuz |
| [lib/ui/widgets/site_security_policy_dialog.dart](../lib/ui/widgets/site_security_policy_dialog.dart) | 794 | [ui-guvenlik-politikasi](ariza-klavuzu/31-uygulama-arayuz.md#ui-guvenlik-politikasi), [bilesen-guvenlik-politikasi-dogrulama](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-guvenlik-politikasi-dogrulama), [bilesen-guvenlik-politikasi-konum](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-guvenlik-politikasi-konum), [bilesen-guvenlik-politikasi-erisim](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-guvenlik-politikasi-erisim) | 31-uygulama-arayuz |
| [lib/ui/widgets/social_auth_buttons.dart](../lib/ui/widgets/social_auth_buttons.dart) | 426 | — | — |
| [lib/ui/widgets/staff_role_card.dart](../lib/ui/widgets/staff_role_card.dart) | 85 | — | — |
| [lib/ui/widgets/staff_roles_section.dart](../lib/ui/widgets/staff_roles_section.dart) | 259 | — | — |
| [lib/ui/widgets/state_view.dart](../lib/ui/widgets/state_view.dart) | 221 | — | — |
| [lib/ui/widgets/subscription_request_card.dart](../lib/ui/widgets/subscription_request_card.dart) | 116 | [bilesen-onay-bekleyen-kartlar](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-onay-bekleyen-kartlar) | — |
| [lib/ui/widgets/survey_parts.dart](../lib/ui/widgets/survey_parts.dart) | 364 | — | — |
| [lib/ui/widgets/team_redirect_card.dart](../lib/ui/widgets/team_redirect_card.dart) | 32 | — | — |
| [lib/ui/widgets/tile_grid.dart](../lib/ui/widgets/tile_grid.dart) | 72 | — | — |
| [lib/ui/widgets/unread_announcement_card.dart](../lib/ui/widgets/unread_announcement_card.dart) | 212 | — | — |
| [lib/ui/widgets/vehicle_card.dart](../lib/ui/widgets/vehicle_card.dart) | 86 | — | — |
| [lib/ui/widgets/visitor_log_parts.dart](../lib/ui/widgets/visitor_log_parts.dart) | 332 | — | — |
| [lib/ui/widgets/voice_control_modal.dart](../lib/ui/widgets/voice_control_modal.dart) | 400 | [bilesen-sesli-modal](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-sesli-modal), [bilesen-sesli-modal-tasma](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-sesli-modal-tasma) | 31-uygulama-arayuz |
| [lib/ui/widgets/voice_live_banner.dart](../lib/ui/widgets/voice_live_banner.dart) | 272 | [bilesen-sesli-banner](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-sesli-banner) | 31-uygulama-arayuz |
| [lib/ui/widgets/web_push_tile.dart](../lib/ui/widgets/web_push_tile.dart) | 126 | — | — |
| [lib/ui/widgets/work_attachment_parts.dart](../lib/ui/widgets/work_attachment_parts.dart) | 1164 | — | — |
| [lib/ui/widgets/work_tracking_parts.dart](../lib/ui/widgets/work_tracking_parts.dart) | 611 | — | — |
| [lib/ui/widgets/yan_menu.dart](../lib/ui/widgets/yan_menu.dart) | 1868 | [ui-mod-hapi](ariza-klavuzu/31-uygulama-arayuz.md#ui-mod-hapi), [ui-menu-yanlis-rol](ariza-klavuzu/31-uygulama-arayuz.md#ui-menu-yanlis-rol), [ui-abonelik-site-onay-menude-yok](ariza-klavuzu/31-uygulama-arayuz.md#ui-abonelik-site-onay-menude-yok), [bilesen-yan-menu-ogeleri](ariza-klavuzu/32-uygulama-bilesenler.md#bilesen-yan-menu-ogeleri) | 31-uygulama-arayuz |
| [server/scripts/_dev_guard.js](../server/scripts/_dev_guard.js) | 9 | [altyapi-apply-betikleri-dev-guard](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-betikleri-dev-guard), [altyapi-teshis-betikleri](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-teshis-betikleri), [altyapi-test-endpoint-artik-kullanici](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-test-endpoint-artik-kullanici) | 20-sunucu-altyapi-ve-yayin |
| [server/scripts/apply_013.js](../server/scripts/apply_013.js) | 24 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_014.js](../server/scripts/apply_014.js) | 25 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_015.js](../server/scripts/apply_015.js) | 29 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_016.js](../server/scripts/apply_016.js) | 52 | [altyapi-apply-betikleri-dev-guard](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-betikleri-dev-guard), [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_017.js](../server/scripts/apply_017.js) | 36 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_018.js](../server/scripts/apply_018.js) | 36 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_019.js](../server/scripts/apply_019.js) | 36 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_020.js](../server/scripts/apply_020.js) | 36 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_021.js](../server/scripts/apply_021.js) | 36 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_022.js](../server/scripts/apply_022.js) | 36 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_023.js](../server/scripts/apply_023.js) | 26 | [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/apply_024.js](../server/scripts/apply_024.js) | 26 | [altyapi-apply-betikleri-dev-guard](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-betikleri-dev-guard), [altyapi-apply-013-024-tek-seferlik](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-apply-013-024-tek-seferlik) | — |
| [server/scripts/check_devs.js](../server/scripts/check_devs.js) | 17 | [altyapi-teshis-betikleri](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-teshis-betikleri) | — |
| [server/scripts/check_screen_qr.js](../server/scripts/check_screen_qr.js) | 24 | [altyapi-teshis-betikleri](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-teshis-betikleri) | — |
| [server/scripts/documents_fsck.mjs](../server/scripts/documents_fsck.mjs) | 316 | — | — |
| [server/scripts/fix_duplicate_resident.mjs](../server/scripts/fix_duplicate_resident.mjs) | 63 | — | — |
| [server/scripts/kapi-mqtt-sync.sh](../server/scripts/kapi-mqtt-sync.sh) | 70 | [altyapi-kapi-mqtt-sync-betik-hatalari](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-kapi-mqtt-sync-betik-hatalari) | 20-sunucu-altyapi-ve-yayin |
| [server/scripts/migrate.js](../server/scripts/migrate.js) | 633 | [altyapi-sema-users-yok](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-sema-users-yok), [altyapi-relation-does-not-exist](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-relation-does-not-exist), [altyapi-migrate-baseline-reddi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-migrate-baseline-reddi), [altyapi-migrate-sql-hatasi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-migrate-sql-hatasi), [altyapi-migrate-uyarilar-checksum](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-migrate-uyarilar-checksum) +1 | 20-sunucu-altyapi-ve-yayin |
| [server/scripts/qa_apartment_pin_section.mjs](../server/scripts/qa_apartment_pin_section.mjs) | 480 | — | — |
| [server/scripts/qa_auth_attempt_limits_pg.mjs](../server/scripts/qa_auth_attempt_limits_pg.mjs) | 246 | — | — |
| [server/scripts/qa_bulk_import.mjs](../server/scripts/qa_bulk_import.mjs) | 1431 | — | — |
| [server/scripts/qa_card_access_section.mjs](../server/scripts/qa_card_access_section.mjs) | 363 | — | — |
| [server/scripts/qa_contracts_section.mjs](../server/scripts/qa_contracts_section.mjs) | 707 | — | — |
| [server/scripts/qa_decision_book_section.mjs](../server/scripts/qa_decision_book_section.mjs) | 590 | — | — |
| [server/scripts/qa_device_scope_pg.mjs](../server/scripts/qa_device_scope_pg.mjs) | 250 | — | — |
| [server/scripts/qa_documents_section.mjs](../server/scripts/qa_documents_section.mjs) | 1609 | — | — |
| [server/scripts/qa_finance_funds_section.mjs](../server/scripts/qa_finance_funds_section.mjs) | 779 | — | — |
| [server/scripts/qa_finance_parties_section.mjs](../server/scripts/qa_finance_parties_section.mjs) | 1119 | — | — |
| [server/scripts/qa_finance4b_accounts.mjs](../server/scripts/qa_finance4b_accounts.mjs) | 231 | — | — |
| [server/scripts/qa_finance4b_expenses.mjs](../server/scripts/qa_finance4b_expenses.mjs) | 351 | — | — |
| [server/scripts/qa_finance4b_late_fee.mjs](../server/scripts/qa_finance4b_late_fee.mjs) | 358 | — | — |
| [server/scripts/qa_finance4b_locks.mjs](../server/scripts/qa_finance4b_locks.mjs) | 343 | — | — |
| [server/scripts/qa_finance4b_r15.mjs](../server/scripts/qa_finance4b_r15.mjs) | 175 | — | — |
| [server/scripts/qa_finance4b_receipts.mjs](../server/scripts/qa_finance4b_receipts.mjs) | 208 | — | — |
| [server/scripts/qa_finance4b_reminders.mjs](../server/scripts/qa_finance4b_reminders.mjs) | 336 | — | — |
| [server/scripts/qa_finance4b_reports.mjs](../server/scripts/qa_finance4b_reports.mjs) | 292 | — | — |
| [server/scripts/qa_finance4b_resident_scope.mjs](../server/scripts/qa_finance4b_resident_scope.mjs) | 256 | — | — |
| [server/scripts/qa_finance4b_review.mjs](../server/scripts/qa_finance4b_review.mjs) | 315 | — | — |
| [server/scripts/qa_finance4b_upgrade.mjs](../server/scripts/qa_finance4b_upgrade.mjs) | 445 | — | — |
| [server/scripts/qa_finance4b.mjs](../server/scripts/qa_finance4b.mjs) | 379 | — | — |
| [server/scripts/qa_pending_registration_pg.mjs](../server/scripts/qa_pending_registration_pg.mjs) | 276 | [test-gercek-pg-qa](ariza-klavuzu/50-arac-test-ve-surec.md#test-gercek-pg-qa) | 50-arac-test-ve-surec |
| [server/scripts/qa_platform_pg.mjs](../server/scripts/qa_platform_pg.mjs) | 11955 | — | — |
| [server/scripts/qa_platform_rules_section.mjs](../server/scripts/qa_platform_rules_section.mjs) | 318 | — | — |
| [server/scripts/qa_push_section.mjs](../server/scripts/qa_push_section.mjs) | 727 | — | — |
| [server/scripts/qa_reservation_section.mjs](../server/scripts/qa_reservation_section.mjs) | 928 | — | — |
| [server/scripts/qa_survey_section.mjs](../server/scripts/qa_survey_section.mjs) | 342 | — | — |
| [server/scripts/qa_tenant_admin_section.mjs](../server/scripts/qa_tenant_admin_section.mjs) | 694 | — | — |
| [server/scripts/qa_visitor_log_section.mjs](../server/scripts/qa_visitor_log_section.mjs) | 415 | — | — |
| [server/scripts/qa_work_tracking_section.mjs](../server/scripts/qa_work_tracking_section.mjs) | 1239 | — | — |
| [server/scripts/sync_mqtt_acl.js](../server/scripts/sync_mqtt_acl.js) | 116 | [altyapi-mqtt-kimlik-reddi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-mqtt-kimlik-reddi), [altyapi-mqtt-acl-yayin-reddi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-mqtt-acl-yayin-reddi), [altyapi-acl-cihaz-atlandi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-acl-cihaz-atlandi), [altyapi-acl-silinen-cihaz-baglaniyor](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-acl-silinen-cihaz-baglaniyor) | 20-sunucu-altyapi-ve-yayin |
| [server/scripts/test_doors_qr.js](../server/scripts/test_doors_qr.js) | 25 | [altyapi-teshis-betikleri](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-teshis-betikleri) | — |
| [server/scripts/test_endpoint.js](../server/scripts/test_endpoint.js) | 33 | [altyapi-test-endpoint-artik-kullanici](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-test-endpoint-artik-kullanici) | — |
| [server/scripts/test_query.js](../server/scripts/test_query.js) | 15 | [altyapi-teshis-betikleri](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-teshis-betikleri) | — |
| [server/scripts/trigger_ota.js](../server/scripts/trigger_ota.js) | 78 | [altyapi-sertifika-suresi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-sertifika-suresi), [altyapi-ota-toplu-komut-hatasi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-ota-toplu-komut-hatasi) | 20-sunucu-altyapi-ve-yayin |
| [server/src/config/cors.js](../server/src/config/cors.js) | 82 | [sunucu-cors-tarayici-engeli](ariza-klavuzu/10-sunucu-api.md#sunucu-cors-tarayici-engeli) | 10-sunucu-api |
| [server/src/config/env.js](../server/src/config/env.js) | 363 | [sunucu-kayit-kod-gelmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-kod-gelmiyor), [sunucu-eposta-hic-cikmiyor-smtp](ariza-klavuzu/10-sunucu-api.md#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-cors-tarayici-engeli](ariza-klavuzu/10-sunucu-api.md#sunucu-cors-tarayici-engeli), [sunucu-sirket-ucu-401-anahtar](ariza-klavuzu/10-sunucu-api.md#sunucu-sirket-ucu-401-anahtar), [altyapi-env-hata-sunucu-baslamiyor](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-env-hata-sunucu-baslamiyor) +6 | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin |
| [server/src/config/process_handlers.js](../server/src/config/process_handlers.js) | 39 | [sunucu-async-hata-istek-asili](ariza-klavuzu/10-sunucu-api.md#sunucu-async-hata-istek-asili), [altyapi-api-acilmiyor-pm2-dongu](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-api-acilmiyor-pm2-dongu), [altyapi-port-8080-kullanimda](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-port-8080-kullanimda), [altyapi-yakalanmamis-hata-loglari](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-yakalanmamis-hata-loglari) | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin |
| [server/src/db.js](../server/src/db.js) | 2080 | [altyapi-health-database-disconnected](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-health-database-disconnected), [altyapi-sema-users-yok](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-sema-users-yok), [altyapi-relation-does-not-exist](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-relation-does-not-exist), [altyapi-sema-baslangic-sql-hatasi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-sema-baslangic-sql-hatasi), [altyapi-db-havuz-zaman-asimi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-db-havuz-zaman-asimi) +3 | 20-sunucu-altyapi-ve-yayin |
| [server/src/jwt.js](../server/src/jwt.js) | 128 | [sunucu-token-401-gecersiz](ariza-klavuzu/10-sunucu-api.md#sunucu-token-401-gecersiz), [sunucu-token-revoked-parola-degisti](ariza-klavuzu/10-sunucu-api.md#sunucu-token-revoked-parola-degisti) | 10-sunucu-api |
| [server/src/mailer.js](../server/src/mailer.js) | 810 | [sunucu-kayit-kod-gelmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-kod-gelmiyor), [sunucu-sifre-sifirlama-mail-gelmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-sifre-sifirlama-mail-gelmiyor), [sunucu-eposta-hic-cikmiyor-smtp](ariza-klavuzu/10-sunucu-api.md#sunucu-eposta-hic-cikmiyor-smtp), [sunucu-yonetici-daveti-mail-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-daveti-mail-yok), [sunucu-daire-bilgisi-eposta-gitmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-daire-bilgisi-eposta-gitmiyor) +2 | 10-sunucu-api |
| [server/src/middlewares/auth_middleware.js](../server/src/middlewares/auth_middleware.js) | 182 | [sunucu-token-401-gecersiz](ariza-klavuzu/10-sunucu-api.md#sunucu-token-401-gecersiz), [sunucu-token-revoked-parola-degisti](ariza-klavuzu/10-sunucu-api.md#sunucu-token-revoked-parola-degisti), [sunucu-oturum-401-kullanici-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-oturum-401-kullanici-yok), [sunucu-oturum-403-hesap-pasif](ariza-klavuzu/10-sunucu-api.md#sunucu-oturum-403-hesap-pasif), [sunucu-db-kesintisi-500-oturum-dusmuyor](ariza-klavuzu/10-sunucu-api.md#sunucu-db-kesintisi-500-oturum-dusmuyor) +5 | 10-sunucu-api |
| [server/src/middlewares/company_auth.js](../server/src/middlewares/company_auth.js) | 73 | [sunucu-sirket-ucu-401-anahtar](ariza-klavuzu/10-sunucu-api.md#sunucu-sirket-ucu-401-anahtar), [arac-sunucu-401](ariza-klavuzu/50-arac-test-ve-surec.md#arac-sunucu-401) | 10-sunucu-api |
| [server/src/middlewares/error_handler.js](../server/src/middlewares/error_handler.js) | 155 | [sunucu-db-kesintisi-500-oturum-dusmuyor](ariza-klavuzu/10-sunucu-api.md#sunucu-db-kesintisi-500-oturum-dusmuyor), [sunucu-hata-500-errorid](ariza-klavuzu/10-sunucu-api.md#sunucu-hata-500-errorid) | 10-sunucu-api |
| [server/src/middlewares/login_throttle.js](../server/src/middlewares/login_throttle.js) | 170 | [sunucu-giris-hesap-kilitli-429](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-hesap-kilitli-429), [sunucu-profil-parola-degistirme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-profil-parola-degistirme-hata) | 10-sunucu-api |
| [server/src/middlewares/rate_limiters.js](../server/src/middlewares/rate_limiters.js) | 309 | [sunucu-giris-ip-hiz-siniri-429](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-ip-hiz-siniri-429), [sunucu-kayit-429-bekleme-sinir](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-429-bekleme-sinir), [sunucu-dogrulama-429-deneme-asildi](ariza-klavuzu/10-sunucu-api.md#sunucu-dogrulama-429-deneme-asildi), [sunucu-sifre-sifirlama-mail-gelmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-sifre-sifirlama-mail-gelmiyor), [sunucu-kapi-acma-429-cok-sik](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-429-cok-sik) +2 | 10-sunucu-api |
| [server/src/middlewares/request_logger.js](../server/src/middlewares/request_logger.js) | 64 | [sunucu-istek-gunlugu-ve-basliklar](ariza-klavuzu/10-sunucu-api.md#sunucu-istek-gunlugu-ve-basliklar) | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin |
| [server/src/middlewares/security_headers.js](../server/src/middlewares/security_headers.js) | 23 | [sunucu-istek-gunlugu-ve-basliklar](ariza-klavuzu/10-sunucu-api.md#sunucu-istek-gunlugu-ve-basliklar) | 10-sunucu-api |
| [server/src/modules/account_common.js](../server/src/modules/account_common.js) | 169 | [sunucu-profil-parola-degistirme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-profil-parola-degistirme-hata) | — |
| [server/src/modules/account_deletion_service.js](../server/src/modules/account_deletion_service.js) | 1009 | — | — |
| [server/src/modules/account_export_service.js](../server/src/modules/account_export_service.js) | 692 | — | — |
| [server/src/modules/account_password_guard.js](../server/src/modules/account_password_guard.js) | 87 | [sunucu-profil-parola-degistirme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-profil-parola-degistirme-hata) | — |
| [server/src/modules/account_routes.js](../server/src/modules/account_routes.js) | 98 | — | — |
| [server/src/modules/announcement_common.js](../server/src/modules/announcement_common.js) | 624 | — | — |
| [server/src/modules/announcement_email_queue.js](../server/src/modules/announcement_email_queue.js) | 440 | — | — |
| [server/src/modules/announcement_email_security.js](../server/src/modules/announcement_email_security.js) | 176 | — | — |
| [server/src/modules/announcement_hide_schema.js](../server/src/modules/announcement_hide_schema.js) | 71 | — | — |
| [server/src/modules/announcement_inbox.js](../server/src/modules/announcement_inbox.js) | 470 | — | — |
| [server/src/modules/announcement_lock.js](../server/src/modules/announcement_lock.js) | 60 | — | — |
| [server/src/modules/announcement_public_routes.js](../server/src/modules/announcement_public_routes.js) | 212 | — | — |
| [server/src/modules/announcement_recipients.js](../server/src/modules/announcement_recipients.js) | 418 | — | — |
| [server/src/modules/announcement_routes.js](../server/src/modules/announcement_routes.js) | 314 | — | — |
| [server/src/modules/announcement_scheduler.js](../server/src/modules/announcement_scheduler.js) | 211 | — | — |
| [server/src/modules/announcement_service.js](../server/src/modules/announcement_service.js) | 1104 | — | — |
| [server/src/modules/annual_report_routes.js](../server/src/modules/annual_report_routes.js) | 73 | — | — |
| [server/src/modules/annual_report_schema.js](../server/src/modules/annual_report_schema.js) | 37 | — | — |
| [server/src/modules/annual_report_service.js](../server/src/modules/annual_report_service.js) | 311 | — | — |
| [server/src/modules/apartment_admin_successor.js](../server/src/modules/apartment_admin_successor.js) | 48 | — | — |
| [server/src/modules/apartment_delegation_close.js](../server/src/modules/apartment_delegation_close.js) | 61 | — | — |
| [server/src/modules/apartment_deletion_audit.js](../server/src/modules/apartment_deletion_audit.js) | 117 | — | — |
| [server/src/modules/apartment_mgmt_core.js](../server/src/modules/apartment_mgmt_core.js) | 193 | — | — |
| [server/src/modules/apartment_mgmt_household.js](../server/src/modules/apartment_mgmt_household.js) | 229 | — | — |
| [server/src/modules/apartment_mgmt_manager.js](../server/src/modules/apartment_mgmt_manager.js) | 195 | — | — |
| [server/src/modules/apartment_mgmt_proxy.js](../server/src/modules/apartment_mgmt_proxy.js) | 192 | — | — |
| [server/src/modules/apartment_mgmt_routes.js](../server/src/modules/apartment_mgmt_routes.js) | 458 | — | — |
| [server/src/modules/apartment_mgmt_rules.js](../server/src/modules/apartment_mgmt_rules.js) | 396 | — | — |
| [server/src/modules/apartment_mgmt_safety.js](../server/src/modules/apartment_mgmt_safety.js) | 302 | — | — |
| [server/src/modules/apartment_mgmt_schema.js](../server/src/modules/apartment_mgmt_schema.js) | 327 | — | — |
| [server/src/modules/apartment_mgmt_service.js](../server/src/modules/apartment_mgmt_service.js) | 1295 | — | — |
| [server/src/modules/apartment_mgmt_vehicles.js](../server/src/modules/apartment_mgmt_vehicles.js) | 339 | — | — |
| [server/src/modules/apartment_pin_schema.js](../server/src/modules/apartment_pin_schema.js) | 283 | — | — |
| [server/src/modules/apartment_records_service.js](../server/src/modules/apartment_records_service.js) | 403 | — | — |
| [server/src/modules/apartment_tenant_admin_sql.js](../server/src/modules/apartment_tenant_admin_sql.js) | 154 | — | — |
| [server/src/modules/apartment_tenant_admin.js](../server/src/modules/apartment_tenant_admin.js) | 56 | — | — |
| [server/src/modules/app_config_routes.js](../server/src/modules/app_config_routes.js) | 79 | — | — |
| [server/src/modules/attention_registry.js](../server/src/modules/attention_registry.js) | 41 | — | — |
| [server/src/modules/audit_service.js](../server/src/modules/audit_service.js) | 192 | — | — |
| [server/src/modules/auth_attempt_limits_schema.js](../server/src/modules/auth_attempt_limits_schema.js) | 28 | — | — |
| [server/src/modules/bank_import_common.js](../server/src/modules/bank_import_common.js) | 104 | — | — |
| [server/src/modules/bank_import_routes.js](../server/src/modules/bank_import_routes.js) | 108 | — | — |
| [server/src/modules/bank_import_schema.js](../server/src/modules/bank_import_schema.js) | 111 | — | — |
| [server/src/modules/bank_import_service.js](../server/src/modules/bank_import_service.js) | 458 | — | — |
| [server/src/modules/bank_line_match.js](../server/src/modules/bank_line_match.js) | 144 | — | — |
| [server/src/modules/bank_line_service.js](../server/src/modules/bank_line_service.js) | 309 | — | — |
| [server/src/modules/bank_match_hints.js](../server/src/modules/bank_match_hints.js) | 99 | — | — |
| [server/src/modules/bank_pdf_parser.js](../server/src/modules/bank_pdf_parser.js) | 435 | — | — |
| [server/src/modules/bank_pdf_service.js](../server/src/modules/bank_pdf_service.js) | 84 | — | — |
| [server/src/modules/bank_pdf_worker.js](../server/src/modules/bank_pdf_worker.js) | 71 | — | — |
| [server/src/modules/brand_theme_common.js](../server/src/modules/brand_theme_common.js) | 92 | — | — |
| [server/src/modules/brand_theme_routes.js](../server/src/modules/brand_theme_routes.js) | 51 | — | — |
| [server/src/modules/brand_theme_schema.js](../server/src/modules/brand_theme_schema.js) | 40 | — | — |
| [server/src/modules/brand_theme_service.js](../server/src/modules/brand_theme_service.js) | 148 | — | — |
| [server/src/modules/budget_routes.js](../server/src/modules/budget_routes.js) | 142 | — | — |
| [server/src/modules/budget_schema.js](../server/src/modules/budget_schema.js) | 133 | — | — |
| [server/src/modules/budget_service.js](../server/src/modules/budget_service.js) | 409 | — | — |
| [server/src/modules/bulk_import_accounts.js](../server/src/modules/bulk_import_accounts.js) | 194 | — | — |
| [server/src/modules/bulk_import_body.js](../server/src/modules/bulk_import_body.js) | 192 | — | — |
| [server/src/modules/bulk_import_export.js](../server/src/modules/bulk_import_export.js) | 456 | — | — |
| [server/src/modules/bulk_import_login_names.js](../server/src/modules/bulk_import_login_names.js) | 263 | — | — |
| [server/src/modules/bulk_import_messages.js](../server/src/modules/bulk_import_messages.js) | 263 | — | — |
| [server/src/modules/bulk_import_opening_schema.js](../server/src/modules/bulk_import_opening_schema.js) | 71 | — | — |
| [server/src/modules/bulk_import_parsers.js](../server/src/modules/bulk_import_parsers.js) | 531 | — | — |
| [server/src/modules/bulk_import_plan_all_in_one.js](../server/src/modules/bulk_import_plan_all_in_one.js) | 182 | — | — |
| [server/src/modules/bulk_import_plan_apartments.js](../server/src/modules/bulk_import_plan_apartments.js) | 217 | — | — |
| [server/src/modules/bulk_import_plan_common.js](../server/src/modules/bulk_import_plan_common.js) | 189 | — | — |
| [server/src/modules/bulk_import_plan_opening.js](../server/src/modules/bulk_import_plan_opening.js) | 114 | — | — |
| [server/src/modules/bulk_import_plan_people.js](../server/src/modules/bulk_import_plan_people.js) | 652 | — | — |
| [server/src/modules/bulk_import_plan.js](../server/src/modules/bulk_import_plan.js) | 46 | — | — |
| [server/src/modules/bulk_import_routes.js](../server/src/modules/bulk_import_routes.js) | 241 | — | — |
| [server/src/modules/bulk_import_schema.js](../server/src/modules/bulk_import_schema.js) | 128 | — | — |
| [server/src/modules/bulk_import_scope.js](../server/src/modules/bulk_import_scope.js) | 51 | — | — |
| [server/src/modules/bulk_import_service.js](../server/src/modules/bulk_import_service.js) | 522 | — | — |
| [server/src/modules/bulk_import_snapshot.js](../server/src/modules/bulk_import_snapshot.js) | 157 | — | — |
| [server/src/modules/bulk_import_spec.js](../server/src/modules/bulk_import_spec.js) | 245 | — | — |
| [server/src/modules/bulk_import_writer.js](../server/src/modules/bulk_import_writer.js) | 734 | — | — |
| [server/src/modules/card_access_access.js](../server/src/modules/card_access_access.js) | 44 | — | — |
| [server/src/modules/card_access_common.js](../server/src/modules/card_access_common.js) | 143 | — | — |
| [server/src/modules/card_access_routes.js](../server/src/modules/card_access_routes.js) | 117 | — | — |
| [server/src/modules/card_access_schema.js](../server/src/modules/card_access_schema.js) | 137 | — | — |
| [server/src/modules/card_access_service.js](../server/src/modules/card_access_service.js) | 218 | — | — |
| [server/src/modules/card_access_verify.js](../server/src/modules/card_access_verify.js) | 67 | — | — |
| [server/src/modules/card_payments_into_finance.js](../server/src/modules/card_payments_into_finance.js) | 18 | — | — |
| [server/src/modules/cargo_notify.js](../server/src/modules/cargo_notify.js) | 77 | — | — |
| [server/src/modules/catalog.js](../server/src/modules/catalog.js) | 374 | — | — |
| [server/src/modules/cctv_routes.js](../server/src/modules/cctv_routes.js) | 144 | — | — |
| [server/src/modules/cctv_schema.js](../server/src/modules/cctv_schema.js) | 113 | — | — |
| [server/src/modules/cctv_service.js](../server/src/modules/cctv_service.js) | 447 | — | — |
| [server/src/modules/cctv_snapshot.js](../server/src/modules/cctv_snapshot.js) | 208 | — | — |
| [server/src/modules/client_error_purge.js](../server/src/modules/client_error_purge.js) | 72 | — | — |
| [server/src/modules/client_error_routes.js](../server/src/modules/client_error_routes.js) | 100 | — | — |
| [server/src/modules/client_error_service.js](../server/src/modules/client_error_service.js) | 435 | — | — |
| [server/src/modules/contracts_access.js](../server/src/modules/contracts_access.js) | 64 | — | — |
| [server/src/modules/contracts_common.js](../server/src/modules/contracts_common.js) | 524 | — | — |
| [server/src/modules/contracts_reminders.js](../server/src/modules/contracts_reminders.js) | 466 | — | — |
| [server/src/modules/contracts_routes.js](../server/src/modules/contracts_routes.js) | 165 | — | — |
| [server/src/modules/contracts_schema.js](../server/src/modules/contracts_schema.js) | 236 | — | — |
| [server/src/modules/contracts_service.js](../server/src/modules/contracts_service.js) | 510 | — | — |
| [server/src/modules/core_modules.js](../server/src/modules/core_modules.js) | 78 | — | — |
| [server/src/modules/credential_revocation.js](../server/src/modules/credential_revocation.js) | 34 | — | — |
| [server/src/modules/decision_book_access.js](../server/src/modules/decision_book_access.js) | 45 | — | — |
| [server/src/modules/decision_book_common.js](../server/src/modules/decision_book_common.js) | 395 | — | — |
| [server/src/modules/decision_book_resident.js](../server/src/modules/decision_book_resident.js) | 145 | — | — |
| [server/src/modules/decision_book_routes.js](../server/src/modules/decision_book_routes.js) | 149 | — | — |
| [server/src/modules/decision_book_schema.js](../server/src/modules/decision_book_schema.js) | 269 | — | — |
| [server/src/modules/decision_book_service.js](../server/src/modules/decision_book_service.js) | 416 | — | — |
| [server/src/modules/device_integrations_routes.js](../server/src/modules/device_integrations_routes.js) | 180 | — | — |
| [server/src/modules/device_integrations_schema.js](../server/src/modules/device_integrations_schema.js) | 117 | — | — |
| [server/src/modules/device_integrations_service.js](../server/src/modules/device_integrations_service.js) | 252 | — | — |
| [server/src/modules/document_access.js](../server/src/modules/document_access.js) | 35 | — | — |
| [server/src/modules/document_attachments.js](../server/src/modules/document_attachments.js) | 193 | — | — |
| [server/src/modules/document_common.js](../server/src/modules/document_common.js) | 513 | — | — |
| [server/src/modules/document_download.js](../server/src/modules/document_download.js) | 121 | — | — |
| [server/src/modules/document_integrity.js](../server/src/modules/document_integrity.js) | 248 | — | — |
| [server/src/modules/document_maintenance.js](../server/src/modules/document_maintenance.js) | 619 | — | — |
| [server/src/modules/document_resident.js](../server/src/modules/document_resident.js) | 266 | — | — |
| [server/src/modules/document_routes.js](../server/src/modules/document_routes.js) | 353 | — | — |
| [server/src/modules/document_schema.js](../server/src/modules/document_schema.js) | 250 | — | — |
| [server/src/modules/document_service.js](../server/src/modules/document_service.js) | 1054 | — | — |
| [server/src/modules/document_storage.js](../server/src/modules/document_storage.js) | 436 | — | — |
| [server/src/modules/document_upload.js](../server/src/modules/document_upload.js) | 261 | — | — |
| [server/src/modules/document_validation.js](../server/src/modules/document_validation.js) | 478 | — | — |
| [server/src/modules/documents_into_drive.js](../server/src/modules/documents_into_drive.js) | 46 | — | — |
| [server/src/modules/door_guard.js](../server/src/modules/door_guard.js) | 61 | — | — |
| [server/src/modules/drive_client.js](../server/src/modules/drive_client.js) | 132 | — | — |
| [server/src/modules/drive_common.js](../server/src/modules/drive_common.js) | 162 | — | — |
| [server/src/modules/drive_routes.js](../server/src/modules/drive_routes.js) | 166 | — | — |
| [server/src/modules/drive_schema.js](../server/src/modules/drive_schema.js) | 174 | — | — |
| [server/src/modules/drive_service.js](../server/src/modules/drive_service.js) | 393 | — | — |
| [server/src/modules/equipment_routes.js](../server/src/modules/equipment_routes.js) | 130 | — | — |
| [server/src/modules/equipment_schema.js](../server/src/modules/equipment_schema.js) | 182 | — | — |
| [server/src/modules/equipment_service.js](../server/src/modules/equipment_service.js) | 642 | — | — |
| [server/src/modules/errors.js](../server/src/modules/errors.js) | 24 | — | — |
| [server/src/modules/feedback_common.js](../server/src/modules/feedback_common.js) | 272 | — | — |
| [server/src/modules/feedback_maintenance.js](../server/src/modules/feedback_maintenance.js) | 51 | — | — |
| [server/src/modules/feedback_routes.js](../server/src/modules/feedback_routes.js) | 165 | — | — |
| [server/src/modules/feedback_schema.js](../server/src/modules/feedback_schema.js) | 166 | — | — |
| [server/src/modules/feedback_service.js](../server/src/modules/feedback_service.js) | 412 | — | — |
| [server/src/modules/feedback_upload.js](../server/src/modules/feedback_upload.js) | 226 | — | — |
| [server/src/modules/finance_4b_common.js](../server/src/modules/finance_4b_common.js) | 289 | — | — |
| [server/src/modules/finance_4b_guard.js](../server/src/modules/finance_4b_guard.js) | 54 | — | — |
| [server/src/modules/finance_4b_routes.js](../server/src/modules/finance_4b_routes.js) | 539 | — | — |
| [server/src/modules/finance_4b_schema.js](../server/src/modules/finance_4b_schema.js) | 1264 | — | — |
| [server/src/modules/finance_access.js](../server/src/modules/finance_access.js) | 39 | — | — |
| [server/src/modules/finance_accounts.js](../server/src/modules/finance_accounts.js) | 1147 | — | — |
| [server/src/modules/finance_charts.js](../server/src/modules/finance_charts.js) | 150 | — | — |
| [server/src/modules/finance_common.js](../server/src/modules/finance_common.js) | 1139 | — | — |
| [server/src/modules/finance_distribution.js](../server/src/modules/finance_distribution.js) | 287 | — | — |
| [server/src/modules/finance_documents_adapter.js](../server/src/modules/finance_documents_adapter.js) | 179 | — | — |
| [server/src/modules/finance_enforcement.js](../server/src/modules/finance_enforcement.js) | 141 | — | — |
| [server/src/modules/finance_expense_analysis.js](../server/src/modules/finance_expense_analysis.js) | 267 | — | — |
| [server/src/modules/finance_expense_documents.js](../server/src/modules/finance_expense_documents.js) | 332 | — | — |
| [server/src/modules/finance_expense_nature_schema.js](../server/src/modules/finance_expense_nature_schema.js) | 91 | — | — |
| [server/src/modules/finance_expense_nature.js](../server/src/modules/finance_expense_nature.js) | 163 | — | — |
| [server/src/modules/finance_expenses.js](../server/src/modules/finance_expenses.js) | 866 | — | — |
| [server/src/modules/finance_export_tables.js](../server/src/modules/finance_export_tables.js) | 383 | — | — |
| [server/src/modules/finance_funds_routes.js](../server/src/modules/finance_funds_routes.js) | 83 | — | — |
| [server/src/modules/finance_funds_schema.js](../server/src/modules/finance_funds_schema.js) | 395 | — | — |
| [server/src/modules/finance_funds_service.js](../server/src/modules/finance_funds_service.js) | 508 | — | — |
| [server/src/modules/finance_funds.js](../server/src/modules/finance_funds.js) | 378 | — | — |
| [server/src/modules/finance_home_routes.js](../server/src/modules/finance_home_routes.js) | 28 | — | — |
| [server/src/modules/finance_home.js](../server/src/modules/finance_home.js) | 175 | — | — |
| [server/src/modules/finance_iban.js](../server/src/modules/finance_iban.js) | 39 | — | — |
| [server/src/modules/finance_late_fee_calc.js](../server/src/modules/finance_late_fee_calc.js) | 180 | — | — |
| [server/src/modules/finance_late_fee.js](../server/src/modules/finance_late_fee.js) | 778 | — | — |
| [server/src/modules/finance_ledger_service.js](../server/src/modules/finance_ledger_service.js) | 538 | — | — |
| [server/src/modules/finance_m1.js](../server/src/modules/finance_m1.js) | 91 | — | — |
| [server/src/modules/finance_money.js](../server/src/modules/finance_money.js) | 87 | — | — |
| [server/src/modules/finance_opening_routes.js](../server/src/modules/finance_opening_routes.js) | 43 | — | — |
| [server/src/modules/finance_opening.js](../server/src/modules/finance_opening.js) | 187 | — | — |
| [server/src/modules/finance_parties_schema.js](../server/src/modules/finance_parties_schema.js) | 306 | — | — |
| [server/src/modules/finance_parties.js](../server/src/modules/finance_parties.js) | 484 | — | — |
| [server/src/modules/finance_payment_info.js](../server/src/modules/finance_payment_info.js) | 411 | — | — |
| [server/src/modules/finance_payment_ref.js](../server/src/modules/finance_payment_ref.js) | 152 | — | — |
| [server/src/modules/finance_payment_routes.js](../server/src/modules/finance_payment_routes.js) | 63 | — | — |
| [server/src/modules/finance_payment_schema.js](../server/src/modules/finance_payment_schema.js) | 288 | — | — |
| [server/src/modules/finance_read_service.js](../server/src/modules/finance_read_service.js) | 719 | — | — |
| [server/src/modules/finance_receipts.js](../server/src/modules/finance_receipts.js) | 850 | — | — |
| [server/src/modules/finance_reminder_mail.js](../server/src/modules/finance_reminder_mail.js) | 133 | — | — |
| [server/src/modules/finance_reminder_queue.js](../server/src/modules/finance_reminder_queue.js) | 550 | — | — |
| [server/src/modules/finance_reminder_scheduler.js](../server/src/modules/finance_reminder_scheduler.js) | 88 | — | — |
| [server/src/modules/finance_reminders.js](../server/src/modules/finance_reminders.js) | 698 | — | — |
| [server/src/modules/finance_reports.js](../server/src/modules/finance_reports.js) | 906 | — | — |
| [server/src/modules/finance_resident_view.js](../server/src/modules/finance_resident_view.js) | 137 | — | — |
| [server/src/modules/finance_routes.js](../server/src/modules/finance_routes.js) | 302 | — | — |
| [server/src/modules/finance_service.js](../server/src/modules/finance_service.js) | 752 | — | — |
| [server/src/modules/finance_settings.js](../server/src/modules/finance_settings.js) | 330 | — | — |
| [server/src/modules/finance_tx.js](../server/src/modules/finance_tx.js) | 96 | — | — |
| [server/src/modules/integrity_schema.js](../server/src/modules/integrity_schema.js) | 282 | — | — |
| [server/src/modules/legal_consent_service.js](../server/src/modules/legal_consent_service.js) | 246 | — | — |
| [server/src/modules/legal_documents.js](../server/src/modules/legal_documents.js) | 600 | — | — |
| [server/src/modules/legal_routes.js](../server/src/modules/legal_routes.js) | 139 | — | — |
| [server/src/modules/management_company_routes.js](../server/src/modules/management_company_routes.js) | 92 | — | — |
| [server/src/modules/management_company_schema.js](../server/src/modules/management_company_schema.js) | 67 | — | — |
| [server/src/modules/management_company_service.js](../server/src/modules/management_company_service.js) | 380 | — | — |
| [server/src/modules/management_type_terms.js](../server/src/modules/management_type_terms.js) | 105 | — | — |
| [server/src/modules/management_types.js](../server/src/modules/management_types.js) | 78 | — | — |
| [server/src/modules/menu_layout_common.js](../server/src/modules/menu_layout_common.js) | 125 | — | — |
| [server/src/modules/menu_layout_routes.js](../server/src/modules/menu_layout_routes.js) | 87 | — | — |
| [server/src/modules/menu_layout_schema.js](../server/src/modules/menu_layout_schema.js) | 30 | — | — |
| [server/src/modules/menu_layout_service.js](../server/src/modules/menu_layout_service.js) | 240 | — | — |
| [server/src/modules/metering_access.js](../server/src/modules/metering_access.js) | 18 | — | — |
| [server/src/modules/metering_billing.js](../server/src/modules/metering_billing.js) | 335 | — | — |
| [server/src/modules/metering_calc.js](../server/src/modules/metering_calc.js) | 130 | — | — |
| [server/src/modules/metering_common.js](../server/src/modules/metering_common.js) | 114 | — | — |
| [server/src/modules/metering_field_routes.js](../server/src/modules/metering_field_routes.js) | 191 | — | — |
| [server/src/modules/metering_field_schema.js](../server/src/modules/metering_field_schema.js) | 51 | — | — |
| [server/src/modules/metering_routes.js](../server/src/modules/metering_routes.js) | 176 | — | — |
| [server/src/modules/metering_schema.js](../server/src/modules/metering_schema.js) | 184 | — | — |
| [server/src/modules/metering_service.js](../server/src/modules/metering_service.js) | 346 | — | — |
| [server/src/modules/module_request_routes.js](../server/src/modules/module_request_routes.js) | 157 | — | — |
| [server/src/modules/module_request_service.js](../server/src/modules/module_request_service.js) | 544 | — | — |
| [server/src/modules/module_routes.js](../server/src/modules/module_routes.js) | 250 | — | — |
| [server/src/modules/module_service.js](../server/src/modules/module_service.js) | 446 | — | — |
| [server/src/modules/neighbor_board_routes.js](../server/src/modules/neighbor_board_routes.js) | 308 | — | — |
| [server/src/modules/neighbor_board_schema.js](../server/src/modules/neighbor_board_schema.js) | 54 | — | — |
| [server/src/modules/notify_channels_routes.js](../server/src/modules/notify_channels_routes.js) | 79 | — | — |
| [server/src/modules/notify_channels_schema.js](../server/src/modules/notify_channels_schema.js) | 32 | — | — |
| [server/src/modules/oauth_login.js](../server/src/modules/oauth_login.js) | 1179 | — | — |
| [server/src/modules/oauth_routes.js](../server/src/modules/oauth_routes.js) | 289 | — | — |
| [server/src/modules/oauth_schema.js](../server/src/modules/oauth_schema.js) | 31 | — | — |
| [server/src/modules/payment_notice_common.js](../server/src/modules/payment_notice_common.js) | 243 | — | — |
| [server/src/modules/payment_notice_routes.js](../server/src/modules/payment_notice_routes.js) | 147 | — | — |
| [server/src/modules/payment_notice_schema.js](../server/src/modules/payment_notice_schema.js) | 168 | — | — |
| [server/src/modules/payment_notice_service.js](../server/src/modules/payment_notice_service.js) | 559 | — | — |
| [server/src/modules/payment_notice_upload.js](../server/src/modules/payment_notice_upload.js) | 206 | — | — |
| [server/src/modules/people_access.js](../server/src/modules/people_access.js) | 96 | — | — |
| [server/src/modules/people_backfill.js](../server/src/modules/people_backfill.js) | 43 | — | — |
| [server/src/modules/people_bulk_service.js](../server/src/modules/people_bulk_service.js) | 160 | — | — |
| [server/src/modules/people_common.js](../server/src/modules/people_common.js) | 420 | — | — |
| [server/src/modules/people_history_service.js](../server/src/modules/people_history_service.js) | 185 | — | — |
| [server/src/modules/people_records.js](../server/src/modules/people_records.js) | 209 | — | — |
| [server/src/modules/people_routes.js](../server/src/modules/people_routes.js) | 323 | — | — |
| [server/src/modules/people_service.js](../server/src/modules/people_service.js) | 2091 | — | — |
| [server/src/modules/people_sync_sql.js](../server/src/modules/people_sync_sql.js) | 348 | — | — |
| [server/src/modules/people_sync.js](../server/src/modules/people_sync.js) | 176 | — | — |
| [server/src/modules/person_invite_routes.js](../server/src/modules/person_invite_routes.js) | 186 | — | — |
| [server/src/modules/person_invite_service.js](../server/src/modules/person_invite_service.js) | 414 | — | — |
| [server/src/modules/plate_format.js](../server/src/modules/plate_format.js) | 57 | — | — |
| [server/src/modules/plate_recognition_common.js](../server/src/modules/plate_recognition_common.js) | 182 | — | — |
| [server/src/modules/plate_recognition_permits.js](../server/src/modules/plate_recognition_permits.js) | 237 | — | — |
| [server/src/modules/plate_recognition_routes.js](../server/src/modules/plate_recognition_routes.js) | 199 | — | — |
| [server/src/modules/plate_recognition_schema.js](../server/src/modules/plate_recognition_schema.js) | 153 | — | — |
| [server/src/modules/plate_recognition_service.js](../server/src/modules/plate_recognition_service.js) | 307 | — | — |
| [server/src/modules/platform_config_routes.js](../server/src/modules/platform_config_routes.js) | 74 | — | — |
| [server/src/modules/platform_config_service.js](../server/src/modules/platform_config_service.js) | 354 | — | — |
| [server/src/modules/platform_rules_routes.js](../server/src/modules/platform_rules_routes.js) | 82 | — | — |
| [server/src/modules/platform_rules_schema.js](../server/src/modules/platform_rules_schema.js) | 206 | — | — |
| [server/src/modules/platform_rules_service.js](../server/src/modules/platform_rules_service.js) | 381 | — | — |
| [server/src/modules/platform_rules.js](../server/src/modules/platform_rules.js) | 391 | — | — |
| [server/src/modules/push_common.js](../server/src/modules/push_common.js) | 211 | — | — |
| [server/src/modules/push_config.js](../server/src/modules/push_config.js) | 120 | — | — |
| [server/src/modules/push_credentials.js](../server/src/modules/push_credentials.js) | 176 | — | — |
| [server/src/modules/push_devices.js](../server/src/modules/push_devices.js) | 425 | — | — |
| [server/src/modules/push_fcm.js](../server/src/modules/push_fcm.js) | 250 | — | — |
| [server/src/modules/push_message.js](../server/src/modules/push_message.js) | 112 | — | — |
| [server/src/modules/push_outbox.js](../server/src/modules/push_outbox.js) | 136 | — | — |
| [server/src/modules/push_preferences.js](../server/src/modules/push_preferences.js) | 172 | — | — |
| [server/src/modules/push_routes.js](../server/src/modules/push_routes.js) | 109 | — | — |
| [server/src/modules/push_schema.js](../server/src/modules/push_schema.js) | 203 | — | — |
| [server/src/modules/push_worker.js](../server/src/modules/push_worker.js) | 849 | — | — |
| [server/src/modules/reservation_access.js](../server/src/modules/reservation_access.js) | 64 | — | — |
| [server/src/modules/reservation_common.js](../server/src/modules/reservation_common.js) | 612 | — | — |
| [server/src/modules/reservation_concierge.js](../server/src/modules/reservation_concierge.js) | 387 | — | — |
| [server/src/modules/reservation_resident.js](../server/src/modules/reservation_resident.js) | 513 | — | — |
| [server/src/modules/reservation_routes.js](../server/src/modules/reservation_routes.js) | 251 | — | — |
| [server/src/modules/reservation_schema.js](../server/src/modules/reservation_schema.js) | 299 | — | — |
| [server/src/modules/reservation_service.js](../server/src/modules/reservation_service.js) | 406 | — | — |
| [server/src/modules/reservation_slots.js](../server/src/modules/reservation_slots.js) | 75 | — | — |
| [server/src/modules/reservation_time.js](../server/src/modules/reservation_time.js) | 122 | — | — |
| [server/src/modules/residency_log_export.js](../server/src/modules/residency_log_export.js) | 161 | — | — |
| [server/src/modules/residency_log_routes.js](../server/src/modules/residency_log_routes.js) | 85 | — | — |
| [server/src/modules/residency_log_schema.js](../server/src/modules/residency_log_schema.js) | 275 | — | — |
| [server/src/modules/residency_log_service.js](../server/src/modules/residency_log_service.js) | 372 | — | — |
| [server/src/modules/residency_log.js](../server/src/modules/residency_log.js) | 257 | — | — |
| [server/src/modules/route_helpers.js](../server/src/modules/route_helpers.js) | 49 | — | — |
| [server/src/modules/site_application_common.js](../server/src/modules/site_application_common.js) | 364 | — | — |
| [server/src/modules/site_application_routes.js](../server/src/modules/site_application_routes.js) | 217 | — | — |
| [server/src/modules/site_application_service.js](../server/src/modules/site_application_service.js) | 1027 | — | — |
| [server/src/modules/sms_login.js](../server/src/modules/sms_login.js) | 135 | — | — |
| [server/src/modules/sms_provider.js](../server/src/modules/sms_provider.js) | 44 | — | — |
| [server/src/modules/staff_role_service.js](../server/src/modules/staff_role_service.js) | 280 | — | — |
| [server/src/modules/survey_access.js](../server/src/modules/survey_access.js) | 44 | — | — |
| [server/src/modules/survey_common.js](../server/src/modules/survey_common.js) | 409 | — | — |
| [server/src/modules/survey_resident.js](../server/src/modules/survey_resident.js) | 169 | — | — |
| [server/src/modules/survey_routes.js](../server/src/modules/survey_routes.js) | 180 | — | — |
| [server/src/modules/survey_schema.js](../server/src/modules/survey_schema.js) | 165 | — | — |
| [server/src/modules/survey_service.js](../server/src/modules/survey_service.js) | 417 | — | — |
| [server/src/modules/team_routes.js](../server/src/modules/team_routes.js) | 203 | — | — |
| [server/src/modules/team_schema.js](../server/src/modules/team_schema.js) | 187 | — | — |
| [server/src/modules/team_service.js](../server/src/modules/team_service.js) | 528 | — | — |
| [server/src/modules/user_account_audit.js](../server/src/modules/user_account_audit.js) | 108 | — | — |
| [server/src/modules/vehicle_service.js](../server/src/modules/vehicle_service.js) | 238 | — | — |
| [server/src/modules/visitor_log_access.js](../server/src/modules/visitor_log_access.js) | 63 | — | — |
| [server/src/modules/visitor_log_common.js](../server/src/modules/visitor_log_common.js) | 275 | — | — |
| [server/src/modules/visitor_log_resident.js](../server/src/modules/visitor_log_resident.js) | 152 | — | — |
| [server/src/modules/visitor_log_routes.js](../server/src/modules/visitor_log_routes.js) | 148 | — | — |
| [server/src/modules/visitor_log_schema.js](../server/src/modules/visitor_log_schema.js) | 145 | — | — |
| [server/src/modules/visitor_log_service.js](../server/src/modules/visitor_log_service.js) | 310 | — | — |
| [server/src/modules/web_push.js](../server/src/modules/web_push.js) | 158 | — | — |
| [server/src/modules/work_attachments_common.js](../server/src/modules/work_attachments_common.js) | 328 | — | — |
| [server/src/modules/work_attachments_read.js](../server/src/modules/work_attachments_read.js) | 124 | — | — |
| [server/src/modules/work_attachments_schema.js](../server/src/modules/work_attachments_schema.js) | 173 | — | — |
| [server/src/modules/work_attachments_service.js](../server/src/modules/work_attachments_service.js) | 344 | — | — |
| [server/src/modules/work_attachments_upload.js](../server/src/modules/work_attachments_upload.js) | 219 | — | — |
| [server/src/modules/work_tracking_access.js](../server/src/modules/work_tracking_access.js) | 63 | — | — |
| [server/src/modules/work_tracking_common.js](../server/src/modules/work_tracking_common.js) | 449 | — | — |
| [server/src/modules/work_tracking_report.js](../server/src/modules/work_tracking_report.js) | 213 | — | — |
| [server/src/modules/work_tracking_resident.js](../server/src/modules/work_tracking_resident.js) | 406 | — | — |
| [server/src/modules/work_tracking_routes.js](../server/src/modules/work_tracking_routes.js) | 348 | — | — |
| [server/src/modules/work_tracking_schema.js](../server/src/modules/work_tracking_schema.js) | 247 | — | — |
| [server/src/modules/work_tracking_service.js](../server/src/modules/work_tracking_service.js) | 524 | — | — |
| [server/src/mqtt_acl_sync.js](../server/src/mqtt_acl_sync.js) | 265 | [altyapi-health-acl-sync-kapali](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-health-acl-sync-kapali), [altyapi-mqtt-acl-yayin-reddi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-mqtt-acl-yayin-reddi), [altyapi-acl-cihaz-atlandi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-acl-cihaz-atlandi), [altyapi-acl-senkron-503](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-acl-senkron-503), [altyapi-acl-silinen-cihaz-baglaniyor](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-acl-silinen-cihaz-baglaniyor) +5 | 20-sunucu-altyapi-ve-yayin, 60-akislar, 61-akislar-devam |
| [server/src/mqtt_bridge.js](../server/src/mqtt_bridge.js) | 1245 | [altyapi-health-mqtt-baglanti-yok](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-health-mqtt-baglanti-yok), [altyapi-health-mqtt-yapilandirilmamis](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-health-mqtt-yapilandirilmamis), [altyapi-health-mqtt-db-error-kodu](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-health-mqtt-db-error-kodu), [altyapi-mqtt-tls-baglanti](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-mqtt-tls-baglanti), [altyapi-mqtt-kimlik-reddi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-mqtt-kimlik-reddi) +19 | 20-sunucu-altyapi-ve-yayin, 60-akislar |
| [server/src/routes/admin_routes.js](../server/src/routes/admin_routes.js) | 1863 | [sunucu-giris-403-onay-pasif-rol](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-403-onay-pasif-rol), [sunucu-token-revoked-parola-degisti](ariza-klavuzu/10-sunucu-api.md#sunucu-token-revoked-parola-degisti), [sunucu-oturum-401-kullanici-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-oturum-401-kullanici-yok), [sunucu-oturum-403-hesap-pasif](ariza-klavuzu/10-sunucu-api.md#sunucu-oturum-403-hesap-pasif), [sunucu-yetki-403-super-user](ariza-klavuzu/10-sunucu-api.md#sunucu-yetki-403-super-user) +22 | 10-sunucu-api, 61-akislar-devam |
| [server/src/routes/app_doors_routes.js](../server/src/routes/app_doors_routes.js) | 557 | [sunucu-kapi-acma-404-yetki](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-404-yetki), [sunucu-sakin-kapi-listede-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-sakin-kapi-listede-yok), [sunucu-kapi-acma-409-cihaz-atanmamis](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-409-cihaz-atanmamis), [sunucu-kapi-acma-cihaz-offline](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-cihaz-offline), [sunucu-kapi-acma-429-cok-sik](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-429-cok-sik) +16 | 10-sunucu-api, 60-akislar |
| [server/src/routes/auth_routes.js](../server/src/routes/auth_routes.js) | 1066 | [sunucu-giris-401](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-401), [sunucu-giris-hesap-kilitli-429](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-hesap-kilitli-429), [sunucu-giris-403-eposta-dogrulanmadi](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-403-eposta-dogrulanmadi), [sunucu-giris-403-onay-pasif-rol](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-403-onay-pasif-rol), [sunucu-token-revoked-parola-degisti](ariza-klavuzu/10-sunucu-api.md#sunucu-token-revoked-parola-degisti) +16 | 10-sunucu-api, 60-akislar |
| [server/src/routes/company_routes.js](../server/src/routes/company_routes.js) | 497 | [sunucu-kapi-acma-409-cihaz-atanmamis](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-409-cihaz-atanmamis), [sunucu-sirket-ucu-401-anahtar](ariza-klavuzu/10-sunucu-api.md#sunucu-sirket-ucu-401-anahtar), [sunucu-sirket-cihaz-kayit-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-sirket-cihaz-kayit-hata), [arac-kayit-http-400-donanim](ariza-klavuzu/50-arac-test-ve-surec.md#arac-kayit-http-400-donanim), [arac-kayitli-cihazlar-pdf](ariza-klavuzu/50-arac-test-ve-surec.md#arac-kayitli-cihazlar-pdf) +2 | 10-sunucu-api |
| [server/src/routes/door_log_routes.js](../server/src/routes/door_log_routes.js) | 272 | [sunucu-yonetici-gecis-gunlugu-bos](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-gecis-gunlugu-bos), [sunucu-offline-log-senkronu-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-offline-log-senkronu-hata), [akis-cevrimdisi-kapi-gunlukleri](ariza-klavuzu/60-akislar.md#akis-cevrimdisi-kapi-gunlukleri), [akis-pdf-ciktilari](ariza-klavuzu/61-akislar-devam.md#akis-pdf-ciktilari) | 10-sunucu-api |
| [server/src/routes/firmware_routes.js](../server/src/routes/firmware_routes.js) | 265 | [sunucu-db-kesintisi-500-oturum-dusmuyor](ariza-klavuzu/10-sunucu-api.md#sunucu-db-kesintisi-500-oturum-dusmuyor), [sunucu-kapi-acma-cihaz-offline](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-cihaz-offline), [sunucu-firmware-manifest-ota](ariza-klavuzu/10-sunucu-api.md#sunucu-firmware-manifest-ota), [sunucu-firmware-bin-indirilemiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-firmware-bin-indirilemiyor), [altyapi-health-database-disconnected](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-health-database-disconnected) +7 | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin |
| [server/src/routes/guest_passes_routes.js](../server/src/routes/guest_passes_routes.js) | 528 | [sunucu-misafir-gecis-olusturma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-gecis-olusturma-hata), [sunucu-misafir-gecis-acma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-gecis-acma-hata), [sunucu-misafir-sayfa-acilmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-sayfa-acilmiyor), [akis-misafir-gecis](ariza-klavuzu/60-akislar.md#akis-misafir-gecis) | 10-sunucu-api |
| [server/src/routes/manager_routes.js](../server/src/routes/manager_routes.js) | 1432 | [sunucu-yetki-403-site-yoneticisi](ariza-klavuzu/10-sunucu-api.md#sunucu-yetki-403-site-yoneticisi), [sunucu-karekod-politika-kapali](ariza-klavuzu/10-sunucu-api.md#sunucu-karekod-politika-kapali), [sunucu-yonetici-daveti-mail-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-daveti-mail-yok), [sunucu-yonetici-cikarma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-cikarma-hata), [sunucu-daire-bilgisi-eposta-gitmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-daire-bilgisi-eposta-gitmiyor) +11 | 10-sunucu-api, 61-akislar-devam |
| [server/src/routes/membership_routes.js](../server/src/routes/membership_routes.js) | 424 | [sunucu-yonetici-sakin-sifre-403](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-sakin-sifre-403), [sunucu-katilim-basvuru-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-katilim-basvuru-hata), [sunucu-kapi-yetkisi-yonetimi-403](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-yetkisi-yonetimi-403), [sunucu-cihaz-sahiplenme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-cihaz-sahiplenme-hata), [sunucu-site-kurulumu-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-site-kurulumu-hata) +4 | 10-sunucu-api, 61-akislar-devam |
| [server/src/routes/public_guest_routes.js](../server/src/routes/public_guest_routes.js) | 2 | [sunucu-misafir-sayfa-acilmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-sayfa-acilmiyor) | 10-sunucu-api, 60-akislar |
| [server/src/security/attempt_limits.js](../server/src/security/attempt_limits.js) | 260 | — | — |
| [server/src/security/client_ip.js](../server/src/security/client_ip.js) | 109 | — | — |
| [server/src/security/cloudflare_ranges.js](../server/src/security/cloudflare_ranges.js) | 66 | — | — |
| [server/src/security/log_redact.js](../server/src/security/log_redact.js) | 26 | [sunucu-yonetici-daveti-mail-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-daveti-mail-yok) | — |
| [server/src/security/login_device_token.js](../server/src/security/login_device_token.js) | 151 | — | — |
| [server/src/security/login_guard.js](../server/src/security/login_guard.js) | 499 | [sunucu-giris-hesap-kilitli-429](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-hesap-kilitli-429) | — |
| [server/src/security/password_hashing.js](../server/src/security/password_hashing.js) | 44 | — | — |
| [server/src/security/password_policy.js](../server/src/security/password_policy.js) | 304 | [sunucu-profil-parola-degistirme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-profil-parola-degistirme-hata) | — |
| [server/src/security/trust_proxy.js](../server/src/security/trust_proxy.js) | 116 | — | — |
| [server/src/server.js](../server/src/server.js) | 390 | [altyapi-api-acilmiyor-pm2-dongu](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-api-acilmiyor-pm2-dongu), [altyapi-env-hata-sunucu-baslamiyor](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-env-hata-sunucu-baslamiyor), [altyapi-env-uyari-jwt-kisa](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-env-uyari-jwt-kisa), [altyapi-env-uyari-eksik-ayarlar](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-env-uyari-eksik-ayarlar), [altyapi-env-degisikligi-etkisiz](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-env-degisikligi-etkisiz) +8 | 20-sunucu-altyapi-ve-yayin |
| [server/src/services/apartment_service.js](../server/src/services/apartment_service.js) | 657 | [sunucu-daire-bilgisi-eposta-gitmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-daire-bilgisi-eposta-gitmiyor), [sunucu-daire-sakin-yonetimi-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-daire-sakin-yonetimi-hata) | 10-sunucu-api |
| [server/src/services/device_service.js](../server/src/services/device_service.js) | 1079 | [sunucu-kapi-acma-409-cihaz-atanmamis](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-409-cihaz-atanmamis), [sunucu-yerel-kontrol-token-bos](ariza-klavuzu/10-sunucu-api.md#sunucu-yerel-kontrol-token-bos), [sunucu-yerel-token-rotasyonu](ariza-klavuzu/10-sunucu-api.md#sunucu-yerel-token-rotasyonu), [sunucu-admin-ota-tetikleme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-admin-ota-tetikleme-hata), [sunucu-admin-cihaz-envanteri-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-admin-cihaz-envanteri-hata) +8 | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin, 61-akislar-devam |
| [server/src/services/door_access_policy.js](../server/src/services/door_access_policy.js) | 342 | [sunucu-kapi-acma-403-uzaktan-kapali](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-403-uzaktan-kapali), [sunucu-karekod-politika-kapali](ariza-klavuzu/10-sunucu-api.md#sunucu-karekod-politika-kapali), [sunucu-tarama-qr-ekran-token](ariza-klavuzu/10-sunucu-api.md#sunucu-tarama-qr-ekran-token), [sunucu-tarama-qr-suresi-doldu](ariza-klavuzu/10-sunucu-api.md#sunucu-tarama-qr-suresi-doldu), [sunucu-tarama-qr-gecersiz-yuk](ariza-klavuzu/10-sunucu-api.md#sunucu-tarama-qr-gecersiz-yuk) +2 | 10-sunucu-api, 60-akislar |
| [server/src/services/door_log_service.js](../server/src/services/door_log_service.js) | 462 | [sunucu-offline-log-senkronu-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-offline-log-senkronu-hata), [altyapi-offline-log-alimi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-offline-log-alimi), [akis-cevrimdisi-kapi-gunlukleri](ariza-klavuzu/60-akislar.md#akis-cevrimdisi-kapi-gunlukleri), [akis-pdf-ciktilari](ariza-klavuzu/61-akislar-devam.md#akis-pdf-ciktilari) | 10-sunucu-api |
| [server/src/services/door_service.js](../server/src/services/door_service.js) | 1091 | [sunucu-kapi-acma-404-yetki](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-404-yetki), [sunucu-sakin-kapi-listede-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-sakin-kapi-listede-yok), [sunucu-kapi-acma-409-cihaz-atanmamis](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-409-cihaz-atanmamis), [sunucu-yerel-kontrol-token-bos](ariza-klavuzu/10-sunucu-api.md#sunucu-yerel-kontrol-token-bos), [sunucu-kapi-gecis-logu-yazilmadi](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-gecis-logu-yazilmadi) +7 | 10-sunucu-api, 60-akislar |
| [server/src/services/firmware_manifest_service.js](../server/src/services/firmware_manifest_service.js) | 78 | [sunucu-firmware-manifest-ota](ariza-klavuzu/10-sunucu-api.md#sunucu-firmware-manifest-ota), [altyapi-ota-hedef-uyusmazligi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-ota-hedef-uyusmazligi) | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin |
| [server/src/services/geofence_service.js](../server/src/services/geofence_service.js) | 335 | [sunucu-geofence-konum-reddi](ariza-klavuzu/10-sunucu-api.md#sunucu-geofence-konum-reddi), [sunucu-geofence-menzil-disi](ariza-klavuzu/10-sunucu-api.md#sunucu-geofence-menzil-disi), [akis-bulut-kapi-acma](ariza-klavuzu/60-akislar.md#akis-bulut-kapi-acma) | 10-sunucu-api, 60-akislar |
| [server/src/services/local_token_service.js](../server/src/services/local_token_service.js) | 82 | [sunucu-yerel-token-rotasyonu](ariza-klavuzu/10-sunucu-api.md#sunucu-yerel-token-rotasyonu), [akis-kapi-yetkileri-izinler](ariza-klavuzu/61-akislar-devam.md#akis-kapi-yetkileri-izinler) | 10-sunucu-api |
| [server/src/services/maintenance_service.js](../server/src/services/maintenance_service.js) | 232 | [sunucu-dogrulama-404-bekleyen-kayit-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-dogrulama-404-bekleyen-kayit-yok), [sunucu-kapi-gecis-logu-yazilmadi](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-gecis-logu-yazilmadi), [altyapi-bakim-temizlik-hatasi](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-bakim-temizlik-hatasi), [altyapi-bakim-saklama-sureleri](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-bakim-saklama-sureleri), [akis-bakim-temizlik-health](ariza-klavuzu/60-akislar.md#akis-bakim-temizlik-health) +1 | 10-sunucu-api, 20-sunucu-altyapi-ve-yayin |
| [server/src/services/membership_rules.js](../server/src/services/membership_rules.js) | 618 | [sunucu-giris-403-eposta-dogrulanmadi](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-403-eposta-dogrulanmadi), [sunucu-kayit-503-eposta-gonderilemedi](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-503-eposta-gonderilemedi), [sunucu-kayit-429-bekleme-sinir](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-429-bekleme-sinir), [sunucu-dogrulama-kod-hatali-400](ariza-klavuzu/10-sunucu-api.md#sunucu-dogrulama-kod-hatali-400), [sunucu-dogrulama-429-deneme-asildi](ariza-klavuzu/10-sunucu-api.md#sunucu-dogrulama-429-deneme-asildi) +6 | 10-sunucu-api |
| [server/src/services/membership_service.js](../server/src/services/membership_service.js) | 3089 | [sunucu-giris-403-eposta-dogrulanmadi](ariza-klavuzu/10-sunucu-api.md#sunucu-giris-403-eposta-dogrulanmadi), [sunucu-profil-parola-degistirme-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-profil-parola-degistirme-hata), [sunucu-yonetici-sakin-sifre-403](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-sakin-sifre-403), [sunucu-kayit-kod-gelmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-kod-gelmiyor), [sunucu-kayit-503-eposta-gonderilemedi](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-503-eposta-gonderilemedi) +20 | 10-sunucu-api, 60-akislar, 61-akislar-devam |
| [server/src/services/qr_access_service.js](../server/src/services/qr_access_service.js) | 553 | [sunucu-karekod-politika-kapali](ariza-klavuzu/10-sunucu-api.md#sunucu-karekod-politika-kapali), [sunucu-qr-token-uretilemiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-qr-token-uretilemiyor), [sunucu-gm60-okuyucu-reddi](ariza-klavuzu/10-sunucu-api.md#sunucu-gm60-okuyucu-reddi), [sunucu-gm60-role-calismadi](ariza-klavuzu/10-sunucu-api.md#sunucu-gm60-role-calismadi), [akis-dinamik-qr-gm60](ariza-klavuzu/60-akislar.md#akis-dinamik-qr-gm60) | 10-sunucu-api, 60-akislar |
| [server/src/services/site_service.js](../server/src/services/site_service.js) | 2681 | [sunucu-yetki-403-site-yoneticisi](ariza-klavuzu/10-sunucu-api.md#sunucu-yetki-403-site-yoneticisi), [sunucu-yonetici-gecis-gunlugu-bos](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-gecis-gunlugu-bos), [sunucu-yonetici-daveti-eslesmedi](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-daveti-eslesmedi), [sunucu-yonetici-daveti-mail-yok](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-daveti-mail-yok), [sunucu-yonetici-cikarma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-cikarma-hata) +8 | 10-sunucu-api |
| [server/src/services/site_setup_core.js](../server/src/services/site_setup_core.js) | 314 | [akis-site-kurulum-davet-sakin-katilim](ariza-klavuzu/61-akislar-devam.md#akis-site-kurulum-davet-sakin-katilim) | — |
| [server/src/services/user_service.js](../server/src/services/user_service.js) | 171 | [sunucu-profil-eposta-degistirilemiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-profil-eposta-degistirilemiyor), [sunucu-admin-kullanici-yonetimi-400](ariza-klavuzu/10-sunucu-api.md#sunucu-admin-kullanici-yonetimi-400) | 10-sunucu-api |
| [server/src/utils/async_errors.js](../server/src/utils/async_errors.js) | 79 | [sunucu-async-hata-istek-asili](ariza-klavuzu/10-sunucu-api.md#sunucu-async-hata-istek-asili) | 10-sunucu-api |
| [server/src/utils/guest_pass_utils.js](../server/src/utils/guest_pass_utils.js) | 326 | [sunucu-misafir-gecis-olusturma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-gecis-olusturma-hata), [sunucu-misafir-gecis-acma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-gecis-acma-hata), [sunucu-misafir-sayfa-acilmiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-misafir-sayfa-acilmiyor), [akis-misafir-gecis](ariza-klavuzu/60-akislar.md#akis-misafir-gecis) | 10-sunucu-api |
| [server/src/utils/helpers.js](../server/src/utils/helpers.js) | 841 | [sunucu-firmware-bin-indirilemiyor](ariza-klavuzu/10-sunucu-api.md#sunucu-firmware-bin-indirilemiyor), [altyapi-ota-manifest-guncelleme-sunmuyor](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-ota-manifest-guncelleme-sunmuyor), [altyapi-ota-dosya-indirilemiyor](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md#altyapi-ota-dosya-indirilemiyor) | 10-sunucu-api |
| [server/src/utils/ids.js](../server/src/utils/ids.js) | 43 | [sunucu-kimlik-gecersiz-400](ariza-klavuzu/10-sunucu-api.md#sunucu-kimlik-gecersiz-400) | 10-sunucu-api |
| [server/src/utils/reserved_email.js](../server/src/utils/reserved_email.js) | 22 | — | — |
| [server/src/utils/safe_text.js](../server/src/utils/safe_text.js) | 119 | — | — |
| [server/src/utils/site_rules.js](../server/src/utils/site_rules.js) | 516 | [sunucu-kapi-acma-403-uzaktan-kapali](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-acma-403-uzaktan-kapali), [sunucu-karekod-politika-kapali](ariza-klavuzu/10-sunucu-api.md#sunucu-karekod-politika-kapali), [sunucu-geofence-menzil-disi](ariza-klavuzu/10-sunucu-api.md#sunucu-geofence-menzil-disi), [sunucu-yonetici-cikarma-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-yonetici-cikarma-hata), [sunucu-kapi-cihaz-atama-403](ariza-klavuzu/10-sunucu-api.md#sunucu-kapi-cihaz-atama-403) +1 | 10-sunucu-api |
| [server/src/utils/validators.js](../server/src/utils/validators.js) | 466 | [sunucu-kayit-400-girdi](ariza-klavuzu/10-sunucu-api.md#sunucu-kayit-400-girdi), [sunucu-hata-500-errorid](ariza-klavuzu/10-sunucu-api.md#sunucu-hata-500-errorid), [sunucu-admin-kullanici-yonetimi-400](ariza-klavuzu/10-sunucu-api.md#sunucu-admin-kullanici-yonetimi-400), [sunucu-daire-sakin-yonetimi-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-daire-sakin-yonetimi-hata), [sunucu-site-kurulumu-hata](ariza-klavuzu/10-sunucu-api.md#sunucu-site-kurulumu-hata) +2 | 10-sunucu-api |
| [tools/klavuz/build.mjs](../tools/klavuz/build.mjs) | 752 | [test-klavuz-araci](ariza-klavuzu/50-arac-test-ve-surec.md#test-klavuz-araci), [test-klavuz-yeni-giris](ariza-klavuzu/50-arac-test-ve-surec.md#test-klavuz-yeni-giris) | 50-arac-test-ve-surec |
| [tools/klavuz/lint.mjs](../tools/klavuz/lint.mjs) | 117 | [test-klavuz-araci](ariza-klavuzu/50-arac-test-ve-surec.md#test-klavuz-araci) | — |
| [tools/klavuz/render.mjs](../tools/klavuz/render.mjs) | 333 | [test-klavuz-araci](ariza-klavuzu/50-arac-test-ve-surec.md#test-klavuz-araci) | — |

## Bu klavuza nasıl giriş eklenir

`tools/klavuz/entries/<NN-alan>.mjs` dosyasına giriş ekleyin (biçim: [tools/klavuz/README.md](../tools/klavuz/README.md)). Satır numarası YAZMAYIN: yalnızca dosya ve aranacak kod parçası (`find`). Ardından `node tools/klavuz/build.mjs --check` ile doğrulayıp `node tools/klavuz/build.mjs` ile belgeleri yenileyin.


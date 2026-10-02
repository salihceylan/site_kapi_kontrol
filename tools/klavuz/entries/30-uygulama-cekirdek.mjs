// Alan 30: Flutter uygulamasinin CEKIRDEGI (kok, oturum, HTTP istemcisi, yerel/UDP kapi, konum, ses, BLE, widget, kisayol, tema, PDF).
// Satir numarasi YAZILMAZ: her ref {file, find, note}; arac satiri koddan cozer (bkz. tools/klavuz/README.md).
// Kapsam disi: lib/ui/* ekranlari (yalnizca tetikleyici cagri noktalari kisaca anilir), sunucu, firmware.

const FLUTTER = 'C:\\Users\\fingonancalime\\SDK\\flutter\\bin\\flutter.bat';
const API = 'https://api.gudeteknoloji.com.tr';
const HEALTH = `curl -sS -m 10 -o /dev/null -w "%{http_code}\\n" ${API}/health`;

export default {
  title: 'Flutter uygulama çekirdeği — kök, oturum, HTTP istemcisi, yerel kapı, konum, ses, BLE, widget, tema, PDF',
  intro:
    'Bu bölüm lib/main.dart, lib/app.dart, lib/config, lib/models, lib/data, lib/services ve lib/styles/app_theme.dart içindeki istemci arızalarını kapsar. ' +
    'İlk bakılacak yerler: ağ/hata mesajı için lib/services/auth_api.dart (_sendRequest, _ensureStatus, _decodePayload, messageForErrorCode), ' +
    'oturum için lib/services/auth_service.dart (initialize, _handleSessionError, refreshSession), ekran seçimi için lib/app.dart (home).',
  files: [
    { file: 'lib/main.dart', note: 'Giriş noktası: yön kilidi, tema tercihini önceden yükler, MyApp başlatır' },
    { file: 'lib/app.dart', note: 'Kök widget: servisleri kurar, oturum/ağ durumuna göre ekran seçer, deep link/kısayol/yaşam döngüsü' },
    { file: 'lib/config/app_config.dart', note: 'API adresi (--dart-define=API_BASE_URL), uygulama adı/sürümü' },
    { file: 'lib/services/auth_api.dart', note: 'HTTP istemcisi: zaman aşımı, GET yeniden denemesi, durum kodu/hata kodu eşlemesi, JSON ayrıştırma' },
    { file: 'lib/services/auth_service.dart', note: 'Oturum (güvenli depo, /me doğrulaması), kapı açma akışı (yerel/bulut/konum), widget senkronu' },
    { file: 'lib/services/api_exception.dart', note: 'ApiException / SessionExpiredException: oturum sonu ve ara katman ayrımı' },
    { file: 'lib/services/network_service.dart', note: 'Açılışta internet yoklaması (/health + yedek adres)' },
    { file: 'lib/services/local_door_service.dart', note: 'Yerel ağ UDP: beacon dinleme, keşif, imzalı açma paketi (protokol v2)' },
    { file: 'lib/services/geofence_service.dart', note: 'Konum izni/GPS doğrulaması, mesafe hesabı' },
    { file: 'lib/services/voice_door_service.dart', note: 'Sesle kapı açma: konuşma tanıma, Türkçe komut eşleme, sesli geri bildirim' },
    { file: 'lib/services/ble_wifi_provision_service.dart', note: 'Bluetooth ile cihaza Wi-Fi/MQTT bilgisi yazma' },
    { file: 'lib/services/deep_link_service.dart', note: 'sitekapi:// bağlantıları ve kısayol eylemleri kuyruğu' },
    { file: 'lib/services/quick_actions_service.dart', note: 'Uygulama simgesi kısayolları (long-press)' },
    { file: 'lib/services/door_widget_service.dart', note: 'Ana ekran widget\'ı: kapı listesi senkronu ve arka planda kapı açma' },
    { file: 'lib/services/theme_service.dart', note: 'Aydınlık/karanlık/sistem tema tercihi ve kalıcılığı' },
    { file: 'lib/services/adaptive_poller.dart', note: 'Yoklama zamanlayıcısı: üstel geri çekilme, görünür değilken atlama' },
    { file: 'lib/services/background_work.dart', note: 'Büyük JSON/PDF işlerini arka plan izolesine alır' },
    { file: 'lib/services/pdf_font_set.dart', note: 'PDF yazı tipleri (Roboto ya da Helvetica yedeği)' },
    { file: 'lib/services/pdf_logs_service.dart', note: 'Kapı geçiş günlüğü PDF raporu' },
    { file: 'lib/services/pdf_credentials_service.dart', note: 'Site giriş bilgileri PDF raporu' },
    { file: 'lib/services/pdf_device_firmware_service.dart', note: 'Cihaz firmware durum PDF raporu' },
    { file: 'lib/models/user_session.dart', note: 'Oturum modeli (güvenli depoya JSON olarak yazılır)' },
    { file: 'lib/models/door_record.dart', note: 'Kapı modeli: politika bayrakları, geofence alanları, JSON ayrıştırma' },
    { file: 'lib/models/door_runtime_status.dart', note: 'Kapı canlı durumu modeli (cihaz çevrimiçi mi, yerel kontrol bilgisi)' },
    { file: 'lib/models/local_door_access.dart', note: 'Yerel kontrol anahtarı önbellek kaydı (24 saat geçerlilik)' },
    { file: 'lib/data/turkey_cities_districts.dart', note: 'İl/ilçe listesi (site oluşturma/düzenleme listeleri)' },
    { file: 'lib/styles/app_theme.dart', note: 'Aydınlık/karanlık ThemeData üretimi' },
  ],
  entries: [
    {
      id: 'cekirdek-sunucuya-baglanilamadi',
      symptom: 'Ekranda "Sunucuya bağlanılamadı" / "Sunucuya ulaşılamadı" / "Sunucuya baglanilamadi." hatası çıkıyor',
      keywords: ['sunucuya bağlanılamadı', 'sunucuya ulaşılamadı', 'baglanilamadi', 'ulasilamadi', 'dns', 'ssl', 'ağ hatası', 'login', 'giriş'],
      refs: [
        {
          file: 'lib/services/auth_api.dart',
          find: '} on http.ClientException catch (error) {',
          note: 'Aktarım hatası (DNS, bağlantı kopması, TLS) burada yakalanır; GET ise bir kez yeniden denenir, değilse ApiException üretilir',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'String _mapClientError(http.ClientException error) {',
          note: 'ClientException metnini üç Türkçe mesaja eşler: SSL, "Sunucuya ulasilamadi" (DNS/soket), genel istemci hatası',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',",
          note: 'Sunucu yanıt verdi ama gövde JSON değil (HTML/düz metin, 5xx/413/429 dışı): ara katman hatası sayılır',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',",
          note: '401/403 yanıtının gövdesi JSON hata zarfı değil: proxy/WAF/captive portal; oturum SONU değildir',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '_session = await api.login(email: email, password: password, role: role);',
          until: "return 'Sunucuya baglanilamadi.';",
          note: 'Giriş: ApiException mesajı aynen döner; ApiException dışındaki HER istisna "Sunucuya baglanilamadi." olur',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'await api.registerIndividual(',
          until: "return 'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz.';",
          note: 'Kayıt (ve parola sıfırlama) için ayrı genel mesaj (Unicode yazımlı)',
        },
      ],
      causes: [
        'Telefonda internet yok ya da alan adı çözülemiyor (ClientException metninde "failed host lookup"/"socket" -> "Sunucuya ulasilamadi. Internet veya DNS ...")',
        'TLS/sertifika sorunu (metinde "certificate"/"handshake"/"tls" -> "SSL baglantisi kurulurken hata olustu.")',
        'API adresi yanlış ya da sunucu kapalı (bkz. cekirdek-api-adresi-yanlis)',
        'Araya giren katman (nginx hata sayfası, modem/captive portal) JSON olmayan gövde döndürdü (bkz. cekirdek-proxy-html-modem-mesaji)',
        'Kod ApiException dışında beklenmeyen bir istisna fırlattı: auth_service genel catch gerçek nedeni gizler ve aynı mesajı gösterir',
      ],
      checks: [
        'Mesajın yazımına bakın: ASCII "ulasilamadi/baglanilamadi" aktarım katmanından, Unicode "ulaşılamadı/bağlanılamadı" sunucu-ara katman yanıtından ya da kayıt/şifre akışından gelir',
        'Aynı ağdan sunucu sağlığını deneyin (aşağıdaki komut): 200 değilse sorun istemci dışındadır',
        'Derlemedeki API adresini doğrulayın (--dart-define=API_BASE_URL verildi mi)',
        'Sorun yalnız belirli bir ağdaysa (otel/şirket Wi-Fi) captive portal/proxy şüphesi: tarayıcıda aynı adresi açın',
        'Sunucu tarafında isteğin ulaşıp ulaşmadığına sunucu alanı girişlerinden bakın (günlükte ilgili yol arayın)',
      ],
      commands: [HEALTH, `${FLUTTER} test test/auth_api_policy_test.dart`],
      tests: ['test/auth_api_policy_test.dart', 'test/fix_fx1_session_test.dart'],
      related: ['cekirdek-api-adresi-yanlis', 'cekirdek-proxy-html-modem-mesaji', 'cekirdek-internet-yok-ekrani'],
    },
    {
      id: 'cekirdek-api-adresi-yanlis',
      symptom: 'Uygulama yanlış/eski sunucuya bağlanıyor ya da hiç bağlanamıyor (API adresi yanlış, localhost, http)',
      keywords: ['api adresi', 'api_base_url', 'dart-define', 'localhost', '10.0.2.2', 'http', 'https', 'cleartext', 'base url'],
      refs: [
        {
          file: 'lib/config/app_config.dart',
          find: "const String _defaultApiBaseUrl = 'https://api.gudeteknoloji.com.tr';",
          note: 'Varsayılan (canlı) API adresi: --dart-define verilmediyse bu kullanılır',
        },
        {
          file: 'lib/config/app_config.dart',
          find: "'API_BASE_URL',",
          note: 'Derleme zamanı geçersiz kılma anahtarı: --dart-define=API_BASE_URL=... (çalışma zamanında değişmez)',
        },
        {
          file: 'lib/config/app_config.dart',
          find: 'const String apiBaseUrl = AppConfig.baseUrl;',
          note: 'Eski kodun kullandığı üst düzey takma ad; kök widget bunu okur',
        },
        {
          file: 'lib/app.dart',
          find: '_authService = AuthService(api: AuthApi(baseUrl: apiBaseUrl));',
          note: 'Tüm API istekleri bu tek AuthApi örneğiyle gider',
        },
        {
          file: 'lib/services/network_service.dart',
          find: "Uri.parse('$apiBaseUrl/health'),",
          note: 'Açılıştaki internet yoklaması da aynı adresin /health ucuna gider',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "final uri = Uri.parse('$baseUrl$path');",
          note: 'Adres + yol düz birleştirilir (sonda "/" kırpılmaz): sonda "/" kalırsa "//auth/login" olur',
          nth: 1,
        },
        {
          file: 'lib/services/door_widget_service.dart',
          find: 'String? normalizeWidgetApiBase(String? raw) {',
          note: 'Widget yalnız https (ya da derlemedeki aynı http adresi) kabul eder; aksi halde widget "Giriş Yapın" der',
        },
        {
          file: 'android/app/src/main/AndroidManifest.xml',
          find: 'android:usesCleartextTraffic="false"',
          note: 'Release derlemede düz http KAPALI: http adresli release sürüm bağlanamaz',
        },
        {
          file: 'android/app/src/debug/AndroidManifest.xml',
          find: 'android:usesCleartextTraffic="true"',
          note: 'Yalnız debug derlemede http serbest (emülatörde http://10.0.2.2:8080 için)',
        },
      ],
      causes: [
        '--dart-define=API_BASE_URL verilmeden derlendi: uygulama canlı API\'ye gider (yerel sunucu denerken veri canlıya yazılabilir)',
        'Release derlemede http:// adres verildi: Android cleartext yasağı nedeniyle bağlanılamaz',
        'Android emülatöründe localhost verildi: emülatör için http://10.0.2.2:8080 gerekir (debug derleme)',
        'Adresin sonunda "/" ya da yol var: istekler "//" ile birleşir (AuthApi adresi kırpmaz)',
        'Adres değişti ama uygulama yeniden DERLENMEDİ: değer çalışma zamanında okunmaz',
      ],
      checks: [
        'Yeniden derleyip adresi açıkça verin: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 (yalnız debug)',
        'Uygulamanın gittiği adresi ağ izleyicisiyle ya da sunucu günlüğüyle doğrulayın',
        'Widget sorunuysa widget\'ın kayıtlı adresi uygulama her kapı listesi alışında yeniden yazılır (api.baseUrl): uygulamayı açıp listeyi yenileyin',
      ],
      commands: [HEALTH, `${FLUTTER} run --dart-define=API_BASE_URL=http://10.0.2.2:8080`],
      tests: ['test/door_widget_service_test.dart'],
      related: ['cekirdek-sunucuya-baglanilamadi', 'cekirdek-widget-bos-ya-da-giris-yapin'],
    },
    {
      id: 'cekirdek-internet-yok-ekrani',
      symptom: 'Giriş ekranı yerine "İnternet yok" ekranı çıkıyor (internet var) ya da o ekran kalkmıyor',
      keywords: ['internet yok', 'no internet', 'yeniden dene', 'health', 'generate_204', 'ağ yoklaması', 'offline'],
      refs: [
        {
          file: 'lib/app.dart',
          find: 'if (!_networkService.hasInternet) {',
          note: 'Yalnız OTURUMSUZ kullanıcı için: internet yoksa NoInternetPage gösterilir (oturumluysa HomePage daha önce döner)',
        },
        {
          file: 'lib/app.dart',
          find: 'onRetry: _networkService.refresh,',
          note: '"Tekrar dene" düğmesi yoklamayı yeniden çalıştırır',
        },
        {
          file: 'lib/services/network_service.dart',
          find: 'Future<bool> _probeInternet() async {',
          note: 'Önce API /health, yanıt gecikirse/başarısızsa yedek adres; biri başarılıysa internet VAR sayılır',
        },
        {
          file: 'lib/services/network_service.dart',
          find: "Uri.parse('https://clients3.google.com/generate_204'),",
          note: 'Yedek adres: /health erişilemezse bu denenir (bu alan adı engelli ağda yedek de başarısız olur)',
        },
        {
          file: 'lib/services/network_service.dart',
          find: 'return response.statusCode >= 200 && response.statusCode < 400;',
          note: '4xx/5xx yanıt "internet yok" sayılır: /health 404/500 dönerse yedek adrese bakılır',
        },
        {
          file: 'lib/services/network_service.dart',
          find: '.timeout(const Duration(seconds: 5));',
          note: 'Her yoklama 5 sn ile sınırlıdır; zaman aşımı = başarısız',
        },
      ],
      causes: [
        'API /health ucu yanıt vermiyor (sunucu kapalı/5xx) VE yedek adres (google generate_204) de engelli ya da erişilemiyor',
        'Ağ çok yavaş: iki adres de 5 sn içinde yanıtlamadı (en kötü ~6,5 sn sonra "internet yok")',
        'Yoklama yalnız açılışta ve "Tekrar dene" ile çalışır: sonradan düzelen ağ otomatik algılanmaz',
        'Test/geliştirme: NetworkService(enabled: false) ise yoklama yapılmaz ve internet VAR kabul edilir',
      ],
      checks: [
        'Aynı ağdan API /health yanıtını kontrol edin (aşağıdaki komut)',
        'Ekran "Tekrar dene" ile kalkıyorsa geçici ağ sorunudur; kalkmıyorsa API adresini doğrulayın (cekirdek-api-adresi-yanlis)',
        'Oturumlu kullanıcı bu ekranı görmez; görüyorsa oturum açılışta düşmüştür (cekirdek-oturum-kendiliginden-dusuyor)',
      ],
      commands: [HEALTH, `${FLUTTER} test test/cold_start_test.dart test/screens/no_internet_layout_test.dart`],
      tests: ['test/cold_start_test.dart', 'test/screens/no_internet_layout_test.dart'],
      related: ['cekirdek-api-adresi-yanlis', 'cekirdek-acilis-splash-takili'],
    },
    {
      id: 'cekirdek-acilis-splash-takili',
      symptom: 'Açılışta logo + dönen çark ekranı çok uzun sürüyor ya da hiç kalkmıyor',
      keywords: ['splash', 'açılış', 'çark', 'logo', 'takıldı', 'yükleniyor', 'secure storage', 'initialize'],
      refs: [
        {
          file: 'lib/app.dart',
          find: 'if (!authReady) {',
          note: 'Oturum yüklemesi bitene kadar her durumda StartupSplash',
        },
        {
          file: 'lib/app.dart',
          find: 'if (!networkReady) {',
          note: 'Oturumsuzsa ağ yoklaması bitene kadar da splash (oturumluysa beklenmez)',
        },
        {
          file: 'lib/app.dart',
          find: 'final authInit = _authService.initialize();',
          note: 'Oturum başlatma açılışta bir kez, beklenmeden başlar; bitince deep link kuyruğu işlenir',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<String?> _readStoredSessionRaw() async {',
          note: 'Güvenli depo okuması ZAMAN AŞIMSIZDIR: platform kanalı yanıt vermezse initialize bitmez',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'await cacheFuture;',
          note: 'Açılış, üç bağımsız okumanın EN YAVAŞINI bekler (oturum, eski kopya, yerel erişim önbelleği)',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '_isReady = true;',
          note: 'Hata olsa bile (try/catch dışında) hazır işaretlenir; yani hata splash\'ı kalıcı yapmaz, askıda kalan okuma yapar',
        },
      ],
      causes: [
        'flutter_secure_storage okuması askıda kalıyor (zaman aşımı yok): initialize hiç tamamlanmaz',
        'Oturumsuz kullanıcıda ağ yoklaması sürüyor: her iki adres yanıtsızsa ~6,5 sn',
        'Soğuk açılışta cihaz yavaş: üç okuma eşzamanlı ama en yavaşı kadar beklenir',
      ],
      checks: [
        'Splash kalıcıysa Android/iOS güvenli depo erişimini (Keystore/Keychain) ve uygulama verisini temizleyip deneyin',
        'Splash birkaç saniye sonra giriş ekranına geçiyorsa ağ yoklaması nedenidir (cekirdek-internet-yok-ekrani)',
        'Giriş yapılmış kullanıcıda splash sonrası boş ekran için cekirdek-giris-sonrasi-ekran-bos girişine bakın',
      ],
      commands: [`${FLUTTER} test test/cold_start_test.dart test/screens/startup_splash_layout_test.dart`],
      tests: ['test/cold_start_test.dart', 'test/screens/startup_splash_layout_test.dart'],
      related: ['cekirdek-internet-yok-ekrani', 'cekirdek-giris-sonrasi-ekran-bos'],
    },
    {
      id: 'cekirdek-giris-sonrasi-ekran-bos',
      symptom: 'Giriş yaptıktan sonra ekran beyaz/boş kalıyor ya da giriş ekranından ilerlemiyor',
      keywords: ['beyaz ekran', 'boş ekran', 'giriş sonrası', 'homepage', 'login', 'ekran değişmiyor', 'şeffaf'],
      refs: [
        {
          file: 'lib/app.dart',
          find: 'animation: Listenable.merge([_authService, _networkService]),',
          note: 'Ekran seçimi hem oturumu hem ağ durumunu dinler; oturum açılınca yeniden kurulup HomePage döner',
        },
        {
          file: 'lib/app.dart',
          find: 'return HomePage(',
          note: 'Oturumlu kullanıcı için ana sayfa; bu widget\'ın kendi build hatası ekranı boş/gri bırakabilir (ekran alanı: lib/ui)',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '_session = await api.login(email: email, password: password, role: role);',
          note: 'Oturum atanır, kalıcılaştırılır, SONRA dinleyiciler bilgilendirilir',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'void _notifySafely() {',
          note: 'AuthService dispose edilmişse bildirim atlanır: ekran yenilenmez',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "return _parsePayload('Oturum bilgisi', () {",
          note: 'Giriş yanıtı beklenen şekilde değilse (user/token eksik) ekran değil HATA MESAJI döner: "Oturum bilgisi verisi beklenen formatta degil."',
        },
        {
          file: 'lib/app.dart',
          find: 'builder: (context, child) {',
          note: 'Tüm sayfaların zemini burada çizilir; Scaffold zemini şeffaf olduğu için bu katman yoksa sayfa boş görünür',
        },
        {
          file: 'lib/styles/app_theme.dart',
          find: 'scaffoldBackgroundColor: Colors.transparent,',
          note: 'Aydınlık temada Scaffold şeffaf (karanlık temada da aynı satır var): zemin MaterialApp builder\'ından gelir',
          any: true,
        },
      ],
      causes: [
        'HomePage build sırasında istisna fırlattı (release\'te gri/boş alan): asıl hata ekran koduna aittir, konsolda "Exception"/"RenderFlex" arayın',
        'Giriş yanıtının şekli bozuk: ekran değişmez, giriş ekranında "verisi beklenen formatta degil" görünür',
        'Sayfa MaterialApp\'ın dışında/üstünde kurulmuş: app.dart builder zemini olmadığı için şeffaf Scaffold boş görünür',
        'Oturum atanmadı: login ApiException ile döndü (mesaj giriş ekranında görünür)',
      ],
      checks: [
        'Debug derlemede konsolu açıp giriş anındaki ilk istisnayı bulun (flutter run çıktısı)',
        'Giriş ekranında kırmızı hata metni var mı? Varsa cekirdek-sunucuya-baglanilamadi ya da cekirdek-json-ayristirma-hatasi',
        'Splash\'ta kalıyorsa cekirdek-acilis-splash-takili',
      ],
      commands: [`${FLUTTER} analyze`, `${FLUTTER} test test/design/app_shell_test.dart test/widget_test.dart`],
      tests: ['test/design/app_shell_test.dart', 'test/widget_test.dart'],
      related: ['cekirdek-acilis-splash-takili', 'cekirdek-json-ayristirma-hatasi'],
    },
    {
      id: 'cekirdek-oturum-kendiliginden-dusuyor',
      symptom: 'Oturum kendiliğinden düşüyor: uygulama bir anda giriş ekranına dönüyor ("Oturum süreniz doldu. Lütfen tekrar giriş yapın.")',
      keywords: ['oturum düştü', 'oturum süreniz doldu', 'çıkış yaptı', '401', 'token', 'logout', 'me', 'otomatik çıkış'],
      refs: [
        {
          file: 'lib/services/auth_service.dart',
          find: 'void _handleSessionError(',
          note: 'Her yetkili istek hatası buradan geçer: 401 (SessionExpiredException) oturumu kapatır, 403 ise önce /me ile doğrulanır',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'if (error is SessionExpiredException ||',
          note: 'Oturumu kapatma kararı: durum koduna dayanır (metne değil); mesaj girişte bir kez gösterilmek üzere saklanır',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'if (status == 401 && unauthorizedIsSession) {',
          note: 'Yetkili uçlarda 401 -> SessionExpiredException ("Oturum süreniz doldu..."); giriş uçlarında bu dal atlanır',
        },
        {
          file: 'lib/services/api_exception.dart',
          find: 'bool get invalidatesSession =>',
          note: 'Varsayılan: yalnız 401 ve ara katmandan gelmeyen yanıt oturumu geçersiz sayar',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<void> _runSessionRefresh(UserSession active) async {',
          note: 'GET /me doğrulaması: 401/403 oturumu kapatır; ağ/5xx/ara katman hatasında çevrimdışı oturum KORUNUR',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'static const Duration _sessionCheckMinInterval = Duration(seconds: 20);',
          note: '/me doğrulaması art arda en çok 20 sn\'de bir (force olmadıkça)',
        },
        {
          file: 'lib/ui/pages/home_page.dart',
          find: 'unawaited(widget.authService.refreshSession());',
          note: 'Uygulama ön plana dönünce /me doğrulaması tetiklenir (oturum bu anda düşebilir)',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'String? takeSessionNotice() {',
          note: 'Düşme nedeni mesajı giriş ekranında BİR KEZ gösterilir ve temizlenir',
        },
      ],
      causes: [
        'Sunucu 401 döndü: token süresi doldu, iptal edildi (parola değişti: TOKEN_REVOKED) ya da kullanıcı silindi',
        '/me doğrulaması (açılış, ön plana dönüş) 401 ya da 403 aldı: hesap pasif/onaysız -> çıkış',
        'Yanıtta is_active=false: "Hesabınız pasif duruma alındı..." mesajıyla çıkış (cekirdek-hesap-pasif-oturum-kapandi)',
        'Başka cihazda/ekranda parola değişimi (cekirdek-sifre-degisince-oturum-kapandi)',
        'ÇIKIŞ OLMAYAN durumlar: ağ hatası, 5xx, proxy/HTML 401-403, eski token ile geç gelen istek yeni oturumu kapatmaz',
      ],
      checks: [
        'Girişte gösterilen mesaj nedeni söyler: "Oturum süreniz doldu", "Şifreniz değiştirildiği için ...", "Hesabınız pasif ..."',
        'Sunucu günlüğünde o kullanıcının /me ve diğer isteklerinin durum kodlarına bakın (401/403 mü)',
        'Sorun yalnız belirli bir ağdaysa 401/403 HTML ise oturum kapanmaz; kapanıyorsa yanıt JSON hata zarfıdır (sunucu kaynaklı)',
        'Token süresi/iptal kuralları sunucu tarafındadır: sunucu alanı klavuzundaki giriş/oturum girişlerine bakın',
      ],
      commands: [
        'ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /me"',
        `${FLUTTER} test test/auth_service_session_test.dart test/fix_fx1_session_test.dart`,
      ],
      tests: ['test/auth_service_session_test.dart', 'test/fix_fx1_session_test.dart', 'test/auth_api_policy_test.dart'],
      related: ['cekirdek-hesap-pasif-oturum-kapandi', 'cekirdek-sifre-degisince-oturum-kapandi', 'cekirdek-acilista-oturum-yok'],
    },
    {
      id: 'cekirdek-sifre-degisince-oturum-kapandi',
      symptom: '"Şifreniz değiştirildiği için oturumunuz sonlandırıldı" mesajıyla çıkış yapılıyor ya da şifre değişince uygulama düşüyor',
      keywords: ['şifre değişti', 'token_revoked', 'oturum sonlandırıldı', 'parola', 'password change', 'yeni token'],
      refs: [
        {
          file: 'lib/services/auth_api.dart',
          find: "if (code == 'TOKEN_REVOKED') {",
          note: 'Parola değişince eski token\'lar iptal edilir (sunucu 401 TOKEN_REVOKED): özel mesajlı SessionExpiredException',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'int _credentialSwapDepth = 0;',
          note: 'Süren parola değişimi sayısı: bu aralıkta eşzamanlı isteklerin TOKEN_REVOKED 401\'i yok sayılır',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<String?> updateMyProfile({',
          note: 'Profil/şifre güncelleme: sunucunun döndürdüğü YENİ token oturuma yazılır; kendi 401\'i gerçek oturum sonudur',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "final newToken = payload['token'];",
          note: 'Şifre değişiminde sunucu yeni token döndürürse o kullanılır, yoksa eski token korunur',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'if (tokenChanged && knownDoors != null) {',
          note: 'Token değişince ana ekran widget\'ı da yeni token ile yeniden yazılır (aksi halde widget eski token ile 401 alır)',
        },
      ],
      causes: [
        'Başka cihazda parola değiştirildi: bu cihazdaki eski token iptal oldu (beklenen davranış)',
        'Sunucu parola değişiminde yeni token döndürmedi: istemci eski (iptal) token ile kalır ve sonraki istek 401 alır',
        'Widget eski token ile kaldı: widget "Giriş Yapın" gösterir (cekirdek-widget-bos-ya-da-giris-yapin)',
      ],
      checks: [
        'Mesaj "Şifreniz değiştirildiği için..." ise nedeni parola değişimidir; yeniden giriş yeterlidir',
        'Parolayı bu cihazda değiştirdiyseniz ve çıkış olduysa PATCH /me yanıtında "token" alanı var mı (sunucu alanı)',
        'Değişimi yapan istek sırasında eşzamanlı isteklerin oturumu kapatmadığı testle doğrulanır (auth_service_session_test)',
      ],
      tests: ['test/auth_service_session_test.dart', 'test/verify_and_profile_ui_test.dart'],
      related: ['cekirdek-oturum-kendiliginden-dusuyor', 'cekirdek-sifre-degistirme-hatalari'],
    },
    {
      id: 'cekirdek-hesap-pasif-oturum-kapandi',
      symptom: '"Hesabınız pasif duruma alındı. Lütfen yöneticinizle iletişime geçin." diyerek oturum kapanıyor',
      keywords: ['hesap pasif', 'pasif', 'is_active', '403', 'onaysız', 'yönetici'],
      refs: [
        {
          file: 'lib/services/auth_service.dart',
          find: "_sessionNotice = 'Hesabınız pasif duruma alındı. Lütfen yöneticinizle iletişime geçin.';",
          note: '/me yanıtında is_active=false ise bu mesajla çıkış yapılır',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: '} else if (error is ApiException && error.isForbidden) {',
          note: 'Bir istek 403 alırsa oturum hemen kapanmaz: önce /me ile hesabın gerçekten pasif olup olmadığı doğrulanır',
        },
        {
          file: 'lib/services/api_exception.dart',
          find: 'bool get isForbidden => statusCode == 403 && !fromIntermediary;',
          note: 'Proxy/WAF kaynaklı 403 bu sınıfa girmez (hesap pasif sinyali sayılmaz)',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'Future<UserSession> fetchMe({',
          note: 'GET /me: 401 -> SessionExpiredException; 403 -> ApiException(403); is_active alanı oturuma işlenir',
        },
      ],
      causes: [
        'Yönetici hesabı pasifleştirdi ya da site onayı/hesap onayı bekleniyor (sunucu 403 döner)',
        '/me yanıtında is_active=false',
        'ÇIKIŞ DEĞİL: 403 HTML ise (proxy/WAF) bu akış tetiklenmez',
      ],
      checks: [
        'Kullanıcının is_active değerini sunucu tarafında doğrulayın (kullanıcı yönetimi ekranı ya da veritabanı; sunucu alanı klavuzu)',
        'Yönetici kullanıcıyı yeniden etkinleştirdiyse kullanıcı yeniden giriş yapmalıdır',
      ],
      tests: ['test/auth_service_session_test.dart', 'test/fix_fx1_session_test.dart'],
      related: ['cekirdek-oturum-kendiliginden-dusuyor'],
    },
    {
      id: 'cekirdek-acilista-oturum-yok',
      symptom: 'Uygulama her açılışta giriş istiyor (oturum hatırlanmıyor) ya da kayıtlı oturum silinmiş görünüyor',
      keywords: ['oturum hatırlanmıyor', 'her seferinde giriş', 'secure storage', 'keystore', 'keychain', 'kalıcı değil', 'persist'],
      refs: [
        {
          file: 'lib/services/auth_service.dart',
          find: 'final data = jsonDecode(raw) as Map<String, dynamic>;',
          until: '} catch (_) {',
          note: 'Kayıtlı oturum JSON\'u çözülemezse ya da UserSession.fromJson fırlatırsa kayıt SESSİZCE SİLİNİR ve giriş ekranı gelir',
        },
        {
          file: 'lib/models/user_session.dart',
          find: 'factory UserSession.fromJson(Map<String, dynamic> json) {',
          note: 'id/full_name/email/role/token zorunlu cast\'ler: biri eksik/tipi farklıysa fırlatır (eski şemalı kayıtlar silinir)',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<void> _persist() async {',
          note: 'Oturumu güvenli depoya yazar; yazma hatası YUTULUR (catch (_) {}): giriş çalışır ama kalıcı olmaz',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();',
          note: 'Oturum yalnızca güvenli depoda tutulur (SharedPreferences\'ta tutulmaz)',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<String?> _takeLegacySession() async {',
          note: 'Eski sürümlerin SharedPreferences kopyası bir kez güvenli depoya taşınır ve silinir',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<void> logout() async {',
          note: 'Çıkış: oturum + yerel erişim önbelleği + widget verisi silinir; sonraki açılışta oturum olmaması normaldir',
        },
      ],
      causes: [
        'Güvenli depo yazması başarısız (platform Keystore/Keychain hatası): _persist hatayı yutar, oturum yalnızca bellekte kalır',
        'Uygulama verisi temizlendi / yeniden yüklendi: güvenli depo boş',
        'Kayıtlı JSON bozuk ya da eski şemalı: initialize kaydı siler',
        'Açılışta /me 401/403 aldı: oturum sunucuca geçersiz (cekirdek-oturum-kendiliginden-dusuyor)',
      ],
      checks: [
        'Girişten sonra uygulamayı kapatıp açın: hâlâ giriş istiyorsa güvenli depo yazma/okuma sorunudur',
        'Girişte bir mesaj gösterildi mi (takeSessionNotice)? Gösterildiyse oturum sunucu tarafından sonlandırılmıştır',
        'Testle doğrulama: auth_service_session_test "Oturum saklama: yalnızca güvenli depo"',
      ],
      tests: ['test/auth_service_session_test.dart', 'test/cold_start_test.dart', 'test/model_parsing_test.dart'],
      related: ['cekirdek-oturum-kendiliginden-dusuyor', 'cekirdek-acilis-splash-takili'],
    },
    {
      id: 'cekirdek-yanlis-rol-menu',
      symptom: 'Kullanıcı yanlış rolle görünüyor (yönetici menüsü yok / daire kullanıcısı gibi) ya da rol değişikliği uygulamaya yansımıyor',
      keywords: ['rol', 'yanlış rol', 'menü yok', 'yetki', 'site_manager', 'apartment_owner', 'individual', 'super_user'],
      refs: [
        {
          file: 'lib/models/user_role.dart',
          find: 'orElse: () => UserRole.apartmentOwner,',
          note: 'Bilinmeyen/yeni rol değeri SESSİZCE daire kullanıcısına düşer (hata vermez)',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'bool _sessionDiffers(UserSession a, UserSession b) {',
          note: '/me yanıtındaki rol/aktiflik/ad/e-posta farkı oturuma yazılır ve ekran yenilenir',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'UserSession _toUserSession({',
          note: 'Sunucu yanıtından oturum üretir; rol alanı yoksa önceki (fallback) rol korunur',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'Future<Map<String, dynamic>> claimDevice({',
          note: 'Cihaz sahiplenince rol sunucuda yükselir; istemci tahmin etmez, /me ile eşitler',
        },
        {
          file: 'lib/app.dart',
          find: 'final currentRole = _authService.session?.role;',
          note: 'Kısayol/deep link ile sesli komut yalnız daire kullanıcısı ve bireysel kullanıcı için açılır',
        },
      ],
      causes: [
        'Sunucuda rol değişti ama /me henüz çalışmadı: açılışta, ön plana dönüşte (20 sn aralık) ve cihaz sahiplenmeden sonra eşitlenir',
        'Sunucu uygulamanın bilmediği bir rol değeri döndürdü: istemci apartmentOwner varsayar',
        'Kayıtlı (eski) oturumdaki rol: /me çevrimdışıyken güncellenmez',
      ],
      checks: [
        'Uygulamayı arka plana alıp geri getirin (/me tetiklenir) ya da çıkış-giriş yapın',
        'Sunucuda kullanıcının rol değerini doğrulayın; değer UserRole.apiValue listesinde olmalı (super_user, site_manager, apartment_owner, individual)',
        'Menü/ekran seçimi rolden gelir: ekran alanı klavuzuna bakın',
      ],
      tests: ['test/auth_service_session_test.dart', 'test/model_parsing_test.dart'],
      related: ['cekirdek-oturum-kendiliginden-dusuyor'],
    },
    {
      id: 'cekirdek-sifre-degistirme-hatalari',
      symptom: 'Profilde şifre değişmiyor: "Mevcut şifreniz hatalı", "mevcut şifrenizi girmelisiniz" ya da "Kendi şifrenizi Profilim ekranından değiştirin"',
      keywords: ['şifre değiştir', 'mevcut şifre', 'current_password', 'profil', 'parola', 'şifre hatalı'],
      refs: [
        {
          file: 'lib/services/auth_service.dart',
          find: "return 'Şifrenizi değiştirmek için mevcut şifrenizi girin.';",
          note: 'İstemci tarafı ön kontrol: yeni şifre varsa mevcut şifre boş olamaz (istek gitmez)',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "if (password != null) 'current_password': currentPassword,",
          note: 'Şifre değişiyorsa mevcut şifre sunucuya zorunlu olarak gönderilir',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "case 'CURRENT_PASSWORD_INVALID':",
          note: 'Yanlış mevcut şifre: 400 ve oturumu KAPATMAZ',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "case 'CURRENT_PASSWORD_LOCKED':",
          note: 'Mevcut şifre için çok fazla hatalı deneme: bekleme süresi mesaja eklenir',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: "case 'USE_PROFILE_PASSWORD_CHANGE':",
          note: 'Yönetici ekranından kendi parolasını değiştirmeye çalışınca çıkar (Profilim kullanılmalı)',
        },
      ],
      causes: [
        'Mevcut şifre yanlış girildi (CURRENT_PASSWORD_INVALID)',
        'Art arda yanlış denemeyle mevcut şifre kilitlendi (CURRENT_PASSWORD_LOCKED, Retry-After)',
        'Yönetici kendi hesabının parolasını kullanıcı yönetiminden değiştirmeyi denedi',
      ],
      checks: [
        'Mesaj metnine bakın: kod -> mesaj eşlemesi messageForErrorCode içindedir',
        'Kilit mesajındaki bekleme süresi dolana kadar bekleyin',
        'Değişiklikten sonra çıkış olursa cekirdek-sifre-degisince-oturum-kapandi',
      ],
      tests: ['test/verify_and_profile_ui_test.dart', 'test/fix_fx1_session_test.dart', 'test/auth_api_policy_test.dart'],
      related: ['cekirdek-sifre-degisince-oturum-kapandi', 'cekirdek-hiz-siniri-cok-fazla-deneme'],
    },
    {
      id: 'cekirdek-hiz-siniri-cok-fazla-deneme',
      symptom: '"Çok fazla hatalı deneme yapıldı. N dakika sonra tekrar deneyin" ya da "Çok fazla istek gönderildi" (429) mesajı çıkıyor',
      keywords: ['429', 'login_locked', 'çok fazla deneme', 'hız sınırı', 'rate limit', 'retry-after', 'kilitli'],
      refs: [
        {
          file: 'lib/services/auth_api.dart',
          find: "case 'LOGIN_LOCKED':",
          note: 'Giriş kilidi: "Çok fazla hatalı deneme yapıldı." + bekleme süresi',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'int? _retryAfterSeconds(http.Response response, Map<String, dynamic> payload) {',
          note: 'Bekleme süresi: önce gövdedeki retry_after_seconds, yoksa Retry-After başlığı',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'static String formatWait(int seconds) {',
          note: 'Saniyeyi "45 saniye / 5 dakika / 2 saat" yazar (yukarı yuvarlar)',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'if (status == 429 && mappedMessage == null) {',
          note: 'Kodu eşlenmemiş genel 429: mesaja "Lütfen X sonra tekrar deneyin." eklenir',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'if (status == 429) {',
          note: 'Proxy (nginx) JSON olmayan 429 döndürürse de "Çok fazla istek gönderildi." sınıflanır',
        },
        {
          file: 'lib/services/api_exception.dart',
          find: 'bool get isRateLimited => statusCode == 429;',
          note: 'Arayüzün 429 durumunu ayırt etmesi için',
        },
      ],
      causes: [
        'Art arda hatalı giriş: sunucu hesabı/IP\'yi geçici kilitler (LOGIN_LOCKED)',
        'Kapı açma/istek sıklığı sunucu hız sınırını aştı (genel 429)',
        'Nginx/proxy kendi hız sınırını uyguladı (JSON olmayan 429)',
      ],
      checks: [
        'Mesajdaki bekleme süresi kadar bekleyin; süre sunucudan gelir (istemci uydurmaz)',
        'Sunucu günlüğünde ilgili yolun 429 yanıtlarını arayın',
        'Kilit/sınır kuralları sunucu alanındadır: sunucu alanı klavuzundaki giriş kilidi ve hız sınırı girişleri',
      ],
      commands: ['ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a /auth/login"'],
      tests: ['test/auth_api_policy_test.dart', 'test/fix_fx1_session_test.dart'],
      related: ['cekirdek-sifre-degistirme-hatalari'],
    },
    {
      id: 'cekirdek-dogrulama-kodu-hatalari',
      symptom: 'E-posta doğrulama kodu kabul edilmiyor ("Kod 30 dakika geçerlidir; yeni kod için ...") ya da kod tekrar gönderilemiyor',
      keywords: ['doğrulama kodu', 'e-posta kodu', 'verify-code', 'resend-code', '30 dakika', 'kayıt', 'bireysel kayıt', 'kodu tekrar gönder'],
      refs: [
        {
          file: 'lib/services/auth_api.dart',
          find: 'Future<Map<String, dynamic>> registerIndividual({',
          note: 'Bireysel kayıt: oturum DÖNMEZ; kullanıcı kodu doğrulayınca oturum açılır',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'Future<UserSession> verifyIndividualCode({',
          note: 'Kod doğrulama: başarılıysa sunucu oturum (token) döndürür',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: 'if (e.statusCode == 404) {',
          note: '404 = aktif kod yok: mesaja "Kod 30 dakika geçerlidir; yeni kod için ..." yönlendirmesi eklenir',
        },
        {
          file: 'lib/services/auth_service.dart',
          find: "return 'Kod tekrar gönderilemedi.';",
          note: 'Tekrar gönderme ApiException dışı hatada bu genel mesajı verir',
        },
        {
          file: 'lib/services/auth_api.dart',
          find: 'Future<Map<String, dynamic>> resendIndividualCode({',
          note: 'Kodu yeniden gönderme isteği (POST /auth/resend-code)',
        },
      ],
      causes: [
        'Kodun 30 dakikalık süresi doldu ya da hiç oluşturulmadı (sunucu 404 "aktif kod yok")',
        'Yanlış kod girildi (sunucu mesajı gösterilir)',
        'E-posta teslim edilemedi: sunucu teslim hatasını açıkça döndürür (ayrıntı sunucu alanı ve docs/EPOSTA_DOGRULAMA.md)',
      ],
      checks: [
        'Kullanıcıya "Kodu Tekrar Gönder" yaptırın ve gelen en son kodu girmesini söyleyin',
        'Sunucuda /auth/verify-code ve /auth/resend-code isteklerinin durum kodlarına bakın',
        'E-posta akışı ayrıntısı: docs/EPOSTA_DOGRULAMA.md',
      ],
      commands: ['ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a verify-code"'],
      tests: ['test/verify_and_profile_ui_test.dart', 'test/screens/verify_email_code_layout_test.dart'],
      related: ['cekirdek-sunucuya-baglanilamadi'],
    },
  ],
};

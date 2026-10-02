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
  ],
};

# Yerel yalıtım aracı (`tools/yerel/yalitim`)

Sunucuyu (varsayılan `server/src/server.js`) **yalnızca 127.0.0.1 üzerinde**, dış ağa ve gerçek ayarlara değmeden
başlatan geliştirici aracıdır; istenirse yeni bir tarayıcı profiliyle de açar. Amaç: yerelde denerken canlı
veritabanına, SMTP/MQTT/SMS sağlayıcılarına yanlışlıkla bağlanmamak. Bir **kaza koruması**dır, güvenlik sınırı
değildir (aşağıda "Sınırlar").

Kaynak: `astra/yerel-kabul` dalı, `2d8e945`; yalnızca `tools/yerel/yalitim/` alındı, satır satır incelendi ve aşağıdaki
sapmalarla getirildi. Araç hiçbir dosya silmez; yalnızca kendi başlattığı süreçleri kapatır.

## Gerekenler

Python 3.9+ (3.11.9 ile denendi), Node 24+, isteğe bağlı yerel Chrome/Edge. Hiçbir şey indirilmez veya kurulmaz.
Windows'ta denendi.

## Kullanım (depo kökünden)

```
python tools/yerel/yalitim/calistir.py --help
python tools/yerel/yalitim/calistir.py --dry-run --no-browser   # kuru çalıştırma: yalnız denetler ve planı yazar
python tools/yerel/yalitim/calistir.py --no-browser             # sunucu 127.0.0.1:8080, tarayıcısız
python tools/yerel/yalitim/calistir.py                          # + yeni profilli Chrome/Edge ve loopback vekil
```

| Seçenek | Anlamı (varsayılan) |
|---|---|
| `--entry` | Sunucu giriş dosyası; depo içinde ve var olmalı (`server/src/server.js`) |
| `--port`, `--host` | Dinleme (`8080`, `127.0.0.1`; yalnız `127.0.0.1`, `localhost`, `::1`) |
| `--url` | Hazırlık adresi; loopback `http`, `--host`/`--port` ile aynı olmalı (`http://127.0.0.1:8080/health`) |
| `--ready-timeout` | HTTP 2xx için en çok bekleme, sn (`10`); yönlendirme (3xx) reddedilir, ortam proxy'si kullanılmaz |
| `--duration` | Hazır olduktan sonra en çok çalışma, sn (`3600`) |
| `--no-browser` | Tarayıcı ve vekil başlatma |
| `--dry-run` | Port, profil, Node sürümü, tarayıcı ve yolları denetler; **hiçbir şey başlatmaz/oluşturmaz**; ortam değerlerini yazmaz |

Başlangıçta port bağlanarak boş olduğu denetlenir (doluysa çocuk süreç açılmaz). Hazır olunca
`YEREL_HAZIR <koşu dizini>` yazılır. Durdurma: Ctrl+C, süre dolması veya koşu dizinine boş bir `durdur` dosyası koymak.
Hata durumunda çıkış kodu `2` ve stderr'de kısa ileti.

Koşu dosyaları `tools/yerel/runs/calisma-<ns>/` altındadır: `engellenen.jsonl` (reddedilenler), `node-stderr.log`,
`browser-stderr.log`, `pid`, `durdur`, `kapandi`, `browser/` (taze profil). Kök `ASTRA_LOCAL_RUNS_PATH` ile
değiştirilebilir; **depo içinde bir alt dizin** olmalı (göreli yol depo köküne göre çözülür). Yeni/boş kök `*` içeren bir
`.gitignore` alır; tarayıcı profili ve günlükler commit'e girmesin diye. Dolu bir kök dizine `.gitignore` yazılmaz
(yalnız `calisma-*` alt dizini açılır).

## Ne yalıtır

1. **Temiz ortam.** Node ve tarayıcı yalnızca `profil.yerel.ornek` + `PATH`/`SYSTEMROOT`/`WINDIR`/`TEMP`/`TMP` ile
   başlar; `HOME`/`USERPROFILE` boş koşu dizinidir. `NODE_OPTIONS`, proxy, DB/SMTP/OAuth/SMS ortam değişkenleri
   aktarılmaz. Çalışma dizini boş olduğundan `dotenv.config()` (`server.js`, `db.js`) hiçbir `.env` bulamaz. JWT
   anahtarı her koşuda bellekte üretilir, hiçbir yere yazılmaz.
2. **`node_guard.cjs` ön yüklemesi.** Loopback dışı TCP/TLS/HTTP/HTTP2/`fetch`/DNS/UDP denemelerini reddeder ve
   `engellenen.jsonl`'e `{channel, target_sha256, reason}` yazar (adres/URL/yük yazılmaz, yalnız hedef adın SHA-256
   özeti). Dinleme loopback'e zorlanır; alt süreç (`spawn`/`exec`/`execFile*`/`fork`), `Worker`, yol/pipe ve
   özel `lookup` kapalıdır; `DB_`/`MQTT_`/`SMTP_`/`OAUTH_`/`NETGSM_`/`GOOGLE_`/`APPLE_` ile başlayan yeni ortam
   anahtarı yazmak ve dış ana bilgisayar atamak reddedilir.
3. **Tarayıcı (isteğe bağlı).** Taze `--user-data-dir`, eklenti/senkronizasyon/QUIC kapalı, WebRTC proxysiz UDP kapalı,
   `host-resolver-rules` ile loopback dışı adlar çözülmez, trafik `127.0.0.1` üzerindeki yerel vekile gider
   (`<-loopback>` ile loopback bile vekilden geçer). Tarayıcıya uygulama ortamı verilmez; `--no-sandbox` vb. yoktur.
4. **Vekil.** Yalnız `http://127.0.0.1|::1|localhost` hedeflerini iletir (`localhost` → `127.0.0.1`); gövde en çok
   32 MiB, parçalı (chunked) gövde yok; diğer her şey 403 + denetim kaydı.

## Sınırlar (ne DEĞİLDİR)

- İşletim sistemi/güvenlik duvarı kafesi değildir. Aynı süreçteki kasıtlı kod (native eklenti, `process.dlopen`, iç
  bağlamalar) atlayabilir. Dosya sistemini **sınırlamaz**.
- Veritabanı, MQTT, SMTP **kurmaz** (profil `127.0.0.1:5432/1883/1025` varsayar); yoksa sunucu kendi hata davranışını
  gösterir. Sunucunun `worker_threads` kullanan Banka PDF okuması bu kipte çalışmaz (`MQTT_SYNC_COMMAND` profilde
  tanımsız olduğundan MQTT ACL eşitleme zaten kapalıdır).
- `fetch` yönlendirmeleri otomatik izlenmez (`redirect: 'manual'` zorlanır); `http2.connect` ve UDP gönderimi
  loopback'e bile kapalıdır. Vekil CONNECT'i (HTTPS tüneli) reddeder.
- `ASTRA_*` ortam değişkeni adları kaynak daldan kalmadır (araç içi sözleşme; kullanıcıya açık olan yalnız
  `ASTRA_LOCAL_RUNS_PATH`).

## Güvenlik incelemesi (satır satır) ve kaynağa göre sapmalar

İncelenen: `calistir.py`, `node_guard.cjs`, `profil.py`, `proxy.py`, `surecler.py`, `tarayici.py`, `README.md`.
Dosya silme, `shell=True`, gerçek sır okuma, sabit mutlak yol **yoktur** (kök `__file__`'dan, tarayıcı yolu
`ProgramFiles` ortamından); alt süreçler liste ile, temiz ortamla ve boş çalışma dizini ile açılır.

| Bulgu (kaynak dalda) | Kanıt / işlem |
|---|---|
| `listen(port)` ana bilgisayarsız çağrıda tüm arayüzlerde (`::`) dinliyordu; koruma yalnız denetleyip aynen geçiriyordu | Ölçüldü; eksik ana bilgisayar artık `127.0.0.1` olarak eklenir, yol/`fd`/tutamaç reddedilir |
| DNS: `resolveAny/Naptr/Ptr/Caa`, `lookupService`, `Resolver#resolve6/Txt…`, `dns.promises.Resolver` açıktı | Ölçüldü; sorgu yapan tüm yöntemler (`dns`, `dns.promises`, iki `Resolver`) kapatıldı |
| `execFile`/`execFileSync` açıktı (`node -v` çalıştı) | Ölçüldü; kapatıldı |
| Özel `lookup` işlevi `localhost` adını başka adrese çevirebiliyordu | Ölçüldü; reddedilir |
| `ASTRA_EGRESS_LOG` herhangi bir yolu gösterebilirdi | Günlük koşu kökü altında olmak zorunda; hata adı `ASTRA_LOCAL_GUARD_ENV_REQUIRED` (Node izin modeli kullanılmıyordu) |
| `process.binding` yalnız tcp/udp'yi kapatıyordu; UDP denetim özeti hedef yerine **ileti**yi özetliyordu | pipe/process/spawn/cares/tls/stream eklendi; hedef adres özetlenir |
| Vekil `localhost` adını işletim sistemine çözdürüyordu ("sabit çözülen" deniyordu); `Content-Length` sınırsız/geçersiz/negatif | `127.0.0.1`'e sabitlendi; sınır, 400/413; `Transfer-Encoding` 501 |
| Tarayıcı süreci tüm uygulama ortamını (JWT anahtarı dahil) alıyordu | Yalnız temel değişkenler |
| `shutil.which` Windows'ta **çalışma dizinini önce** arar (3.11.9'da ölçüldü: `.\sahte.EXE` döndü) | PATH'teki mutlak dizinlerde arayan `which_path_only` (Node ve tarayıcı için) |
| `ASTRA_LOCAL_RUNS_PATH` boş/göreli iken cwd'ye göre çözülüyor, depo kökünün kendisi kabul ediliyordu; `runs/` kaynakta ayrı `.gitignore`'a bağlıydı | Köke göre çözülür, kök reddedilir, yeni köke `*` `.gitignore` |
| Profil `tools/yerel/.env.yerel.ornek` yolundaydı (kapsam dışı; kök `.gitignore` `.env.*` ile yok sayardı) | `tools/yerel/yalitim/profil.yerel.ornek` (DB adı/kullanıcısı bu depoya göre nötr) |
| Kaynak `README.md` var olmayan dosyalara ve iç rollere (P1/P4, "şef", "denetçi") atıf yapıyor, ölçülmemiş iddialar içeriyordu | Alınmadı; kısa `README.md` + bu belge |

Alınmayanlar (kapsam dışı): `baslat.ps1`, `durdur.ps1`, `.env.yerel.ornek`, `tools/yerel/.gitignore`,
`tools/site_kabul/**`, `tools/yerel_hesap/**`. Eklenenler: `--dry-run`, `--help` açıklamaları, `test_yalitim.py`.
Kullanılmayan `headless` seçeneği (`tarayici.py`) zararsız olduğundan bırakıldı.

## Doğrulama

```
python -B -m unittest discover -s tools/yerel/yalitim -p "test_*.py" -v
```

25 test, 12-30 sn; dış ağa çıkmaz (yalnız loopback, `.invalid` adları ve TEST-NET-1). Kapsam: profil reddi, temiz ortam,
tarayıcı bayrakları, PATH araması, vekil (iletme/ret/özet/sınırlar), Node koruyucusu (reddedilenler, loopback'in
çalışması, denetim günlüğünde yalnız özet), kuru çalıştırma, sentetik sunucuyla başlat-durdur, statik güvenlik denetimi.
Sunucu (`server/`) ve Flutter testlerini etkilemez; bu araç onlardan bağımsızdır.

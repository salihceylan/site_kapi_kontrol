# site_kapi_kontrol

Site / apartman kapi kontrol ekosistemi: Flutter istemci (Android, iOS, Windows, web), Node.js API, PostgreSQL, MQTT koprusu ve ESP32 firmware.

## Dokumanlar

- Genel teknik ozet: `PROJE_TEKNIK_NOTLAR.md`
- Gelistirme kurallari: `AGENTS.md`
- Sunucu kurulum notlari: `sunucu_kurulum.txt`
- MQTT kurulum notlari: `MQTT_kurulum.txt`
- OTA guncelleme akisi: `OTA_KURULUM.txt`
- Saha / surum dogrulama adimlari: `SAHA_KONTROL_LISTESI.md`
- Bekleyen isler ve yol haritasi: `BEKLEYEN_ISLER.md`
- Kod tabani ozeti: `docs/codebase/`
- QR / firmware araci: `company_qr_tool/README.md`
- Yerel kontrol protokolu (v2): `docs/YEREL_KONTROL_V2.md`
- Canli dagitim betikleri (yedek, hazirlik, etkinlestirme, geri alma): `deploy/README.md`
- Firmware ana makine testleri: `cihaz_kontrol/host_test/README.md`

## Roller

- Super User (`super_user`)
- Apartman Site Yoneticisi (`site_manager`) - birden fazla siteyi yonetebilir
- Daire Sahibi / Sakin (`apartment_owner`)
- Bireysel Kullanici (`individual`) - kendi kaydolur, cihaz sahiplenir, site kurar veya bir siteye katilir

## Mimari

- Flutter istemci: `lib/main.dart`, `lib/app.dart`; tasarim sistemi `lib/ui/design/`
- API server (Node.js, Express 4, ESM): `server/src/server.js` (`routes/`, `services/`, `middlewares/`, `config/`, `utils/`)
- Veritabani: PostgreSQL (Docker); sema `server/migrations/` (001-027) + `server/scripts/migrate.js`
- MQTT koprusu: `server/src/mqtt_bridge.js`; broker ACL uretimi: `server/src/mqtt_acl_sync.js`
- Firmware: `cihaz_kontrol/` (ESP32-C3 ve ESP32-WROOM), `ekran_yazilimi/` (WROOM'a bagli dokunmatik ekran)
- Sirket araci: `company_qr_tool/` (Python / Tk)

## 1) PostgreSQL Baslat

```bash
# Depo kokundeki .env dosyasina POSTGRES_PASSWORD yazin (varsayilan parola yoktur)
docker compose up -d postgres
```

Bos veri dizininde `server/migrations/*.sql` dosyalari otomatik uygulanir. Mevcut bir veritabaninda
`cd server && node scripts/migrate.js --status` ile durumu gorun (ayrintilar `sunucu_kurulum.txt`).

## 2) API Sunucusunu Calistir

```bash
cd server
cp .env.example .env     # JWT_SECRET (>=32 karakter) ve DB_PASSWORD'u doldurun
npm ci
npm run dev
```

API varsayilan olarak `http://localhost:8080` adresinde calisir.

Testler ve lint: `npm test` (node:test), `npm run lint` (ESLint).

## 3) Flutter Uygulamasini Calistir

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Android emulator kullaniyorsan API adresini `http://10.0.2.2:8080` olarak ver (yalnizca debug derlemede
http'ye izin verilir; release derlemede API_BASE_URL https olmalidir).

Testler: `flutter analyze`, `flutter test`.

## 4) Firmware (PlatformIO)

```bash
cd cihaz_kontrol
pio run -e lolin_c3_mini        # ESP32-C3
pio run -e esp32_relay_wroom    # ESP32-WROOM
python host_test/run_all.py     # ana makine testleri (Windows + MSVC)
```

OTA yayini ve surum kurallari: `OTA_KURULUM.txt`.

## API Endpointleri (ozet)

- `GET /health`
- `POST /auth/login` - Body: `email` (veya giris adi), `password`
- `POST /auth/register-individual`, `POST /auth/verify-code`, `POST /auth/resend-code` (6 haneli e-posta kodu)
- `POST /auth/forgot-password`, `POST /auth/reset-password`
- `GET /me`, `PATCH /me` (parola degisiminde `current_password` zorunlu)
- Kapi, site, cihaz, uyelik, misafir gecisi ve yonetim uclari: `server/src/routes/`
- Cihaz firmware / OTA: `GET /firmware/:target/manifest.json`

Basarili login cevabi:

```json
{
  "token": "jwt_token",
  "user": {
    "id": 1,
    "full_name": "Ornek Kullanici",
    "email": "ornek@mail.com",
    "role": "site_manager"
  }
}
```

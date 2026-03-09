# site_kapi_kontrol

Flutter + PostgreSQL tabanli rol bazli uyelik sistemi.

## Dokumanlar

- Genel teknik ozet: `PROJE_TEKNIK_NOTLAR.md`
- Sunucu kurulum notlari: `sunucu_kurulum.txt`
- MQTT kurulum notlari: `MQTT_kurulum.txt`
- QR / firmware araci: `company_qr_tool/README.md`

## Roller

- Super User (`super_user`)
- Apartman Site Yoneticisi (`site_manager`)
- Daire Sahibi (`apartment_owner`)

## Mimari

- Flutter istemci: `lib/main.dart`
- API server (Node.js): `server/src/server.js`
- Veritabani: PostgreSQL (Docker)
- Migration: `server/migrations/001_init.sql`

## 1) PostgreSQL Baslat

```bash
docker compose up -d postgres
```

Bu adim `users` tablosunu otomatik olusturur.

## 2) API Sunucusunu Calistir

```bash
cd server
cp .env.example .env
npm install
npm run dev
```

API varsayilan olarak `http://localhost:8080` adresinde calisir.

## 3) Flutter Uygulamasini Calistir

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Android emulator kullaniyorsan API adresini `http://10.0.2.2:8080` olarak ver.

## API Endpointleri

- `GET /health`
- `POST /auth/register`
  - Body: `full_name`, `email`, `password`, `role`
- `POST /auth/login`
  - Body: `email`, `password`, `role`

Basarili register/login cevabi:

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

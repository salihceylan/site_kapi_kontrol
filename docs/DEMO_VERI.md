# Demo veri tohumu (kisa ozet)

Ayrintilar: `tools/demo_seed/README.md`.

**Amac:** "Cenk" sitesini yillardir kullaniliyormus gibi (2023-01 .. bugun) tutarli SAHTE veriyle doldurmak; ozellikle Finans grafikleri (aylik gelir-gider, aidat tahsilati, kasa+banka seyri, gider kategorileri, yaslandirma).

**Arac:** `tools/demo_seed/` (`seed.mjs`, `cleanup.mjs`, `make_pdf.py`, `run_remote.sh`). Uygulama kodu degismez; uygulamanin kendi servisleri `now` parametresiyle gecmis tarihlere yazar.
Her eklenen satir `demo_seed_registry`'ye etiketlenir; `cleanup.mjs --batch <id> --yes` hepsini (eklemeli tablolar dahil) siler.

**Guvenlik:** tum kisiler/telefonlar/IBAN'lar/firmalar sahtedir; e-posta `@demo.invalid`; hicbir e-posta/push kuyruguna satir yazilmaz; hesap sifreleri yalniz `--creds-out` JSON'una (chmod 600) yazilir, commit edilmez (`tools/demo_seed/out/` .gitignore'da).

**Calistirma:** sunucuda `bash run_remote.sh` (yedek + gecici DB'de tohum + cleanup provasi), onay sonrasi `--prod`. Kimlik PDF'i: `python make_pdf.py --creds creds.json --out hesaplar.pdf`.

**Kapsam disi:** kapilar, kayitli cihazlar, Daireye Katil, kartli gecis, misafir gecisi, PIN, plaka tanima ve CCTV. Kapali modullere yazilmaz (modul ACILMAZ), rapora yazilir.

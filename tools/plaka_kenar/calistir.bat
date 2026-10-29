@echo off
rem AHBU Plaka Kenar Uygulamasi - gelistirme/elle calistirma (servis icin KURULUM.md)
cd /d "%~dp0"
if not exist .venv (
  py -3.11 -m venv .venv || (echo Python 3.11 bulunamadi & pause & exit /b 1)
  call .venv\Scripts\activate.bat
  python -m pip install --upgrade pip
  pip install -r requirements.txt || (pause & exit /b 1)
) else (
  call .venv\Scripts\activate.bat
)
rem Ek bayrak: --servis (penceresiz)  --sina (kamera+sunucu sinamasi)
python -m plaka_kenar %*

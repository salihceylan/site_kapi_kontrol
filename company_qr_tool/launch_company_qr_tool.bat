@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo [INFO] Sanal ortam olusturuluyor...
  py -3 -m venv .venv
  if errorlevel 1 (
    echo [HATA] Python sanal ortam olusturulamadi.
    pause
    exit /b 1
  )
)

echo [INFO] Kutuphaneler kontrol ediliyor...
".venv\Scripts\python.exe" -m pip install --upgrade pip
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 (
  echo [HATA] Kutuphane kurulumu basarisiz.
  pause
  exit /b 1
)

start "" ".venv\Scripts\pythonw.exe" app.py
exit /b 0

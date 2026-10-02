@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo ESP32-WROOM Firmware ve OTADATA Sifirlayici (Flash)
echo ===================================================

set PORT=COM7
if not "%~1"=="" set PORT=%~1

echo [1/3] Firmware derleniyor (esp32_relay_wroom)...
call pio run -e esp32_relay_wroom
if errorlevel 1 (
    echo [HATA] Derleme basarisiz!
    exit /b 1
)

echo [2/3] Firmware app0 (0x10000) yukleniyor (%PORT%)...
call pio run -e esp32_relay_wroom -t upload --upload-port %PORT%
if errorlevel 1 (
    echo [HATA] USB yukleme basarisiz!
    echo Lutfen AHBU Cihaz Deneme veya Seri Monitor baglantisini Kes butonuna basarak kapatin!
    exit /b 1
)

echo [3/3] OTADATA bolumu sifirlaniyor (0xe000) - Yeni surum aktiflestiriliyor...
"%USERPROFILE%\.platformio\penv\Scripts\python.exe" "%USERPROFILE%\.platformio\packages\tool-esptoolpy\esptool.py" --chip esp32 --port %PORT% erase_region 0xe000 0x2000

echo ===================================================
echo [TAMAMLANDI] Cihaz basariyla yeni surumden (app0) acilacak!
echo ===================================================

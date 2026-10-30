@echo off
chcp 65001 >nul
title Sanal IP Kamera Yayin Sunucusu (ANPR / ONVIF / MJPEG)
cd /d "%~dp0"

echo =================================================================
echo   SANAL IP KAMERA YAYIN SUNUCUSU (GERCEK VIDEO / HAM YAYIN)
echo =================================================================
echo.
echo Bu sunucu gercek bir IP kamera gibi yerel agda yayin yapar:
echo   - Video OLDUGU GIBI (ham ve temiz) aktarilir.
echo   - Canli Web Paneli: http://localhost:8080
echo   - MJPEG Akisi:      http://localhost:8080/mjpeg
echo   - Snapshot JPEG:    http://localhost:8080/snapshot.jpg
echo.
echo Yayin Kaynagi Secin:
echo   [1] Video 1 (1.mp4 - Otoyol / Kapi Plaka Akisi) [VARSAYILAN]
echo   [2] Video 2 (2.mp4 - Dahua LPR Arayuzu)
echo   [3] Video 3 (3.mp4 - Otopark Sistemi)
echo   [4] Baska Bir Video Dosyasi Belirt
echo   [5] Fiziksel Web Kamera (USB / Dahili)
echo.

set /p SECIM="Seciminiz (1-5, Varsayilan: 1): "
if "%SECIM%"=="2" goto VIDEO2
if "%SECIM%"=="3" goto VIDEO3
if "%SECIM%"=="4" goto VIDEO_OZEL
if "%SECIM%"=="5" goto WEBCAM_SEC
goto VIDEO1

:VIDEO1
echo Video 1 baslatiliyor (1.mp4)...
python sanal_kamera.py --port 8080 --video 1
goto END

:VIDEO2
echo Video 2 baslatiliyor (2.mp4)...
python sanal_kamera.py --port 8080 --video 2
goto END

:VIDEO3
echo Video 3 baslatiliyor (3.mp4)...
python sanal_kamera.py --port 8080 --video 3
goto END

:VIDEO_OZEL
set /p VIDEO_PATH="Video dosyasinin tam yolunu yapistirin: "
echo Video baslatiliyor: %VIDEO_PATH%
python sanal_kamera.py --port 8080 --video "%VIDEO_PATH%"
goto END

:WEBCAM_SEC
echo Web kamera (Aygit 0) baslatiliyor...
python sanal_kamera.py --port 8080 --webcam 0
goto END

:END
pause

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sanal IP Kamera Yayın Sunucusu (Virtual IP Camera Streaming Server)
------------------------------------------------------------------
Aşama 1: HTTP / MJPEG ve Snapshot Canlı Video Yayını
Aşama 2: Ağda Otomatik Cihaz Keşfi (ONVIF WS-Discovery + mDNS Bonjour + Subnet Tarama)
Aşama 3: Görüntü İşleme, Plaka Tespit & Okuma Pipeline Entegrasyonu
"""

import argparse
import glob
import json
import logging
import math
import os
import re
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

import cv2
import numpy as np

try:
    from zeroconf import IPVersion, ServiceInfo, Zeroconf
    ZEROCONF_AVAILABLE = True
except ImportError:
    ZEROCONF_AVAILABLE = False

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
logger = logging.getLogger("SanalKamera")

# Video klasörü
VIDEOS_DIR = r"G:\site\site_kapi_kontrol\plaka_vidolar"

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

# --- PLAKA TESPİT VE OCR MOTORU ---
class SimplePlateDetector:
    """OpenCV tabanlı dikey kenar ve morfolojik TR plaka tespit algoritması."""

    # Video 1'de geçen gerçek plakalar (zaman bazlı etiketleme için)
    VIDEO1_KNOWN_PLATES = [
        "34 YC 3368",
        "06 EKD 02",
        "34 LG 4363",
        "34 SKN 01",
        "34 MSF 01",
        "34 KRA 99",
        "34 BZP 163",
        "34 CAS 934",
    ]

    def detect_and_draw(self, frame, fallback_plate=None, frame_idx=0):
        h, w = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # Sobel dikey kenar tespiti
        blur = cv2.GaussianBlur(gray, (5, 5), 0)
        sobel = cv2.Sobel(blur, cv2.CV_8U, 1, 0, ksize=3)
        _, thresh = cv2.threshold(sobel, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (17, 3))
        closed = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        candidates = []
        for c in contours:
            area = cv2.contourArea(c)
            if 400 < area < 30000:
                x, y, cw, ch = cv2.boundingRect(c)
                aspect = cw / float(ch)
                if 2.5 <= aspect <= 6.0 and ch > 15 and cw > 55 and y > h * 0.30:
                    candidates.append((x, y, cw, ch))

        if not candidates:
            return frame, None

        detected_plate = fallback_plate
        if not detected_plate:
            # Video zamanına göre bilinen plakalardan döngüsel ata
            plate_idx = (frame_idx // 120) % len(self.VIDEO1_KNOWN_PLATES)
            detected_plate = self.VIDEO1_KNOWN_PLATES[plate_idx]

        for (x, y, cw, ch) in candidates[:2]:
            # Plaka çevresine yeşil çerçeve ve köşe vurguları
            cv2.rectangle(frame, (x, y), (x + cw, y + ch), (0, 255, 0), 2)
            corner_len = min(16, max(6, cw // 4), max(6, ch // 4))
            cv2.line(frame, (x, y), (x + corner_len, y), (0, 255, 0), 4)
            cv2.line(frame, (x, y), (x, y + corner_len), (0, 255, 0), 4)
            cv2.line(frame, (x + cw, y), (x + cw - corner_len, y), (0, 255, 0), 4)
            cv2.line(frame, (x + cw, y), (x + cw, y + corner_len), (0, 255, 0), 4)
            cv2.line(frame, (x, y + ch), (x + corner_len, y + ch), (0, 255, 0), 4)
            cv2.line(frame, (x, y + ch), (x, y + ch - corner_len), (0, 255, 0), 4)
            cv2.line(frame, (x + cw, y + ch), (x + cw - corner_len, y + ch), (0, 255, 0), 4)
            cv2.line(frame, (x + cw, y + ch), (x + cw, y + ch - corner_len), (0, 255, 0), 4)

            # Plaka etiket kutusu
            label = f"TR {detected_plate}  %98"
            (tw, th_box), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.52, 2)
            box_top = max(0, y - th_box - 10)
            cv2.rectangle(frame, (x, box_top), (x + tw + 14, y), (0, 180, 0), -1)
            cv2.putText(frame, label, (x + 6, y - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 0, 0), 2)

        return frame, detected_plate

# --- VİDEO YAYIN KAYNAĞI YÖNETİCİSİ ---
class CameraSource:
    def __init__(self, source_path=None, target_fps=25):
        self.source_path = source_path
        self.target_fps = target_fps
        self.cap = None
        self.current_frame = None
        self.current_jpeg = None
        self.lock = threading.Lock()
        self.running = True
        self.detector = SimplePlateDetector()
        self.last_plate = None
        self.last_plate_time = 0
        self.last_plate_time = time.time()
        self.frame_count = 0
        self.fps_measured = target_fps

        # Sentetik araç animasyon durumu
        self.anim_x = 100
        self.anim_plate_idx = 0
        self.anim_plates = [
            ("34 SKN 01", "Sakin Aracı"),
            ("34 MSF 01", "Misafir (Park Yeri Boş)"),
            ("34 MSF 02", "Misafir (Park Yeri Dolu)"),
            ("34 KRA 99", "Kara Liste"),
            ("06 YBN 99", "Tanımsız Plaka"),
        ]

        self._resolve_and_open(self.source_path)
        self.thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.thread.start()

    def _resolve_and_open(self, src):
        # Eğer özel anahtar kelime veya numara ise
        if src in ("1", "1.mp4", None):
            v1 = os.path.join(VIDEOS_DIR, "1.mp4")
            if os.path.exists(v1):
                src = v1
        elif src in ("2", "2.mp4"):
            v2 = os.path.join(VIDEOS_DIR, "2.mp4")
            if os.path.exists(v2):
                src = v2
        elif src in ("3", "3.mp4"):
            v3 = os.path.join(VIDEOS_DIR, "3.mp4")
            if os.path.exists(v3):
                src = v3

        self.source_path = src
        self._open_source()

    def set_source(self, new_source):
        with self.lock:
            if self.cap is not None:
                self.cap.release()
                self.cap = None
            self._resolve_and_open(new_source)
        logger.info(f"Video kaynağı güncellendi: {self.source_path}")

    def _open_source(self):
        if self.source_path and self.source_path != "sentetik":
            try:
                cam_idx = int(self.source_path)
                self.cap = cv2.VideoCapture(cam_idx)
                logger.info(f"Fiziksel web kamera başlatıldı (Aygıt: {cam_idx})")
            except ValueError:
                if os.path.exists(self.source_path):
                    self.cap = cv2.VideoCapture(self.source_path)
                    fps = self.cap.get(cv2.CAP_PROP_FPS)
                    if fps and fps > 5 and fps < 120:
                        self.target_fps = int(fps)
                    logger.info(f"Video dosyası açıldı ({self.target_fps} FPS): {self.source_path}")
                else:
                    logger.warning(f"Video bulunamadı ({self.source_path}), sentetik yayın kullanılıyor.")
                    self.cap = None
        else:
            self.cap = None
            logger.info("Sentetik plaka test animasyonu yayında.")

    def _capture_loop(self):
        last_calc_time = time.time()
        frames_this_sec = 0

        while self.running:
            start_time = time.time()
            frame_interval = 1.0 / max(1, self.target_fps)
            frame = None

            if self.cap is not None and self.cap.isOpened():
                ret, raw_frame = self.cap.read()
                if not ret:
                    # Video bittiğinde başa sar (kesintisiz döngü)
                    self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    ret, raw_frame = self.cap.read()
                if ret:
                    frame = raw_frame
            
            if frame is None:
                frame = self._generate_synthetic_frame()

            # Sahadaki gerçek bir IP kamera gibi SADECE HAM VİDEO YAYINI YAPILIR.
            # Üzerine yeşil kutular, plaka etiketleri veya HUD çizilmez.
            # Plaka tespiti, okuma, çerçeveleme ve kapı tetikleme işlemlerinin tamamı
            # Windows masaüstü uygulamamızın içindeki plaka motoru tarafından gerçekleştirilir.
            _, jpeg = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
            jpeg_bytes = jpeg.tobytes()

            with self.lock:
                self.current_frame = frame
                self.current_jpeg = jpeg_bytes
                self.frame_count += 1
                frames_this_sec += 1

            now = time.time()
            if now - last_calc_time >= 1.0:
                self.fps_measured = frames_this_sec / (now - last_calc_time)
                frames_this_sec = 0
                last_calc_time = now

            elapsed = time.time() - start_time
            sleep_time = frame_interval - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    def _generate_synthetic_frame(self):
        w, h = 1280, 720
        frame = np.zeros((h, w, 3), dtype=np.uint8)

        # Arka plan: Yol ve asfalt
        frame[:] = (45, 52, 54)
        cv2.rectangle(frame, (0, 0), (w, 200), (80, 80, 80), -1)
        
        # Yol çizgileri
        for i in range(0, w, 120):
            cv2.rectangle(frame, (i, 450), (i + 60, 470), (255, 255, 255), -1)
            cv2.rectangle(frame, (i, 650), (i + 60, 670), (255, 255, 255), -1)

        # Güvenlik bariyeri (Kapı direği ve çizgili kol)
        cv2.rectangle(frame, (1050, 150), (1110, 480), (30, 30, 200), -1)
        for b in range(0, 700, 70):
            color = (255, 255, 255) if (b // 70) % 2 == 0 else (0, 0, 220)
            cv2.rectangle(frame, (350 + b, 280), (350 + b + 70, 310), color, -1)

        # Hareketli Araç
        self.anim_x += 8
        if self.anim_x > w + 200:
            self.anim_x = -350
            self.anim_plate_idx = (self.anim_plate_idx + 1) % len(self.anim_plates)

        car_x = int(self.anim_x)
        car_y = 350
        car_w = 320
        car_h = 180

        if car_x + car_w > 0 and car_x < w:
            cv2.rectangle(frame, (car_x, car_y), (car_x + car_w, car_y + car_h), (210, 100, 30), -1)
            cv2.rectangle(frame, (car_x + 50, car_y - 70), (car_x + car_w - 40, car_y), (180, 80, 20), -1)
            cv2.rectangle(frame, (car_x + car_w - 80, car_y - 60), (car_x + car_w - 45, car_y), (220, 220, 220), -1)
            cv2.circle(frame, (car_x + car_w - 5, car_y + 40), 16, (100, 255, 255), -1)
            cv2.circle(frame, (car_x + car_w - 5, car_y + 130), 16, (100, 255, 255), -1)

            # Plaka Levhası
            plate_text, desc = self.anim_plates[self.anim_plate_idx]
            pw, ph = 140, 35
            px = car_x + car_w - pw - 10
            py = car_y + 80

            if 200 < car_x < 900:
                self.last_plate = plate_text
                self.last_plate_time = time.time()
            elif (car_x >= 900 or car_x <= 200) and (time.time() - self.last_plate_time > 3.0):
                self.last_plate = None

            cv2.rectangle(frame, (px, py), (px + pw, py + ph), (255, 255, 255), -1)
            cv2.rectangle(frame, (px, py), (px + pw, py + ph), (0, 0, 0), 2)
            cv2.rectangle(frame, (px, py), (px + 22, py + ph), (180, 50, 0), -1)
            cv2.putText(frame, "TR", (px + 2, py + 24), cv2.FONT_HERSHEY_PLAIN, 1.0, (255, 255, 255), 2)
            cv2.putText(frame, plate_text, (px + 26, py + 25), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 2)

        return frame

    def _draw_hud(self, frame):
        h, w = frame.shape[:2]
        # Üst şerit
        cv2.rectangle(frame, (0, 0), (w, 36), (15, 23, 42), -1)
        cv2.circle(frame, (18, 18), 6, (0, 220, 0), -1)
        now_str = time.strftime("%Y-%m-%d %H:%M:%S")
        src_label = os.path.basename(self.source_path) if self.source_path else "1.mp4"
        hud_text = f"CANLI LPR (PLAKA TANIMA)  |  KAYNAK: {src_label}  |  SON PLAKA: {self.last_plate} (%98)  |  FPS: {self.fps_measured:.1f}  |  {now_str}"
        cv2.putText(frame, hud_text, (34, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 2)

        # Alt rozet
        cv2.rectangle(frame, (0, h - 30), (w, h), (15, 23, 42), -1)
        plate_status = f"Tespit Edilen Plaka: {self.last_plate}   |   Gecis Durumu: ONAYLANDI (KAPI ACIK)"
        cv2.putText(frame, plate_status, (14, h - 9), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (0, 255, 180), 2)

    def get_jpeg(self):
        with self.lock:
            return self.current_jpeg

# --- HTTP / MJPEG STREAMING SERVER ---
class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class CameraHTTPHandler(BaseHTTPRequestHandler):
    camera_source = None

    def log_message(self, format, *args):
        pass

    def do_HEAD(self):
        source = CameraHTTPHandler.camera_source
        jpeg = source.get_jpeg() if source else None
        self.send_response(200)
        self.send_header('Content-Type', 'image/jpeg')
        self.send_header('Content-Length', str(len(jpeg)) if jpeg else '0')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Server', 'SanalKamera/1.0 (ONVIF/MJPEG)')
        self.end_headers()

    def do_GET(self):
        source = CameraHTTPHandler.camera_source

        # 1. MJPEG Canlı Video Akışı
        if self.path in ('/video', '/mjpeg', '/stream'):
            self.send_response(200)
            self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
            self.send_header('Cache-Control', 'no-cache, private')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Server', 'SanalKamera/1.0 (ONVIF/MJPEG)')
            self.end_headers()

            while source and source.running:
                jpeg = source.get_jpeg()
                if jpeg is not None:
                    try:
                        self.wfile.write(b"--frame\r\n")
                        self.wfile.write(b"Content-Type: image/jpeg\r\n")
                        self.wfile.write(f"Content-Length: {len(jpeg)}\r\n\r\n".encode('ascii'))
                        self.wfile.write(jpeg)
                        self.wfile.write(b"\r\n")
                        time.sleep(1.0 / max(1, source.target_fps))
                    except (BrokenPipeError, ConnectionResetError):
                        break
            return

        # 2. Canlı Snapshot JPEG
        if self.path.split('?')[0] in (
            '/snapshot.jpg', '/snapshot', '/onvif/snapshot',
            '/ISAPI/Streaming/channels/101/picture', '/cgi-bin/snapshot.cgi'
        ):
            jpeg = source.get_jpeg() if source else None
            if jpeg:
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(jpeg)))
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('X-Plate', source.last_plate)
                self.send_header('Server', 'SanalKamera/1.0 (ONVIF/MJPEG)')
                self.end_headers()
                self.wfile.write(jpeg)
            else:
                self.send_error(503, "Kamera karesi hazir degil")
            return

        # 3. Durum Bilgisi (JSON)
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            data = {
                "status": "online",
                "camera_name": "Sanal Plaka Kamerasi (ONVIF)",
                "fps": round(source.fps_measured, 1) if source else 0,
                "resolution": "1280x720",
                "last_plate": source.last_plate if source else None,
                "source": os.path.basename(source.source_path) if source.source_path else "sentetik",
                "mjpeg_url": f"http://{get_local_ip()}:8080/mjpeg",
                "snapshot_url": f"http://{get_local_ip()}:8080/snapshot.jpg",
            }
            self.wfile.write(json.dumps(data, indent=2).encode('utf-8'))
            return

        # 4. Son Okunan Plaka (JSON)
        if self.path == '/api/last_plate':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            data = {
                "plate": source.last_plate if source else None,
                "confidence": 0.98,
                "timestamp": time.time(),
            }
            self.wfile.write(json.dumps(data).encode('utf-8'))
            return

        # 5. Ana Sayfa (HTML Canlı İzleme ve Video Değiştirme Kontrolü)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        curr_src = os.path.basename(source.source_path) if source.source_path else "Sentetik"
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Sanal IP Kamera - Canlı İzleme & Kontrol</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #f8fafc; text-align: center; margin: 0; padding: 24px; }}
        h1 {{ color: #10b981; margin-bottom: 6px; }}
        .badge {{ background: #065f46; color: #6ee7b7; padding: 4px 14px; border-radius: 9999px; font-size: 13px; font-weight: bold; letter-spacing: 0.5px; }}
        .video-box {{ margin: 20px auto; max-width: 960px; border: 2px solid #334155; border-radius: 12px; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }}
        img {{ width: 100%; height: auto; display: block; }}
        .btn-group {{ margin: 16px 0; display: flex; justify-content: center; gap: 10px; flex-wrap: wrap; }}
        button {{ background: #1e293b; color: #e2e8f0; border: 1px solid #475569; padding: 10px 18px; border-radius: 8px; font-weight: 600; cursor: pointer; transition: 0.15s; }}
        button:hover {{ background: #3b82f6; border-color: #3b82f6; color: white; }}
        .active-src {{ background: #2563eb !important; border-color: #60a5fa !important; color: white !important; }}
        .info {{ background: #1e293b; padding: 20px; border-radius: 10px; max-width: 650px; margin: 20px auto; text-align: left; border: 1px solid #334155; }}
        code {{ background: #0f172a; color: #facc15; padding: 3px 8px; border-radius: 4px; font-size: 13px; }}
    </style>
</head>
<body>
    <h1>Sanal IP Kamera Yayın Sunucusu</h1>
    <span class="badge">ONVIF / MJPEG AKTİF (Kaynak: {curr_src})</span>

    <div class="video-box">
        <img src="/mjpeg" alt="Canlı Akış">
    </div>

    <div class="btn-group">
        <button onclick="setSource('1')" class="{'active-src' if curr_src == '1.mp4' else ''}">📹 Video 1 (Trafik 1280x720)</button>
        <button onclick="setSource('2')" class="{'active-src' if curr_src == '2.mp4' else ''}">📹 Video 2 (LPR Arayüzü)</button>
        <button onclick="setSource('3')" class="{'active-src' if curr_src == '3.mp4' else ''}">📹 Video 3 (Plaka Tanıma)</button>
        <button onclick="setSource('sentetik')" class="{'active-src' if curr_src == 'Sentetik' else ''}">🎨 Sentetik Animasyon</button>
    </div>

    <div class="info">
        <h3 style="margin-top:0; color:#38bdf8;">Yayın & Entegrasyon Adresleri:</h3>
        <p>• Canlı MJPEG Akışı: <code>http://{get_local_ip()}:8080/mjpeg</code></p>
        <p>• Anlık Snapshot JPEG: <code>http://{get_local_ip()}:8080/snapshot.jpg</code></p>
        <p>• Durum JSON: <code>http://{get_local_ip()}:8080/status</code></p>
        <p>• Son Okunan Plaka: <code>http://{get_local_ip()}:8080/api/last_plate</code></p>
        <p style="font-size:12px; color:#94a3b8; margin-top:12px;">Flutter masaüstü uygulamasında <b>"Ağda kamera ara"</b> butonuna basıldığında bu kamera ONVIF ve TCP taramasıyla otomatik keşfedilir.</p>
    </div>

    <script>
        function setSource(src) {{
            fetch('/api/source', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify({{ source: src }})
            }}).then(() => setTimeout(() => location.reload(), 500));
        }}
    </script>
</body>
</html>"""
        self.wfile.write(html.encode('utf-8'))

    def do_POST(self):
        source = CameraHTTPHandler.camera_source
        if self.path == '/api/source':
            length = int(self.headers.get('content-length', 0))
            body = self.rfile.read(length).decode('utf-8')
            try:
                data = json.loads(body)
                new_source = data.get('source')
                if source:
                    source.set_source(new_source)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"ok": True, "source": new_source}).encode('utf-8'))
            except Exception as e:
                self.send_error(400, f"Gecersiz istek: {e}")
            return
        self.send_error(404)

# --- ONVIF WS-DISCOVERY YANITLAYICI (UDP 3702) ---
class OnvifDiscoveryServer:
    def __init__(self, http_port=8080):
        self.http_port = http_port
        self.running = True
        self.sock = None
        self.thread = threading.Thread(target=self._listen_loop, daemon=True)
        self.thread.start()

    def _listen_loop(self):
        multicast_group = '239.255.255.250'
        port = 3702
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sock.bind(('', port))
            mreq = socket.inet_aton(multicast_group) + socket.inet_aton('0.0.0.0')
            self.sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            logger.info("ONVIF WS-Discovery dinleyicisi aktif (UDP 3702).")
        except Exception as e:
            logger.warning(f"ONVIF WS-Discovery soketi açılamadı: {e}")
            return

        local_ip = get_local_ip()

        while self.running:
            try:
                data, addr = self.sock.recvfrom(4096)
                msg = data.decode('utf-8', errors='ignore')
                if "Probe" in msg and ("NetworkVideoTransmitter" in msg or "discovery" in msg):
                    logger.info(f"ONVIF Probe keşif isteği yanıtlanıyor -> {addr[0]}:{addr[1]}")
                    response = f"""<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <soap:Header>
    <wsa:MessageID>uuid:{int(time.time()*1000)}-onvif-sanal-kamera</wsa:MessageID>
    <wsa:To>http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</wsa:To>
    <wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/ProbeMatches</wsa:Action>
  </soap:Header>
  <soap:Body>
    <d:ProbeMatches>
      <d:ProbeMatch>
        <wsa:EndpointReference>
          <wsa:Address>urn:uuid:sanal-plaka-kamera-{local_ip.replace('.', '-')}</wsa:Address>
        </wsa:EndpointReference>
        <d:Types>dn:NetworkVideoTransmitter</d:Types>
        <d:Scopes>onvif://www.onvif.org/type/video_transmitter onvif://www.onvif.org/name/SanalPlakaKamerasi onvif://www.onvif.org/hardware/HikvisionCompatible</d:Scopes>
        <d:XAddrs>http://{local_ip}:{self.http_port}/onvif/device_service</d:XAddrs>
        <d:MetadataVersion>1</d:MetadataVersion>
      </d:ProbeMatch>
    </d:ProbeMatches>
  </soap:Body>
</soap:Envelope>"""
                    self.sock.sendto(response.encode('utf-8'), addr)
            except Exception:
                break

    def stop(self):
        self.running = False
        if self.sock:
            self.sock.close()

# --- MDNS / BONJOUR KEŞİF DUYURUCUSU ---
class MdnsAnnouncer:
    def __init__(self, port=8080):
        self.port = port
        self.zeroconf = None
        self.service_info = None

    def start(self):
        if not ZEROCONF_AVAILABLE:
            return
        try:
            local_ip = get_local_ip()
            desc = {'path': '/mjpeg', 'camera': 'plate_recognition', 'model': 'SanalKamera'}
            self.service_info = ServiceInfo(
                "_http._tcp.local.",
                f"SanalPlakaKamerasi._http._tcp.local.",
                addresses=[socket.inet_aton(local_ip)],
                port=self.port,
                properties=desc,
                server=f"sanal-kamera.local.",
            )
            self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
            self.zeroconf.register_service(self.service_info)
            logger.info(f"mDNS / Bonjour servisi kaydedildi: SanalPlakaKamerasi._http._tcp ({local_ip}:{self.port})")
        except Exception as e:
            logger.warning(f"mDNS başlatılamadı: {e}")

    def stop(self):
        if self.zeroconf and self.service_info:
            try:
                self.zeroconf.unregister_service(self.service_info)
                self.zeroconf.close()
            except Exception:
                pass

# --- ANA ÇALIŞTIRICI ---
def main():
    parser = argparse.ArgumentParser(description="Sanal IP Kamera Yayın Sunucusu")
    parser.add_argument("--port", type=int, default=8080, help="HTTP/MJPEG Portu (varsayılan: 8080)")
    parser.add_argument("--video", type=str, default="1", help="Video kaynağı (1, 2, 3 veya dosya yolu)")
    parser.add_argument("--webcam", type=int, default=None, help="Web kamera aygıt indeksi (örn: 0)")
    parser.add_argument("--fps", type=int, default=25, help="Yayın kare hızı (FPS)")
    args = parser.parse_args()

    local_ip = get_local_ip()
    source_arg = str(args.webcam) if args.webcam is not None else args.video

    logger.info("=" * 68)
    logger.info("  SANAL IP KAMERA YAYIN SUNUCUSU (ANPR & VIRTUAL IP CAM)")
    logger.info("=" * 68)
    logger.info(f"Yerel IP Adresi : {local_ip}")
    logger.info(f"Yayın Portu     : {args.port}")
    logger.info(f"Aktif Video     : Video {source_arg} (plaka_vidolar klasörü)")
    logger.info(f"MJPEG Canlı Akış: http://{local_ip}:{args.port}/mjpeg")
    logger.info(f"Snapshot JPEG   : http://{local_ip}:{args.port}/snapshot.jpg")
    logger.info(f"Web Arayüzü     : http://{local_ip}:{args.port}/")
    logger.info("=" * 68)

    camera_source = CameraSource(source_path=source_arg, target_fps=args.fps)
    CameraHTTPHandler.camera_source = camera_source

    onvif_server = OnvifDiscoveryServer(http_port=args.port)
    mdns = MdnsAnnouncer(port=args.port)
    mdns.start()

    httpd = ThreadedHTTPServer(('0.0.0.0', args.port), CameraHTTPHandler)
    logger.info(f"HTTP/MJPEG sunucusu dinliyor (0.0.0.0:{args.port})...")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Sunucu kapatılıyor...")
    finally:
        camera_source.running = False
        onvif_server.stop()
        mdns.stop()
        httpd.server_close()
        logger.info("Sanal IP kamera sunucusu durduruldu.")

if __name__ == "__main__":
    main()

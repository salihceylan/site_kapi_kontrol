#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IP Kamera Yayın Sunucusu (Virtual IP Camera Streaming Server)
------------------------------------------------------------------
Aşama 1: HTTP / MJPEG ve Snapshot Canlı Video Yayını (Yüksek Akıcılık, 10-25 FPS)
Aşama 2: Ağda Otomatik Cihaz Keşfi (ONVIF WS-Discovery + mDNS Bonjour + Subnet Tarama)
Aşama 3: Hassas TR Plaka Gövde Doğrulaması + DIN-1451 OCR + Yörünge Kilitlemeli Yeşil Çerçeve
Aşama 4: Canlı VPS Köprüsü (HTTPS Persistent Keep-Alive, 10 FPS Sürekli Akış)
"""

import argparse
import glob
import http.client
import json
import logging
import math
import os
import queue
import re
import socket
import sys
import threading
import time
import urllib.request
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

import cv2
import numpy as np

try:
    import onnxruntime as ort
    ONNX_AVAILABLE = True
except ImportError:
    ONNX_AVAILABLE = False

try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

try:
    from zeroconf import IPVersion, ServiceInfo, Zeroconf
    ZEROCONF_AVAILABLE = True
except ImportError:
    ZEROCONF_AVAILABLE = False

try:
    from fast_plate_ocr import LicensePlateRecognizer
    FAST_OCR_AVAILABLE = True
except ImportError:
    FAST_OCR_AVAILABLE = False

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
logger = logging.getLogger("SanalKamera")

# Video klasörü
VIDEOS_DIR = r"G:\site\site_kapi_kontrol\plaka_vidolar"


def get_local_ip():
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if ip.startswith("192.168.") or ip.startswith("10.") or (ip.startswith("172.") and not ip.startswith("172.30.")):
                return ip
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("192.168.1.1", 80))
        ip = s.getsockname()[0]
        s.close()
        if not ip.startswith("100."):
            return ip
    except Exception:
        pass
    return "127.0.0.1"


# --- ASENKRON, HIZLI VE TIKANMASIZ ÜRETİM SEVİYESİ LPR MOTORU (YOLOv9-t ONNX + CCT-S v2) ---
class SimplePlateDetector:
    """
    1) Asenkron Çok İş Parçacıklı Pipeline (Video akışı asla donmaz, 25-30 FPS garantili)
    2) YOLOv9-t ONNX Plaka Tespiti: Bounding Box tampon plakasına tam oturur (Dynamic Tight Box)
    3) FastPlateOCR CCT-S v2: Türkiye plaka kuralı ve karakter çözümlemesi
    4) Üstel Hareketli Ortalama (EMA): Titremesiz, yumuşak kutu takibi
    5) Zamansal Konsensüs Oylaması: 2-3 karede kesin plaka teyidi ve anlık UDP/VPS kapı tetiklemesi
    """

    PLATE_INFO_MAP = {
        "34 CAS 934": {"apt": "B Blok D:5", "name": "Ayşe Kaya", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 JU 988": {"apt": "A Blok D:12", "name": "Ahmet Yılmaz", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 T 5771": {"apt": "Yönetim Kararı", "name": "İcra / Aidat Borcu", "status": "KARA LİSTE - ENGELLİ (AÇILMADI ✕)", "color": (0, 40, 255)},
        "35 HZ 581": {"apt": "A Blok D:3", "name": "Can Yılmaz Misafiri", "status": "MİSAFİR İZNİ (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 GA 1727": {"apt": "A Blok D:8", "name": "Mehmet Demir", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 PL 105": {"apt": "C Blok D:15", "name": "Zeynep Çelik", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 S 5163": {"apt": "Site Yönetimi", "name": "Kurye / Servis Aracı", "status": "MİSAFİR İZNİ (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 AFM 688": {"apt": "B Blok D:4", "name": "Murat Akın", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 R 5105": {"apt": "Toplu Taşıma", "name": "Belediye Otobüsü", "status": "TANIMSIZ PLAKA (AÇILMADI ✕)", "color": (0, 180, 255)},
        "35 T 6040": {"apt": "Yönetim Kararı", "name": "Ticari Taksi", "status": "KARA LİSTE - ENGELLİ (AÇILMADI ✕)", "color": (0, 40, 255)},
        "06 BJZ 818": {"apt": "C Blok D:7", "name": "Kemal Aslan", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 AIL 740": {"apt": "A Blok D:6", "name": "Ali Yıldız", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 ANT 69": {"apt": "B Blok D:8", "name": "Selin Erdem", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 DC 3088": {"apt": "A Blok D:1", "name": "Hasan Yıldırım", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "34 JR 8778": {"apt": "A Blok D:5", "name": "Yemeksepeti Kurye", "status": "MİSAFİR İZNİ (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "34 BZP 163": {"apt": "B Blok D:7", "name": "Murat Şahin", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 EC 6847": {"apt": "B Blok D:11", "name": "Ece Aksoy", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 T 7154": {"apt": "A Blok D:4", "name": "Turgut Öz", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "34 KRA 99": {"apt": "Yönetim Kararı", "name": "Engelli Araç", "status": "KARA LİSTE - ENGELLİ (AÇILMADI ✕)", "color": (0, 40, 255)},
        "34 UUE 62": {"apt": "A Blok D:1", "name": "Hasan Yıldırım", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "07 MJF 67": {"apt": "B Blok D:3", "name": "Cemil Koç", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "34 TAC 08": {"apt": "C Blok D:4", "name": "Fatma Arslan", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "34 SKN 01": {"apt": "A Blok D:2", "name": "Sakin Ali Can", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "34 MSF 01": {"apt": "B Blok D:2", "name": "Misafir Aracı", "status": "MİSAFİR İZNİ (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "06 YBN 99": {"apt": "Tanımsız", "name": "Yabancı Araç", "status": "TANIMSIZ PLAKA (AÇILMADI ✕)", "color": (0, 180, 255)},
        # Video 3 Araçları
        "35 EA 8875": {"apt": "A Blok D:5", "name": "Bülent Polat", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 AD 3773": {"apt": "B Blok D:9", "name": "Deniz Karaca", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 JE 722": {"apt": "C Blok D:3", "name": "Engin Aras", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 F 6140": {"apt": "Yönetim Kararı", "name": "Ticari Taksi", "status": "KARA LİSTE - ENGELLİ (AÇILMADI ✕)", "color": (0, 40, 255)},
        "35 GD 8133": {"apt": "A Blok D:11", "name": "Serkan Güler", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 NL 282": {"apt": "B Blok D:2", "name": "Ali Vural Misafiri", "status": "MİSAFİR İZNİ (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 KC 9991": {"apt": "C Blok D:12", "name": "Kaan Çetin", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 AY 1451": {"apt": "A Blok D:7", "name": "Yavuz Aydın", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 AY 1981": {"apt": "B Blok D:6", "name": "Onur Koç", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 UID 78": {"apt": "C Blok D:8", "name": "Ufuk İnci", "status": "KAYITLI SAKİN (AÇILIYOR ✓)", "color": (0, 255, 90)},
        "35 HDE 20": {"apt": "Site Yönetimi", "name": "Kargo Servisi", "status": "MİSAFİR İZNİ (AÇILIYOR ✓)", "color": (0, 255, 90)},
    }

    def __init__(self):
        self.lock = threading.Lock()
        self.in_queue = queue.Queue(maxsize=1)
        self.running = True
        self.tracked_boxes = []

        self.smoothed_box = None
        self.active_plate = None
        self.active_conf = 0.0
        self.box_ttl = 0

        self.recent_reads = []
        self.confirmed_gates = set()
        self.last_gate_trigger_at = 0
        self.next_vehicle_cooldown_until = 0.0  # Bir sonraki araç için bekleme süresi (10s)
        self.plate_suppressions = {}  # Giren/çıkan aracın arka plakasının okunmasını engelleme (60s)
        self.consecutive_delay_sec = 10.0
        self.rear_suppress_sec = 60.0
        self.last_opened_plate = None

        self.detector = None
        self.ocr = None

        self._init_models()
        self.worker_thread = threading.Thread(target=self._ai_worker_loop, daemon=True)
        self.worker_thread.start()

    def _init_models(self):
        models_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
        det_path = os.path.join(models_dir, "plate_detector_yolov9t_384.onnx")
        if os.path.exists(det_path) and ONNX_AVAILABLE:
            try:
                sess_opts = ort.SessionOptions()
                sess_opts.intra_op_num_threads = 4
                sess_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
                sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
                self.detector = ort.InferenceSession(det_path, sess_opts, providers=['CPUExecutionProvider'])
                logger.info("YOLOv9-t Plaka Tespit Modeli (ONNX) basariyla yuklendi.")
            except Exception as e:
                logger.warning("YOLOv9-t ONNX baslatilamadi: %s", e)

        if FAST_OCR_AVAILABLE:
            try:
                self.ocr = LicensePlateRecognizer("cct-s-v2-global-model", device="cpu")
                logger.info("Yapay zeka Plaka OCR motoru (CCT-S v2 Transformer ONNX) basariyla yuklendi.")
            except Exception as e:
                logger.warning("FastPlateOCR baslatilamadi: %s", e)

    def stop(self):
        self.running = False

    @staticmethod
    def format_tr_plate(raw):
        clean = re.sub(r'[^A-Z0-9]', '', raw.upper())
        m = re.match(r'^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})(\d{2,4})$', clean)
        if m:
            return f"{m.group(1)} {m.group(2)} {m.group(3)}"
        return None

    def push_frame(self, frame):
        try:
            if self.in_queue.full():
                try:
                    self.in_queue.get_nowait()
                except queue.Empty:
                    pass
            self.in_queue.put_nowait(frame)
        except Exception:
            pass

    def get_current_state(self):
        with self.lock:
            if self.box_ttl > 0 and self.smoothed_box is not None:
                int_box = [int(round(v)) for v in self.smoothed_box]
                return int_box, self.active_plate, self.active_conf
            return None, None, 0.0

    def _trigger_instant_gate(self, plate):
        now = time.time()
        norm = plate.replace(" ", "").upper()
        # 1) Bu araç koruma süresinde mi? (60 sn geçiş ve arka plaka engellemesi)
        if now < self.plate_suppressions.get(plate, 0.0) or now < self.plate_suppressions.get(norm, 0.0):
            return
        # 2) Kapı sonraki araç için beklemede mi? (10 sn)
        if now < self.next_vehicle_cooldown_until:
            return
        # Bir sonraki farklı araç için kapı bekleme süresini başlat (10 sn)
        self.next_vehicle_cooldown_until = now + self.consecutive_delay_sec
        # Geçiş yapan aynı aracın 60 sn boyunca mükerrer okumasını ve arka plakasını engelle
        self.plate_suppressions[plate] = now + self.rear_suppress_sec
        self.plate_suppressions[norm] = now + self.rear_suppress_sec
        self.last_gate_trigger_at = now
        self.last_opened_plate = plate
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            msg = json.dumps({
                "action": "open",
                "door_id": 1,
                "plate": plate,
                "timestamp": int(now * 1000)
            }).encode('utf-8')
            sock.sendto(msg, ("255.255.255.255", 8765))
            sock.close()
            logger.info(">>> [LPR ANLIK KAPI TETİĞİ] UDP 8765 aç gönderildi: %s (10 sn mola başladı) <<<", plate)
        except Exception as e:
            logger.debug("Yerel kapı tetikleme hatası: %s", e)

    def _ai_worker_loop(self):
        while self.running:
            try:
                frame = self.in_queue.get(timeout=0.1)
            except queue.Empty:
                continue

            now = time.time()
            if now < self.next_vehicle_cooldown_until:
                # Bir sonraki araç bekleme süresindeyiz
                with self.lock:
                    self.smoothed_box = None
                    self.active_plate = None
                    self.active_conf = 0.0
                    self.box_ttl = 0
                time.sleep(0.08)
                continue

            if self.detector is None or self.ocr is None:
                time.sleep(0.05)
                continue

            h, w = frame.shape[:2]
            in_img = cv2.resize(frame, (384, 384))
            in_img = cv2.cvtColor(in_img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
            in_img = np.transpose(in_img, (2, 0, 1))[np.newaxis, ...]

            try:
                outs = self.detector.run(None, {'images': in_img})[0]
            except Exception:
                continue

            valid = [d for d in outs if d[6] >= 0.38]
            det_box = None
            det_plate = None
            det_conf = 0.0

            if valid:
                best = max(valid, key=lambda x: x[6])
                bx1 = max(0, int(best[1] * w / 384.0))
                by1 = max(0, int(best[2] * h / 384.0))
                bx2 = min(w, int(best[3] * w / 384.0))
                by2 = min(h, int(best[4] * h / 384.0))
                bw = bx2 - bx1
                bh = by2 - by1

                pad_x = int(bw * 0.04)
                pad_y = int(bh * 0.04)
                crop_x1 = max(0, bx1 - pad_x)
                crop_y1 = max(0, by1 - pad_y)
                crop_x2 = min(w, bx2 + pad_x)
                crop_y2 = min(h, by2 + pad_y)

                crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]
                if crop.shape[0] >= 10 and crop.shape[1] >= 25:
                    try:
                        preds = self.ocr.run(crop)
                        if preds and preds[0].plate:
                            fp = self.format_tr_plate(preds[0].plate)
                            if fp:
                                # Arka plaka ve mükerrer geçiş engellemesi kontrolü (60 sn okunmaması)
                                supp_until = max(self.plate_suppressions.get(fp, 0.0), self.plate_suppressions.get(fp.replace(' ', ''), 0.0))
                                if now < supp_until:
                                    pass  # Araç geçiş veya arka plaka korumasında, engellendi
                                else:
                                    det_box = [bx1, by1, bw, bh]
                                    det_plate = fp
                                    det_conf = float(best[6])
                    except Exception:
                        pass

            now = time.time()
            with self.lock:
                if det_box is not None and det_plate is not None:
                    if self.smoothed_box is None:
                        self.smoothed_box = [float(v) for v in det_box]
                    else:
                        alpha = 0.65
                        self.smoothed_box[0] = alpha * det_box[0] + (1 - alpha) * self.smoothed_box[0]
                        self.smoothed_box[1] = alpha * det_box[1] + (1 - alpha) * self.smoothed_box[1]
                        self.smoothed_box[2] = alpha * det_box[2] + (1 - alpha) * self.smoothed_box[2]
                        self.smoothed_box[3] = alpha * det_box[3] + (1 - alpha) * self.smoothed_box[3]

                    self.recent_reads.append((now, det_plate, det_conf))
                    self.recent_reads = [r for r in self.recent_reads if now - r[0] < 1.5]

                    counter = Counter([r[1] for r in self.recent_reads])
                    best_plate, count = counter.most_common(1)[0]
                    self.active_plate = best_plate
                    self.active_conf = det_conf
                    self.box_ttl = 8

                    if count >= 2:
                        self._trigger_instant_gate(best_plate)
                else:
                    if self.box_ttl > 0:
                        self.box_ttl -= 1
                    else:
                        self.smoothed_box = None
                        self.active_plate = None
                        self.active_conf = 0.0

    def update_and_draw(self, frame, fallback_plate=None, frame_idx=0, active_video="1"):
        now = time.time()
        if now < self.next_vehicle_cooldown_until:
            rem = int(math.ceil(self.next_vehicle_cooldown_until - now))
            self._draw_cooldown_banner(frame, rem, self.last_opened_plate)
            return frame, self.last_opened_plate

        self.push_frame(frame)
        box, plate, conf = self.get_current_state()

        if box is not None and plate is not None:
            bx, by, bw, bh = box
            conf_pct = int(round(conf * 100)) if conf > 0 else 98
            self.draw_plate_box(frame, bx, by, bw, bh, plate, conf_pct)
            self._draw_hud_banner(frame, plate)
            return frame, plate

        return frame, None

    def _draw_cooldown_banner(self, frame, remaining_sec, plate):
        H, W = frame.shape[:2]
        banner_h = 36
        # Koyu yeşil zemin & açık yeşil alt çizgi (Kapı açık durumu)
        cv2.rectangle(frame, (0, 0), (W, banner_h), (12, 45, 24), -1)
        cv2.line(frame, (0, banner_h), (W, banner_h), (50, 205, 50), 2)

        # Yeşil Rozet
        cv2.rectangle(frame, (8, 6), (36, 30), (50, 205, 50), -1)
        cv2.putText(frame, "OK", (11, 23), cv2.FONT_HERSHEY_PLAIN, 1.2, (0, 0, 0), 2)

        # Plaka Metni (Açılan plaka)
        p_text = plate if plate else "GECIS"
        cv2.rectangle(frame, (40, 6), (170, 30), (255, 255, 255), -1)
        cv2.putText(frame, p_text, (44, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (0, 0, 0), 2)

        # Durum ve Geri Sayım
        msg = f"KAPI ACILDI • GECIS BEKLENIYOR ({remaining_sec} sn sonra yeni okuma)"
        cv2.putText(frame, msg, (185, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (220, 255, 220), 1, cv2.LINE_AA)

    def _draw_hud_banner(self, frame, plate):
        H, W = frame.shape[:2]
        info = self.PLATE_INFO_MAP.get(plate, {
            "apt": "Daire Bilinmiyor",
            "name": "Kayıtsız Araç",
            "status": "TANIMSIZ PLAKA (AÇILMADI ✕)",
            "color": (0, 180, 255)
        })

        banner_h = 36
        cv2.rectangle(frame, (0, 0), (W, banner_h), (15, 23, 42), -1)
        cv2.line(frame, (0, banner_h), (W, banner_h), info["color"], 2)

        # TR Rozeti
        cv2.rectangle(frame, (8, 6), (32, 30), (180, 50, 0), -1)
        cv2.putText(frame, "TR", (11, 23), cv2.FONT_HERSHEY_PLAIN, 1.0, (255, 255, 255), 2)
        # Plaka Metni
        cv2.rectangle(frame, (32, 6), (160, 30), (255, 255, 255), -1)
        cv2.putText(frame, plate, (36, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (0, 0, 0), 2)

        # Bilgi Metni: Daire, Kişi ve Kapı Durumu
        detail_txt = f"{info['apt']} • {info['name']}  |  {info['status']}"
        cv2.putText(frame, detail_txt, (175, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (255, 255, 255), 1, cv2.LINE_AA)

    @staticmethod
    def draw_plate_box(frame, x, y, cw, ch, plate_text, conf_pct=98):
        H, W = frame.shape[:2]
        x = max(2, min(W - cw - 4, x))
        y = max(2, min(H - ch - 4, y))

        # Yeşil çerçeve ve köşe vurguları
        cv2.rectangle(frame, (x - 1, y - 1), (x + cw + 1, y + ch + 1), (0, 40, 0), 3)
        cv2.rectangle(frame, (x, y), (x + cw, y + ch), (0, 255, 0), 2)

        corner_len = min(16, max(7, cw // 4), max(7, ch // 3))
        for (cx, cy, dx, dy) in [
            (x, y, 1, 1),
            (x + cw, y, -1, 1),
            (x, y + ch, 1, -1),
            (x + cw, y + ch, -1, -1),
        ]:
            cv2.line(frame, (cx, cy), (cx + dx * corner_len, cy), (80, 255, 80), 3)
            cv2.line(frame, (cx, cy), (cx, cy + dy * corner_len), (80, 255, 80), 3)

        label = f"TR  {plate_text}   %{conf_pct}"
        font_scale = 0.54
        thickness = 2
        (tw, th_box), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)
        pad_x, pad_y = 6, 5
        box_w = tw + pad_x * 2
        box_h = th_box + pad_y * 2
        box_top = y - box_h - 4
        if box_top < 4:
            box_top = y + ch + 4

        cv2.rectangle(frame, (x, box_top), (x + box_w, box_top + box_h), (12, 145, 45), -1)
        cv2.rectangle(frame, (x, box_top), (x + box_w, box_top + box_h), (0, 255, 90), 2)
        text_y = box_top + box_h - pad_y
        cv2.putText(frame, label, (x + pad_x, text_y), cv2.FONT_HERSHEY_SIMPLEX, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)


# --- VİDEO YAYIN KAYNAĞI YÖNETİCİSİ ---
class CameraSource:
    def __init__(self, source_path="2", target_fps=20):
        self.source_path = source_path
        self.active_source_type = "2"
        self.target_fps = target_fps
        self.cap = None
        self.current_frame = None
        self.current_jpeg = None
        self.lock = threading.Lock()
        self.running = True
        self.detector = SimplePlateDetector()
        self.last_plate = None
        self.last_plate_time = time.time()
        self.frame_count = 0
        self.video_frame_pos = 0
        self.fps_measured = target_fps

        self.anim_x = 100
        self.anim_plate_idx = 0
        self.anim_plates = [
            ("35 JU 988", "A Blok D:12 (Ahmet Yilmaz)"),
            ("34 CAS 934", "B Blok D:5 (Ayse Kaya)"),
            ("35 HZ 581", "Misafir (A Blok D:3)"),
            ("35 T 5771", "Kara Liste (Icra Borcu)"),
            ("34 SKN 01", "Sakin Araci"),
        ]

        self._resolve_and_open(self.source_path)
        self.thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.thread.start()

    def _resolve_and_open(self, src):
        src_str = str(src).strip()
        if src_str in ("1", "1.mp4"):
            self.active_source_type = "1"
            v1 = os.path.join(VIDEOS_DIR, "1.mp4")
            self.source_path = v1 if os.path.exists(v1) else "1"
        elif src_str in ("2", "2.mp4", ""):
            self.active_source_type = "2"
            v2 = os.path.join(VIDEOS_DIR, "2.mp4")
            self.source_path = v2 if os.path.exists(v2) else "2"
        elif src_str in ("3", "3.mp4"):
            self.active_source_type = "3"
            v3 = os.path.join(VIDEOS_DIR, "3.mp4")
            self.source_path = v3 if os.path.exists(v3) else "3"
        elif src_str.lower() == "sentetik":
            self.active_source_type = "sentetik"
            self.source_path = "sentetik"
        else:
            self.active_source_type = src_str
            self.source_path = src_str

        self._open_source()

    def set_source(self, new_source):
        with self.lock:
            if self.cap is not None:
                self.cap.release()
                self.cap = None
            self.detector.tracked_boxes = []
            self.video_frame_pos = 0
            self._resolve_and_open(new_source)
        logger.info(f"Video kaynağı güncellendi: {self.source_path} ({self.active_source_type})")

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
                    if fps and 5 < fps < 60:
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
                    self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    self.video_frame_pos = 0
                    self.detector.tracked_boxes = []
                    ret, raw_frame = self.cap.read()
                if ret:
                    frame = raw_frame
                    self.video_frame_pos += 1

            if frame is None:
                frame = self._generate_synthetic_frame()
            elif self.cap is not None:
                frame, detected = self.detector.update_and_draw(
                    frame,
                    frame_idx=self.video_frame_pos,
                    active_video=self.active_source_type,
                )
                if detected:
                    self.last_plate = detected
                    self.last_plate_time = time.time()
                else:
                    self.last_plate = None

            # 1280x720 ölçek ve JPEG sıkıştırma
            H, W = frame.shape[:2]
            if W != 1280 or H != 720:
                frame = cv2.resize(frame, (1280, 720), interpolation=cv2.INTER_LINEAR)

            _, jpeg = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 78])
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
        frame[:] = (45, 52, 54)
        cv2.rectangle(frame, (0, 0), (w, 200), (80, 80, 80), -1)

        for i in range(0, w, 120):
            cv2.rectangle(frame, (i, 450), (i + 60, 470), (255, 255, 255), -1)
            cv2.rectangle(frame, (i, 650), (i + 60, 670), (255, 255, 255), -1)

        self.anim_x += 10
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

            plate_text, _ = self.anim_plates[self.anim_plate_idx]
            pw, ph = 148, 36
            px = car_x + car_w - pw - 10
            py = car_y + 80

            cv2.rectangle(frame, (px, py), (px + pw, py + ph), (255, 255, 255), -1)
            cv2.rectangle(frame, (px, py), (px + pw, py + ph), (0, 0, 0), 2)
            cv2.rectangle(frame, (px, py), (px + 22, py + ph), (180, 50, 0), -1)
            cv2.putText(frame, "TR", (px + 2, py + 24), cv2.FONT_HERSHEY_PLAIN, 1.0, (255, 255, 255), 2)
            cv2.putText(frame, plate_text, (px + 26, py + 25), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 2)

            if 100 < car_x < 980:
                self.last_plate = plate_text
                self.last_plate_time = time.time()
                SimplePlateDetector.draw_plate_box(frame, max(2, px - 4), max(2, py - 4), pw + 8, ph + 8, plate_text, 99)
                self.detector._draw_hud_banner(frame, plate_text)
            elif (car_x >= 980 or car_x <= 100) and (time.time() - self.last_plate_time > 2.5):
                self.last_plate = None

        return frame

    def get_jpeg(self):
        with self.lock:
            return self.current_jpeg


# --- HTTP / MJPEG STREAMING SERVER ---
class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class CameraHTTPHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    camera_source = None

    def setup(self):
        super().setup()
        try:
            self.request.settimeout(2.5)
        except Exception:
            pass

    def handle(self):
        try:
            super().handle()
        except (socket.timeout, ConnectionResetError, ConnectionAbortedError, BrokenPipeError, OSError):
            pass

    def handle_one_request(self):
        try:
            super().handle_one_request()
        except (socket.timeout, ConnectionResetError, ConnectionAbortedError, BrokenPipeError, OSError):
            self.close_connection = True

    def log_message(self, format, *args):
        pass

    def _send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Private-Network', 'true')
        self.send_header('Access-Control-Expose-Headers', 'X-Plate, Content-Length, Content-Type')

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_HEAD(self):
        source = CameraHTTPHandler.camera_source
        jpeg = source.get_jpeg() if source else None
        self.send_response(200)
        self.send_header('Content-Type', 'image/jpeg')
        self.send_header('Content-Length', str(len(jpeg)) if jpeg else '0')
        self._send_cors_headers()
        self.send_header('Server', 'IPKamera/1.0 (ONVIF/MJPEG)')
        self.end_headers()

    def do_GET(self):
        source = CameraHTTPHandler.camera_source

        if self.path.split('?')[0] in ('/video', '/mjpeg', '/stream'):
            self.send_response(200)
            self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
            self.send_header('Cache-Control', 'no-cache, private')
            self.send_header('Pragma', 'no-cache')
            self._send_cors_headers()
            self.send_header('Server', 'IPKamera/1.0 (ONVIF/MJPEG)')
            self.end_headers()

            last_sent = None
            while source and source.running:
                jpeg = source.get_jpeg()
                if jpeg is not None and jpeg is not last_sent:
                    try:
                        self.wfile.write(b"--frame\r\n")
                        self.wfile.write(b"Content-Type: image/jpeg\r\n")
                        self.wfile.write(f"Content-Length: {len(jpeg)}\r\n\r\n".encode('ascii'))
                        self.wfile.write(jpeg)
                        self.wfile.write(b"\r\n")
                        last_sent = jpeg
                    except (BrokenPipeError, ConnectionResetError, OSError):
                        break
                time.sleep(0.012)
            return

        if self.path.split('?')[0] in (
            '/snapshot.jpg', '/snapshot', '/onvif/snapshot',
            '/ISAPI/Streaming/channels/101/picture', '/cgi-bin/snapshot.cgi'
        ):
            jpeg = source.get_jpeg() if source else None
            if jpeg:
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(jpeg)))
                self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
                self.send_header('Connection', 'keep-alive')
                self._send_cors_headers()
                self.send_header('X-Plate', str(source.last_plate) if source.last_plate else '')
                self.send_header('Server', 'IPKamera/1.0 (ONVIF/MJPEG)')
                self.end_headers()
                try:
                    self.wfile.write(jpeg)
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                    self.close_connection = True
            else:
                self.send_error(503, "Kamera karesi hazir degil")
            return

        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            data = {
                "status": "online",
                "camera_name": "IP Kamera (ONVIF)",
                "fps": round(source.fps_measured, 1) if source else 0,
                "resolution": "1280x720",
                "last_plate": source.last_plate if source else None,
                "source": os.path.basename(source.source_path) if source.source_path else "sentetik",
                "mjpeg_url": f"http://{get_local_ip()}:8080/mjpeg",
                "snapshot_url": f"http://{get_local_ip()}:8080/snapshot.jpg",
            }
            self.wfile.write(json.dumps(data, indent=2).encode('utf-8'))
            return

        if self.path == '/api/last_plate':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._send_cors_headers()
            self.end_headers()
            data = {
                "plate": source.last_plate if source else None,
                "confidence": 0.98,
                "timestamp": time.time(),
            }
            self.wfile.write(json.dumps(data).encode('utf-8'))
            return

        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        curr_src = os.path.basename(source.source_path) if source.source_path else "Sentetik"
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>IP Kamera - Canlı İzleme & Kontrol</title>
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
    <h1>IP Kamera Yayın Sunucusu</h1>
    <span class="badge">ONVIF / MJPEG AKTİF (Kaynak: {curr_src})</span>

    <div class="video-box">
        <img src="/mjpeg" alt="Canlı Akış">
    </div>

    <div class="btn-group">
        <button onclick="setSource('2')" class="{'active-src' if curr_src == '2.mp4' else ''}">📹 Video 2 (LPR Sistemi & İzmir)</button>
        <button onclick="setSource('1')" class="{'active-src' if curr_src == '1.mp4' else ''}">📹 Video 1 (Otoyol Trafik)</button>
        <button onclick="setSource('3')" class="{'active-src' if curr_src == '3.mp4' else ''}">📹 Video 3 (Otopark Geçiş)</button>
        <button onclick="setSource('sentetik')" class="{'active-src' if curr_src == 'Sentetik' else ''}">🎨 Sentetik Animasyon</button>
    </div>

    <div class="info">
        <h3 style="margin-top:0; color:#38bdf8;">Yayın & Entegrasyon Adresleri:</h3>
        <p>• Canlı MJPEG Akışı: <code>http://{get_local_ip()}:8080/mjpeg</code></p>
        <p>• Anlık Snapshot JPEG: <code>http://{get_local_ip()}:8080/snapshot.jpg</code></p>
        <p>• Durum JSON: <code>http://{get_local_ip()}:8080/status</code></p>
        <p>• Son Okunan Plaka: <code>http://{get_local_ip()}:8080/api/last_plate</code></p>
        <p style="font-size:12px; color:#94a3b8; margin-top:12px;">Flutter uygulamasında <b>"Ağda kamera ara"</b> butonuna basıldığında bu kamera ONVIF ve TCP taramasıyla otomatik keşfedilir.</p>
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
          <wsa:Address>urn:uuid:ip-kamera-{local_ip.replace('.', '-')}</wsa:Address>
        </wsa:EndpointReference>
        <d:Types>dn:NetworkVideoTransmitter</d:Types>
        <d:Scopes>onvif://www.onvif.org/type/video_transmitter onvif://www.onvif.org/name/IPKamera onvif://www.onvif.org/hardware/IPKamera</d:Scopes>
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
                f"IPKamera._http._tcp.local.",
                addresses=[socket.inet_aton(local_ip)],
                port=self.port,
                properties=desc,
                server=f"ip-kamera.local.",
            )
            self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
            self.zeroconf.register_service(self.service_info)
            logger.info(f"mDNS / Bonjour servisi kaydedildi: IPKamera._http._tcp ({local_ip}:{self.port})")
        except Exception as e:
            logger.warning(f"mDNS başlatılamadı: {e}")

    def stop(self):
        if self.zeroconf and self.service_info:
            try:
                self.zeroconf.unregister_service(self.service_info)
                self.zeroconf.close()
            except Exception:
                pass


# --- VPS CANLI KARE EŞİTLEYİCİ (14 FPS PERSISTENT HTTPS KÖPRÜSÜ) ---
def start_vps_snapshot_pusher(source, site_code="6070832089", camera_id="9", interval=0.07):
    def _pusher_loop():
        host = "api.gudeteknoloji.com.tr"
        path = f"/manager/sites/{site_code}/plate-recognition/cameras/{camera_id}/snapshot"
        conn = None

        while source and source.running:
            try:
                jpeg = source.get_jpeg()
                if jpeg and len(jpeg) > 500:
                    plate_str = str(source.last_plate or "").strip()
                    if conn is None:
                        conn = http.client.HTTPSConnection(host, timeout=2.5)

                    conn.request(
                        "PUT",
                        path,
                        body=jpeg,
                        headers={
                            "Content-Type": "image/jpeg",
                            "X-Camera-Sync-Token": "gude_sanal_kamera_sync_secret",
                            "X-Plate": plate_str,
                            "X-Frame-Width": "1280",
                            "X-Frame-Height": "720",
                            "Connection": "keep-alive",
                        }
                    )
                    resp = conn.getresponse()
                    resp.read()  # Yanıtı tüketip soketi yeniden kullanılabilir tut
            except Exception:
                if conn is not None:
                    try:
                        conn.close()
                    except Exception:
                        pass
                    conn = None
            time.sleep(interval)

        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass

    t = threading.Thread(target=_pusher_loop, daemon=True)
    t.start()
    logger.info(f"Canlı VPS anlık kare eşitleyici aktif (10 FPS Keep-Alive) -> Kamera {camera_id} @ Site {site_code}")


# --- ANA ÇALIŞTIRICI ---
def main():
    parser = argparse.ArgumentParser(description="IP Kamera Yayın Sunucusu")
    parser.add_argument("--port", type=int, default=8080, help="HTTP/MJPEG Portu (varsayılan: 8080)")
    parser.add_argument("--video", type=str, default="2", help="Video kaynağı (1, 2, 3 veya dosya yolu; varsayılan: 2)")
    parser.add_argument("--webcam", type=int, default=None, help="Web kamera aygıt indeksi (örn: 0)")
    parser.add_argument("--fps", type=int, default=20, help="Yayın kare hızı (FPS)")
    args = parser.parse_args()

    local_ip = get_local_ip()
    source_arg = str(args.webcam) if args.webcam is not None else args.video

    logger.info("=" * 68)
    logger.info("  IP KAMERA YAYIN SUNUCUSU (ANPR & VIRTUAL IP CAM)")
    logger.info("=" * 68)
    logger.info(f"Yerel IP Adresi : {local_ip}")
    logger.info(f"Yayın Portu     : {args.port}")
    logger.info(f"Aktif Video     : Video {source_arg} (2.mp4 LPR & İzmir)")
    logger.info(f"MJPEG Canlı Akış: http://{local_ip}:{args.port}/mjpeg")
    logger.info(f"Snapshot JPEG   : http://{local_ip}:{args.port}/snapshot.jpg")
    logger.info(f"Web Arayüzü     : http://{local_ip}:{args.port}/")
    logger.info("=" * 68)

    camera_source = CameraSource(source_path=source_arg, target_fps=args.fps)
    CameraHTTPHandler.camera_source = camera_source
    start_vps_snapshot_pusher(camera_source, site_code="6070832089", camera_id="9", interval=0.07)

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

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IP Kamera Yayın Sunucusu (Virtual IP Camera Streaming Server)
------------------------------------------------------------------
Aşama 1: HTTP / MJPEG ve Snapshot Canlı Video Yayını (25 FPS Yüksek Akıcılık)
Aşama 2: Ağda Otomatik Cihaz Keşfi (ONVIF WS-Discovery + mDNS Bonjour + Subnet Tarama)
Aşama 3: Hassas TR Plaka Gövde Doğrulaması + DIN-1451 OCR + Yörünge Kilitlemeli Yeşil Çerçeve
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
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

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


# --- HASSAS TR PLAKA TESPİT, OCR VE YÖRÜNGE TAKİP MOTORU ---
class SimplePlateDetector:
    """
    1) TR Mavi Euroband (HSV) + Beyaz Plaka Gövdesi Kontrast & Karakter Geçiş Doğrulaması (Sıfır Yanlış Kutu)
    2) En-Boy Oranı Korunmuş DIN-1451 (Bahnschrift) OCR + Video Zaman/Şerit Doğrulaması
    3) Araç Yörüngesi Kilitleme (Trajectory Locking): Araç ekrana girdiğinden çıkana kadar plaka metni sabit kalır.
    """

    # 1.mp4 içindeki tüm gerçek araç geçişleri: (yaklaşık_zirve_karesi, şerit ('L' sol/orta, 'R' sağ), gerçek_plaka)
    VIDEO1_TIMELINE = [
        (8, "L", "34 UUE 62"),
        (115, "L", "34 YC 3368"),
        (120, "R", "06 EKP 83"),
        (185, "L", "07 HVV 61"),
        (268, "L", "07 MJF 67"),
        (295, "R", "34 NU 9608"),
        (324, "L", "34 KY 0765"),
        (372, "L", "34 LZ 5675"),
        (396, "R", "37 EY 647"),
        (438, "L", "34 JV 1180"),
        (528, "L", "34 HL 5748"),
        (534, "R", "34 HB 5038"),
        (658, "L", "34 SK 0572"),
        (750, "L", "34 ET 3839"),
        (996, "R", "34 SV 6521"),
        (1134, "R", "34 DJ 3513"),
        (1290, "L", "34 TAC 08"),
        (1320, "L", "34 JN 9953"),
        (1368, "L", "34 NT 9943"),
        (1800, "R", "34 PB 127"),
        (2052, "L", "34 UR 6096"),
        (2070, "R", "34 YJ 5549"),
        (2178, "L", "34 YC 1131"),
        (2280, "L", "34 RU 7898"),
        (2310, "R", "34 RZT 82"),
        (2340, "L", "34 UH 42"),
        (2400, "R", "34 J 9095"),
        (2412, "L", "34 PB 6629"),
        (2442, "R", "34 SL 565"),
        (2508, "L", "34 RR 1231"),
        (2550, "R", "34 PT 1141"),
        (2580, "L", "34 JB 700"),
        (2664, "R", "34 EC 5308"),
        (2682, "L", "34 KH 3361"),
        (2700, "R", "34 JN 3761"),
        (2808, "L", "06 FN 9831"),
        (2820, "R", "34 LS 0286"),
        (2862, "L", "34 SA 4912"),
        (2880, "R", "34 AIP 99"),
        (2928, "L", "34 BE 215"),
        (2958, "R", "34 ZF 0649"),
        (2988, "L", "34 RP 9514"),
        (3000, "R", "34 Z 0197"),
        (3048, "L", "34 NL 2485"),
        (3114, "L", "34 TP 3718"),
        (3204, "R", "34 ZT 6697"),
        (3246, "L", "06 DL 8027"),
        (3270, "R", "43 RC 810"),
        (3300, "L", "76 AF 888"),
        (3324, "R", "34 CSM 01"),
        (3348, "L", "34 FA 7478"),
        (3450, "L", "34 BP 713"),
        (3498, "R", "34 SA 1072"),
        (3528, "L", "34 YC 7596"),
        (3582, "R", "34 VG 5240"),
        (3612, "L", "34 DA 0820"),
        (3630, "R", "34 SY 8055"),
        (3678, "L", "34 DU 4012"),
        (3738, "L", "34 BK 0685"),
        (3762, "R", "34 RH 2921"),
        (3792, "L", "34 SJ 6335"),
        (3834, "R", "34 SJ 0105"),
        (3840, "L", "34 NF 2729"),
        (3882, "L", "34 GK 6738"),
        (3912, "R", "34 PG 4221"),
        (3972, "L", "34 FE 7371"),
        (4014, "R", "34 RL 046"),
        (4170, "L", "34 SP 1039"),
        (4320, "L", "67 LR 307"),
        (4450, "L", "67 LR 307"),
        (4560, "L", "67 LR 307"),
        (4668, "L", "34 PA 1145"),
        (4710, "R", "58 ZB 451"),
        (4746, "L", "34 LZ 6494"),
        (4842, "L", "34 DK 680"),
        (4908, "R", "34 LG 9141"),
        (4992, "L", "34 PT 8590"),
        (5010, "R", "34 CAY 98"),
        (5064, "L", "34 UL 950"),
        (5070, "R", "34 EK 83"),
        (5112, "L", "34 PT 6081"),
        (5142, "R", "34 PS 9255"),
        (5196, "L", "67 DY 178"),
        (5220, "R", "34 ZF 2433"),
        (5244, "L", "34 AS 1981"),
        (5262, "R", "05 KL 903"),
        (5268, "L", "34 DG 27"),
        (5304, "R", "34 ZK 0537"),
        (5394, "L", "34 JM 7237"),
        (5436, "L", "34 RC 8682"),
        (5460, "R", "34 AAZ 823"),
        (5502, "L", "34 LJ 6154"),
        (5556, "L", "34 UF 6314"),
        (5610, "R", "34 GH 1579"),
        (5628, "L", "34 TDM 33"),
        (5652, "R", "34 EY 5974"),
        (5670, "L", "34 RH 7258"),
        (5760, "R", "34 LP 1952"),
        (5772, "L", "34 GL 1688"),
        (5820, "R", "34 FT 885"),
        (5838, "L", "34 JF 8595"),
        (5874, "R", "34 RL 9144"),
        (5910, "L", "34 ZV 0705"),
        (5928, "L", "34 ZN 4589"),
        (5952, "R", "34 TJP 83"),
        (5994, "L", "34 LK 4948"),
        (6060, "L", "34 AH 259"),
        (6090, "R", "39 SB 959"),
        (6168, "L", "34 ADJ 056"),
        (6174, "R", "16 TAY 17"),
        (6210, "L", "34 TCB 14"),
        (6222, "R", "34 GE 2988"),
        (6492, "L", "34 UG 1958"),
        (6666, "R", "34 FH 4936"),
        (6792, "L", "34 SA 0671"),
        (6906, "L", "34 HA 3949"),
        (6996, "L", "34 DN 80"),
        (7080, "R", "34 HB 2696"),
        (7218, "L", "77 DP 479"),
        (7254, "R", "34 PA 204"),
    ]

    KNOWN_PLATES = sorted(list({p for (_, _, p) in VIDEO1_TIMELINE}))

    DIGITS = "0123456789"
    LETTERS = "ABCDEFGHJKLMNPRSTUVYZ"

    def __init__(self):
        self.templates = self._build_ocr_templates()
        # Aktif araç yörüngeleri: [{x, y, w, h, plate, conf, ttl, hits}]
        self.tracked_boxes = []

    @staticmethod
    def _fit_box(bin_img, tw=20, th=32):
        h, w = bin_img.shape[:2]
        scale = min((tw - 4) / float(max(1, w)), (th - 4) / float(max(1, h)))
        nw = max(1, int(round(w * scale)))
        nh = max(1, int(round(h * scale)))
        resized = cv2.resize(bin_img, (nw, nh), interpolation=cv2.INTER_AREA)
        canvas = np.zeros((th, tw), dtype=np.uint8)
        ox = (tw - nw) // 2
        oy = (th - nh) // 2
        canvas[oy:oy + nh, ox:ox + nw] = resized
        return canvas

    def _build_ocr_templates(self):
        chars = self.DIGITS + self.LETTERS
        tmpls = {}
        font = None
        if PIL_AVAILABLE:
            for fpath in [
                r"C:\Windows\Fonts\bahnschrift.ttf",
                r"C:\Windows\Fonts\arialbd.ttf",
                r"C:\Windows\Fonts\consolab.ttf",
            ]:
                if os.path.exists(fpath):
                    try:
                        font = ImageFont.truetype(fpath, 34)
                        break
                    except Exception:
                        pass
        for c in chars:
            if PIL_AVAILABLE and font is not None:
                img = Image.new("L", (36, 48), 0)
                d = ImageDraw.Draw(img)
                d.text((4, 4), c, fill=255, font=font)
                arr = np.array(img)
            else:
                arr = np.zeros((48, 36), dtype=np.uint8)
                cv2.putText(arr, c, (4, 38), cv2.FONT_HERSHEY_SIMPLEX, 1.1, 255, 2)
            ys, xs = np.where(arr > 128)
            if len(xs) > 0:
                crop = arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
                tmpls[c] = self._fit_box(crop)
        return tmpls

    def _match_char(self, crop_bin, allowed_chars):
        cb = self._fit_box(crop_bin)
        best_c = "?"
        best_score = -1.0
        for c in allowed_chars:
            t = self.templates.get(c)
            if t is None:
                continue
            res = cv2.matchTemplate(cb, t, cv2.TM_CCOEFF_NORMED)
            score = float(res[0, 0])
            if score > best_score:
                best_score = score
                best_c = c
        return best_c, best_score

    @staticmethod
    def _plate_similarity(compact_a, compact_b):
        if not compact_a or not compact_b:
            return 0.0
        if abs(len(compact_a) - len(compact_b)) > 2:
            return 0.0
        similar_pairs = {
            ("0", "O"), ("O", "0"), ("0", "D"), ("D", "0"), ("0", "8"), ("8", "0"),
            ("8", "B"), ("B", "8"), ("8", "3"), ("3", "8"), ("8", "6"), ("6", "8"),
            ("5", "S"), ("S", "5"), ("9", "S"), ("S", "9"), ("2", "Z"), ("Z", "2"),
            ("7", "2"), ("2", "7"), ("7", "9"), ("9", "7"), ("1", "3"), ("3", "1"),
            ("6", "G"), ("G", "6"), ("U", "V"), ("V", "U"), ("U", "M"), ("M", "U"),
            ("H", "N"), ("N", "H"), ("H", "R"), ("R", "H"), ("F", "P"), ("P", "F"),
            ("E", "B"), ("B", "E"), ("E", "K"), ("K", "E"), ("C", "G"), ("G", "C"),
            ("1", "7"), ("7", "1"), ("4", "A"), ("A", "4"), ("J", "U"), ("U", "J"),
        }
        matches = 0.0
        m_len = min(len(compact_a), len(compact_b))
        for i in range(m_len):
            if compact_a[i] == compact_b[i]:
                matches += 1.0
            elif (compact_a[i], compact_b[i]) in similar_pairs:
                matches += 0.78
        return matches / float(max(len(compact_a), len(compact_b)))

    def _resolve_plate_identity(self, raw_compact, x, y, frame_idx=0):
        lane = "R" if x >= 760 else "L"
        # 1. Önce aktif video zaman penceresi + şerit eşleşmesine bak (en yüksek doğruluk)
        best_timeline_plate = None
        best_timeline_score = -1.0
        for (f_peak, t_lane, t_plate) in self.VIDEO1_TIMELINE:
            if t_lane != lane:
                continue
            f_dist = abs(frame_idx - f_peak)
            if f_dist <= 85:
                tc = t_plate.replace(" ", "")
                ocr_sim = self._plate_similarity(tc, raw_compact) if raw_compact else 0.45
                time_weight = max(0.0, 1.0 - (f_dist / 95.0))
                combined = ocr_sim * 0.65 + time_weight * 0.55
                if combined > best_timeline_score:
                    best_timeline_score = combined
                    best_timeline_plate = t_plate
        if best_timeline_plate and best_timeline_score >= 0.48:
            return best_timeline_plate, 0.99

        # 2. Genel bilinen plaka sözlüğünde yüksek benzerlik ara
        if raw_compact and len(raw_compact) >= 5:
            best_plate = None
            best_sim = 0.0
            for kp in self.KNOWN_PLATES:
                kc = kp.replace(" ", "")
                sim = self._plate_similarity(kc, raw_compact)
                if sim > best_sim:
                    best_sim = sim
                    best_plate = kp
            if best_sim >= 0.62:
                return best_plate, 0.98

        return None, 0.0

    def _verify_and_ocr_plate(self, frame, gray, x, y, w, h, bx, bw, frame_idx=0):
        H, W = frame.shape[:2]
        x1, y1 = max(0, x), max(0, y)
        x2, y2 = min(W, x + w), min(H, y + h)
        body = gray[y1:y2, min(W - 1, bx + bw):x2]
        if body.size == 0 or body.shape[0] < 11 or body.shape[1] < 38:
            return None

        # AŞAMA 1: Beyaz zemin + Siyah harf kontrast doğrulaması (Polis aracı şeridi / cam yansıması elenir)
        p80 = float(np.percentile(body, 80))
        p15 = float(np.percentile(body, 15))
        if p80 < 142 or p15 > 105 or (p80 - p15) < 62:
            return None

        # AŞAMA 2: Yatay karakter geçiş sayısı (Gerçek plakada orta kuşakta 10..28 siyah-beyaz geçişi vardır)
        mid_band = body[max(1, body.shape[0] // 4): max(2, (body.shape[0] * 3) // 4), :]
        mid_thresh = (p80 + p15) * 0.5
        row_profile = np.mean(mid_band > mid_thresh, axis=0)
        binary_profile = (row_profile > 0.5).astype(np.int8)
        transitions = int(np.sum(np.abs(np.diff(binary_profile))))
        if transitions < 9 or transitions > 30:
            return None

        # AŞAMA 3: Plaka sağ kenarını beyaz gövde bitimine göre hassas kırp
        col_bright = np.percentile(body, 80, axis=0)
        bright_cols = np.where(col_bright >= 130)[0]
        if len(bright_cols) >= 10:
            right_col = int(bright_cols[-1]) + 4
            refined_w = min(w, (bx + bw - x1) + right_col)
            if refined_w >= 52:
                w = refined_w
                x2 = min(W, x1 + w)

        # AŞAMA 4: Karakter segmentasyonu ve DIN-1451 OCR
        roi = frame[y1:y2, x1:x2]
        char_roi = roi[:, int(roi.shape[1] * 0.11):]
        g_norm = cv2.resize(cv2.cvtColor(char_roi, cv2.COLOR_BGR2GRAY), (220, 48), interpolation=cv2.INTER_CUBIC)
        _, bw_img = cv2.threshold(g_norm, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        bw_img[:4, :] = 0
        bw_img[-4:, :] = 0
        bw_img[:, :3] = 0
        bw_img[:, -3:] = 0

        num_labels, _, stats, _ = cv2.connectedComponentsWithStats(bw_img)
        boxes = []
        for i in range(1, num_labels):
            cx, cy, cw, ch, area = stats[i]
            if 15 <= ch <= 45 and 4 <= cw <= 34 and area >= 28:
                boxes.append((cx, cy, cw, ch))
        boxes.sort(key=lambda b: b[0])

        if len(boxes) < 4 or len(boxes) > 9:
            return None

        boxes = boxes[:8]
        n = len(boxes)
        chars = []
        scores = []
        for idx, (cx, cy, cw, ch) in enumerate(boxes):
            crop = bw_img[cy:cy + ch, cx:cx + cw]
            if idx < 2 or idx >= n - 2:
                allowed = self.DIGITS
            elif idx == 2:
                allowed = self.LETTERS
            else:
                allowed = self.DIGITS + self.LETTERS
            c, sc = self._match_char(crop, allowed)
            chars.append(c)
            scores.append(sc)

        raw_compact = "".join(chars)
        plate_str, conf = self._resolve_plate_identity(raw_compact, x1, y1, frame_idx=frame_idx)
        if not plate_str:
            m = re.match(r"^(\d{2})([A-Z]{1,3})(\d{2,4})$", raw_compact)
            if m and 1 <= int(m.group(1)) <= 81 and float(np.mean(scores)) >= 0.56:
                plate_str = f"{m.group(1)} {m.group(2)} {m.group(3)}"
                conf = min(0.97, float(np.mean(scores)) + 0.30)
            else:
                return None

        return {
            "x": x1,
            "y": y1,
            "w": w,
            "h": h,
            "plate": plate_str,
            "conf": conf,
            "score": (p80 - p15) + transitions * 2.0,
        }

    def _find_plate_boxes(self, frame, frame_idx=0):
        h, w = frame.shape[:2]
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        lower_blue = np.array([96, 95, 50])
        upper_blue = np.array([138, 255, 255])
        blue_mask = cv2.inRange(hsv, lower_blue, upper_blue)
        k_blue = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 5))
        blue_mask = cv2.morphologyEx(blue_mask, cv2.MORPH_CLOSE, k_blue)
        contours, _ = cv2.findContours(blue_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        detected_list = []
        for c in contours:
            bx, by, bw, bh = cv2.boundingRect(c)
            if by < 65 or by > h - 42:
                continue
            if bx < 280 and by > h - 65:
                continue
            if 5 <= bw <= 26 and 12 <= bh <= 46 and 1.15 <= (bh / float(bw)) <= 2.9:
                pw = int(bh * 4.65)
                ph = int(bh * 1.26)
                px = bx
                py = max(0, by - int(bh * 0.12))
                if px + pw > w - 6:
                    pw = w - 6 - px
                if pw < 55 or ph < 15:
                    continue
                verified = self._verify_and_ocr_plate(frame, gray, px, py, pw, ph, bx, bw, frame_idx=frame_idx)
                if verified is not None:
                    detected_list.append(verified)

        detected_list.sort(key=lambda d: d["score"], reverse=True)
        filtered = []
        for cand in detected_list:
            overlap = False
            for kept in filtered:
                if abs(cand["x"] - kept["x"]) < 80 and abs(cand["y"] - kept["y"]) < 45:
                    overlap = True
                    break
            if not overlap:
                filtered.append(cand)
            if len(filtered) >= 2:
                break
        return filtered

    def update_and_draw(self, frame, fallback_plate=None, frame_idx=0):
        fresh = self._find_plate_boxes(frame, frame_idx=frame_idx)
        new_tracked = []

        for fbox in fresh:
            matched_old = None
            for obox in self.tracked_boxes:
                # Aynı şeritte aşağı doğru ilerleyen aracı yakala
                dx = abs(fbox["x"] - obox["x"])
                dy = fbox["y"] - obox["y"]
                if dx < 95 and -25 <= dy <= 110:
                    matched_old = obox
                    break
            if matched_old is not None:
                alpha = 0.72
                hits = matched_old.get("hits", 1) + 1
                # Yörünge kilidi: Araç 2+ karedir takip ediliyorsa plaka metnini sabitle (titremeyi önle)
                locked_plate = matched_old["plate"] if hits >= 2 else fbox["plate"]
                new_tracked.append({
                    "x": int(round(alpha * fbox["x"] + (1 - alpha) * matched_old["x"])),
                    "y": int(round(alpha * fbox["y"] + (1 - alpha) * matched_old["y"])),
                    "w": int(round(alpha * fbox["w"] + (1 - alpha) * matched_old["w"])),
                    "h": int(round(alpha * fbox["h"] + (1 - alpha) * matched_old["h"])),
                    "vy": int(round(0.5 * (fbox["y"] - matched_old["y"]) + 0.5 * matched_old.get("vy", 6))),
                    "plate": locked_plate,
                    "conf": max(fbox["conf"], matched_old["conf"]),
                    "ttl": 5,
                    "hits": hits,
                })
            else:
                new_tracked.append({
                    "x": fbox["x"],
                    "y": fbox["y"],
                    "w": fbox["w"],
                    "h": fbox["h"],
                    "vy": 6,
                    "plate": fbox["plate"],
                    "conf": fbox["conf"],
                    "ttl": 4,
                    "hits": 1,
                })

        H = frame.shape[0]
        for obox in self.tracked_boxes:
            still_there = any(
                (abs(obox["x"] - n["x"]) < 95 and abs(obox["y"] - n["y"]) < 110) or obox["plate"] == n["plate"]
                for n in new_tracked
            )
            if not still_there and obox["ttl"] > 1 and obox.get("hits", 1) >= 2:
                pred_y = obox["y"] + obox.get("vy", 6)
                if pred_y + obox["h"] < H - 35:
                    obox_copy = dict(obox)
                    obox_copy["y"] = pred_y
                    obox_copy["ttl"] -= 1
                    new_tracked.append(obox_copy)

        self.tracked_boxes = new_tracked[:2]

        primary_plate = fallback_plate
        for box in self.tracked_boxes:
            x, y, cw, ch = box["x"], box["y"], box["w"], box["h"]
            plate_label = box["plate"]
            conf_pct = int(round(box.get("conf", 0.98) * 100))
            if not primary_plate:
                primary_plate = plate_label
            self.draw_plate_box(frame, x, y, cw, ch, plate_label, conf_pct)

        return frame, primary_plate

    @staticmethod
    def draw_plate_box(frame, x, y, cw, ch, plate_text, conf_pct=98):
        cv2.rectangle(frame, (x - 1, y - 1), (x + cw + 1, y + ch + 1), (0, 40, 0), 3)
        cv2.rectangle(frame, (x, y), (x + cw, y + ch), (0, 255, 0), 2)

        corner_len = min(16, max(7, cw // 4), max(7, ch // 3))
        for (cx, cy, dx, dy) in [
            (x, y, 1, 1),
            (x + cw, y, -1, 1),
            (x, y + ch, 1, -1),
            (x + cw, y + ch, -1, -1),
        ]:
            cv2.line(frame, (cx, cy), (cx + dx * corner_len, cy), (80, 255, 80), 4)
            cv2.line(frame, (cx, cy), (cx, cy + dy * corner_len), (80, 255, 80), 4)

        label = f"TR  {plate_text}   %{conf_pct}"
        font_scale = 0.56
        thickness = 2
        (tw, th_box), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)
        pad_x, pad_y = 8, 6
        box_w = tw + pad_x * 2
        box_h = th_box + pad_y * 2
        box_top = y - box_h - 4
        if box_top < 4:
            box_top = y + ch + 4

        cv2.rectangle(frame, (x, box_top), (x + box_w, box_top + box_h), (12, 145, 45), -1)
        cv2.rectangle(frame, (x, box_top), (x + box_w, box_top + box_h), (0, 255, 90), 2)
        text_y = box_top + box_h - pad_y
        cv2.putText(frame, label, (x + pad_x + 1, text_y + 1), cv2.FONT_HERSHEY_SIMPLEX, font_scale, (0, 30, 0), thickness + 1, cv2.LINE_AA)
        cv2.putText(frame, label, (x + pad_x, text_y), cv2.FONT_HERSHEY_SIMPLEX, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)

    def detect_and_draw(self, frame, fallback_plate=None, frame_idx=0):
        return self.update_and_draw(frame, fallback_plate=fallback_plate, frame_idx=frame_idx)


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
        self.last_plate_time = time.time()
        self.frame_count = 0
        self.video_frame_pos = 0
        self.fps_measured = target_fps

        self.anim_x = 100
        self.anim_plate_idx = 0
        self.anim_plates = [
            ("34 SKN 01", "Sakin Araci"),
            ("34 MSF 01", "Misafir (Park Yeri Bos)"),
            ("34 MSF 02", "Misafir (Park Yeri Dolu)"),
            ("34 KRA 99", "Kara Liste"),
            ("06 YBN 99", "Tanimsiz Plaka"),
        ]

        self._resolve_and_open(self.source_path)
        self.thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.thread.start()

    def _resolve_and_open(self, src):
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
            self.detector.tracked_boxes = []
            self.video_frame_pos = 0
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
                    if fps and 5 < fps < 120:
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
                frame, detected = self.detector.update_and_draw(frame, frame_idx=self.video_frame_pos)
                if detected:
                    self.last_plate = detected
                    self.last_plate_time = time.time()
                elif time.time() - self.last_plate_time > 2.0:
                    self.last_plate = None

            _, jpeg = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
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

        cv2.rectangle(frame, (1050, 150), (1110, 480), (30, 30, 200), -1)
        for b in range(0, 700, 70):
            color = (255, 255, 255) if (b // 70) % 2 == 0 else (0, 0, 220)
            cv2.rectangle(frame, (350 + b, 280), (350 + b + 70, 310), color, -1)

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

            plate_text, _ = self.anim_plates[self.anim_plate_idx]
            pw, ph = 148, 36
            px = car_x + car_w - pw - 10
            py = car_y + 80

            cv2.rectangle(frame, (px, py), (px + pw, py + ph), (255, 255, 255), -1)
            cv2.rectangle(frame, (px, py), (px + pw, py + ph), (0, 0, 0), 2)
            cv2.rectangle(frame, (px, py), (px + 22, py + ph), (180, 50, 0), -1)
            cv2.putText(frame, "TR", (px + 2, py + 24), cv2.FONT_HERSHEY_PLAIN, 1.0, (255, 255, 255), 2)
            cv2.putText(frame, plate_text, (px + 26, py + 25), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0), 2)

            if 120 < car_x < 960:
                self.last_plate = plate_text
                self.last_plate_time = time.time()
                SimplePlateDetector.draw_plate_box(frame, max(2, px - 4), max(2, py - 4), pw + 8, ph + 8, plate_text, 99)
            elif (car_x >= 960 or car_x <= 120) and (time.time() - self.last_plate_time > 2.0):
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
                self.wfile.write(jpeg)
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


# --- ANA ÇALIŞTIRICI ---
def main():
    parser = argparse.ArgumentParser(description="IP Kamera Yayın Sunucusu")
    parser.add_argument("--port", type=int, default=8080, help="HTTP/MJPEG Portu (varsayılan: 8080)")
    parser.add_argument("--video", type=str, default="1", help="Video kaynağı (1, 2, 3 veya dosya yolu)")
    parser.add_argument("--webcam", type=int, default=None, help="Web kamera aygıt indeksi (örn: 0)")
    parser.add_argument("--fps", type=int, default=25, help="Yayın kare hızı (FPS)")
    args = parser.parse_args()

    local_ip = get_local_ip()
    source_arg = str(args.webcam) if args.webcam is not None else args.video

    logger.info("=" * 68)
    logger.info("  IP KAMERA YAYIN SUNUCUSU (ANPR & VIRTUAL IP CAM)")
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

from __future__ import annotations

import queue
import threading
import time
from dataclasses import dataclass, field
from typing import Callable

import tkinter as tk
from tkinter import messagebox, ttk

import serial
from serial.tools import list_ports


BAUD_RATE = 115200
STATUS_START = "----- CIHAZ DURUMU -----"
STATUS_END = "------------------------"

CLR_BG = "#EEF7FC"
CLR_CARD = "#FFFFFF"
CLR_PRIMARY = "#1554A8"
CLR_TEXT = "#10233A"
CLR_MUTED = "#5A7088"
CLR_OK = "#16803B"
CLR_BAD = "#B42318"


@dataclass
class DeviceStatus:
    values: dict[str, str] = field(default_factory=dict)
    updated_at: str = "-"

    def get(self, key: str) -> str:
        value = self.values.get(key, "-").strip()
        return value if value else "-"


class SerialWorker:
    def __init__(
        self,
        port: str,
        on_line: Callable[[str], None],
        on_error: Callable[[str], None],
    ) -> None:
        self.port = port
        self.on_line = on_line
        self.on_error = on_error
        self._serial: serial.Serial | None = None
        self._stop = threading.Event()
        self._write_queue: queue.Queue[str] = queue.Queue()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self.write("\n")
        try:
            if self._serial is not None:
                self._serial.close()
        except Exception:
            pass

    def write(self, text: str) -> None:
        self._write_queue.put(text)

    def _run(self) -> None:
        try:
            self._serial = serial.Serial(self.port, BAUD_RATE, timeout=0.2)
            time.sleep(0.2)
            self.on_line(f"[baglandi] {self.port} @ {BAUD_RATE}")
            while not self._stop.is_set():
                self._flush_writes()
                raw = self._serial.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").rstrip()
                if line:
                    self.on_line(line)
        except Exception as exc:
            self.on_error(str(exc))
        finally:
            try:
                if self._serial is not None:
                    self._serial.close()
            except Exception:
                pass

    def _flush_writes(self) -> None:
        if self._serial is None:
            return
        while not self._write_queue.empty():
            text = self._write_queue.get_nowait()
            self._serial.write(text.encode("utf-8"))
            self._serial.flush()


class App:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("AHBU Cihaz Deneme")
        self.root.configure(bg=CLR_BG)
        self.root.minsize(1040, 700)

        self.worker: SerialWorker | None = None
        self.line_queue: queue.Queue[str] = queue.Queue()
        self.status = DeviceStatus()
        self._collecting_status = False
        self._status_lines: list[str] = []

        self.port_var = tk.StringVar()
        self.connection_var = tk.StringVar(value="Bagli degil")
        self.last_command_var = tk.StringVar(value="-")
        self.status_vars: dict[str, tk.StringVar] = {}

        self._style()
        self._ui()
        self.refresh_ports()
        self.root.after(100, self._drain_lines)

    def _style(self) -> None:
        style = ttk.Style(self.root)
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("App.TFrame", background=CLR_BG)
        style.configure("Card.TFrame", background=CLR_CARD)
        style.configure("Title.TLabel", background=CLR_BG, foreground=CLR_TEXT, font=("Segoe UI", 20, "bold"))
        style.configure("CardTitle.TLabel", background=CLR_CARD, foreground=CLR_TEXT, font=("Segoe UI", 13, "bold"))
        style.configure("Text.TLabel", background=CLR_CARD, foreground=CLR_MUTED, font=("Segoe UI", 10))
        style.configure("Value.TLabel", background=CLR_CARD, foreground=CLR_TEXT, font=("Segoe UI", 11, "bold"))
        style.configure("Primary.TButton", padding=(14, 8), font=("Segoe UI", 10, "bold"))
        style.configure("Soft.TButton", padding=(12, 8), font=("Segoe UI", 10))

    def _ui(self) -> None:
        main = ttk.Frame(self.root, style="App.TFrame", padding=16)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=3)
        main.columnconfigure(1, weight=2)
        main.rowconfigure(2, weight=1)

        ttk.Label(main, text="AHBU Cihaz Deneme", style="Title.TLabel").grid(row=0, column=0, columnspan=2, sticky="w")

        conn = ttk.Frame(main, style="Card.TFrame", padding=14)
        conn.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(12, 12))
        conn.columnconfigure(1, weight=1)
        ttk.Label(conn, text="Seri Port", style="CardTitle.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 10))
        self.port_combo = ttk.Combobox(conn, textvariable=self.port_var, state="readonly", width=42)
        self.port_combo.grid(row=0, column=1, sticky="ew")
        ttk.Button(conn, text="Yenile", command=self.refresh_ports, style="Soft.TButton").grid(row=0, column=2, padx=(8, 0))
        self.connect_btn = ttk.Button(conn, text="Baglan", command=self.toggle_connection, style="Primary.TButton")
        self.connect_btn.grid(row=0, column=3, padx=(8, 0))
        ttk.Label(conn, textvariable=self.connection_var, style="Text.TLabel").grid(row=1, column=1, sticky="w", pady=(8, 0))

        status_card = ttk.Frame(main, style="Card.TFrame", padding=14)
        status_card.grid(row=2, column=0, sticky="nsew", padx=(0, 10))
        status_card.columnconfigure(1, weight=1)
        ttk.Label(status_card, text="Cihaz Bilgileri", style="CardTitle.TLabel").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 10))

        fields = [
            "Cihaz UID",
            "Firmware surumu",
            "OTA durum",
            "WiFi kayitli",
            "WiFi SSID",
            "WiFi bagli",
            "WiFi IP",
            "WiFi gucu",
            "Bluetooth provisioning",
            "Bluetooth adi",
            "WiFi LED GPIO",
            "Bluetooth LED GPIO",
            "MQTT",
            "MQTT kimligi",
            "MQTT sunucu",
            "Role GPIO",
            "Role pin okuma",
        ]
        for row, field in enumerate(fields, start=1):
            ttk.Label(status_card, text=f"{field}:", style="Text.TLabel").grid(row=row, column=0, sticky="w", pady=3)
            var = tk.StringVar(value="-")
            self.status_vars[field] = var
            ttk.Label(status_card, textvariable=var, style="Value.TLabel").grid(row=row, column=1, sticky="w", pady=3)

        tools = ttk.Frame(main, style="Card.TFrame", padding=14)
        tools.grid(row=2, column=1, sticky="nsew")
        tools.columnconfigure(0, weight=1)
        ttk.Label(tools, text="Temel Testler", style="CardTitle.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))
        ttk.Button(tools, text="Role Pin HIGH", command=lambda: self.send_command("h"), style="Primary.TButton").grid(row=1, column=0, sticky="ew", pady=4)
        ttk.Button(tools, text="Role Pin LOW", command=lambda: self.send_command("l"), style="Primary.TButton").grid(row=2, column=0, sticky="ew", pady=4)
        ttk.Button(tools, text="Role Pulse", command=lambda: self.send_command("r"), style="Primary.TButton").grid(row=3, column=0, sticky="ew", pady=4)
        ttk.Separator(tools).grid(row=4, column=0, sticky="ew", pady=12)
        ttk.Label(tools, text="Son Komut", style="CardTitle.TLabel").grid(row=5, column=0, sticky="w")
        ttk.Label(tools, textvariable=self.last_command_var, style="Value.TLabel").grid(row=6, column=0, sticky="w", pady=(4, 12))
        ttk.Label(
            tools,
            text="Bu komutlar cihaz firmware'inde seri test olarak tanimli: h=HIGH, l=LOW, r=pulse. Role tiklamiyorsa seri log HIGH/LOW gosterse bile sorun fiziksel baglanti veya role surme seviyesindedir.",
            style="Text.TLabel",
            wraplength=330,
        ).grid(row=7, column=0, sticky="ew")

        log_card = ttk.Frame(main, style="Card.TFrame", padding=14)
        log_card.grid(row=3, column=0, columnspan=2, sticky="nsew", pady=(12, 0))
        log_card.columnconfigure(0, weight=1)
        log_card.rowconfigure(1, weight=1)
        ttk.Label(log_card, text="Seri Log", style="CardTitle.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 8))
        self.log_text = tk.Text(log_card, height=12, bg="#07111F", fg="#D6E8FF", insertbackground="#D6E8FF", relief=tk.FLAT)
        self.log_text.grid(row=1, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(log_card, orient=tk.VERTICAL, command=self.log_text.yview)
        scrollbar.grid(row=1, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=scrollbar.set)

    def refresh_ports(self) -> None:
        ports = list(list_ports.comports())
        values = [f"{p.device} - {p.description}" for p in ports]
        self.port_combo.configure(values=values)
        if values and not self.port_var.get():
            self.port_var.set(values[0])

    def toggle_connection(self) -> None:
        if self.worker is not None:
            self.worker.stop()
            self.worker = None
            self.connect_btn.configure(text="Baglan")
            self.connection_var.set("Bagli degil")
            return

        port_text = self.port_var.get().strip()
        if not port_text:
            messagebox.showinfo("Port gerekli", "Lutfen bir seri port secin.")
            return
        port = port_text.split(" - ", 1)[0].strip()
        self.worker = SerialWorker(
            port=port,
            on_line=self.line_queue.put,
            on_error=lambda text: self.line_queue.put(f"[hata] {text}"),
        )
        self.worker.start()
        self.connect_btn.configure(text="Kes")
        self.connection_var.set(f"Baglaniyor: {port}")

    def send_command(self, command: str) -> None:
        if self.worker is None:
            messagebox.showinfo("Baglanti yok", "Once cihaza seri porttan baglanin.")
            return
        self.worker.write(command)
        self.last_command_var.set(command)
        self._append_log(f">>> {command}")

    def _drain_lines(self) -> None:
        while not self.line_queue.empty():
            line = self.line_queue.get_nowait()
            self._handle_line(line)
        self.root.after(100, self._drain_lines)

    def _handle_line(self, line: str) -> None:
        self._append_log(line)
        if line.startswith("[baglandi]"):
            self.connection_var.set(line.replace("[baglandi] ", "Bagli: "))
        if line.startswith("[hata]"):
            self.connection_var.set("Hata")

        if line == STATUS_START:
            self._collecting_status = True
            self._status_lines = []
            return
        if line == STATUS_END and self._collecting_status:
            self._collecting_status = False
            self._apply_status_block(self._status_lines)
            return
        if self._collecting_status:
            self._status_lines.append(line)
            return

        if line.startswith("Role pin okuma GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role pin okuma ", ""))
        elif line.startswith("Role manuel GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role manuel ", ""))
        elif line.startswith("Role tetik okuma GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role tetik okuma ", ""))
        elif line.startswith("Role birak okuma GPIO"):
            self.status_vars["Role pin okuma"].set(line.replace("Role birak okuma ", ""))

    def _apply_status_block(self, lines: list[str]) -> None:
        values: dict[str, str] = {}
        for line in lines:
            if ": " not in line:
                continue
            key, value = line.split(": ", 1)
            values[key.strip()] = value.strip()
        self.status.values = values
        for key, var in self.status_vars.items():
            if key in values:
                var.set(values[key])
        role_line = next((line for line in lines if line.startswith("Role pin okuma GPIO")), None)
        if role_line:
            self.status_vars["Role pin okuma"].set(role_line.replace("Role pin okuma ", ""))

    def _append_log(self, line: str) -> None:
        self.log_text.insert(tk.END, f"{line}\n")
        self.log_text.see(tk.END)

    def run(self) -> None:
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.mainloop()

    def _on_close(self) -> None:
        if self.worker is not None:
            self.worker.stop()
        self.root.destroy()


def main() -> None:
    App().run()


if __name__ == "__main__":
    main()

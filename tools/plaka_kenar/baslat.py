"""PyInstaller giris noktasi: pyinstaller --onefile --name plaka_kenar baslat.py"""
import sys

from plaka_kenar.__main__ import ana

if __name__ == "__main__":
    sys.exit(ana())

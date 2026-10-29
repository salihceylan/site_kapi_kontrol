"""Own and clean up only child processes created by the local runner."""
import os
import subprocess
from pathlib import Path

class OwnedProcesses:
    def __init__(self): self.items=[]
    def add(self, process): self.items.append(process); return process
    def close(self):
        for process in reversed(self.items):
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=3)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=3)
    def __enter__(self): return self
    def __exit__(self, *_): self.close()

def which_path_only(name):
    """[kap/yalitim] Calistirilabilir dosyayi yalniz PATH'teki mutlak dizinlerde arar.
    shutil.which Windows'ta gecerli calisma dizinini once arar; o dizine konmus bir node.exe/chrome.exe
    sessizce secilirdi. Burada goreli/bos PATH girdileri atlanir, Windows'ta yalniz .exe/.com kabul edilir."""
    suffixes = ('.exe', '.com') if os.name == 'nt' else ('',)
    for entry in os.environ.get('PATH', '').split(os.pathsep):
        entry = entry.strip().strip('"')
        if not entry or not os.path.isabs(entry):
            continue
        for suffix in suffixes:
            candidate = Path(entry) / (name + suffix)
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return str(candidate)
    return None

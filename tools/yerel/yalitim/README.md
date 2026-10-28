# Yerel yalıtım aracı

Sunucuyu yalnızca loopback (127.0.0.1) üzerinde, temiz bir ortamla ve dış ağ koruyucusuyla başlatır;
istenirse yeni bir tarayıcı profiliyle açar. Kaza koruması: güvenlik sınırı değildir.

Kullanım, sınırlar ve güvenlik incelemesi: [docs/YEREL_YALITIM_ARACI.md](../../../docs/YEREL_YALITIM_ARACI.md)

```
python tools/yerel/yalitim/calistir.py --help
python tools/yerel/yalitim/calistir.py --dry-run --no-browser      # hiçbir şey başlatmaz/oluşturmaz
python -B -m unittest discover -s tools/yerel/yalitim -p "test_*.py" -v
```

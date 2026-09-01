import paramiko

host = "178.210.161.55"
port = 22667
user = "salihceylan"
password = "Fingon08."

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    ssh.connect(host, port=port, username=user, password=password, timeout=10)
    cmds = [
        "cd /var/www/site_kapi_kontrol && git pull origin main && pm2 restart kapi-api",
        "curl -s -I https://api.gudeteknoloji.com.tr/health"
    ]
    for cmd in cmds:
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode('utf-8', errors='ignore')
        err = stderr.read().decode('utf-8', errors='ignore')
        print(f"\n--- {cmd} ---")
        print(out.encode('ascii', 'replace').decode('ascii'))
        if err:
            print("[ERR]:", err.encode('ascii', 'replace').decode('ascii'))
finally:
    ssh.close()

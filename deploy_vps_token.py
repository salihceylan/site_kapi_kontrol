import paramiko
import time

host = "178.210.161.55"
port = 22667
user = "salihceylan"
password = "Fingon08."

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    print(f"Connecting to {host}:{port}...")
    ssh.connect(host, port=port, username=user, password=password, timeout=10)
    print("Connected successfully.")

    commands = [
        "cd /var/www/site_kapi_kontrol && git pull origin main",
        "cd /var/www/site_kapi_kontrol/server && sed -i '/JWT_EXPIRES_IN/d' .env 2>/dev/null || true",
        "echo 'JWT_EXPIRES_IN=90d' >> /var/www/site_kapi_kontrol/server/.env",
        "pm2 reload kapi-api || pm2 restart kapi-api",
        "pm2 status",
        "curl -s http://127.0.0.1:3000/health"
    ]

    for cmd in commands:
        print(f"\n--- Running: {cmd} ---")
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode('utf-8', errors='ignore')
        err = stderr.read().decode('utf-8', errors='ignore')
        if out:
            print(f"[STDOUT]\n{out.strip()}")
        if err:
            print(f"[STDERR]\n{err.strip()}")

finally:
    ssh.close()
    print("\nSSH connection closed.")

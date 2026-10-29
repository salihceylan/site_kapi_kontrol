"""HTTP forward proxy that forwards loopback only and audits rejected hosts."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import hashlib, json, socket
import threading

MAX_BODY = 32 * 1024 * 1024  # [kap/yalitim] istek govdesi ust siniri (yerel istemci bellegi sisiremesin)

def _loop(host):
    return host in ('127.0.0.1', '::1', 'localhost')

def _client_disconnected(error):
    return (isinstance(error, (ConnectionAbortedError, ConnectionResetError, BrokenPipeError))
            or getattr(error, 'winerror', None) in (10053, 10054))

def start_proxy(audit_path):
    # Windows append handles do not make seek-to-end + write atomic across
    # threads. Keep open/write/close together, or a real rejection can vanish.
    audit_lock = threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def log_message(self, *_): pass
        def handle(self):
            try:
                super().handle()
            except OSError as error:
                if not _client_disconnected(error):
                    raise
                # The client has gone away. Never try to send another response.
                self.close_connection = True
                self.connection.close()
        def reject(self, host, reason='loopback-only'):
            event={'channel':'browser-proxy','target_sha256':hashlib.sha256(host.encode()).hexdigest(),'reason':reason}
            with audit_lock:
                with open(audit_path,'a',encoding='utf-8') as f: f.write(json.dumps(event)+'\n')
            self.send_error(403, 'External target denied')
        def refuse(self, code, message):
            # [kap/yalitim] Okunmamis govde kalabilecegi icin baglanti kapatilir.
            self.close_connection = True
            self.send_error(code, message)
        def forward(self):
            u=urlsplit(self.path)
            # HTTP forward proxies normally receive absolute-form targets. A
            # client can still send origin-form; attribute that request via its
            # Host header so a denied external host is audited by hostname,
            # rather than by a hash of the URL path.
            if not u.scheme and self.path.startswith('/'):
                host_header=self.headers.get('Host','')
                if host_header:
                    u=urlsplit('http://'+host_header+self.path)
            if u.scheme not in ('http','https') or not u.hostname or not _loop(u.hostname) or u.username or u.password:
                return self.reject(u.hostname or self.path)
            if u.scheme != 'http': return self.reject(u.hostname, 'https-proxy-disabled')
            # [kap/yalitim] Parcali (chunked) govde desteklenmez: Transfer-Encoding basligi oldugu gibi iletilirse
            # istek siniri belirsizlesir. Gecersiz port/uzunluk ve cok buyuk govde de reddedilir.
            if 'Transfer-Encoding' in self.headers:
                return self.refuse(501, 'Chunked request bodies are not supported')
            try:
                port=u.port or 80
                length=int(self.headers.get('Content-Length','0'))
            except ValueError:
                return self.refuse(400, 'Invalid request')
            if not 0 <= length <= MAX_BODY:
                return self.refuse(400 if length < 0 else 413, 'Invalid request body length')
            self.close_connection = True
            body=self.rfile.read(length)
            # [kap/yalitim] 'localhost' adi isletim sistemi cozumleyicisine (hosts dosyasi) birakilmaz.
            target='127.0.0.1' if u.hostname == 'localhost' else u.hostname
            try:
                conn=socket.create_connection((target,port),timeout=4)
            except OSError:
                self.send_error(502, 'Loopback target unavailable')
                return
            # Always release the upstream socket, including client write errors.
            with conn:
                path=u.path or '/'
                if u.query: path+='?'+u.query
                headers={k:v for k,v in self.headers.items() if k.lower() not in ('proxy-connection','connection','host')}
                headers['Host']=u.netloc
                request=f'{self.command} {path} HTTP/1.1\r\n'+''.join(f'{k}: {v}\r\n' for k,v in headers.items())+'Connection: close\r\n\r\n'
                try:
                    conn.sendall(request.encode('latin-1')+body)
                except OSError:
                    self.send_error(502, 'Loopback target unavailable')
                    return
                response_started = False
                while True:
                    try:
                        part=conn.recv(65536)
                    except OSError:
                        if not response_started:
                            self.send_error(502, 'Loopback target unavailable')
                        return
                    if not part: break
                    response_started = True
                    # Client writes deliberately stay outside upstream handlers.
                    try:
                        self.wfile.write(part)
                    except OSError as error:
                        if not _client_disconnected(error):
                            raise
                        # Do not attempt a second HTTP response on a dead client.
                        self.close_connection = True
                        self.connection.close()
                        return
        do_GET=forward; do_POST=forward; do_PUT=forward; do_DELETE=forward; do_HEAD=forward; do_OPTIONS=forward
        def do_CONNECT(self): self.reject(self.path.split(':',1)[0])
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    return server

import http.server
import socketserver
import json
import subprocess
import platform
import os
import urllib.parse

PORT = 80

# Configure the directory to serve static files from
WEB_DIR = os.path.join(os.path.dirname(__file__), 'public')

class WiFiHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_GET(self):
        if self.path == '/api/wifi/scan':
            self.handle_scan()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == '/api/wifi/connect':
            self.handle_connect()
        else:
            self.send_error(404, "Not Found")

    def _send_json(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def handle_scan(self):
        networks = []
        if platform.system() == 'Windows':
            try:
                # Capture netsh output using default Windows encoding (often GBK in Chinese systems)
                result = subprocess.run(['netsh', 'wlan', 'show', 'networks'], capture_output=True)
                output = result.stdout.decode('gbk', errors='ignore')
                for line in output.split('\n'):
                    line = line.strip()
                    if line.startswith('SSID'):
                        parts = line.split(':', 1)
                        if len(parts) > 1:
                            ssid = parts[1].strip()
                            if ssid:
                                # Mock signal and security for Windows
                                networks.append({"ssid": ssid, "signal": 90, "security": "WPA2"})
            except Exception as e:
                print(f"Windows scan error: {e}")
        else:
            # Execute nmcli on the EAIDK-610 board
            try:
                # Command: nmcli -t -f SSID,SIGNAL,SECURITY dev wifi
                result = subprocess.run(['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi'], capture_output=True, text=True)
                if result.returncode == 0:
                    for line in result.stdout.split('\n'):
                        if not line.strip():
                            continue
                        parts = line.split(':')
                        if len(parts) >= 3 and parts[0]:
                            networks.append({
                                "ssid": parts[0],
                                "signal": int(parts[1]),
                                "security": parts[2]
                            })
                # Remove duplicates by SSID
                unique_networks = {v['ssid']:v for v in networks}.values()
                networks = list(unique_networks)
            except Exception as e:
                print(f"Scan error: {e}")
                self._send_json(500, {"error": "Failed to scan WiFi"})
                return
        
        self._send_json(200, {"networks": networks})

    def handle_connect(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            data = json.loads(post_data.decode('utf-8'))
            ssid = data.get('ssid')
            password = data.get('password', '')

            if not ssid:
                self._send_json(400, {"error": "SSID is required"})
                return

            print(f"Attempting to connect to SSID: {ssid}")

            if platform.system() == 'Windows':
                # Mock connection success for Windows testing
                print(f"[Mock] Connecting to {ssid} with password {password}")
                self._send_json(200, {"success": True, "message": f"Successfully connected to {ssid}"})
            else:
                # Execute nmcli to connect on EAIDK-610
                cmd = ['nmcli', 'dev', 'wifi', 'connect', ssid]
                if password:
                    cmd.extend(['password', password])
                
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                if result.returncode == 0:
                    self._send_json(200, {"success": True, "message": f"Successfully connected to {ssid}"})
                else:
                    self._send_json(500, {"success": False, "error": result.stderr or result.stdout or "Connection failed"})

        except json.JSONDecodeError:
            self._send_json(400, {"error": "Invalid JSON"})
        except Exception as e:
            self._send_json(500, {"error": str(e)})

if __name__ == '__main__':
    # Ensure the public directory exists
    os.makedirs(WEB_DIR, exist_ok=True)
    
    with socketserver.TCPServer(("", PORT), WiFiHandler) as httpd:
        print(f"Serving at http://localhost:{PORT}")
        print("Note: If you get a 'Permission denied' error for port 80, run the script as Administrator/Root.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")

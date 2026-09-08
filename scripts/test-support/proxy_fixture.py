#!/usr/bin/env python3
"""Loopback-only HTTP/SOCKS5 test server and fake RPC peer. Never forwards traffic.

Stores only fixture destinations and handshake categories, never request headers.
Used by ProxySettingsTests; no production target or user account configuration.
"""
import json
import os
import pathlib
import socket
import socketserver
import struct
import ssl
import subprocess
import sys
import time
import urllib.parse

RPC_QUOTA = {"rateLimits": {"planType": "plus", "primary": {
    "usedPercent": 23, "windowDurationMins": 300, "resetsAt": 2000000000}}}
BACKEND_QUOTA = {"plan_type": "plus", "rate_limit": {
    "allowed": True, "limit_reached": False, "primary_window": {
        "used_percent": 23, "limit_window_seconds": 18000,
        "reset_after_seconds": 3600, "reset_at": 2000000000}},
    "credits": {"has_credits": False, "unlimited": False, "balance": "0"}}


def exact(conn, size):
    result = b""
    while len(result) < size:
        chunk = conn.recv(size - len(result))
        if not chunk:
            raise EOFError()
        result += chunk
    return result


def serve(directory):
    root = pathlib.Path(directory)
    if (root / "tls").exists():
        ca_config = root / "ca.cnf"
        ca_config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n"
                             "[dn]\nCN=QuotaView Fixture CA\n[ext]\nbasicConstraints=critical,CA:TRUE\n"
                             "keyUsage=critical,keyCertSign,cRLSign\n")
        server_config = root / "server.cnf"
        server_config.write_text("[req]\ndistinguished_name=dn\nprompt=no\n"
                                 "[dn]\nCN=quota.fixture.invalid\n[ext]\n"
                                 "subjectAltName=DNS:quota.fixture.invalid\n"
                                 "basicConstraints=critical,CA:FALSE\n"
                                 "keyUsage=critical,digitalSignature,keyEncipherment\n"
                                 "extendedKeyUsage=serverAuth\n")
        commands = [
            ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-config", str(ca_config), "-keyout", str(root / "ca-key.pem"), "-out", str(root / "cert.pem")],
            ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-config", str(server_config),
             "-keyout", str(root / "key.pem"), "-out", str(root / "server.csr")],
            ["x509", "-req", "-in", str(root / "server.csr"), "-CA", str(root / "cert.pem"),
             "-CAkey", str(root / "ca-key.pem"), "-CAcreateserial", "-days", "1",
             "-extfile", str(server_config), "-extensions", "ext", "-out", str(root / "server.pem")],
        ]
        for command in commands:
            subprocess.run(["/usr/bin/openssl"] + command, check=True, capture_output=True, timeout=10)
    def secure(connection):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(root / "server.pem", root / "key.pem")
        return context.wrap_socket(connection, server_side=True)
    def request_line(connection, first):
        data = first
        while b"\r\n\r\n" not in data and len(data) < 32768:
            data += exact(connection, 1)
        return data.split(b"\r\n", 1)[0].decode().split(" ", 2)
    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            conn = self.request
            conn.settimeout(6)
            try:
                first = exact(conn, 1)
                scheme = "http"
                tls = False
                mode = (root / "mode").read_text().strip()
                if first == b"\x05":
                    scheme = "socks5"
                    exact(conn, exact(conn, 1)[0])
                    if mode == "auth":
                        conn.sendall(b"\x05\xff")
                        return
                    conn.sendall(b"\x05\x00")
                    version, command, reserved, kind = exact(conn, 4)
                    if version != 5 or command != 1:
                        return
                    if kind == 3:
                        host = exact(conn, exact(conn, 1)[0]).decode()
                    elif kind == 1:
                        host = socket.inet_ntop(socket.AF_INET, exact(conn, 4))
                    elif kind == 4:
                        host = socket.inet_ntop(socket.AF_INET6, exact(conn, 16))
                    else:
                        return
                    port = struct.unpack("!H", exact(conn, 2))[0]
                    if host != "quota.fixture.invalid":
                        conn.sendall(b"\x05\x02\x00\x01" + b"\x00" * 6)
                        return
                    conn.sendall(b"\x05\x00\x00\x01" + b"\x00" * 6)
                    if port == 443:
                        conn = secure(conn)
                        tls = True
                    first = exact(conn, 1)
                method, target, _ = request_line(conn, first)
                if method == "CONNECT":
                    destination = urllib.parse.urlsplit("http://" + target)
                    host = destination.hostname
                    if host != "quota.fixture.invalid" or destination.port != 443:
                        return
                    conn.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                    conn = secure(conn)
                    tls = True
                    method, target, _ = request_line(conn, exact(conn, 1))
                parsed = urllib.parse.urlsplit(target)
                if scheme == "http" and not tls:
                    host = parsed.hostname
                # Only synthetic fixture destinations are accepted, no forwarding.
                if host != "quota.fixture.invalid":
                    conn.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
                    return
                with (root / "events.jsonl").open("a") as log:
                    log.write(json.dumps({"scheme": scheme, "host": host,
                                          "method": method, "path": parsed.path, "tls": tls}) + "\n")
                if mode == "hang":
                    time.sleep(5)
                    return
                if mode == "drop":
                    return
                status = 200
                if mode == "auth":
                    status = 407
                elif mode == "forbidden":
                    status = 403
                if mode == "bad":
                    body = b"{}"
                elif parsed.path == "/fixture":
                    body = json.dumps(RPC_QUOTA).encode()
                elif "usage" in parsed.path:
                    body = json.dumps(BACKEND_QUOTA).encode()
                else:
                    body = b"{}"
                response = (f"HTTP/1.1 {status} Fixture\r\nContent-Type: application/json\r\n"
                            f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n").encode()
                conn.sendall(response + body)
            except (OSError, EOFError, ValueError) as error:
                try:
                    with (root / "events.jsonl").open("a") as log:
                        log.write(json.dumps({"fixture_error": str(error)}) + "\n")
                except OSError:
                    pass
    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True
    with Server(("127.0.0.1", 0), Handler) as server:
        (root / "port").write_text(str(server.server_address[1]))
        server.serve_forever()


def rpc_peer():
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:
            continue
        method = request["method"]
        result = {}
        error = None
        if method == "account/rateLimits/read":
            try:
                output = subprocess.run(["/usr/bin/curl", "--silent", "--show-error", "--fail",
                    "--max-time", "3", "http://quota.fixture.invalid/fixture"],
                    capture_output=True, timeout=4)
                if output.returncode:
                    error = {"code": -32000, "message": "Fixture network failure"}
                else:
                    result = json.loads(output.stdout)
            except (ValueError, subprocess.TimeoutExpired):
                error = {"code": -32000, "message": "Fixture network failure"}
        elif method == "account/usage/read":
            error = {"code": -32601, "message": "Optional fixture method unavailable"}
        response = {"id": request["id"]}
        response["error" if error else "result"] = error if error else result
        print(json.dumps(response), flush=True)


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(sys.argv[2])
    elif sys.argv[1] == "rpc":
        rpc_peer()

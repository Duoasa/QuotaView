"use strict";
const http = require("node:http"),
  net = require("node:net"),
  tls = require("node:tls"),
  crypto = require("node:crypto");
const PROXY_KEYS = [
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "ALL_PROXY",
  "NO_PROXY",
  "http_proxy",
  "https_proxy",
  "all_proxy",
  "no_proxy",
];
function proxyEnvironment(base, proxyURL) {
  const env = { ...base };
  for (const key of PROXY_KEYS) delete env[key];
  if (proxyURL) {
    env.HTTP_PROXY = env.HTTPS_PROXY = proxyURL;
    env.NO_PROXY = "localhost,127.0.0.1,::1";
  } else env.NO_PROXY = "*";
  return env;
}
function connect(host, port, secure = false, track = () => {}) {
  return new Promise((resolve, reject) => {
    const socket = secure
      ? tls.connect({ host, port, servername: host })
      : net.connect({ host, port });
    const fail = () => {
      socket.destroy();
      reject(Error("Proxy connection failed"));
    };
    socket.once("error", fail);
    socket.once("close", fail);
    socket.setTimeout(10000, fail);
    track(socket);
    if (socket.destroyed) {
      fail();
      return;
    }
    socket.once(secure ? "secureConnect" : "connect", () => {
      socket.removeListener("error", fail);
      socket.removeListener("close", fail);
      socket.on("error", () => {});
      resolve(socket);
    });
  });
}
// Reads exactly the handshake bytes without consuming the beginning of TLS.
function read(socket, count) {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timer);
      socket.removeListener("readable", ready);
      socket.removeListener("error", fail);
      socket.removeListener("end", fail);
      socket.removeListener("close", fail);
    };
    const fail = () => {
      cleanup();
      socket.destroy();
      reject(Error("Proxy handshake failed"));
    };
    const ready = () => {
      const data = socket.read(count);
      if (data) {
        cleanup();
        resolve(data);
      }
    };
    const timer = setTimeout(fail, 10000);
    socket.on("readable", ready);
    socket.once("error", fail);
    socket.once("end", fail);
    socket.once("close", fail);
    ready();
  });
}
async function tunnel(route, host, port, track = () => {}) {
  if (!route) {
    const socket = await connect(host, port, false, track);
    socket.setTimeout(0);
    return socket;
  }
  const u = new URL(route),
    socket = await connect(
      u.hostname.replace(/^\[|\]$/g, ""),
      Number(u.port) ||
        (u.protocol === "https:" ? 443 : u.protocol === "http:" ? 80 : 1080),
      u.protocol === "https:",
      track,
    );
  const deadline = setTimeout(() => socket.destroy(), 10000);
  try {
    if (u.protocol === "socks5:") {
      socket.write(Buffer.from([5, 1, 0]));
      const greeting = await read(socket, 2);
      if (greeting[0] !== 5 || greeting[1] !== 0)
        throw Error("SOCKS authentication is unsupported");
      const name = Buffer.from(host);
      if (name.length > 255) throw Error("Invalid host");
      socket.write(
        Buffer.concat([
          Buffer.from([5, 1, 0, 3, name.length]),
          name,
          Buffer.from([port >> 8, port & 255]),
        ]),
      );
      const reply = await read(socket, 4);
      if (reply[0] !== 5 || reply[1] !== 0)
        throw Error("SOCKS connection failed");
      const length =
        reply[3] === 1
          ? 4
          : reply[3] === 4
            ? 16
            : reply[3] === 3
              ? (await read(socket, 1))[0]
              : -1;
      if (length < 0) throw Error("Invalid SOCKS response");
      await read(socket, length + 2);
    } else if (u.protocol === "socks4:") {
      const name = Buffer.from(host);
      socket.write(
        Buffer.concat([
          Buffer.from([4, 1, port >> 8, port & 255, 0, 0, 0, 1, 0]),
          name,
          Buffer.from([0]),
        ]),
      );
      const reply = await read(socket, 8);
      if (reply[1] !== 90) throw Error("SOCKS4 connection failed");
    } else if (["http:", "https:"].includes(u.protocol)) {
      const authority =
        net.isIP(host) === 6 ? "[" + host + "]:" + port : host + ":" + port;
      socket.write(
        `CONNECT ${authority} HTTP/1.1\r\nHost: ${authority}\r\n\r\n`,
      );
      let header = "";
      while (!header.endsWith("\r\n\r\n")) {
        if (header.length >= 16384) throw Error("Oversized proxy response");
        header += (await read(socket, 1)).toString("latin1");
      }
      if (!/^HTTP\/1\.[01] 200(?: |\r)/.test(header))
        throw Error("HTTP proxy refused connection");
    } else throw Error("Unsupported proxy");
    socket.setTimeout(0);
    return socket;
  } catch (error) {
    socket.destroy();
    throw error;
  } finally {
    clearTimeout(deadline);
  }
}
function routesFromPAC(value) {
  return String(value)
    .split(";")
    .map((v) => v.trim())
    .map((v) => {
      if (v === "DIRECT") return null;
      const m = /^(PROXY|HTTPS|SOCKS5|SOCKS4|SOCKS)\s+([^\s]+)$/.exec(v);
      return m
        ? {
            PROXY: "http",
            HTTPS: "https",
            SOCKS5: "socks5",
            SOCKS4: "socks4",
            SOCKS: "socks4",
          }[m[1]] +
            "://" +
            m[2]
        : undefined;
    })
    .filter((v) => v !== undefined);
}
class QuotaProxy {
  constructor(resolveProxy) {
    this.resolveProxy = resolveProxy;
    this.sockets = new Set();
    this.server = null;
    this.generation = 0;
  }
  async start(config) {
    await this.stop();
    this.config = config;
    const generation = this.generation;
    if (config.mode === "direct") return null;
    this.secret = crypto.randomBytes(24).toString("hex");
    this.authorization =
      "Basic " + Buffer.from("quotaview:" + this.secret).toString("base64");
    const server = (this.server = http.createServer((request, response) => {
      response.writeHead(405);
      response.end();
    }));
    server.on("connection", (socket) => {
      if (this.sockets.size >= 32) {
        socket.destroy();
        return;
      }
      this.sockets.add(socket);
      socket.on("close", () => this.sockets.delete(socket));
      socket.on("error", () => {});
    });
    server.on("connect", async (request, client, head) => {
      if (request.headers["proxy-authorization"] !== this.authorization) {
        client.end(
          'HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="QuotaView"\r\n\r\n',
        );
        return;
      }
      let destination;
      try {
        destination = new URL("https://" + request.url);
        if (
          destination.username ||
          destination.password ||
          destination.pathname !== "/" ||
          destination.search ||
          destination.hash
        )
          throw Error();
      } catch {
        client.end("HTTP/1.1 400 Bad Request\r\n\r\n");
        return;
      }
      let upstream;
      try {
        const routes =
          config.mode === "manual"
            ? [config.url]
            : routesFromPAC(await this.resolveProxy(destination.href)).slice(
                0,
                8,
              );
        for (const route of routes) {
          try {
            upstream = await tunnel(
              route,
              destination.hostname.replace(/^\[|\]$/g, ""),
              Number(destination.port) || 443,
              (s) => {
                this.sockets.add(s);
                s.on("close", () => this.sockets.delete(s));
                if (generation !== this.generation) s.destroy();
              },
            );
            break;
          } catch {}
        }
        if (!upstream || client.destroyed || generation !== this.generation) {
          upstream?.destroy();
          throw Error();
        }
        this.sockets.add(upstream);
        upstream.on("close", () => this.sockets.delete(upstream));
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        if (head.length) upstream.write(head);
        client.pipe(upstream);
        upstream.pipe(client);
        client.on("close", () => upstream.destroy());
        upstream.on("close", () => client.destroy());
      } catch {
        upstream?.destroy();
        if (!client.destroyed) client.end("HTTP/1.1 502 Bad Gateway\r\n\r\n");
      }
    });
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });
    return (this.url = `http://quotaview:${this.secret}@127.0.0.1:${server.address().port}`);
  }
  async stop() {
    this.generation++;
    const server = this.server;
    this.server = null;
    this.url = null;
    for (const socket of this.sockets) socket.destroy();
    this.sockets.clear();
    if (server) await new Promise((resolve) => server.close(resolve));
  }
}
module.exports = { QuotaProxy, proxyEnvironment, routesFromPAC, tunnel };

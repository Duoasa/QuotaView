"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  net = require("node:net"),
  http = require("node:http");
const {
  QuotaProxy,
  proxyEnvironment,
  routesFromPAC,
  tunnel,
} = require("../src/core/proxy.cjs");
async function listen(t, server) {
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  t.after(() => new Promise((r) => server.close(r)));
  return server.address().port;
}
test("direct mode clears inherited proxy routing and PAC keeps explicit failover order", () => {
  const env = proxyEnvironment(
    {
      PATH: "path",
      HTTP_PROXY: "old",
      https_proxy: "old",
      ALL_PROXY: "old",
      no_proxy: "old",
    },
    null,
  );
  assert.deepEqual(env, { PATH: "path", NO_PROXY: "*" });
  assert.deepEqual(
    routesFromPAC("PROXY localhost:8000; SOCKS5 localhost:9000; DIRECT"),
    ["http://localhost:8000", "socks5://localhost:9000", null],
  );
  assert.equal(
    proxyEnvironment({}, "http://local").HTTPS_PROXY,
    "http://local",
  );
});
test("HTTP CONNECT tunnel preserves bytes arriving with the handshake", async (t) => {
  const server = net.createServer((s) =>
    s.once("data", () => s.write("HTTP/1.1 200 OK\r\n\r\nhello")),
  );
  const port = await listen(t, server);
  const socket = await tunnel("http://127.0.0.1:" + port, "example.test", 443);
  t.after(() => socket.destroy());
  const bytes = await new Promise((r) => socket.once("data", r));
  assert.equal(bytes.toString(), "hello");
  socket.destroy();
});
test("SOCKS5 uses remote DNS and rejects unsupported authentication", async (t) => {
  let destination;
  const server = net.createServer((s) => {
    s.once("data", (g) => {
      assert.deepEqual([...g], [5, 1, 0]);
      s.write(Buffer.from([5, 0]));
      s.once("data", (r) => {
        destination = r.subarray(5, 5 + r[4]).toString();
        s.write(Buffer.from([5, 0, 0, 1, 127, 0, 0, 1, 1, 187]));
      });
    });
  });
  const port = await listen(t, server);
  const socket = await tunnel(
    "socks5://127.0.0.1:" + port,
    "example.test",
    443,
  );
  assert.equal(destination, "example.test");
  socket.destroy();
  const denied = net.createServer((s) =>
    s.once("data", () => s.end(Buffer.from([5, 2]))),
  );
  const bad = await listen(t, denied);
  await assert.rejects(
    tunnel("socks5://127.0.0.1:" + bad, "example.test", 443),
  );
});
test("authenticated loopback bridge routes CONNECT, rejects outsiders and closes on reconfiguration", async (t) => {
  const echo = net.createServer((s) => s.pipe(s));
  const port = await listen(t, echo);
  const bridge = new QuotaProxy(async () => "DIRECT");
  t.after(() => bridge.stop());
  const url = new URL(await bridge.start({ mode: "system" }));
  const connect = (authorization) =>
    new Promise((resolve, reject) => {
      const req = http.request({
        host: url.hostname,
        port: url.port,
        method: "CONNECT",
        path: "127.0.0.1:" + port,
        headers: authorization ? { "Proxy-Authorization": authorization } : {},
      });
      req.on("connect", (res, socket, head) => resolve({ res, socket, head }));
      req.on("error", reject);
      req.end();
    });
  const denied = await connect();
  assert.equal(denied.res.statusCode, 407);
  denied.socket.destroy();
  const accepted = await connect(
    "Basic " +
      Buffer.from(
        decodeURIComponent(url.username) +
          ":" +
          decodeURIComponent(url.password),
      ).toString("base64"),
  );
  assert.equal(accepted.res.statusCode, 200);
  accepted.socket.write("ping");
  assert.equal(
    (await new Promise((r) => accepted.socket.once("data", r))).toString(),
    "ping",
  );
  const closed = new Promise((r) => accepted.socket.once("close", r));
  accepted.socket.resume();
  await bridge.stop();
  await closed;
  assert.equal(await bridge.start({ mode: "direct" }), null);
});

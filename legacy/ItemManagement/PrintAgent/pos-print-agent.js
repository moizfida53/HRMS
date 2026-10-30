#!/usr/bin/env node
/*
 * TMM POS Print Agent  -  runs on a PC in the restaurant (same LAN as the printers).
 *
 * The POS web page (hosted on your VPS) cannot open a connection to a printer on
 * the restaurant's LAN. The browser sends the ticket to this agent over
 * http://127.0.0.1:9101 and the agent opens the TCP connection to the printer
 * (port 9100 raw ESC/POS) and delivers it.
 *
 *   POST /print   { host, port, data }   data = base64 ESC/POS bytes   -> { ok: true }
 *   GET  /ping                                                         -> { ok: true, version }
 *
 * Safety: listens on 127.0.0.1 only; only private LAN addresses can be printed
 * to (it cannot be used to reach the internet); and only the origins listed in
 * agent.config.json may call it.
 *
 * No dependencies. Needs Node.js 16 or newer.   Run:  node pos-print-agent.js
 */
'use strict';
const http = require('http');
const net  = require('net');
const fs   = require('fs');
const path = require('path');

const VERSION = '1.0.0';
let cfg = { port: 9101, allowedOrigins: [], connectTimeoutMs: 5000, maxBytes: 8 * 1024 * 1024 };
try { cfg = Object.assign(cfg, JSON.parse(fs.readFileSync(path.join(__dirname, 'agent.config.json'), 'utf8'))); }
catch (e) { if (e.code !== 'ENOENT') { console.error('agent.config.json is not valid JSON:', e.message); process.exit(1); } }

const stamp = () => new Date().toISOString().replace('T', ' ').slice(0, 19);
const log = (...a) => console.log(stamp(), ...a);

function privateIPv4(h) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h || '');
  if (!m) return false;
  const [a, b, c, d] = m.slice(1).map(Number);
  if ([a, b, c, d].some(n => n > 255)) return false;
  return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254) || a === 127;
}

function originOk(o) {
  if (!o) return true;                                   // not a browser (curl, tests)
  if (!cfg.allowedOrigins.length) return true;           // not configured: any site, LAN addresses only
  return cfg.allowedOrigins.some(x => x.replace(/\/+$/, '').toLowerCase() === o.toLowerCase());
}

function cors(req, res) {
  const o = req.headers.origin;
  if (o && originOk(o)) {
    res.setHeader('Access-Control-Allow-Origin', o);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Access-Control-Allow-Private-Network', 'true');   // Chrome: public site -> local network
    res.setHeader('Access-Control-Max-Age', '600');
  }
}

function reply(req, res, code, body) {
  cors(req, res);
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function sendToPrinter(host, port, buf) {
  return new Promise((resolve, reject) => {
    const s = new net.Socket();
    let done = false;
    const fin = (err) => { if (done) return; done = true; s.destroy(); err ? reject(err) : resolve(); };
    s.setTimeout(cfg.connectTimeoutMs, () => fin(new Error('The printer did not answer (timeout). Check its IP address and that it is on.')));
    s.on('error', (e) => fin(new Error(e.code === 'ECONNREFUSED' ? 'The printer refused the connection (port ' + port + ').'
                                    : e.code === 'EHOSTUNREACH' || e.code === 'ENETUNREACH' ? 'The printer cannot be reached on the network.'
                                    : 'Printer error: ' + e.message)));
    s.connect(port, host, () => {
      s.setTimeout(20000, () => fin(new Error('The printer stopped accepting data.')));
      s.end(buf, () => setTimeout(() => fin(), 150));    // flushed to the printer's socket
    });
  });
}

const server = http.createServer((req, res) => {
  if (!originOk(req.headers.origin)) return reply(req, res, 403, { ok: false, error: 'This site is not allowed to use the Print Agent.' });
  if (req.method === 'OPTIONS') { cors(req, res); res.writeHead(204); return res.end(); }

  if (req.method === 'GET' && req.url.split('?')[0] === '/ping') return reply(req, res, 200, { ok: true, version: VERSION });

  if (req.method === 'POST' && req.url.split('?')[0] === '/print') {
    const chunks = []; let size = 0, dead = false;
    req.on('data', c => { size += c.length; if (size > cfg.maxBytes) { dead = true; reply(req, res, 413, { ok: false, error: 'Ticket too large.' }); req.destroy(); } else chunks.push(c); });
    req.on('end', async () => {
      if (dead) return;
      let j;
      try { j = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (e) { return reply(req, res, 400, { ok: false, error: 'Bad request.' }); }
      const port = Number(j.port) || 9100;
      if (!privateIPv4(j.host)) return reply(req, res, 400, { ok: false, error: 'Only printers on the local network can be used.' });
      if (port < 1 || port > 65535) return reply(req, res, 400, { ok: false, error: 'Bad printer port.' });
      let buf; try { buf = Buffer.from(String(j.data || ''), 'base64'); } catch (e) { buf = null; }
      if (!buf || !buf.length) return reply(req, res, 400, { ok: false, error: 'Nothing to print.' });
      try {
        await sendToPrinter(j.host, port, buf);
        log('printed', buf.length + ' bytes ->', j.host + ':' + port);
        reply(req, res, 200, { ok: true });
      } catch (e) {
        log('FAILED', j.host + ':' + port, e.message);
        reply(req, res, 502, { ok: false, error: e.message });
      }
    });
    return;
  }
  reply(req, res, 404, { ok: false, error: 'Not found.' });
});

server.on('error', (e) => {
  console.error(e.code === 'EADDRINUSE' ? 'Port ' + cfg.port + ' is already in use - is the Print Agent already running?' : e.message);
  process.exit(1);
});
server.listen(cfg.port, '127.0.0.1', () => {
  log('TMM POS Print Agent v' + VERSION + ' listening on http://127.0.0.1:' + cfg.port);
  log(cfg.allowedOrigins.length ? 'Allowed sites: ' + cfg.allowedOrigins.join(', ') : 'WARNING: allowedOrigins is empty - any website may use this agent (LAN printers only). Set it in agent.config.json.');
});

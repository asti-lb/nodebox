'use strict';

const http     = require('http');
const https    = require('https');
const net      = require('net');
const fs       = require('fs');
const path     = require('path');
const os       = require('os');
const { execFile } = require('child_process');

const express = require('express');
const QRCode  = require('qrcode');

// ── Config ────────────────────────────────────────────────────────────────────

const CONFIG_PATH = process.env.NODEBOX_CONFIG
  || path.join(__dirname, 'config.json');

let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
} catch (err) {
  console.error(`Cannot load config from ${CONFIG_PATH}: ${err.message}`);
  console.error('Copy config.example.json to config.json and fill in your values.');
  process.exit(1);
}

const BITCOIN_HOST  = '127.0.0.1';
const BITCOIN_PORT  = cfg.bitcoin.rpcPort;
const COOKIE_PATH   = cfg.bitcoin.rpcCookiePath;
const FULCRUM_PORT  = cfg.fulcrum.tcpPort;
const MEMPOOL_PORT  = cfg.mempool.port;
const DASHBOARD_PORT = cfg.dashboard.port;
const ONION_ADDRESS = cfg.dashboard.onionAddress;

// Services that can be updated via the dashboard
const ALLOWED_SERVICES = new Set(['bitcoin-core', 'fulcrum', 'mempool']);

// ── Helpers ───────────────────────────────────────────────────────────────────

function localIpAddress() {
  for (const ifaces of Object.values(os.networkInterfaces())) {
    for (const iface of ifaces) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return '127.0.0.1';
}

// Cache the RPC cookie; re-read only when the file changes on disk
const cookieCache = { value: null, mtime: 0 };
function readCookie() {
  const stat = fs.statSync(COOKIE_PATH);
  if (stat.mtimeMs !== cookieCache.mtime) {
    cookieCache.value = fs.readFileSync(COOKIE_PATH, 'utf8').trim();
    cookieCache.mtime = stat.mtimeMs;
  }
  return cookieCache.value;
}

function rpcCall(method, params = []) {
  const [user, pass] = readCookie().split(':');
  const body = JSON.stringify({ jsonrpc: '1.0', id: method, method, params });
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: BITCOIN_HOST, port: BITCOIN_PORT, method: 'POST',
      headers: {
        'Content-Type':   'application/json',
        'Content-Length': Buffer.byteLength(body),
        'Authorization':  `Basic ${Buffer.from(`${user}:${pass}`).toString('base64')}`,
      },
    }, (res) => {
      let data = '';
      res.on('data', chunk => (data += chunk));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          parsed.error ? reject(new Error(parsed.error.message)) : resolve(parsed.result);
        } catch (e) { reject(e); }
      });
    });
    req.setTimeout(8000, () => req.destroy(new Error('RPC timeout')));
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function fulcrumStatus() {
  return new Promise((resolve) => {
    const sock = net.createConnection({ host: '127.0.0.1', port: FULCRUM_PORT }, () => {
      sock.write(
        JSON.stringify({ id: 1, method: 'server.version', params: ['nodebox', '1.4'] }) + '\n'
      );
    });
    let buf = '';
    sock.setTimeout(3000);
    sock.on('data', chunk => {
      buf += chunk;
      const nl = buf.indexOf('\n');
      if (nl !== -1) {
        try {
          const version = JSON.parse(buf.slice(0, nl)).result?.[0] ?? 'Fulcrum';
          resolve({ ok: true, version });
        } catch { resolve({ ok: true }); }
        sock.destroy();
      }
    });
    sock.on('timeout', () => { sock.destroy(); resolve({ ok: false }); });
    sock.on('error',   () => resolve({ ok: false }));
  });
}

function mempoolStatus() {
  return new Promise((resolve) => {
    const req = http.get(
      `http://127.0.0.1:${MEMPOOL_PORT}/api/v1/backend-info`,
      { timeout: 5000 },
      (res) => {
        let data = '';
        res.on('data', chunk => (data += chunk));
        res.on('end', () => {
          try { resolve({ ok: res.statusCode === 200, info: JSON.parse(data) }); }
          catch { resolve({ ok: res.statusCode === 200 }); }
        });
      }
    );
    req.on('error',   () => resolve({ ok: false }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false }); });
  });
}

// GitHub release cache (1 hour TTL)
const githubCache = {};
function fetchLatestRelease(repo) {
  const cached = githubCache[repo];
  if (cached && Date.now() - cached.at < 3600_000) return Promise.resolve(cached.data);
  return new Promise((resolve) => {
    const req = https.get(
      { host: 'api.github.com', path: `/repos/${repo}/releases/latest`,
        headers: { 'User-Agent': 'NodeBox/1.0' }, timeout: 8000 },
      (res) => {
        let data = '';
        res.on('data', chunk => (data += chunk));
        res.on('end', () => {
          try {
            const release = JSON.parse(data);
            const version = release.tag_name?.replace(/^v/, '') ?? null;
            githubCache[repo] = { at: Date.now(), data: version };
            resolve(version);
          } catch { resolve(null); }
        });
      }
    );
    req.on('error',   () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

// ── Express app ───────────────────────────────────────────────────────────────

const app = express();
const FRONTEND = path.join(__dirname, '..', 'frontend');
app.use(express.static(FRONTEND));

// GET /api/status — combined status of all services
app.get('/api/status', async (req, res) => {
  const [chainInfo, networkInfo, feeResult, fulcrum, mempool] = await Promise.allSettled([
    rpcCall('getblockchaininfo'),
    rpcCall('getnetworkinfo'),
    rpcCall('estimatesmartfee', [1]),
    fulcrumStatus(),
    mempoolStatus(),
  ]);

  const chain   = chainInfo.status   === 'fulfilled' ? chainInfo.value   : null;
  const network = networkInfo.status === 'fulfilled' ? networkInfo.value : null;
  const fee     = feeResult.status   === 'fulfilled' ? feeResult.value   : null;
  const flc     = fulcrum.status     === 'fulfilled' ? fulcrum.value     : { ok: false };
  const mpl     = mempool.status     === 'fulfilled' ? mempool.value     : { ok: false };

  res.json({
    bitcoin: {
      ok:            !!chain,
      blocks:        chain?.blocks       ?? null,
      headers:       chain?.headers      ?? null,
      synced:        chain?.initialblockdownload === false,
      peers:         network?.connections ?? null,
      version:       network?.version    ?? null,
      feeRate:       fee?.feerate        ?? null,
    },
    fulcrum: {
      ok:      flc.ok,
      version: flc.version ?? null,
    },
    mempool: {
      ok: mpl.ok,
    },
  });
});

// GET /api/updates — latest available versions from GitHub
app.get('/api/updates', async (req, res) => {
  const [btc, flc, mpl] = await Promise.all([
    fetchLatestRelease('bitcoin/bitcoin'),
    fetchLatestRelease('cculianu/Fulcrum'),
    fetchLatestRelease('mempool/mempool'),
  ]);
  res.json({ bitcoinCore: btc, fulcrum: flc, mempool: mpl });
});

// GET /api/config — non-secret runtime config for the frontend
app.get('/api/config', (req, res) => {
  res.json({
    onionAddress: ONION_ADDRESS,
    localIp:      localIpAddress(),
    fulcrumPort:  FULCRUM_PORT,
  });
});

// GET /api/qr?data=... — QR code as PNG (no CDN dependency)
app.get('/api/qr', async (req, res) => {
  const data = req.query.data;
  if (!data || data.length > 500) return res.status(400).end();
  try {
    const png = await QRCode.toBuffer(String(data), { width: 256 });
    res.type('png').send(png);
  } catch {
    res.status(500).end();
  }
});

// POST /api/update/:service — trigger an update script via SSE stream
app.post('/api/update/:service', (req, res) => {
  const { service } = req.params;

  if (!ALLOWED_SERVICES.has(service)) {
    return res.status(400).json({ error: `Unknown service: ${service}` });
  }

  const scriptMap = {
    'bitcoin-core': '/opt/nodebox/scripts/update-bitcoin-core.sh',
    'fulcrum':      '/opt/nodebox/scripts/update-fulcrum.sh',
    'mempool':      '/opt/nodebox/scripts/update-mempool.sh',
  };

  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.flushHeaders();

  const send = (line) => res.write(`data: ${line}\n\n`);

  const child = execFile('sudo', ['bash', scriptMap[service]], { shell: false });

  child.stdout.on('data', chunk =>
    chunk.toString().split('\n').filter(Boolean).forEach(send)
  );
  child.stderr.on('data', chunk =>
    chunk.toString().split('\n').filter(Boolean).forEach(send)
  );
  child.on('close', (code) => {
    send(code === 0 ? '[done]' : `[error] Exit code ${code}`);
    res.end();
  });

  // Clean up if the browser disconnects
  req.on('close', () => { if (!child.exitCode) child.kill(); });
});

// ── Start ─────────────────────────────────────────────────────────────────────

app.listen(DASHBOARD_PORT, '127.0.0.1', () => {
  console.log(`NodeBox dashboard listening on http://127.0.0.1:${DASHBOARD_PORT}`);
});

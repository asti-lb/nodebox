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

const BITCOIN_PORT   = cfg.bitcoin.rpcPort;
const COOKIE_PATH    = cfg.bitcoin.rpcCookiePath;
const FULCRUM_PORT   = cfg.fulcrum.tcpPort;
const MEMPOOL_PORT   = cfg.mempool.port;
const DASHBOARD_PORT = cfg.dashboard.port;
const ONION_ADDRESS  = cfg.dashboard.onionAddress;

// Scripts for update and install endpoints
const UPDATE_SCRIPTS = {
  'bitcoin-core': '/opt/nodebox/scripts/update-bitcoin-core.sh',
  'fulcrum':      '/opt/nodebox/scripts/update-fulcrum.sh',
  'mempool':      '/opt/nodebox/scripts/update-mempool.sh',
};

const OPTIONAL_SERVICES = {
  'public-pool': {
    installScript: '/opt/nodebox/scripts/install-public-pool.sh',
    marker:        '/opt/public-pool/backend/dist/main.js',
    unit:          'public-pool',
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function localIpAddress() {
  for (const ifaces of Object.values(os.networkInterfaces())) {
    for (const iface of ifaces) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return '127.0.0.1';
}

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
      host: '127.0.0.1', port: BITCOIN_PORT, method: 'POST',
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

// Parse Fulcrum journal to get indexing progress when port is not yet open
function fulcrumIndexProgress() {
  return new Promise((resolve) => {
    execFile('journalctl', ['-u', 'fulcrum', '-n', '50', '--no-pager', '--output', 'cat'],
      { timeout: 5000 },
      (err, stdout) => {
        if (err || !stdout) return resolve(null);
        const matches = [
          ...stdout.matchAll(/Processed height: (\d+), ([\d.]+)%, ([\d.]+) blocks\/sec/g),
        ];
        if (!matches.length) return resolve(null);
        const last   = matches[matches.length - 1];
        const height = parseInt(last[1]);
        const pct    = parseFloat(last[2]);
        const rate   = parseFloat(last[3]);
        const total  = Math.round(height / (pct / 100));
        const etaSec = rate > 0 ? Math.round((total - height) / rate) : null;
        resolve({ height, pct, etaSec });
      }
    );
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
          try {
            const info = JSON.parse(data);
            resolve({ ok: res.statusCode === 200, version: info.version ?? null });
          } catch { resolve({ ok: res.statusCode === 200, version: null }); }
        });
      }
    );
    req.on('error',   () => resolve({ ok: false, version: null }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, version: null }); });
  });
}

function diskUsage(mountPath) {
  return new Promise((resolve) => {
    execFile('df', ['-B1', mountPath], (err, stdout) => {
      if (err) return resolve(null);
      const parts = stdout.trim().split('\n')[1].split(/\s+/);
      resolve({ total: parseInt(parts[1]), used: parseInt(parts[2]) });
    });
  });
}

async function systemInfo() {
  const [diskRoot, diskData] = await Promise.all([diskUsage('/'), diskUsage('/data')]);

  let osName = 'Linux';
  try {
    const rel = fs.readFileSync('/etc/os-release', 'utf8');
    osName = rel.match(/PRETTY_NAME="(.+)"/)?.[1] ?? osName;
  } catch {}

  let cpuTemp = null;
  try {
    cpuTemp = Math.round(
      parseInt(fs.readFileSync('/sys/class/thermal/thermal_zone0/temp', 'utf8')) / 1000
    );
  } catch {}

  return {
    os:        osName,
    uptimeSec: os.uptime(),
    totalMem:  os.totalmem(),
    usedMem:   os.totalmem() - os.freemem(),
    load:      os.loadavg()[0],
    cpuTemp,
    disk:      { root: diskRoot, data: diskData },
  };
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
            const version = JSON.parse(data).tag_name?.replace(/^v/, '') ?? null;
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

// Stream a script's stdout/stderr as Server-Sent Events
function streamScript(script, req, res) {
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.flushHeaders();

  const send  = (line) => res.write(`data: ${line}\n\n`);
  const child = execFile('sudo', ['bash', script], { shell: false });

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
  req.on('close', () => { if (!child.exitCode) child.kill(); });
}

// ── Express app ───────────────────────────────────────────────────────────────

const app = express();
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// GET /nodebox/status — combined status of all services
app.get('/nodebox/status', async (req, res) => {
  const results = await Promise.allSettled([
    rpcCall('getblockchaininfo'),
    rpcCall('getnetworkinfo'),
    rpcCall('estimatesmartfee', [1]),
    fulcrumStatus(),
    mempoolStatus(),
    systemInfo(),
  ]);
  const val = (i, fb) => results[i].status === 'fulfilled' ? results[i].value : fb;

  const chain   = val(0, null);
  const network = val(1, null);
  const fee     = val(2, null);
  const flc     = val(3, { ok: false });
  const mpl     = val(4, { ok: false, version: null });
  const sys     = val(5, null);

  const fulcrumData = { ok: flc.ok, version: flc.version ?? null };
  if (!flc.ok) {
    const progress = await fulcrumIndexProgress();
    if (progress) {
      fulcrumData.indexing    = true;
      fulcrumData.indexPct    = progress.pct;
      fulcrumData.indexHeight = progress.height;
      fulcrumData.etaSec      = progress.etaSec;
    }
  }

  res.json({
    bitcoin: {
      ok:       !!chain,
      blocks:   chain?.blocks                   ?? null,
      headers:  chain?.headers                  ?? null,
      synced:   chain?.initialblockdownload === false,
      progress: chain?.verificationprogress     ?? null,
      peers:    network?.connections            ?? null,
      version:  network?.version                ?? null,
      feeRate:  fee?.feerate                    ?? null,
    },
    fulcrum: fulcrumData,
    mempool: { ok: mpl.ok, version: mpl.version },
    system:  sys,
  });
});

// GET /nodebox/updates — latest available versions from GitHub
app.get('/nodebox/updates', async (req, res) => {
  const [btc, flc, mpl] = await Promise.all([
    fetchLatestRelease('bitcoin/bitcoin'),
    fetchLatestRelease('cculianu/Fulcrum'),
    fetchLatestRelease('mempool/mempool'),
  ]);
  res.json({ bitcoinCore: btc, fulcrum: flc, mempool: mpl });
});

// GET /nodebox/config — non-secret runtime config for the frontend
app.get('/nodebox/config', (req, res) => {
  res.json({
    onionAddress: ONION_ADDRESS,
    localIp:      localIpAddress(),
    fulcrumPort:  FULCRUM_PORT,
  });
});

// GET /nodebox/qr?data=... — QR code as PNG (no CDN dependency)
app.get('/nodebox/qr', async (req, res) => {
  const data = req.query.data;
  if (!data || data.length > 500) return res.status(400).end();
  try {
    const png = await QRCode.toBuffer(String(data), { width: 256 });
    res.type('png').send(png);
  } catch {
    res.status(500).end();
  }
});

// GET /nodebox/services — status of optional installable services
app.get('/nodebox/services', async (req, res) => {
  const result = {};
  for (const [name, svc] of Object.entries(OPTIONAL_SERVICES)) {
    const installed = fs.existsSync(svc.marker);
    result[name] = {
      installed,
      running: installed
        ? await new Promise((resolve) =>
            execFile('systemctl', ['is-active', '--quiet', svc.unit], (err) => resolve(!err))
          )
        : false,
    };
  }
  res.json(result);
});

// POST /nodebox/install/:service — run install script via SSE
app.post('/nodebox/install/:service', (req, res) => {
  const svc = OPTIONAL_SERVICES[req.params.service];
  if (!svc) return res.status(400).json({ error: 'Unknown service' });
  streamScript(svc.installScript, req, res);
});

// POST /nodebox/update/:service — run update script via SSE
app.post('/nodebox/update/:service', (req, res) => {
  const script = UPDATE_SCRIPTS[req.params.service];
  if (!script) return res.status(400).json({ error: 'Unknown service' });
  streamScript(script, req, res);
});

// ── Start ─────────────────────────────────────────────────────────────────────

app.listen(DASHBOARD_PORT, '127.0.0.1', () => {
  console.log(`NodeBox dashboard listening on http://127.0.0.1:${DASHBOARD_PORT}`);
});

'use strict';

// Shared helpers used by all pages.

async function fetchStatus() {
  try {
    const res = await fetch('/nodebox/status');
    return res.ok ? res.json() : null;
  } catch { return null; }
}

async function fetchUpdates() {
  try {
    const res = await fetch('/nodebox/updates');
    return res.ok ? res.json() : null;
  } catch { return null; }
}

async function fetchServices() {
  try {
    const res = await fetch('/nodebox/services');
    return res.ok ? res.json() : null;
  } catch { return null; }
}

async function fetchConfig() {
  try {
    const res = await fetch('/nodebox/config');
    return res.ok ? res.json() : null;
  } catch { return null; }
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function setbadge(id, ok) {
  const el = document.getElementById(id);
  if (!el) return;
  if (ok === null) {
    el.className = 'badge badge-syncing';
    el.textContent = 'Syncing';
  } else {
    el.className = `badge badge-${ok ? 'ok' : 'error'}`;
    el.textContent = ok ? 'Online' : 'Offline';
  }
}

function fmtDuration(sec) {
  if (!sec || sec <= 0) return '—';
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function fmtBytes(b) {
  if (b >= 1e12) return `${(b / 1e12).toFixed(1)} TB`;
  if (b >= 1e9)  return `${(b / 1e9).toFixed(1)} GB`;
  if (b >= 1e6)  return `${(b / 1e6).toFixed(0)} MB`;
  return `${b} B`;
}

// Bitcoin Core version integer → display string (e.g. 3100000 → "v31.0")
function fmtBtcVersion(v) {
  if (!v) return '—';
  const major = Math.floor(v / 10000);
  const minor = Math.floor((v % 10000) / 100);
  const patch = v % 100;
  return patch > 0 ? `v${major}.${minor}.${patch}` : `v${major}.${minor}`;
}

// Like fmtBtcVersion but returns null (not "—") when version is absent, and no "v" prefix
function btcVersionStr(v) {
  if (!v) return null;
  const major = Math.floor(v / 10000);
  const minor = Math.floor((v % 10000) / 100);
  const patch = v % 100;
  return patch > 0 ? `${major}.${minor}.${patch}` : `${major}.${minor}`;
}

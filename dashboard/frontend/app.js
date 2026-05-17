'use strict';

// Shared helpers used by all pages.

async function fetchStatus() {
  try {
    const res = await fetch('/api/status');
    return res.ok ? res.json() : null;
  } catch { return null; }
}

async function fetchUpdates() {
  try {
    const res = await fetch('/api/updates');
    return res.ok ? res.json() : null;
  } catch { return null; }
}

async function fetchConfig() {
  try {
    const res = await fetch('/api/config');
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

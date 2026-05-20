# NodeBox Roadmap

## In Progress / Next Up

### Dashboard: Service Grid (iPhone-Style)
- Replace current service list with a grid of app icons (Bitcoin Core, Fulcrum, mempool.space, Public Pool, …)
- Click on icon → dedicated service detail page
- Detail page shows: status badge, version, uptime, last log lines, update button
- Design reference: iOS home screen grid layout

### nostr-vpn Integration
- Goal: connect phone or laptop to the NodeBox from anywhere, without a central server
- Uses Nostr pubkeys for identity, WireGuard-based data plane (FIPS)
- No Tailscale account, no third party — decentralized by design
- See: https://github.com/mmalmi/nostr-vpn
- **Status:** Test in branch `test/nostr-vpn`
- iOS not yet publicly available; NAT traversal reliability needs real-world testing
- Revisit for production once iOS is stable and NAT traversal is battle-tested (~2027)

---

## Phase 2 — Installer Script

One command sets up the full stack on a fresh Debian 13 system:

```bash
curl -fsSL https://nodebox.install/setup.sh | sudo bash
```

**Known install-order constraints:**
1. Tor must start first → wait for `.onion` address to be assigned
2. Generate Fulcrum SSL cert after Tor is up → include `.onion` as SAN
3. Nginx Esplora rewrite required (`/api/<non-v1>/` → `/api/v1/`)
4. Dashboard routes under `/nodebox/` (not `/api/`) to avoid Esplora conflict

---

## Phase 3 — Bootable ISO

Bootable USB image: download → flash → boot → "Install NodeBox" → done in ~30 min.

---

## Phase 4 — Hardware Product

Pre-configured Mini-PC (Dell OptiPlex or similar) with NodeBox pre-installed.

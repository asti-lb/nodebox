# NodeBox Roadmap

## In Progress / Next Up

### Dashboard: Uninstall Optional Services
- Remove mempool.space and Public Pool from the dashboard, as a runner task

### Dashboard: Login
- Protect the dashboard before the public release; it can trigger updates and restarts

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
- **Status:** Not started. Planned test in branch `test/nostr-vpn`
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
5. Set up `nodebox-runner` and unattended security updates (`scripts/install-runner.sh`, `scripts/install-os-updates.sh`)
6. Install `configs/sshd-nodebox.conf` only after an SSH key is in place
7. Allow Fulcrum and Public Pool ports for the local network only, on any private address range
8. Publish `nodebox.local` over IPv4 only: the stack does not listen on IPv6 (avahi: `use-ipv6=no`, `publish-aaaa-on-ipv4=no`)
9. Set mempool's `STDOUT_LOG_MIN_PRIORITY` to `info` to keep debug output out of the journal

---

## Phase 3 — Bootable ISO

Bootable USB image: download → flash → boot → "Install NodeBox" → done in ~30 min.

---

## Phase 4 — Hardware Product

Pre-configured Mini-PC (Dell OptiPlex or similar) with NodeBox pre-installed.

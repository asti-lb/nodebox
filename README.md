# NodeBox

A minimal, privacy-focused Bitcoin full node stack for home use.

**Bitcoin Core + Fulcrum + mempool.space — nothing more.**

---

## Philosophy

Most node implementations try to do everything. NodeBox does one thing well: run a private, sovereign Bitcoin node that just works.

- **No Docker** — systemd services, transparent and auditable
- **No bloat** — Bitcoin Core, Fulcrum, mempool.space only
- **Privacy-first** — Tor + I2P only, no clearnet Bitcoin traffic
- **Self-sovereign** — your keys, your node, your rules

## Stack

| Component | Purpose |
|---|---|
| Bitcoin Core | Full node, validates every block and transaction |
| Fulcrum | Electrum server — connects Sparrow, BitBox, and other wallets |
| mempool.space | Self-hosted block explorer |
| Tor + I2P | All Bitcoin traffic — no clearnet exposure |
| Nginx | Serves dashboard at `nodebox.local`, mempool at `nodebox.local/mempool` |

## Hardware

Tested on Dell OptiPlex 3050 (i5-7500T, 16 GB RAM, 2 TB NVMe).
Any x86_64 machine with 8 GB RAM and 2 TB storage should work.

## Status

> ⚠️ Early development — not ready for production use.

- [x] Phase 1: Stack components (Bitcoin Core, Fulcrum, mempool.space, Tor, Nginx)
- [x] Phase 2: Web dashboard
- [ ] Phase 3: One-command installer (`curl | bash`)
- [ ] Phase 4: Bootable ISO image

## Repository Layout

```
configs/        Service configuration files
services/       systemd unit files
scripts/        Update scripts (Bitcoin Core, Fulcrum, mempool)
dashboard/      Web dashboard (Node.js backend + plain HTML/CSS/JS frontend)
install.sh      Installer (Phase 3 — work in progress)
```

## Security

NodeBox is designed to be audited. If you find a security issue, please open a GitHub issue.

## License

MIT — see [LICENSE](LICENSE)

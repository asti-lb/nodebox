# NodeBox

A minimal, privacy-focused Bitcoin full node stack for home use.

**Bitcoin Core + Fulcrum + mempool.space — nothing more.**

---

## Philosophy

Most node implementations try to do everything. NodeBox does one thing well: run a private, sovereign Bitcoin node that just works.

- **No Docker** — systemd services, transparent and auditable
- **No bloat** — Bitcoin Core, Fulcrum, mempool.space, plus optional Public Pool
- **Privacy-first** — Tor + I2P only, no clearnet Bitcoin traffic
- **Self-sovereign** — your keys, your node, your rules

## Stack

| Component | Purpose |
|---|---|
| Bitcoin Core | Full node, validates every block and transaction |
| Fulcrum | Electrum server — connects Sparrow, BlueWallet, and other wallets |
| mempool.space | Self-hosted block explorer |
| Tor + I2P | All Bitcoin traffic — no clearnet exposure |
| Nginx | Serves dashboard at `nodebox.local`, mempool at `nodebox.local/mempool` |
| Public Pool | Optional solo mining pool for the home network |

## Hardware

Tested on Dell OptiPlex 3050 (i5-7500T, 16 GB RAM, 2 TB NVMe).
Any x86_64 machine with 8 GB RAM and 2 TB storage should work.

## Status

> ⚠️ Early development — not ready for production use.

- [x] Phase 1: Full stack and web dashboard, including one-click updates for Debian and all services
- [ ] Phase 2: One-command installer (`curl | bash`)
- [ ] Phase 3: Bootable ISO image
- [ ] Phase 4: Pre-installed hardware

## Repository Layout

```
configs/        Service configuration, tested Bitcoin Core version, release signing keys
services/       systemd unit files
scripts/        Update and install tasks, nodebox-runner, mempool watchdog
dashboard/      Web dashboard (Node.js backend + plain HTML/CSS/JS frontend)
install.sh      Installer (Phase 2 — not started)
```

## Security

NodeBox is designed to be audited. If you find a security issue, please open a GitHub issue.

## License

MIT — see [LICENSE](LICENSE)

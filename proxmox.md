# Proxmox Infrastructure

## Host

- Hostname: `VFIEVOX3`
- Proxmox VE version: `pve-manager/9.2.21`
- Kernel: `7.0.14-5-pve`
- Repository: `https://github.com/pioneershahid/homelab.git`
- Repository branch: `main`
- Repository working directory: `/opt/homelab`

## LXC inventory

| CT ID | Role | Management and repository status |
|---:|---|---|
| 100 | Pi-hole | Native `pihole-FTL` service; no Docker installation |
| 101 | Frigate | Compose configuration tracked |
| 102 | Photos / Immich | Compose configuration being tracked |
| 103 | Network services | Compose configurations tracked |
| 104 | Servarr / media automation | Compose configuration tracked |
| 105 | Cockpit | System-managed; Docker not installed; socket enabled |
| 107 | Gitea | Excluded; installed and managed using Proxmox Community Scripts |
| 108 | Media services | Compose configuration tracked |
| 109 | Monitoring | Excluded; deployed separately |
| 110 | GitHub Actions runner | Self-hosted runner; used for LAN smoke tests and controlled deployment workflows |

Gitea Community Scripts project:
https://github.com/community-scripts/ProxmoxVE

## Configuration and safety policy

- Persistent application data remains on the relevant LXC or storage mount.
- Do not copy application databases, media libraries, or runtime directories
  into this repository.
- Do not commit real `.env` files, passwords, API tokens, private keys,
  certificate state, or database credentials.
- Validate repository copies before considering any deployment.
- Do not restart or recreate services as part of configuration inventory.
- Gitea and Monitoring are intentionally outside this Compose migration.
- GitHub Actions runner (CT 110) is used for controlled CI workflows that
  require access to the homelab LAN.
- Repository validation and deployment are separate operations; only the
  explicitly configured deployment workflow applies changes to services.

## Change log

- Recorded the Proxmox host and LXC inventory.
- Tracked Compose configurations for Frigate, Photos/Immich, Network,
  Servarr, and Media services.
- Added GitHub Actions validation and controlled Homepage deployment.
- Added LAN smoke tests and a disposable LXC integration test.

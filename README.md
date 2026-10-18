# Homelab Infrastructure

Private configuration repository for the Proxmox homelab.

## Goals

- Keep reviewed Docker Compose configurations under version control.
- Document the Proxmox host and LXC inventory.
- Keep credentials, tokens, certificates, and runtime state out of Git.
- Validate configuration changes before considering deployment.
- Avoid downtime by separating configuration migration from deployment.

## Repository layout

| Path | Purpose |
|---|---|
| `frigate/` | Frigate |
| `network/` | Traefik, Authelia, Homepage, and related network services |
| `photos/` | Immich photo and video management |
| `servarr/` | Media automation and download services |
| `media/` | Media server and related services |
| `proxmox.md` | Proxmox host and LXC inventory |

## Out of scope

- **Gitea (CT 107):** installed and managed separately using the
  [Proxmox Community Scripts project](https://github.com/community-scripts/ProxmoxVE).
  It is intentionally excluded from this Docker Compose migration.
- **Monitoring (CT 109):** deployed separately and intentionally excluded
  from this migration.
- **Pi-hole (CT 100) and Cockpit (CT 105):** system-managed services rather
  than Docker Compose deployments; documented in `proxmox.md`.

## Secrets and persistent data

- Never commit real `.env` files or credentials.
- Use `.env.example` files with placeholders only.
- Keep databases, application state, media libraries, backups, certificates,
  and other runtime data on their intended hosts or storage mounts.
- Review Compose files for hardcoded secrets before staging them.
- Do not rotate a live credential as part of a configuration-only migration.

## Safe configuration workflow

1. Inventory the live configuration.
2. Copy configuration files without copying application state.
3. Replace hardcoded secrets in the repository copy with appropriate variables.
4. Validate the copy in the relevant deployment context.
5. Review the complete Git diff and check for secrets or runtime data.
6. Commit and push only reviewed files.
7. Treat deployment as a separate, explicitly reviewed operation.

**A successful Git commit does not mean a configuration has been deployed.**

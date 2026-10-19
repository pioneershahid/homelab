# Homelab Infrastructure

Private configuration repository for the Proxmox homelab. This repository tracks Docker Compose configurations, Ansible automation, CI workflows, and infrastructure documentation.

The repository uses GitHub Actions to validate configuration changes and a dedicated self-hosted runner for controlled homelab tests and Homepage deployment.

## Goals

- Keep reviewed Docker Compose configurations and infrastructure automation under version control.
- Validate Compose and Ansible changes before deployment.
- Separate CI validation, infrastructure testing, and production deployment.
- Keep credentials, certificates, application state, and runtime data out of Git.
- Minimize service disruption by deploying only explicitly selected services.

## Repository layout

| Path | Purpose |
|---|---|
| `frigate/` | Frigate Compose configuration and environment template |
| `media/` | Media server Compose configuration |
| `network/` | Traefik, Authelia, Homepage, and related network services |
| `photos/` | Immich Compose configuration |
| `servarr/` | Media automation and download services |
| `ansible/inventory/` | Homelab Ansible inventory |
| `ansible/playbooks/` | Ansible validation and Homepage deployment playbooks |
| `.github/workflows/` | CI, smoke-test, integration-test, and deployment workflows |
| `scripts/` | Homelab smoke-test scripts |
| `docs/` | CI setup and disposable LXC integration-test documentation |
| `proxmox.md` | Proxmox host and LXC inventory |
| `requirements-dev.txt` | Python dependencies used by Ansible CI and deployment |

## CI and deployment architecture

### GitHub-hosted validation

The following workflows run on GitHub-hosted Ubuntu runners:

| Workflow | Trigger | Purpose |
|---|---|---|
| `Validate Docker Compose` | Push to `main`, pull request, or manual | Validates the seven tracked Compose configurations |
| `Ansible validation` | Relevant Ansible/dependency changes, or manual | Checks playbook syntax, inventory, lint, and a safe localhost smoke test |

These workflows validate repository configuration. They do not deploy application changes to production.

### Self-hosted homelab runner

The dedicated GitHub Actions runner runs in LXC 110, named `github-runner`, under the `runner` account. Jobs requiring access to the homelab use the labels:

`self-hosted`, `linux`, `x64`, `homelab-smoke`

Self-hosted workflows can access homelab infrastructure and must be treated as privileged operations. Keep them manual unless there is a clear, reviewed reason to automate their triggers. Do not run untrusted pull-request code on the self-hosted runner.

### Available operational workflows

| Workflow | Trigger | Scope |
|---|---|---|
| `Deploy Homepage` | Manual | Deploys the tracked Homepage Compose file to the Docker LXC |
| `Homelab LAN smoke tests` | Manual | Runs the LAN service probes in `scripts/smoke-test-lan.sh` |
| `Disposable LXC integration test` | Manual, restricted to `main` | Provisions, tests, and cleans up the dedicated disposable test LXC |

The disposable LXC integration test uses reserved CTID 990 and restricted SSH commands. See [`docs/ci-lxc-test.md`](docs/ci-lxc-test.md) before modifying its workflow or Proxmox-side setup.

## Homepage deployment

The current Ansible deployment targets the Docker LXC at `192.168.1.27` through the `docker_hosts` inventory group.

To deploy:

1. Review and commit the intended changes to `main`.
2. Confirm the relevant GitHub validation workflows pass.
3. Open the repository's **Actions** tab.
4. Select **Deploy Homepage** and run the workflow from `main`.
5. Review the job output and verify Homepage health.

The playbook stages and validates the repository Compose file, backs up the existing live Compose file, and runs `docker compose up -d --no-deps homepage`. It then checks the resulting service status.

**Deployment scope is intentionally limited:** this playbook deploys the Homepage Compose file only. It does not synchronize Homepage configuration files such as `config/services.yaml`, modify the live `.env` file, or deploy other services. Those changes require a separately reviewed process.

A successful CI run validates configuration; a successful deployment run indicates that the deployment playbook completed its checks. Neither should be treated as proof that unrelated services or all application functionality have been tested.

## Secrets and persistent data

- Never commit real `.env` files, passwords, API tokens, private keys, or credentials.
- Use `.env.example` files containing placeholders only.
- Keep Traefik certificate state, application databases, media libraries, backups, and runtime logs out of Git.
- Keep deployment and integration-test private keys on the appropriate runner account with restrictive file permissions.
- Verify SSH host keys; do not disable strict host-key checking to work around connection failures.
- Review `git diff` and `git status` before every commit.

The repository's `.gitignore` excludes environment files and selected runtime state. Ignore rules are a safeguard, not a substitute for reviewing staged files.

## Safe configuration workflow

1. Inspect the current live configuration without modifying services.
2. Update the repository configuration and its documentation.
3. Validate Compose and Ansible changes using the appropriate CI workflow.
4. Review the complete diff for accidental secrets, runtime data, and unintended service changes.
5. Commit and push reviewed changes to GitHub.
6. Run production deployment only when explicitly intended and supported by the relevant workflow.
7. Verify service health after deployment.

**A Git commit or passing validation workflow does not mean a configuration has been deployed.**

## Out of scope

- **Gitea (CT 107):** installed and managed separately using the [Proxmox Community Scripts project](https://github.com/community-scripts/ProxmoxVE).
- **Monitoring (CT 109):** deployed separately.
- **Pi-hole (CT 100) and Cockpit (CT 105):** system-managed services documented in [`proxmox.md`](proxmox.md).

These services are intentionally outside the current Docker Compose migration and Homepage deployment scope.

## Maintenance principles

- Prefer small, reviewable changes over broad infrastructure refactors.
- Keep CI validation safe and independent of production services.
- Keep production deployment manual and narrowly scoped.
- Do not automatically destroy or adopt an existing LXC during integration testing.
- Update documentation whenever runner setup, workflow behavior, inventory, or deployment scope changes.

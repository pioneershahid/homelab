
# Disposable Proxmox LXC integration test

## Purpose

This manual GitHub Actions workflow tests the lifecycle of one disposable
Debian 13 LXC on Proxmox. It does not deploy or change production services.

## Fixed infrastructure

- Proxmox host: `VFIEVOX3` (`192.168.1.35`)
- Dedicated runner: LXC `110`, user `runner`
- Restricted Proxmox account: `homelab-ci`
- Reserved test CTID: `990`
- Template: `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`
- Storage: `local-lvm`
- Bridge: `vmbr0`, DHCP
- Limits: 1 CPU core, 512 MiB RAM, 4 GiB root disk
- Test service: `nginx-light` inside the disposable container

## One-time Proxmox setup

1. Confirm CTID 990 is unused with `pct list` and `pct status 990`.
2. Confirm the Debian 13 template and `local-lvm` storage are available.
3. Create the `homelab-ci` account without general shell or Docker access.
4. Install `/usr/local/sbin/homelab-ci-lxc` as root-owned mode `0755`.
5. Install `/usr/local/sbin/homelab-ci-ssh-wrapper` as root-owned mode `0755`.
6. Configure `/etc/sudoers.d/homelab-ci-lxc` with only the four approved actions:
   `create`, `ip`, `status`, and `destroy`.
7. Validate with `visudo -cf /etc/sudoers.d/homelab-ci-lxc` and `sshd -t`.
8. Generate the dedicated Ed25519 key as the `runner` account in LXC 110.
9. Install only the public key in `/home/homelab-ci/.ssh/authorized_keys`,
   using the forced command and `restrict` options.
10. Verify the public key matches the runner key.
11. Compare the Proxmox SSH host-key fingerprint against the runner's
    `known_hosts` entry. Never disable strict host-key checking.

Do not copy the private key into the repository or paste it into chat.

## Workflow operation

1. Open GitHub repository Actions.
2. Select **Disposable LXC integration test**.
3. Select **Run workflow** on `main`.
4. Confirm provisioning, HTTP verification, and cleanup all pass.
5. Verify on Proxmox that CT 990 is absent after the run.

The workflow is manual-only and must not be attached to pull-request events.
Protect `main` so untrusted changes cannot execute on the self-hosted runner.

## Safety rules

- CTID 990 is reserved exclusively for this test.
- Never remove a container based only on its ID; verify the description and tag.
- Never run broad cleanup commands such as `pct list | ... | xargs pct destroy`.
- Never grant the runner unrestricted root SSH, general sudo, Docker socket,
  or Proxmox API administrator credentials.
- If CT 990 already exists, the workflow must stop and an administrator must
  inspect it. Do not overwrite or automatically adopt it.
- If cleanup fails, inspect `pct status 990`, `pct config 990`, and task logs
  manually before taking action.
- Do not run this workflow from an untrusted branch or fork.

## Troubleshooting

- **SSH permission denied:** check the runner private key, host authorized key,
  account ownership, and SSH logs on Proxmox.
- **Host key verification failed:** compare fingerprints; do not bypass checking.
- **CTID already exists:** stop and inspect the existing container.
- **No DHCP address:** inspect `vmbr0`, the LAN DHCP service, and `pct config 990`.
- **APT or Nginx installation fails:** inspect container network/DNS access.
- **HTTP test fails:** inspect the container address, Nginx status, and LAN
  connectivity from LXC 110.
- **Cleanup fails:** do not delete any other CT. Verify the test marker and
  inspect Proxmox task logs before retrying the restricted `destroy` action.

## Current scope

This test validates container provisioning, package installation, LAN HTTP
reachability, and cleanup. It does not yet validate Terraform/OpenTofu,
Ansible, application-specific deployment, backups, or rollback of production.



## Verification history

### First successful integration run

- Workflow: `Disposable LXC integration test`
- Result: passed
- Provisioning: Debian 13, CTID 990
- Test service: Nginx
- Test address: `192.168.1.95` (DHCP; not fixed)
- HTTP assertion: exact response `homelab-ci-lxc-test-ok`
- Cleanup: CT configuration and logical volume removed
- Existing production LXCs: not modified
- Notes: locale and systemd/nesting warnings were non-fatal

Re-run this workflow manually from `main` to verify the lifecycle after
changes to the wrapper, template, networking, or workflow.

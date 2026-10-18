#!/usr/bin/env bash
# Secure bootstrap for the homelab-ci SSH-to-Proxmox LXC test runner.
# Run as root on the Proxmox host. Review HOST_ALIAS and LXCID before use.
set -Eeuo pipefail
umask 077

CTID=990
RUNNER_LXCID=110
TEMPLATE='local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst'
MARKER='managed-by=homelab-ci-lxc-test'
TAG='homelab-ci-test'
ACCOUNT='homelab-ci'
HOST_ALIAS="${HOST_ALIAS:-}"   # Must match the host token in runner's known_hosts
KEY_NAME="${KEY_NAME:-homelab-ci-proxmox}"
LXC_SCRIPT=/usr/local/sbin/homelab-ci-lxc
SSH_WRAPPER=/usr/local/sbin/homelab-ci-ssh-wrapper
SUDOERS_FILE=/etc/sudoers.d/homelab-ci-lxc
AUTH_KEYS=/home/homelab-ci/.ssh/authorized_keys
CONFIG="/etc/pve/lxc/${CTID}.conf"

die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [[ ${EUID} -eq 0 ]] || die "Run this script as root on the Proxmox host."; }

install_host_files() {
  need_root
  command -v pct >/dev/null || die "pct not found; run on the Proxmox host."
  command -v visudo >/dev/null || die "visudo not found."
  command -v sshd >/dev/null || die "sshd not found."

  # A dedicated non-login account. Do not add it to docker or other privileged groups.
  if ! id "$ACCOUNT" >/dev/null 2>&1; then
    useradd --create-home --home-dir "/home/$ACCOUNT" --shell /usr/sbin/nologin "$ACCOUNT"
  else
    usermod --home "/home/$ACCOUNT" --shell /usr/sbin/nologin "$ACCOUNT"
  fi
  gpasswd -d "$ACCOUNT" docker >/dev/null 2>&1 || true
  install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 0700 "/home/$ACCOUNT/.ssh"

  cat >"$LXC_SCRIPT" <<'LXC_EOF'
#!/bin/bash
set -Eeuo pipefail

CTID=990
TEMPLATE='local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst'
MARKER='managed-by=homelab-ci-lxc-test'
TAG='homelab-ci-test'
CONFIG="/etc/pve/lxc/${CTID}.conf"
created_here=0

owned() {
  [[ -f "$CONFIG" ]] &&
    grep -Fxq "#${MARKER}" "$CONFIG" &&
    grep -Fxq "tags: ${TAG}" "$CONFIG"
}
require_owned() {
  if ! owned; then
    echo "Refusing: CT ${CTID} is not verified as the CI test container." >&2
    exit 1
  fi
}
cleanup_failed_create() {
  rc=$?
  trap - EXIT
  if (( rc != 0 && created_here == 1 )) && owned; then
    echo "Provisioning failed; cleaning up CT ${CTID}." >&2
    if [[ "$(pct status "$CTID" 2>/dev/null || true)" == "status: running" ]]; then
      pct stop "$CTID" || true
    fi
    pct destroy "$CTID" --purge ||
      echo "WARNING: manual cleanup may be required for CT ${CTID}." >&2
  fi
  exit "$rc"
}

case "${1:-}" in
  create)
    # Never adopt, overwrite, or reuse an existing CTID.
    if [[ -e "$CONFIG" ]]; then
      echo "Refusing: CT ${CTID} already exists." >&2
      exit 1
    fi
    pveam list local | grep -Fq "${TEMPLATE#local:}" || {
      echo "Required Debian template not found." >&2
      exit 1
    }
    trap cleanup_failed_create EXIT
    pct create "$CTID" "$TEMPLATE" \
      --hostname homelab-ci-test \
      --ostype debian \
      --cores 1 \
      --memory 512 \
      --swap 512 \
      --rootfs local-lvm:4 \
      --net0 name=eth0,bridge=vmbr0,ip=dhcp \
      --unprivileged 1 \
      --onboot 0 \
      --description "$MARKER" \
      --tags "$TAG"
    created_here=1
    require_owned
    pct start "$CTID"
    ready=0
    for _ in $(seq 1 30); do
      if pct exec "$CTID" -- /bin/sh -c \
        'hostname -I | grep -Eq "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"'; then
        ready=1
        break
      fi
      sleep 2
    done
    [[ "$ready" == 1 ]] || {
      echo "Test container did not obtain an IP address." >&2
      exit 1
    }
    pct exec "$CTID" -- /bin/sh -ec \
      'apt-get update &&
       DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nginx-light &&
       printf "%s\n" "homelab-ci-lxc-test-ok" > /var/www/html/index.html &&
       systemctl enable --now nginx'
    trap - EXIT
    created_here=0
    echo "Created and provisioned test container ${CTID}."
    ;;
  ip)
    require_owned
    [[ "$(pct status "$CTID")" == "status: running" ]] || {
      echo "Test container is not running." >&2
      exit 1
    }
    ip=$(
      pct exec "$CTID" -- hostname -I |
        tr ' ' '\n' |
        grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$' |
        grep -v '^127\\.' |
        head -n 1
    )
    [[ -n "$ip" ]] || { echo "No IPv4 address found." >&2; exit 1; }
    printf '%s\n' "$ip"
    ;;
  status)
    require_owned
    pct status "$CTID"
    ;;
  destroy)
    if [[ ! -e "$CONFIG" ]]; then
      echo "Test container already absent."
      exit 0
    fi
    require_owned
    if [[ "$(pct status "$CTID")" == "status: running" ]]; then
      pct shutdown "$CTID" --timeout 30 || pct stop "$CTID"
    fi
    require_owned
    pct destroy "$CTID" --purge
    echo "Destroyed test container ${CTID}."
    ;;
  *)
    echo "Allowed actions: create, ip, status, destroy" >&2
    exit 2
    ;;
esac
LXC_EOF
  chown root:root "$LXC_SCRIPT"
  chmod 0755 "$LXC_SCRIPT"

  cat >"$SSH_WRAPPER" <<'WRAPPER_EOF'
#!/bin/bash
set -euo pipefail

# SSH_ORIGINAL_COMMAND must be exactly one approved verb; no arguments accepted.
case "${SSH_ORIGINAL_COMMAND:-}" in
  create|ip|status|destroy)
    exec /usr/bin/sudo -n /usr/local/sbin/homelab-ci-lxc "$SSH_ORIGINAL_COMMAND"
    ;;
  *)
    echo "Command not allowed." >&2
    exit 2
    ;;
esac
WRAPPER_EOF
  chown root:root "$SSH_WRAPPER"
  chmod 0755 "$SSH_WRAPPER"

  cat >"$SUDOERS_FILE" <<'SUDOERS_EOF'
homelab-ci ALL=(root) NOPASSWD: /usr/local/sbin/homelab-ci-lxc create, /usr/local/sbin/homelab-ci-lxc ip, /usr/local/sbin/homelab-ci-lxc status, /usr/local/sbin/homelab-ci-lxc destroy
SUDOERS_EOF
  chown root:root "$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"

  visudo -cf "$SUDOERS_FILE"
  sshd -t
  echo "Host files installed and syntax checks passed."
}

configure_authorized_key() {
  need_root
  [[ -n "$HOST_ALIAS" ]] || die "Set HOST_ALIAS to the exact Proxmox host token used in runner's known_hosts, then rerun with HOST_ALIAS=..."
  command -v pct >/dev/null || die "pct not found."
  id "$ACCOUNT" >/dev/null 2>&1 || die "Account $ACCOUNT does not exist; run host-install first."
  [[ -e "/etc/pve/lxc/${RUNNER_LXCID}.conf" ]] || die "Runner LXC ${RUNNER_LXCID} does not exist."

  # Generate the dedicated key inside LXC 110 as the unprivileged runner account.
  pct exec "$RUNNER_LXCID" -- /bin/sh -ec '
    id runner >/dev/null 2>&1 || { echo "runner account missing in LXC 110" >&2; exit 1; }
    install -d -o runner -g "$(id -gn runner)" -m 0700 /home/runner/.ssh
    if [ ! -f /home/runner/.ssh/'"$KEY_NAME"'" ]; then
      runuser -u runner -- ssh-keygen -t ed25519 -N "" -C "homelab-ci-runner" -f /home/runner/.ssh/'"$KEY_NAME"'
    fi
    test -s /home/runner/.ssh/'"$KEY_NAME"'.pub
  '

  local pubkey keytype keydata comment
  pubkey="$(pct exec "$RUNNER_LXCID" -- cat "/home/runner/.ssh/${KEY_NAME}.pub")"
  read -r keytype keydata comment <<<"$pubkey"
  [[ "$keytype" == ssh-ed25519 && -n "$keydata" ]] || die "Unexpected public-key format."

  install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 0700 "/home/$ACCOUNT/.ssh"
  touch "$AUTH_KEYS"
  chown "$ACCOUNT:$ACCOUNT" "$AUTH_KEYS"
  chmod 0600 "$AUTH_KEYS"

  # Remove only an existing entry with this key's exact key material, then add the restricted entry.
  local tmp
  tmp="$(mktemp)"
  awk -v key="$keydata" '{
    if ($0 ~ /ssh-ed25519/ && index($0, key)) next
    print
  }' "$AUTH_KEYS" >"$tmp"
  printf 'restrict,command="/usr/local/sbin/homelab-ci-ssh-wrapper" %s %s\n' "$keytype" "$keydata" >>"$tmp"
  install -o "$ACCOUNT" -g "$ACCOUNT" -m 0600 "$tmp" "$AUTH_KEYS"
  rm -f "$tmp"

  # Compare the installed authorized key to the public key held by runner in LXC 110.
  local installed_key
  installed_key="$(awk -v key="$keydata" '$0 ~ /command="\\/usr\\/local\\/sbin\\/homelab-ci-ssh-wrapper"/ && index($0,key) {print $NF}' "$AUTH_KEYS" | tail -n 1)"
  [[ "$installed_key" == "$keydata" ]] || die "Installed authorized key does not match runner public key."

  echo "Installed restricted public key for runner. Verify host-key trust from LXC 110:"
  echo "  pct exec ${RUNNER_LXCID} -- runuser -u runner -- ssh-keygen -F '${HOST_ALIAS}' -f /home/runner/.ssh/known_hosts"
  echo "  pct exec ${RUNNER_LXCID} -- runuser -u runner -- ssh-keygen -lf /home/runner/.ssh/known_hosts"
  echo "Compare that entry's SHA256 fingerprint with the Proxmox host key fingerprint:"
  echo "  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
  echo "Do not use StrictHostKeyChecking=no or otherwise bypass host-key checking."
}

show_checks() {
  need_root
  visudo -cf "$SUDOERS_FILE"
  sshd -t
  stat -c '%U:%G %a %n' "$LXC_SCRIPT" "$SSH_WRAPPER" "$SUDOERS_FILE"
  echo "Check the account has no general shell and is not in docker:"
  getent passwd "$ACCOUNT" || true
  id "$ACCOUNT" || true
  echo "Approved sudo commands:"
  sudo -l -U "$ACCOUNT" || true
}

usage() {
  cat <<'USAGE'
Usage (run as root on the Proxmox host):
  homelab-ci-bootstrap.sh host-install
      Create/configure account, install both scripts and sudoers, run visudo + sshd checks.
  HOST_ALIAS=proxmox.example.lan homelab-ci-bootstrap.sh install-key
      Generate runner key in LXC 110 and install restricted public key on the Proxmox host.
      HOST_ALIAS must exactly match the runner's known_hosts entry.
  homelab-ci-bootstrap.sh verify
      Re-run syntax checks and print ownership/mode/account/sudo diagnostics.

Review CTID=990, runner LXC ID=110, storage names, bridge, and template before running.
The script does not disable strict host-key checking and does not install a private key on Proxmox.
After install-key, manually compare SHA256 fingerprints as printed above.
USAGE
}
case "${1:-}" in
  host-install) install_host_files ;;
  install-key) configure_authorized_key ;;
  verify) show_checks ;;
  *) usage; exit 2 ;;
esac

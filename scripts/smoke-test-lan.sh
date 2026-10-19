#!/usr/bin/env bash
set -uo pipefail

# Homelab smoke tests for internal services.
# Usage:
#   bash scripts/smoke-test.sh [service_name]
#
# Examples:
#   bash scripts/smoke-test.sh          # Runs all service checks
#   bash scripts/smoke-test.sh frigate  # Probes only frigate
#   bash scripts/smoke-test.sh homepage # Probes only homepage

target_filter="${1:-all}"
failures=0
passed=0

probe() {
  local name="$1"
  local url="$2"
  shift 2

  if [[ "$target_filter" != "all" && "$target_filter" != "$name" ]]; then
    return 0
  fi

  local code
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 15 "$@" "$url" 2>/dev/null)" || code=000

  if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
    printf 'PASS %-14s HTTP %s\n' "$name" "$code"
    passed=$((passed + 1))
  else
    printf 'FAIL %-14s HTTP %s (%s)\n' "$name" "$code" "$url"
    failures=$((failures + 1))
  fi
}

echo "=== Homelab Smoke Tests (Target: ${target_filter}) ==="

# Frigate (CT 101)
probe frigate http://192.168.1.30:5000/

# Immich / Photos (CT 102)
probe immich http://192.168.1.28:2283/api/server/ping

# Network services (CT 103)
probe homepage http://192.168.1.27:3000/
probe traefik http://192.168.1.27/ --max-time 12
probe authelia https://auth.shahidmustafa.ie/api/health \
  --resolve auth.shahidmustafa.ie:443:192.168.1.27

# Servarr / media automation (CT 104)
probe sonarr http://192.168.1.31:8989/ping
probe radarr http://192.168.1.31:7878/ping

# Media services (CT 108)
probe jellyfin http://192.168.1.25:8096/health
probe jellyseerr http://192.168.1.25:5055/api/v1/status
probe duplicati http://192.168.1.25:8200/

# Monitoring (CT 109)
probe grafana http://192.168.1.99:3000/
probe prometheus http://192.168.1.99:9090/
probe alertmanager http://192.168.1.99:9093/

echo
printf 'Summary: %d passed, %d failed\n' "$passed" "$failures"

if (( failures > 0 )); then
  exit 1
fi

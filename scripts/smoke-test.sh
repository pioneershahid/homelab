#!/usr/bin/env bash
set -u

# LAN-only smoke tests. No credentials, writes, or service restarts.
# HTTP 2xx/3xx means reachable; public DNS is intentionally excluded.

passed=0
failed=0

probe() {
  local id="$1"
  local label="$2"
  local url="$3"
  local resolve="${4:-}"
  local code rc

  if [[ -n "$resolve" ]]; then
    code=$(pct exec "$id" -- curl -sS -o /dev/null \
      -w '%{http_code}' --connect-timeout 3 --max-time 10 \
      --resolve "$resolve" "$url" 2>/dev/null)
    rc=$?
  else
    code=$(pct exec "$id" -- curl -sS -o /dev/null \
      -w '%{http_code}' --connect-timeout 3 --max-time 10 \
      "$url" 2>/dev/null)
    rc=$?
  fi

  if [[ $rc -eq 0 && "$code" =~ ^[23][0-9][0-9]$ ]]; then
    printf 'PASS  %-22s HTTP %s\n' "$label" "$code"
    ((passed+=1))
  else
    printf 'FAIL  %-22s HTTP %s (curl/pct exit %s)\n' \
      "$label" "${code:-000}" "$rc"
    ((failed+=1))
  fi
}

echo "=== Homelab LAN smoke tests ==="

probe 101 frigate       http://127.0.0.1:5000/
probe 102 immich        http://127.0.0.1:2283/
probe 103 homepage      http://127.0.0.1:3000/
probe 103 traefik-http  http://127.0.0.1:80/
probe 103 authelia      https://auth.shahidmustafa.ie/ \
  "auth.shahidmustafa.ie:443:127.0.0.1"

probe 104 sonarr        http://127.0.0.1:8989/
probe 104 radarr        http://127.0.0.1:7878/

probe 108 jellyfin      http://127.0.0.1:8096/
probe 108 jellyseerr    http://127.0.0.1:5055/
probe 108 duplicati     http://127.0.0.1:8200/

probe 109 grafana       http://192.168.1.99:3000/
probe 109 prometheus    http://192.168.1.99:9090/
probe 109 alertmanager  http://192.168.1.99:9093/

echo
printf 'Summary: %d passed, %d failed\n' "$passed" "$failed"

if (( failed > 0 )); then
  exit 1
fi

#!/usr/bin/env bash

set -u

passed=0
failed=0

probe() {
  local name="$1"
  local url="$2"
  local resolve="${3:-}"
  local code
  local -a args

  args=(-sS -o /dev/null --connect-timeout 5 --max-time 15
        -w '%{http_code}')

  if [[ -n "$resolve" ]]; then
    args+=(--resolve "$resolve")
  fi

  if code=$(curl "${args[@]}" "$url"); then
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
      printf 'PASS %-14s HTTP %s\n' "$name" "$code"
      ((passed += 1))
    else
      printf 'FAIL %-14s HTTP %s\n' "$name" "$code"
      ((failed += 1))
    fi
  else
    printf 'FAIL %-14s connection/request error\n' "$name"
    ((failed += 1))
  fi
}

echo "=== Homelab LAN smoke tests ==="

probe frigate      http://192.168.1.30:5000/
probe immich       http://192.168.1.28:2283/
probe homepage     http://192.168.1.27:3000/
probe traefik-http http://192.168.1.27:80/
probe authelia     https://auth.shahidmustafa.ie/ \
  auth.shahidmustafa.ie:443:192.168.1.27

probe sonarr       http://192.168.1.31:8989/
probe radarr       http://192.168.1.31:7878/

probe jellyfin     http://192.168.1.25:8096/
probe jellyseerr   http://192.168.1.25:5055/
probe duplicati    http://192.168.1.25:8200/

probe grafana      http://192.168.1.99:3000/
probe prometheus   http://192.168.1.99:9090/
probe alertmanager http://192.168.1.99:9093/

echo
printf 'Summary: %d passed, %d failed\n' "$passed" "$failed"

if (( failed > 0 )); then
  exit 1
fi

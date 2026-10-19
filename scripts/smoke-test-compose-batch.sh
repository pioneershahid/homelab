
#!/usr/bin/env bash
set -uo pipefail

failures=0

probe() {
  local name="$1"
  local url="$2"
  shift 2

  local code
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 12 "$@" "$url" 2>/dev/null)" || code=000

  if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
    printf 'PASS %-12s HTTP %s\n' "$name" "$code"
  else
    printf 'FAIL %-12s HTTP %s (%s)\n' "$name" "$code" "$url"
    failures=$((failures + 1))
  fi
}

probe immich \
  http://192.168.1.28:2283/api/server/ping

probe traefik \
  http://192.168.1.27/ \
  --max-time 12

probe authelia \
  https://auth.shahidmustafa.ie/api/health \
  --resolve auth.shahidmustafa.ie:443:192.168.1.27

probe sonarr \
  http://192.168.1.31:8989/ping

probe radarr \
  http://192.168.1.31:7878/ping

probe jellyfin \
  http://192.168.1.25:8096/health

probe jellyseerr \
  http://192.168.1.25:5055/api/v1/status

probe duplicati \
  http://192.168.1.25:8200/

echo
echo "Smoke-test failures: $failures"
exit "$((failures > 0))"

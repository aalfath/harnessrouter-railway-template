#!/usr/bin/env bash
# Railway start wrapper for HarnessRouter Community Edition. Runs as root under tini, prepares a few
# Railway-specific settings, then runs upstream's unchanged /app/entrypoint.sh, which installs the
# agent CLIs into /data, drops privileges and starts the console (:$PORT), the gateway
# (127.0.0.1:8080) and the runner (127.0.0.1:8081). Never prints a secret.
set -uo pipefail

PY=/usr/local/bin/python3
DATA_DIR="${HR_DATA_DIR:-/data}"
log() { printf '[railway] %s\n' "$*"; }
is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# ── 1. The console is on a public URL: never without a real password ─────────────────────────
if [ "${HR_AUTH_DISABLED:-}" = "1" ]; then
  log "ERROR: HR_AUTH_DISABLED=1 would open the console (and your provider keys) to anyone on the public URL. Remove it."
  exit 1
fi
export HR_AUTH_USER="${HR_AUTH_USER:-harnessrouter}"
if [ -f "$DATA_DIR/selfhost-auth.json" ]; then
  log "console: sign in with the credentials saved under Profile (they replace HR_AUTH_USER/HR_AUTH_PASSWORD)"
elif pw="${HR_AUTH_PASSWORD:-}"; [ "${#pw}" -lt 16 ]; then
  log "ERROR: HR_AUTH_PASSWORD is empty or shorter than 16 characters. Set it to a long random value (the template generates one)."
  exit 1
else
  log "console: user '$HR_AUTH_USER', password = the HR_AUTH_PASSWORD variable"
fi

# ── 2. Per-session users need their uids mapped in this container ─────────────────────────────
# Every agent turn runs as its own uid (upstream default 20000+). If the user namespace maps fewer
# ids, start the session uids just above the product user (10001) instead.
top="$(awk 'BEGIN{m=0} {t=$1+$3; if (t>m) m=t} END{printf "%.0f", m}' /proc/self/uid_map 2>/dev/null)"
if is_uint "$top" && [ "$top" -gt 0 ] && [ -z "${HR_SESSION_UID_BASE:-}" ] && [ "$top" -lt 21024 ]; then
  if [ "$top" -ge 11026 ]; then
    export HR_SESSION_UID_BASE=10002
    log "uids: only ids below $top are mapped, so session users start at 10002"
  else
    log "WARNING: only ids below $top are mapped; per-session users may fail"
  fi
fi

# ── 3. Size work to this service, not to the host Railway shows (32+ CPUs) ───────────────────
cpus=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r q p < /sys/fs/cgroup/cpu.max || true
  if is_uint "${q:-}" && is_uint "${p:-}" && [ "$p" -gt 0 ]; then cpus=$(( (q + p - 1) / p )); fi
fi
is_uint "$cpus" || cpus=2
mem_mb=""
if [ -r /sys/fs/cgroup/memory.max ]; then
  m="$(cat /sys/fs/cgroup/memory.max)"; is_uint "$m" && mem_mb=$(( m / 1048576 ))
fi
is_uint "$mem_mb" || mem_mb=2048
if [ -z "${HARNESS_GLOBAL_CONCURRENCY:-}" ]; then
  c=$(( mem_mb / 700 )); [ "$c" -gt "$cpus" ] && c="$cpus"; [ "$c" -lt 1 ] && c=1; [ "$c" -gt 4 ] && c=4
  export HARNESS_GLOBAL_CONCURRENCY="$c"
fi
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$(( cpus < 4 ? cpus : 4 ))}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"
export UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-4}"
log "sizing: ${cpus} CPU, ${mem_mb} MB RAM -> at most $HARNESS_GLOBAL_CONCURRENCY agent turn(s) at once (set HARNESS_GLOBAL_CONCURRENCY to change)"
[ "$mem_mb" -lt 1000 ] && log "note: below 1 GB RAM only light agent turns fit; give the service 1 GB or more for Claude Code or Codex"

# ── 4. Agent CLIs by volume size ───────────────────────────────────────────────────────────────
# Upstream installs every agent CLI into the data volume on first start (its default set needs
# several GB). A Free or Trial volume is 0.5 GB, so pick a set that fits, unless HR_BACKENDS is set.
mkdir -p "$DATA_DIR"
vol_mb="$(df -Pm "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $2}')"
is_uint "$vol_mb" || vol_mb=0
if [ -z "${HR_BACKENDS:-}" ]; then
  if   [ "$vol_mb" -lt 1500 ];  then HR_BACKENDS="opencode"
  elif [ "$vol_mb" -lt 4000 ];  then HR_BACKENDS="claude,codex,opencode,pi"
  else HR_BACKENDS="claude,codex,hermes,pi,opencode"
  fi
  log "agents: ${vol_mb} MB volume -> HR_BACKENDS=$HR_BACKENDS (set HR_BACKENDS to choose your own)"
else
  log "agents: HR_BACKENDS=$HR_BACKENDS (set by you; volume ${vol_mb} MB)"
fi
export HR_BACKENDS

# ── 5. Plain provider keys -> upstream's environment connections ──────────────────────────────
# Keys added in the console (account menu > Bring your own key) are stored encrypted on the volume
# and are tried first; these are the fallback.
conns=()
add_conn() {  # <plain variable> <provider id>
  local key="${!1:-}" var="HR_SECRET_GLOBAL_HARNESS_CONN_$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
  unset "$1"
  [ -n "${key//[[:space:]]/}" ] || return 0
  if [ -n "${!var:-}" ]; then log "providers: $var is set, so $1 was not used"; return 0; fi
  export "$var=$(K="$key" N="$2" "$PY" -I -c 'import json,os; print(json.dumps({"name":os.environ["N"],"provider":os.environ["N"],"api_key":os.environ["K"].strip()}))')"
  conns+=("$2")
}
add_conn ANTHROPIC_API_KEY anthropic
add_conn OPENAI_API_KEY openai
add_conn OPENROUTER_API_KEY openrouter
if [ "${#conns[@]}" -gt 0 ]; then
  chain="$(printf '%s\n' "${conns[@]}" | "$PY" -I -c 'import json,sys; print(json.dumps({"chain": sys.stdin.read().split()}))')"
  for b in ${HR_BACKENDS//,/ }; do
    pv="HR_SECRET_GLOBAL_HARNESS_POLICY_$(printf '%s' "${b//-/_}" | tr '[:lower:]' '[:upper:]')"
    [ -n "${!pv:-}" ] || export "$pv=$chain"
  done
  log "providers: ${conns[*]} from variables"
else
  log "providers: no key variable set; add one in the console (account menu > Bring your own key)"
fi

# ── 6. Run upstream; an unexpected stop must exit non-zero so Railway restarts it ─────────────
/app/entrypoint.sh "$@" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null; wait "$child"; exit 143' TERM INT
wait "$child"; st=$?
if [ "$st" -eq 0 ]; then
  log "HarnessRouter stopped with status 0; exiting 1 so Railway's restart policy brings it back"
  st=1
fi
exit "$st"

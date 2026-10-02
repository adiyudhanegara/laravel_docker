#!/usr/bin/env bash
set -Euo pipefail

cd "${APP_HOME:-/app}"
umask 002

fpm_pid=
vite_pid=
stopping=

start_fpm() {
  php-fpm &
  fpm_pid=$!
}

vite_command() {
  if [[ -f pnpm-lock.yaml ]]; then
    echo "corepack pnpm run dev"
  elif [[ -f yarn.lock ]]; then
    echo "corepack yarn dev"
  else
    echo "npm run dev"
  fi
}

# Vite only starts when compose publishes a port for it (VITE_PORT) and the
# project has a "dev" script with its dependencies installed.
start_vite() {
  vite_pid=
  [[ -n "${VITE_PORT:-}" ]] || return 0
  [[ -f package.json ]] && grep -q '"dev"[[:space:]]*:' package.json || return 0

  if [[ ! -d node_modules ]]; then
    echo "starter: node_modules is missing; install the frontend dependencies, then run 'reload'." >&2
    return 0
  fi

  rm -f public/hot
  # LARAVEL_SAIL makes laravel-vite-plugin listen on 0.0.0.0:$VITE_PORT and
  # advertise http://localhost:$VITE_PORT, which is what the browser on the
  # host can reach. It is scoped to Vite so PHP never sees it. setsid gives
  # Vite its own process group so the whole tree can be stopped on reload.
  LARAVEL_SAIL=1 setsid $(vite_command) &
  vite_pid=$!
}

stop_vite() {
  [[ -n "$vite_pid" ]] || return 0
  kill -- "-$vite_pid" 2>/dev/null
  wait "$vite_pid" 2>/dev/null
  vite_pid=
  rm -f public/hot
}

reload_services() {
  echo "starter: reloading PHP-FPM and Vite"
  kill -USR2 "$fpm_pid"
  stop_vite
  start_vite
}

shutdown() {
  stopping=1
  stop_vite
  kill -QUIT "$fpm_pid" 2>/dev/null
}

trap reload_services USR1 USR2
trap shutdown TERM INT QUIT

# The banner only prints for interactive shells, so mark this one as such.
[[ -f /usr/local/bin/motd.sh ]] && ( PS1=1; source /usr/local/bin/motd.sh )

start_fpm
start_vite

# wait returns early whenever a trapped signal arrives, so keep waiting until
# PHP-FPM itself is gone; the container lives and dies with it.
status=0
while kill -0 "$fpm_pid" 2>/dev/null; do
  wait "$fpm_pid"
  status=$?
done

stop_vite
[[ -n "$stopping" ]] && exit 0
exit "$status"

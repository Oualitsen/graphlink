#!/usr/bin/env bash
# Usage:
#   server.sh start <name> <port> -- <command...>   (run from the server directory)
#   server.sh stop  <name>
# State lives in the current directory: .server.pid (process-group id), .server.log.
# Only the process group we started is ever killed. A busy port we do not own is an
# error, unless FORCE_KILL_PORT=1.
set -u

READY_TIMEOUT="${READY_TIMEOUT:-300}"
PID_FILE=.server.pid
LOG_FILE=.server.log

group_alive() { kill -0 -- "-$1" 2>/dev/null; }

kill_group() {
  local pgid=$1
  group_alive "$pgid" || return 0
  kill -TERM -- "-$pgid" 2>/dev/null
  for _ in $(seq 1 20); do
    group_alive "$pgid" || return 0
    sleep 0.5
  done
  kill -KILL -- "-$pgid" 2>/dev/null
}

port_owners() { lsof -ti "tcp:$1" -sTCP:LISTEN 2>/dev/null; }

# Prints the owners still listening after the grace period (nothing when the port is free).
wait_for_port_release() {
  local owners
  for _ in $(seq 1 30); do
    owners=$(port_owners "$1")
    [[ -z $owners ]] && return 0
    sleep 1
  done
  echo "$owners"
}

http_ready() {
  local body
  if [[ -n ${READY_PATH:-} ]]; then
    [[ $(curl -s -o /dev/null --max-time 3 -w '%{http_code}' "http://localhost:$1$READY_PATH") == 200 ]]
    return
  fi
  body=$(curl -s --max-time 3 -X POST -H 'Content-Type: application/json' \
    -d '{"query":"{__typename}"}' "http://localhost:$1/graphql") || return 1
  [[ "$body" == *'"__typename"'* ]]
}

ws_ready() {
  [[ ${SKIP_WS:-0} == 1 ]] && return 0
  curl -s -i -N --max-time 2 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    -H 'Sec-WebSocket-Protocol: graphql-transport-ws' \
    "http://localhost:$1/graphql" 2>/dev/null | head -1 | grep -q ' 101'
}

stop() {
  if [[ -f $PID_FILE ]]; then
    kill_group "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
  fi
}

start() {
  local name=$1 port=$2
  shift 2
  [[ ${1:-} == -- ]] && shift
  stop

  # A previous server may still be shutting down: Gradle's bootRun JVM is stopped by the daemon, after our group is gone.
  local owners
  if [[ ${FORCE_KILL_PORT:-0} == 1 ]]; then owners=$(port_owners "$port"); else owners=$(wait_for_port_release "$port"); fi
  if [[ -n $owners ]]; then
    if [[ ${FORCE_KILL_PORT:-0} == 1 ]]; then
      echo "$owners" | xargs kill -9 2>/dev/null
      sleep 1
    else
      echo "$name: port $port is held by pid(s) $(echo $owners | tr '\n' ' ') that this script did not start." >&2
      echo "Stop them, or rerun with FORCE_KILL_PORT=1." >&2
      exit 1
    fi
  fi

  set -m
  "$@" >"$LOG_FILE" 2>&1 &
  local pid=$!
  set +m
  echo "$pid" >"$PID_FILE"

  echo "$name: waiting for port $port (log: $PWD/$LOG_FILE)"
  local deadline=$((SECONDS + READY_TIMEOUT))
  until http_ready "$port" && ws_ready "$port"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$name: process exited before it was ready. Last log lines:" >&2
      tail -n 40 "$LOG_FILE" >&2
      rm -f "$PID_FILE"
      exit 1
    fi
    if ((SECONDS >= deadline)); then
      echo "$name: not ready after ${READY_TIMEOUT}s. Last log lines:" >&2
      tail -n 40 "$LOG_FILE" >&2
      stop
      exit 1
    fi
    sleep 1
  done
  echo "$name: ready on port $port"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  stop) stop ;;
  *) echo "usage: $0 start <name> <port> -- <cmd...> | stop" >&2; exit 2 ;;
esac

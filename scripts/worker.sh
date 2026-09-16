#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compose_file="${repo_root}/compose.yaml"
docker_socket="/run/user/$(id -u)/docker.sock"

usage() {
  echo "Usage: $0 pair <https://sowhat-site> | login | start | stop | status | logs" >&2
}

action="${1:-}"
case "${action}" in
  pair)
    if [[ $# -ne 2 ]]; then
      usage
      exit 2
    fi
    ;;
  login | start | stop | status | logs)
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ ! -S "${docker_socket}" ]]; then
  echo "Missing rootless Docker socket ${docker_socket}; run setup-host.sh first." >&2
  exit 3
fi

docker_socket_gid="$(stat -c '%g' "${docker_socket}")"
if [[ ! "${docker_socket_gid}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Could not resolve the rootless Docker socket group; rerun the host setup." >&2
  exit 3
fi

export DOCKER_HOST="unix://${docker_socket}"
export TASK_WORKER_DOCKER_SOCKET_PATH="${docker_socket}"
export TASK_WORKER_DOCKER_SOCKET_GID="${docker_socket_gid}"
compose=(docker compose -f "${compose_file}")

case "${action}" in
  pair)
    site_url="$2"
    if [[ -t 0 ]]; then
      read -r -s -p "Paste the one-time pairing code: " pairing_code
      echo >&2
    else
      IFS= read -r pairing_code
    fi
    if [[ -z "${pairing_code}" ]]; then
      echo "The pairing code cannot be empty." >&2
      exit 3
    fi
    "${compose[@]}" pull
    "${compose[@]}" run --rm task-worker-state-init
    printf '%s\n' "${pairing_code}" | "${compose[@]}" run --rm --no-deps -T \
      --entrypoint node task-worker dist/pair.js "${site_url}"
    unset pairing_code
    ;;
  login)
    "${compose[@]}" pull
    "${compose[@]}" run --rm task-worker-state-init
    "${compose[@]}" run --rm --no-deps --entrypoint \
      /app/node_modules/.bin/codex \
      task-worker -c 'cli_auth_credentials_store="file"' login --device-auth
    ;;
  start)
    "${compose[@]}" pull
    "${compose[@]}" up -d --no-build
    "${compose[@]}" ps
    ;;
  stop)
    "${compose[@]}" stop task-worker
    ;;
  status)
    "${compose[@]}" ps
    ;;
  logs)
    "${compose[@]}" logs --tail 200 -f task-worker
    ;;
esac

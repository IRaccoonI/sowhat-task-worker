#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compose_file="${repo_root}/compose.yaml"
env_file="${SOWHAT_TASK_WORKER_ENV_FILE:-${HOME}/.config/sowhat/task-worker.env}"
docker_socket="/run/user/$(id -u)/docker.sock"

usage() {
  echo "Usage: $0 <bootstrap|start|stop|status|logs>" >&2
}

action="${1:-}"
if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

case "${action}" in
  bootstrap | start | stop | status | logs) ;;
  *)
    usage
    exit 2
    ;;
esac
if [[ ! -f "${env_file}" ]]; then
  echo "Missing ${env_file}; copy .env.example and fill it first." >&2
  exit 3
fi
env_mode="$(stat -c '%a' "${env_file}")"
if [[ "${env_mode}" != "600" ]]; then
  echo "${env_file} must have mode 0600; found ${env_mode}." >&2
  exit 3
fi
if [[ ! -S "${docker_socket}" ]]; then
  echo "Missing rootless Docker socket ${docker_socket}; run setup-host.sh first." >&2
  exit 3
fi

export DOCKER_HOST="unix://${docker_socket}"
export TASK_WORKER_DOCKER_SOCKET_PATH="${docker_socket}"
compose=(docker compose --env-file "${env_file}" -f "${compose_file}")

case "${action}" in
  bootstrap)
    "${compose[@]}" pull
    "${compose[@]}" up -d --no-build
    "${compose[@]}" exec task-worker \
      /app/node_modules/.bin/codex \
      -c 'cli_auth_credentials_store="file"' login --device-auth
    "${compose[@]}" restart task-worker
    "${compose[@]}" exec task-worker \
      /app/node_modules/.bin/codex \
      -c 'cli_auth_credentials_store="file"' login status
    "${compose[@]}" ps
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

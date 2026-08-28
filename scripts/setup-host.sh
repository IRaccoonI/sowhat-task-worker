#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this one-time host setup with sudo: sudo $0" >&2
  exit 2
fi

operator_user="${SUDO_USER:-}"
if [[ -z "${operator_user}" || "${operator_user}" == "root" ]]; then
  echo "Run this script with sudo from the dedicated non-root operator account." >&2
  exit 2
fi
if [[ ! "${operator_user}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Unsupported operator account name." >&2
  exit 2
fi

if [[ ! -r /etc/os-release ]]; then
  echo "This setup requires Ubuntu 24.04." >&2
  exit 3
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
  echo "This setup is pinned to Ubuntu 24.04; found ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
  exit 3
fi

operator_uid="$(id -u "${operator_user}")"
operator_home="$(getent passwd "${operator_user}" | cut -d: -f6)"
runtime_dir="/run/user/${operator_uid}"
docker_socket="${runtime_dir}/docker.sock"

apt-get install -y uidmap

install -m 0644 "${repo_root}/apparmor/bwrap-userns-restrict" \
  /etc/apparmor.d/bwrap-userns-restrict
install -m 0644 "${repo_root}/apparmor/sowhat-task-runner" \
  /etc/apparmor.d/sowhat-task-runner
apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
apparmor_parser -r /etc/apparmor.d/sowhat-task-runner

loginctl enable-linger "${operator_user}"
systemctl start "user@${operator_uid}.service"

if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
  echo "Docker rootless extras are missing. Install the official Docker Engine packages, then rerun." >&2
  exit 3
fi

sudo -u "${operator_user}" env \
  HOME="${operator_home}" \
  XDG_RUNTIME_DIR="${runtime_dir}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
  dockerd-rootless-setuptool.sh install --force

for _ in {1..15}; do
  [[ -S "${docker_socket}" ]] && break
  sleep 1
done
if [[ ! -S "${docker_socket}" ]]; then
  echo "Rootless Docker did not create ${docker_socket}. Check the user Docker service." >&2
  exit 4
fi

security_options="$(sudo -u "${operator_user}" env DOCKER_HOST="unix://${docker_socket}" \
  docker info --format '{{json .SecurityOptions}}')"
if [[ "${security_options}" != *rootless* ]]; then
  echo "The new Docker daemon did not report rootless mode." >&2
  exit 4
fi

echo "Task-worker host setup is ready for ${operator_user} (${docker_socket})."

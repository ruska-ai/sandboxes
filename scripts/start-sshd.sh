#!/usr/bin/env bash
set -euo pipefail

if [ -S /var/run/docker.sock ]; then
  sock_gid="$(stat -c '%g' /var/run/docker.sock)"
  group_name="$(getent group "${sock_gid}" | cut -d: -f1 || true)"

  if [ -z "${group_name}" ]; then
    group_name="hostdocker"
    groupadd -g "${sock_gid}" "${group_name}"
  fi

  usermod -aG "${group_name}" "${DEV_USERNAME}"
fi

exec /usr/sbin/sshd -D

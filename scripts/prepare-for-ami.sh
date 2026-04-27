#!/usr/bin/env bash
#
# Pre-bake cleanup. Run on a known-good instance immediately before
# stopping it and creating an AMI. Strips environment-specific state
# (deployed app, host keys, machine-id, logs, shell history, cloud-init
# state) so the resulting AMI is reusable for staging, production, or
# production-green.
#
# Usage (logged in as julian):
#   sudo bash ~/bps-setup/scripts/prepare-for-ami.sh
#
# Idempotent — safe to re-run if you abort partway through.

SCRIPT_START=${SECONDS}
SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOTAL_STEPS=9

. "${SETUP_ROOT}/lib/common.sh"

trap 'rc=$?
  if (( rc == 0 )); then
    step_summary
    echo
    echo "Ready to snapshot. Stop the instance from the AWS console (or"
    echo "\`aws ec2 stop-instances\`), then \`aws ec2 create-image\`."
  else
    printf "\n!!! prepare-for-ami.sh failed in step %d/%d after %s !!!\n" \
      "${STEP_NUM}" "${TOTAL_STEPS}" \
      "$(fmt_duration $((SECONDS - SCRIPT_START)))" >&2
  fi' EXIT

# 1. Stop and disable per-stage sidekiq instances so they don't auto-start
#    on the next boot (production launches will enable their own
#    sidekiq@<env> after the first cap deploy).
step_start "Stop and disable sidekiq instances"
mapfile -t SIDEKIQ_UNITS < <(systemctl list-units --all --no-legend 'sidekiq@*' \
  | awk '{print $1}')
for unit in "${SIDEKIQ_UNITS[@]}"; do
  [[ -z ${unit} ]] && continue
  systemctl stop "${unit}" || true
  systemctl disable "${unit}" || true
done

# 2. Wipe the deployed app tree. /var/www/bpsd9 itself stays (julian:webapp,
#    mode 2775) so the next cap deploy lands cleanly.
step_start "Remove deployed app tree under ${APP_ROOT}"
shopt -s nullglob
for entry in "${APP_ROOT}"/*; do
  rm -rf "${entry}"
done
shopt -u nullglob

# 3. Clear shell history and user-level caches that accumulate during
#    debugging (bundler, gem, yarn, npm, gh, awscli history).
step_start "Clear shell history and user caches"
for home in /home/* /root; do
  [[ -d ${home} ]] || continue
  rm -f \
    "${home}/.bash_history" \
    "${home}/.lesshst" \
    "${home}/.viminfo" \
    "${home}/.python_history" \
    "${home}/.wget-hsts"
  rm -rf \
    "${home}/.bundle/cache" \
    "${home}/.gem/cache" \
    "${home}/.cache" \
    "${home}/.yarn/cache" \
    "${home}/.npm" \
    "${home}/.local/share/gh"
done

# 4. cloud-init: reset state so first boot of the next instance re-runs
#    network/instance-id setup. Without this you get "this hostname is
#    already configured" weirdness on derived launches.
step_start "Reset cloud-init state"
if command -v cloud-init >/dev/null; then
  cloud-init clean --logs --seed
fi

# 5. SSH host keys. If we don't remove these, every instance launched
#    from this AMI presents the same host fingerprint — clients trusting
#    one would silently trust impersonators. cloud-init / the ssh
#    package's first-boot generator regenerates them on next boot.
step_start "Regenerate SSH host keys on next boot"
rm -f /etc/ssh/ssh_host_*

# 6. machine-id. Used by systemd, journald, dbus to identify this host;
#    must be unique per instance. systemd will regenerate on first boot
#    when the file is empty (NOT missing).
step_start "Reset machine-id"
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# 7. Truncate accumulated logs and rotate the journal. install.sh did
#    this once at AMI build; debug sessions since then have refilled it.
step_start "Truncate logs and vacuum journal"
find /var/log -type f \( -name '*.log' -o -name '*.[0-9]' -o -name '*.gz' \
  -o -name 'syslog*' -o -name 'auth.log*' \) -exec truncate -s 0 {} +
journalctl --rotate >/dev/null
journalctl --vacuum-time=1s >/dev/null

# 8. Remove the temporary `ubuntu` user. Skip if anyone is logged in as
#    ubuntu right now (you don't want to yank the rug out from under the
#    operator). Run this script as julian, not as ubuntu.
step_start "Remove the ubuntu user"
if id -u ubuntu >/dev/null 2>&1; then
  if who | awk '{print $1}' | grep -qx ubuntu; then
    echo "ubuntu has an active login session; skipping removal." >&2
    echo "Re-run this script while logged in as julian." >&2
  else
    deluser --remove-home ubuntu
    rm -f /etc/sudoers.d/90-cloud-init-users  # AWS default ubuntu sudoer drop-in
  fi
else
  echo "ubuntu user already removed."
fi

# 9. apt cleanup so the snapshot is small.
step_start "Clean apt caches"
apt-get autoremove -y
apt-get clean

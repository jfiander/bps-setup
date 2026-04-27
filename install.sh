#!/usr/bin/env bash
#
# bpsd9 AMI provisioning script.
#
# Usage: sudo bash install.sh
#
# Run on a clean Ubuntu LTS server image. Idempotent — safe to re-run.
# The user provisions the EC2 instance, opens SSH, drops authorized_keys for
# the deploy / julian users, and tests a Capistrano deploy after this completes.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "install.sh must be run as root (sudo bash install.sh)" >&2
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release; then
  echo "install.sh targets Ubuntu only" >&2
  exit 1
fi

UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

RBENV_ROOT=/opt/rbenv
RUBY_VERSIONS=(2.7.4 3.3.11 4.0.3)
RUBY_GLOBAL=3.3.11
NODE_MAJOR=22
APP_NAME=bpsd9
APP_ROOT=/var/www/${APP_NAME}

export DEBIAN_FRONTEND=noninteractive

#
# 1. Preflight: refresh apt, install nala, switch subsequent installs to nala.
#
apt-get update -y
apt-get install -y nala

pkg_install() { nala install -y --no-install-recommends "$@"; }

#
# 2. Base packages (build deps for ruby + native gems, mysql client, image libs).
#
pkg_install \
  build-essential git curl ca-certificates gnupg dirmngr lsb-release pkg-config \
  autoconf bison \
  libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libgdbm-dev \
  libncurses5-dev libxml2-dev libxslt1-dev \
  tzdata logrotate \
  imagemagick libvips \
  libmysqlclient-dev default-mysql-client

#
# 3. Users.
#
#    deploy — Capistrano target; locked password, no sudo.
#    julian — admin; locked password, NOPASSWD sudo.
#
ensure_user() {
  local user=$1 sudoer=$2
  if ! id -u "${user}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "${user}"
  fi
  passwd -l "${user}" >/dev/null
  install -d -m 0700 -o "${user}" -g "${user}" "/home/${user}/.ssh"
  if [[ "${sudoer}" == "sudo" ]]; then
    usermod -aG sudo "${user}"
  fi
}

ensure_user deploy nosudo
ensure_user julian sudo

install -m 0440 /dev/stdin /etc/sudoers.d/julian <<'EOF'
julian ALL=(ALL) NOPASSWD: ALL
EOF
visudo -cf /etc/sudoers.d/julian >/dev/null

# Authorize public keys for julian. Required so you can log in as julian
# after sshd is hardened to pubkey-only in step 4.
#
# Sources, deduped:
#   1. /home/ubuntu/.ssh/authorized_keys (so the AWS default key Just Works
#      for julian too)
#   2. an optional pasted key from this prompt
#
# Re-runnable: existing keys aren't re-added.
JULIAN_AUTH_KEYS=/home/julian/.ssh/authorized_keys
touch "${JULIAN_AUTH_KEYS}"

append_pubkey() {
  local line=$1
  [[ -z ${line} || ${line} =~ ^[[:space:]]*# ]] && return 0
  grep -qxF "${line}" "${JULIAN_AUTH_KEYS}" || echo "${line}" >> "${JULIAN_AUTH_KEYS}"
}

UBUNTU_AUTH_KEYS=/home/ubuntu/.ssh/authorized_keys
if [[ -s ${UBUNTU_AUTH_KEYS} ]]; then
  while IFS= read -r line; do append_pubkey "${line}"; done < "${UBUNTU_AUTH_KEYS}"
fi

echo
echo "==> Paste an additional public SSH key for julian, or blank line to skip."
echo "    (julian already accepts /home/ubuntu/.ssh/authorized_keys.)"
read -r -p "julian pubkey: " JULIAN_PUBKEY
append_pubkey "${JULIAN_PUBKEY}"

chown julian:julian "${JULIAN_AUTH_KEYS}"
chmod 0600 "${JULIAN_AUTH_KEYS}"

#
# 4. Harden sshd: keys only, no PAM password auth, no root login.
#
install -m 0644 /dev/stdin /etc/ssh/sshd_config.d/99-bpsd9.conf <<'EOF'
# Managed by install.sh — bpsd9 AMI hardening.
#
# UsePAM stays yes: with UsePAM no, sshd's allowed_user() rejects any
# account whose shadow password starts with '!' (locked), which includes
# the deploy/julian users created by this script — they'd never be able
# to log in by pubkey. Password auth is still off because all three
# password-bearing methods are explicitly disabled below.
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
PermitRootLogin no
PubkeyAuthentication yes
EOF
sshd -t
systemctl reload ssh

#
# 5. App directory.
#
install -d -o deploy -g deploy -m 0755 "${APP_ROOT}"

#
# 6. Redis (sidekiq backend, on-instance).
#
pkg_install redis-server
systemctl enable --now redis-server

#
# 7. nginx + Phusion Passenger from the official Phusion apt repo.
#
install -d -m 0755 /etc/apt/keyrings
# Always refresh. Two sources, merged into one keyring:
#   1. Phusion's auto-key bundle URL (canonical)
#   2. The current release-signing key fetched directly from a public
#      keyserver, in case the bundle is lagging behind a key rotation.
# Keep this list in sync with whatever Phusion is currently using to sign
# the Release.gpg for the active Ubuntu codename.
PHUSION_KEY_IDS=(D870AB033FB45BD1 561F9B9CAC40B2F7)
PHUSION_KEYRING=/etc/apt/keyrings/phusion.gpg

curl -fsSL https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key.txt \
  | gpg --dearmor --yes -o "${PHUSION_KEYRING}"

# Use a throwaway GNUPGHOME so we don't depend on /root/.gnupg existing
# and don't leave dirmngr state behind.
GPG_TMP=$(mktemp -d)
chmod 700 "${GPG_TMP}"
for ks in hkps://keys.openpgp.org hkp://keyserver.ubuntu.com:80; do
  if gpg --homedir "${GPG_TMP}" \
       --no-default-keyring --keyring "${PHUSION_KEYRING}" \
       --keyserver "${ks}" --recv-keys "${PHUSION_KEY_IDS[@]}"; then
    break
  fi
done
gpgconf --homedir "${GPG_TMP}" --kill all 2>/dev/null || true
rm -rf "${GPG_TMP}"
chmod 0644 "${PHUSION_KEYRING}"
cat >/etc/apt/sources.list.d/passenger.list <<EOF
deb [signed-by=/etc/apt/keyrings/phusion.gpg] https://oss-binaries.phusionpassenger.com/apt/passenger ${UBUNTU_CODENAME} main
EOF
apt-get update -y
pkg_install nginx libnginx-mod-http-passenger

OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 0644 "${OPS_DIR}/nginx/bpsd9.conf" /etc/nginx/sites-available/bpsd9.conf
ln -sf /etc/nginx/sites-available/bpsd9.conf /etc/nginx/sites-enabled/bpsd9.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

#
# 8. System rbenv at /opt/rbenv, group-writable so deploy can install gems.
#
if [[ ! -d ${RBENV_ROOT} ]]; then
  git clone https://github.com/rbenv/rbenv.git "${RBENV_ROOT}"
fi
if [[ ! -d ${RBENV_ROOT}/plugins/ruby-build ]]; then
  git clone https://github.com/rbenv/ruby-build.git "${RBENV_ROOT}/plugins/ruby-build"
fi
(cd "${RBENV_ROOT}" && git pull --ff-only) || true
(cd "${RBENV_ROOT}/plugins/ruby-build" && git pull --ff-only) || true

chgrp -R staff "${RBENV_ROOT}"
chmod -R g+rwxs "${RBENV_ROOT}"
usermod -aG staff deploy

install -m 0644 /dev/stdin /etc/profile.d/rbenv.sh <<EOF
export RBENV_ROOT=${RBENV_ROOT}
export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:\$PATH
EOF

export RBENV_ROOT
export PATH="${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:${PATH}"
eval "$(rbenv init -)"

#
# 9. Ruby installs (2.7.4 master, 3.3.11 intermediate/global, 4.0.3 edge).
#
for v in "${RUBY_VERSIONS[@]}"; do
  rbenv install -s "${v}"
  # Latest bundler requires Ruby >= 3.2; pin older rubies to the last
  # compatible release.
  IFS=. read -r rb_major rb_minor _ <<<"${v}"
  if (( rb_major < 3 )) || (( rb_major == 3 && rb_minor < 2 )); then
    bundler_args=(-v 2.4.22)
  else
    bundler_args=()
  fi
  RBENV_VERSION="${v}" rbenv exec gem install bundler "${bundler_args[@]}" --no-document
done
rbenv global "${RUBY_GLOBAL}"
rbenv rehash

#
# 10. Node.js (NodeSource) + Yarn (corepack). Frontend will move to React.
#
if ! command -v node >/dev/null || [[ "$(node -v)" != v${NODE_MAJOR}.* ]]; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi
corepack enable
corepack prepare yarn@stable --activate

#
# 11. Sidekiq systemd unit (templated per RAILS_ENV instance: sidekiq@production).
#
install -m 0644 "${OPS_DIR}/sidekiq@.service" /etc/systemd/system/sidekiq@.service
systemctl daemon-reload
# Don't enable/start here — first cap deploy must populate ${APP_ROOT}/current.
# After first deploy, run: systemctl enable --now sidekiq@production

#
# 12. julian's GitHub access + personal repos.
#
#     - install gh (GitHub CLI) from the official apt repo
#     - generate an ed25519 SSH key for julian
#     - try `gh auth login` interactively, then `gh ssh-key add`; on any
#       failure, print the pubkey + URL and pause so it can be added by hand
#     - clone jfiander/bpsd9-ssh into ~julian/repos and symlink jaws
#     - copy config/ops/bash-env/ into ~julian (populate that dir with the
#       desired dotfiles in this repo before running install.sh)
#
install -d -m 0755 /etc/apt/keyrings
if [[ ! -s /etc/apt/keyrings/githubcli.gpg ]]; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli.gpg
  chmod 0644 /etc/apt/keyrings/githubcli.gpg
fi
cat >/etc/apt/sources.list.d/github-cli.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main
EOF
apt-get update -y
pkg_install gh

JULIAN_HOME=/home/julian
JULIAN_SSH_KEY="${JULIAN_HOME}/.ssh/github"

if [[ ! -s ${JULIAN_SSH_KEY} ]]; then
  sudo -u julian -H ssh-keygen -t ed25519 -N '' \
    -C "julian@$(hostname)" -f "${JULIAN_SSH_KEY}"
fi
sudo -u julian -H ssh-keyscan -t ed25519,ecdsa,rsa github.com \
  >> "${JULIAN_HOME}/.ssh/known_hosts" 2>/dev/null || true
sudo -u julian -H bash -c "sort -u -o ${JULIAN_HOME}/.ssh/known_hosts ${JULIAN_HOME}/.ssh/known_hosts"

KEY_TITLE="julian@$(hostname) ($(date +%Y-%m-%d))"

if sudo -u julian -H gh auth status >/dev/null 2>&1; then
  echo "gh already authenticated for julian; skipping login."
else
  echo
  echo "==> Authenticating julian with GitHub (interactive)."
  echo "    Choose: GitHub.com / HTTPS / Login with a web browser."
  echo "    If you skip this (Ctrl-C), the key will be added manually below."
  if ! sudo -u julian -H gh auth login --git-protocol https --hostname github.com --web; then
    echo "gh auth login skipped or failed; falling back to manual key entry."
  fi
fi

if sudo -u julian -H gh auth status >/dev/null 2>&1; then
  PUB_KEY_BODY=$(awk '{print $1" "$2}' "${JULIAN_SSH_KEY}.pub")
  if sudo -u julian -H gh ssh-key list 2>/dev/null | grep -qF "${PUB_KEY_BODY}"; then
    echo "julian's public key is already registered on GitHub; skipping."
  else
    sudo -u julian -H gh ssh-key add "${JULIAN_SSH_KEY}.pub" --title "${KEY_TITLE}"
  fi
else
  echo
  echo "==> Add this key to https://github.com/settings/ssh/new (title: ${KEY_TITLE}):"
  echo
  cat "${JULIAN_SSH_KEY}.pub"
  echo
  read -r -p "Press Enter once the key is added on GitHub..." _
fi

sudo -u julian -H install -d -m 0755 "${JULIAN_HOME}/repos"

if [[ ! -d ${JULIAN_HOME}/repos/bpsd9-ssh ]]; then
  sudo -u julian -H git clone git@github.com:jfiander/bpsd9-ssh.git \
    "${JULIAN_HOME}/repos/bpsd9-ssh"
else
  sudo -u julian -H git -C "${JULIAN_HOME}/repos/bpsd9-ssh" pull --ff-only || true
fi

JAWS_SRC="${JULIAN_HOME}/repos/bpsd9-ssh/jaws/run.rb"
if [[ -f ${JAWS_SRC} ]]; then
  chmod +x "${JAWS_SRC}"
  ln -sf "${JAWS_SRC}" /usr/local/bin/jaws
else
  echo "warning: ${JAWS_SRC} not found; skipping jaws symlink." >&2
fi

# Copy bash-env files (dotfiles + regular files) from this repo into julian's home.
BASH_ENV_SRC="${OPS_DIR}/bash-env"
if [[ ! -d ${BASH_ENV_SRC} ]]; then
  echo "warning: ${BASH_ENV_SRC} not found; skipping bash-env copy." >&2
else
  shopt -s dotglob nullglob
  copied=0
  for f in "${BASH_ENV_SRC}"/*; do
    base=$(basename "${f}")
    [[ ${base} == .git || ${base} == .gitkeep || ${base} == README.md ]] && continue
    if [[ -d ${f} ]]; then
      # Merge directory contents into the existing target dir
      # (so e.g. bash-env/.ssh/config lands at ~/.ssh/config, not ~/.ssh/.ssh/config).
      install -d -o julian -g julian "${JULIAN_HOME}/${base}"
      cp -a "${f}/." "${JULIAN_HOME}/${base}/"
    else
      cp -a "${f}" "${JULIAN_HOME}/${base}"
    fi
    copied=$((copied + 1))
  done
  shopt -u dotglob nullglob
  echo "bash-env: copied ${copied} item(s) into ${JULIAN_HOME}."
  chown -R julian:julian "${JULIAN_HOME}"
fi

#
# 13. Logrotate for app logs.
#
install -m 0644 /dev/stdin /etc/logrotate.d/${APP_NAME} <<EOF
${APP_ROOT}/shared/log/*.log {
  weekly
  missingok
  rotate 8
  compress
  delaycompress
  notifempty
  copytruncate
  su deploy deploy
}
EOF

#
# 14. Cleanup so the resulting AMI is small.
#
apt-get autoremove -y
apt-get clean
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +

echo "install.sh complete. Add SSH keys for deploy + julian, then run cap deploy."

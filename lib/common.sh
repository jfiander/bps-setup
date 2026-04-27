# Shared environment for install.sh and individual step scripts.
#
# Sourced by ../install.sh and (optionally) by ../steps/*.sh when
# running a single step manually:
#
#   sudo bash -c '. lib/common.sh && . steps/12-julian-github.sh'

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
  echo "must be run as root (sudo)" >&2
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release; then
  echo "targets Ubuntu only" >&2
  exit 1
fi

UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

# Path / version constants. Keep this list in sync with the rest of the
# tree; step files only consume these, never redefine them.
RBENV_ROOT=/opt/rbenv
RUBY_VERSIONS=(2.7.4 3.3.11 4.0.3)
RUBY_GLOBAL=3.3.11
NODE_MAJOR=22
APP_NAME=bpsd9
APP_ROOT=/var/www/${APP_NAME}
JULIAN_HOME=/home/julian
JULIAN_SSH_KEY="${JULIAN_HOME}/.ssh/github"
# GitHub account that owns the private repos this AMI clones (bpsd9-ssh,
# etc.). Used by step 12 to verify gh is logged in as the right user.
EXPECTED_GH_USER=jfiander
PHUSION_KEYRING=/etc/apt/keyrings/phusion.gpg
# Phusion's Release.gpg signing keys. The `auto-software-signing-gpg-key.txt`
# bundle has historically lagged behind rotations, so we also pull these by
# ID from a public keyserver.
PHUSION_KEY_IDS=(D870AB033FB45BD1 561F9B9CAC40B2F7)

# Resolve the setup-repo root (parent of lib/) regardless of how the
# caller invoked us.
OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkg_install() { nala install -y --no-install-recommends "$@"; }

# If rbenv has already been installed (by step 8 or a previous run),
# put it on PATH so later steps can call rbenv/gem/bundle directly.
# This is the difference that lets `sudo bash install.sh 9` work in
# isolation: step 8 also does this, but a single-step invocation skips
# step 8 entirely.
if [[ -x ${RBENV_ROOT}/bin/rbenv ]]; then
  export RBENV_ROOT
  export PATH="${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:${PATH}"
  eval "$(rbenv init -)"
fi

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

# --- Status banner -----------------------------------------------------
#
# install.sh seeds SCRIPT_START before sourcing this file; standalone
# step invocations get their own clock.
SCRIPT_START=${SCRIPT_START:-${SECONDS}}
TOTAL_STEPS=${TOTAL_STEPS:-14}
STEP_NUM=${STEP_NUM:-0}

fmt_duration() {
  local s=$1
  printf '%02d:%02d' $((s / 60)) $((s % 60))
}

step_start() {
  local name=$1
  STEP_NUM=$((STEP_NUM + 1))
  STEP_STARTED=${SECONDS}
  printf '\n=== [%d/%d] %s — total %s ===\n' \
    "${STEP_NUM}" "${TOTAL_STEPS}" "${name}" \
    "$(fmt_duration $((SECONDS - SCRIPT_START)))"
}

step_summary() {
  printf '\n=== install.sh complete: %d/%d steps, total %s ===\n' \
    "${STEP_NUM}" "${TOTAL_STEPS}" \
    "$(fmt_duration $((SECONDS - SCRIPT_START)))"
}

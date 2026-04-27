# julian's GitHub access + personal repos.
#
#   - install gh (GitHub CLI) from the official apt repo
#   - generate an ed25519 SSH key for julian
#   - try `gh auth login` interactively, then `gh ssh-key add`; on any
#     failure, print the pubkey + URL and pause so it can be added by hand
#   - clone jfiander/bpsd9-ssh into ~julian/repos and symlink jaws
#   - copy bash-env/ into ~julian (populate that dir with the desired
#     dotfiles in this repo before running install.sh)

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

if [[ ! -s ${JULIAN_SSH_KEY} ]]; then
  sudo -u julian -H ssh-keygen -t ed25519 -N '' \
    -C "julian@$(hostname)" -f "${JULIAN_SSH_KEY}"
fi
# Append + dedupe github.com host keys. The redirection has to happen
# inside the sudo subshell so julian owns the file (otherwise root writes
# it and the next sort fails with EACCES).
sudo -u julian -H bash -c "
  ssh-keyscan -t ed25519,ecdsa,rsa github.com >> ${JULIAN_HOME}/.ssh/known_hosts 2>/dev/null || true
  sort -u -o ${JULIAN_HOME}/.ssh/known_hosts ${JULIAN_HOME}/.ssh/known_hosts
"

KEY_TITLE="julian@$(hostname) ($(date +%Y-%m-%d))"

# Run gh from julian's home — sudo preserves cwd, and julian can't stat
# /home/ubuntu/* (mode 0750), so anything that calls back into git from
# the script's cwd fails with EACCES.
gh_julian() { sudo -u julian -H bash -c 'cd ~ && '"$*"; }

if gh_julian 'gh auth status' >/dev/null 2>&1; then
  echo "gh already authenticated for julian; skipping login."
else
  echo
  echo "==> Authenticating julian with GitHub (interactive)."
  echo "    Choose: GitHub.com / HTTPS / Login with a web browser."
  echo "    If you skip this (Ctrl-C), the key will be added manually below."
  # admin:public_key scope is needed for `gh ssh-key add` below.
  if ! gh_julian 'gh auth login --git-protocol https --hostname github.com --web --scopes admin:public_key'; then
    echo "gh auth login skipped or failed; falling back to manual key entry."
  fi
fi

if gh_julian 'gh auth status' >/dev/null 2>&1; then
  # Sanity-check the GitHub user before we register an SSH key against
  # them or try to clone private repos. EXPECTED_GH_USER comes from
  # lib/common.sh; override there if the owner of bpsd9-ssh changes.
  AUTHED_GH_USER=$(gh_julian 'gh api user --jq .login')
  echo "gh authenticated as: ${AUTHED_GH_USER}"
  if [[ -n "${EXPECTED_GH_USER:-}" && "${AUTHED_GH_USER}" != "${EXPECTED_GH_USER}" ]]; then
    echo "ERROR: gh is logged in as '${AUTHED_GH_USER}' but '${EXPECTED_GH_USER}' was expected." >&2
    echo "Run: sudo -u julian -H bash -c 'cd ~ && gh auth logout -h github.com' and re-run this step." >&2
    exit 1
  fi

  # Make sure the existing token has admin:public_key (a prior login may
  # have skipped it). `gh auth refresh` would re-prompt the device-code
  # flow even when the scope is already granted, so check first.
  if gh_julian 'gh auth status 2>&1' | grep -qE 'Token scopes:.*admin:public_key'; then
    echo "admin:public_key scope already granted; skipping refresh."
  else
    gh_julian "gh auth refresh -h github.com -s admin:public_key" || true
  fi

  PUB_KEY_BODY=$(awk '{print $1" "$2}' "${JULIAN_SSH_KEY}.pub")
  if gh_julian 'gh ssh-key list' 2>/dev/null | grep -qF "${PUB_KEY_BODY}"; then
    echo "julian's public key is already registered on GitHub; skipping."
  else
    gh_julian "gh ssh-key add ${JULIAN_SSH_KEY}.pub --title '${KEY_TITLE}'"
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

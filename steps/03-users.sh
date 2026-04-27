# deploy — Capistrano target; locked password, no sudo.
# julian — admin; locked password, NOPASSWD sudo.
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

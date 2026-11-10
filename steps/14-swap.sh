# Swap: a cushion for the services under memory pressure, not working memory. Same layout as the
# USPS fleet (/swapfile, swappiness 10). Without it, a Ruby or native-gem compile on a small instance
# leaves the OOM killer picking between the build and the web server.
SWAP_FILE=/swapfile
if swapon --show=NAME --noheadings | grep -qxF "${SWAP_FILE}"; then
  echo "swap: ${SWAP_FILE} already active"
else
  if [[ ! -f ${SWAP_FILE} ]]; then
    # shellcheck disable=SC2153  # SWAP_SIZE is set in lib/common.sh, not a typo of SWAP_FILE
    fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}"
    chmod 0600 "${SWAP_FILE}"
    mkswap "${SWAP_FILE}" > /dev/null
  fi
  swapon "${SWAP_FILE}"
  echo "swap: enabled ${SWAP_FILE}"
fi
grep -qE "^${SWAP_FILE}[[:space:]]" /etc/fstab || echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab

install -m 0644 /dev/stdin /etc/sysctl.d/99-swap.conf <<'EOF'
# Managed by setup/install.sh: only swap under real memory pressure.
vm.swappiness=10
EOF
sysctl -q -p /etc/sysctl.d/99-swap.conf

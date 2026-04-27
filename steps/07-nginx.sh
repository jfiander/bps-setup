# nginx + Phusion Passenger from the official Phusion apt repo.
install -d -m 0755 /etc/apt/keyrings

# Always refresh. Two sources, merged into one keyring:
#   1. Phusion's auto-key bundle URL (canonical)
#   2. The current release-signing key fetched directly from a public
#      keyserver, in case the bundle is lagging behind a key rotation.
curl -fsSL https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key.txt \
  | gpg --dearmor --yes -o "${PHUSION_KEYRING}"

# Throwaway GNUPGHOME so we don't depend on /root/.gnupg existing
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
deb [signed-by=${PHUSION_KEYRING}] https://oss-binaries.phusionpassenger.com/apt/passenger ${UBUNTU_CODENAME} main
EOF
apt-get update -y
pkg_install nginx libnginx-mod-http-passenger

install -m 0644 "${OPS_DIR}/nginx/bpsd9.conf" /etc/nginx/sites-available/bpsd9.conf
ln -sf /etc/nginx/sites-available/bpsd9.conf /etc/nginx/sites-enabled/bpsd9.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

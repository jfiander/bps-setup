# System rbenv at /opt/rbenv, group-writable so deploy can install gems.
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

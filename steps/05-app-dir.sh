# App directory.
#
# Capistrano deploys as julian (admin); sidekiq runs as deploy (service
# isolation). Both need to read/write the same tree, so a shared
# `webapp` group with setgid on the parent is what makes that work:
# files created under here inherit the webapp group automatically.
groupadd -f webapp
usermod -aG webapp julian
usermod -aG webapp deploy

mkdir -p "${APP_ROOT}"
chown julian:webapp "${APP_ROOT}"
chmod 2775 "${APP_ROOT}"

# App directory.
#
# julian is the single app uid: Capistrano deploys as julian, Passenger runs as
# julian (it switches to the owner of current/config/environment.rb), and the
# sidekiq unit is pinned to julian:webapp. The shared `webapp` group exists so
# any additional service can be granted access without another chown pass.
#
# Setgid on the parent propagates the group to new subdirectories, but not the
# group-write bit — that comes from the umask of whoever creates the file.
groupadd -f webapp
usermod -aG webapp julian
usermod -aG webapp deploy

mkdir -p "${APP_ROOT}"
chown julian:webapp "${APP_ROOT}"
chmod 2775 "${APP_ROOT}"

# Repair an already-deployed tree. Capistrano creates shared/ and releases/
# itself, so a box provisioned before the deploy user changed still carries the
# old ownership — most visibly shared/log/*.log, which the previous sidekiq uid
# owned and the new one could not write. Idempotent, so safe on every re-run.
if [[ -d ${APP_ROOT}/shared ]]; then
  chown -R julian:webapp "${APP_ROOT}"

  # Group-write on shared/ only. releases/ is rebuilt by every deploy under the
  # app uid, and application.yml below holds secrets that stay owner-only.
  chmod -R g+w "${APP_ROOT}/shared"
  find "${APP_ROOT}/shared" -type d -exec chmod g+s {} +

  if [[ -f ${APP_ROOT}/shared/config/application.yml ]]; then
    chmod 0600 "${APP_ROOT}/shared/config/application.yml"
  fi
fi

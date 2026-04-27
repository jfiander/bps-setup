# Sidekiq systemd unit (templated per RAILS_ENV instance: sidekiq@production).
install -m 0644 "${OPS_DIR}/sidekiq@.service" /etc/systemd/system/sidekiq@.service
systemctl daemon-reload
# Don't enable/start here — first cap deploy must populate ${APP_ROOT}/current.
# After first deploy, run: systemctl enable --now sidekiq@production

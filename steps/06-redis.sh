# Redis (sidekiq backend, on-instance).
pkg_install redis-server
systemctl enable --now redis-server

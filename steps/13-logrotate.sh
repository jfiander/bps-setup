install -m 0644 /dev/stdin /etc/logrotate.d/${APP_NAME} <<EOF
${APP_ROOT}/shared/log/*.log {
  weekly
  missingok
  rotate 8
  compress
  delaycompress
  notifempty
  copytruncate
  su deploy deploy
}
EOF

# Rotate the app's logs and upload each rotated production log to S3 (see scripts/upload_log_file.sh).
# ifempty keeps the upload script's nightly heartbeat going on days with no requests.
upload_script="${JULIAN_HOME}/sh/upload_log_file.sh"
upload_log="${JULIAN_HOME}/logs/upload_logs.log"
install -d -m 0755 -o julian -g julian "${JULIAN_HOME}/sh" "${JULIAN_HOME}/logs"
install -m 0775 -o julian -g julian "${OPS_DIR}/scripts/upload_log_file.sh" "${upload_script}"
touch "${upload_log}"
chown julian:julian "${upload_log}"

install -m 0644 /dev/stdin "/etc/logrotate.d/${APP_NAME}" <<EOF
${APP_ROOT}/shared/log/*.log {
  daily
  missingok
  rotate 14
  compress
  delaycompress
  ifempty
  copytruncate
  su julian webapp
  postrotate
    ${upload_script} "\$(basename "\$1").1" >> ${upload_log} 2>&1
  endscript
}
EOF

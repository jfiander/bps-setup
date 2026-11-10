# Cleanup so the resulting AMI is small.
apt-get autoremove -y
apt-get clean
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +

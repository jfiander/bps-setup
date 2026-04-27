# Harden sshd: keys only, no PAM password auth, no root login.
install -m 0644 /dev/stdin /etc/ssh/sshd_config.d/99-bpsd9.conf <<'EOF'
# Managed by install.sh — bpsd9 AMI hardening.
#
# UsePAM stays yes: with UsePAM no, sshd's allowed_user() rejects any
# account whose shadow password starts with '!' (locked), which includes
# the deploy/julian users created by this script — they'd never be able
# to log in by pubkey. Password auth is still off because all three
# password-bearing methods are explicitly disabled below.
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
PermitRootLogin no
PubkeyAuthentication yes
EOF
sshd -t
systemctl reload ssh

# bps-setup

Provisioning scripts for the **bpsd9** Rails app on AWS EC2 (Ubuntu LTS).
Run on a clean Ubuntu instance to bake an AMI that can serve any environment
(staging / production) once Capistrano deploys the app.

## What it installs

- Build deps + `nala`
- `deploy` user (Capistrano target, locked password) and `julian` user
  (admin, NOPASSWD sudo, locked password)
- Hardened sshd: pubkey only, no PAM/password auth, no root login
- Redis (sidekiq backend)
- nginx + Phusion Passenger from the official Phusion apt repo
- System rbenv at `/opt/rbenv` (group-writable for `deploy`) with Ruby
  2.7.4, 3.3.11 (global), and 4.0.3
- Node.js 22 + Yarn (via corepack)
- Templated `sidekiq@.service` systemd unit
- GitHub CLI, an ed25519 SSH key for `julian`, and `julian`'s personal
  bash environment from [`bash-env/`](bash-env/)
- `jaws` symlink (`/usr/local/bin/jaws`) from the private
  `jfiander/bpsd9-ssh` repo

The script is idempotent — re-run it after pulling updates.

## Run it

From a fresh EC2 instance, logged in as the default `ubuntu` user with your
key:

```sh
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/jfiander/bps-setup.git ~/bps-setup
sudo bash ~/bps-setup/install.sh
```

The script is interactive at two points:

1. **Paste an additional public key for julian (optional).** Right after
   the user is created, the script seeds
   `/home/julian/.ssh/authorized_keys` from
   `/home/ubuntu/.ssh/authorized_keys` (so the key you launched the
   instance with works for julian immediately) and prompts for an extra
   key. Blank line to accept just the seeded keys.
2. **GitHub login for julian.** The script runs `gh auth login --web` as
   `julian` so it can register the freshly-generated SSH key on GitHub.
   Follow the on-screen one-time code prompt. If you skip, the script
   falls back to printing the public key and pausing while you add it
   manually at <https://github.com/settings/ssh/new>.

## After it finishes

1. Drop `/home/deploy/.ssh/authorized_keys` (Capistrano deploy key — the
   script does not seed this; julian's key is handled by the prompt
   above).
2. Open a second SSH session as `julian` to verify pubkey + sudo work
   **before logging out of `ubuntu`**.
3. Bake the AMI.
4. Launch a new instance, run `cap <stage> deploy` from your workstation.
5. After the first deploy populates `/var/www/bpsd9/current`, enable the
   sidekiq unit per stage:
   ```sh
   sudo systemctl enable --now sidekiq@production
   ```

## Layout

| Path | Purpose |
| --- | --- |
| [`install.sh`](install.sh) | Main provisioning script (run as root) |
| [`nginx/bpsd9.conf`](nginx/bpsd9.conf) | nginx + Passenger site config (port 80; ALB terminates TLS) |
| [`sidekiq@.service`](sidekiq@.service) | Templated systemd unit; instance name is the Rails env |
| [`bash-env/`](bash-env/) | Files copied into `/home/julian/` (dotfiles supported) |

## Notes

- The script does not delete the default `ubuntu` user; remove it manually
  once you've confirmed `julian` works.
- `install.sh` truncates `/var/log/*.log` at the end so the baked AMI is
  small. Comment that line out if running on a long-lived host.
- Anything in [`bash-env/`](bash-env/) is `cp -a`'d on top of `julian`'s
  home each run, so manual edits to those files on the server get
  clobbered on re-run.

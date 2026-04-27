# bash-env

Files placed in this directory are copied into `/home/julian/` by
[../install.sh](../install.sh) (step 12).

Drop in whatever julian wants in `$HOME` — for example `.bashrc`,
`.bash_profile`, `.bash_aliases`, `.inputrc`, `.gitconfig`. Dotfiles are
supported (the copy uses `dotglob`). `README.md`, `.gitkeep`, and `.git` are
skipped.

Source of truth was `jfiander/bash-env`; populate this directory with the
files from that repo (or anything you want baked into the AMI for julian).

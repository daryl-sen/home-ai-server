# Model Switching (27B Dense ↔ 35B-A3B MoE)

A self-contained, portable setup for switching `llama-server` between two models with one command. Switch takes ~20–30s.

This directory is the **source of truth**. Files get deployed to `~/llama-server/` on the VM, where the systemd user unit reads them.

---

## How It Works

A user-level systemd service (under `~/.config/systemd/user/`) runs `llama-server` as your user. The unit reads `~/llama-server/active.conf`, which is a symlink pointing at one of the per-model configs in `~/llama-server/configs/`. The `switch-model` script repoints the symlink and restarts the service.

Because it's a user service, `sudo` is only needed once during initial setup (to enable lingering so the service starts at boot without you logging in). After that, all switching is unprivileged.

```
model-switching/                 (this repo dir — source of truth)
├── configs/
│   ├── 27b.conf                 (fast mode)
│   └── 35b.conf                 (accurate mode)
├── switch-model                 (switcher script)
├── llama-server.service         (systemd user unit)
├── install.sh                   (one-shot bootstrap)
└── README.md
```

After deployment, the VM mirrors this layout at `~/llama-server/`, with an extra `active.conf` symlink that `install.sh` creates.

---

## First-Time Setup

Prerequisites on the VM: `llama.cpp` built at `~/llama.cpp/build/bin/llama-server`, and the GGUF model files present at the paths in `configs/*.conf` (edit those configs if your paths differ).

From your laptop, in the repo root:

```bash
# 1. Copy this directory to the VM as ~/llama-server/
rsync -a --delete model-switching/ daryl@<VM-IP>:~/llama-server/

# 2. Run the bootstrap on the VM (pass 27b or 35b as the starting model)
ssh daryl@<VM-IP> '~/llama-server/install.sh 35b'
```

`install.sh` does the following on the VM:
1. Makes `switch-model` executable.
2. Creates the `active.conf` symlink pointing at the chosen default config.
3. Copies `llama-server.service` into `~/.config/systemd/user/`.
4. Runs `sudo loginctl enable-linger $USER` (one-time, prompts for sudo) so the service starts at boot.
5. Enables and starts the systemd user service.

### Optional: convenience alias on the VM

```bash
ssh daryl@<VM-IP>
echo 'alias switch-model=~/llama-server/switch-model' >> ~/.zshrc   # or ~/.bashrc
# or symlink onto PATH:
mkdir -p ~/.local/bin && ln -sf ~/llama-server/switch-model ~/.local/bin/switch-model
```

### Optional: retire an older system-level service

If you previously ran `llama-server` from `/etc/systemd/system/`, retire it so it doesn't fight the new user service:

```bash
sudo systemctl disable --now llama-server
sudo rm /etc/systemd/system/llama-server.service /etc/llama-server.conf
sudo systemctl daemon-reload
```

---

## Subsequent Runs

### Daily use (on the VM)

```bash
switch-model 27b       # fast mode
switch-model 35b       # accurate mode
switch-model status    # show active config + service state
switch-model restart   # restart without changing model
```

API endpoint is unchanged: `http://<VM-IP>:8080/v1/`.

### Updating configs / scripts

Edit files in this repo, commit, then redeploy:

```bash
rsync -a --delete model-switching/ daryl@<VM-IP>:~/llama-server/
ssh daryl@<VM-IP> 'systemctl --user daemon-reload && systemctl --user restart llama-server'
```

`--delete` keeps the VM in sync with the repo, but it will also remove `active.conf` on the VM — that's fine, just re-run `~/llama-server/install.sh <model>` (or recreate the symlink manually) afterward. If you'd rather preserve `active.conf`, drop `--delete` or add `--exclude active.conf`.

### Logs and debugging

```bash
journalctl --user -u llama-server -f               # live logs
journalctl --user -u llama-server --no-pager -n 50 # recent failures
systemctl --user status llama-server               # service state
```

---

## Persistence Across Reboots

- The `active.conf` symlink survives reboots → whichever model you last selected auto-loads.
- `loginctl enable-linger` (set during install) makes the user service start at boot without anyone logging in.

---

## Moving to Another Machine

```bash
rsync -a model-switching/ newhost:~/llama-server/
ssh newhost '~/llama-server/install.sh'
```

Assuming the new host has `llama.cpp` built at `~/llama.cpp/build/bin/llama-server` and the model files exist at the paths in the configs, that's the entire migration. Adjust `configs/*.conf` `MODEL_PATH` if the new host stores models elsewhere.

---

## Caveat: Vision Support Differences

If a model variant doesn't support vision, you'd want to drop `MMPROJ_PATH` from its config — but the service unit always passes `--mmproj ${MMPROJ_PATH}`, which fails on an empty value. Two options:

**Option A — per-model service units:** create `llama-server@.service` (templated) with one ExecStart per variant, and have the switcher start/stop the right instance.

**Option B — wrapper script:** replace `ExecStart` with `ExecStart=%h/llama-server/run.sh`, where `run.sh` builds the argument list and only appends `--mmproj` when `MMPROJ_PATH` is set.

Skip this entirely if both models keep vision support.

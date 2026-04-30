# Model Switching (27B Dense ↔ 35B-A3B MoE)

A self-contained setup for switching `llama-server` between two models with one command. Switch takes ~20–30s.

The repo itself is the install location — files are read in-place from `~/home-ai-server/model-switching/`. No rsync, no separate deploy step.

---

## How It Works

A user-level systemd service (under `~/.config/systemd/user/`) runs `llama-server` as your user. The unit reads `~/home-ai-server/model-switching/active.conf`, which is a symlink pointing at one of the per-model configs in `configs/`. The `switch-model` script repoints the symlink and restarts the service, which causes `llama-server` to exit (releasing GPU memory) and start back up with the new model loaded.

Because it's a user service, `sudo` is only needed once during initial setup (to enable lingering so the service starts at boot without you logging in). After that, all switching is unprivileged.

```
~/home-ai-server/model-switching/
├── configs/
│   ├── 27b.conf                 (fast mode)
│   └── 35b.conf                 (accurate mode)
├── active.conf                  → symlink to one of configs/*.conf (created by install.sh)
├── switch-model                 (switcher script)
├── llama-server.service         (systemd user unit)
├── install.sh                   (one-shot bootstrap)
└── README.md
```

---

## First-Time Setup

Prerequisites on the Ubuntu server:
- Repo cloned at `~/home-ai-server`
- `llama.cpp` built at `~/llama.cpp/build/bin/llama-server`
- GGUF model files present at `~/models/<MODEL_NAME>` matching the names in `configs/*.conf` (edit those configs if your filenames differ)

Then:

```bash
# Run the bootstrap (pass 27b or 35b as the starting model; defaults to 35b)
~/home-ai-server/model-switching/install.sh 35b
```

`install.sh` does:
1. Makes `switch-model` executable.
2. Creates the `active.conf` symlink pointing at the chosen default config.
3. Copies `llama-server.service` into `~/.config/systemd/user/`.
4. Runs `sudo loginctl enable-linger $USER` (one-time, prompts for sudo) so the service starts at boot.
5. Enables and starts the systemd user service.

When it finishes, `llama-server` is running with the default model on `http://<server-ip>:8080/v1/`.

### Optional: convenience alias

```bash
echo 'alias switch-model=~/home-ai-server/model-switching/switch-model' >> ~/.bashrc
# or symlink onto PATH:
mkdir -p ~/.local/bin && ln -sf ~/home-ai-server/model-switching/switch-model ~/.local/bin/switch-model
```

---

## Subsequent Runs

### Switching models

```bash
~/home-ai-server/model-switching/switch-model 27b       # fast mode
~/home-ai-server/model-switching/switch-model 35b       # accurate mode
~/home-ai-server/model-switching/switch-model status    # show active config + service state
~/home-ai-server/model-switching/switch-model restart   # restart without changing model
```

(Or just `switch-model 27b` if you set up the alias above.)

The restart causes the running `llama-server` process to exit, which releases the model from GPU memory; systemd then starts it again with the new config and the new model is loaded fresh. API endpoint is unchanged: `http://<server-ip>:8080/v1/`.

### Updating configs / scripts

Pull the repo and reload:

```bash
cd ~/home-ai-server && git pull
systemctl --user daemon-reload    # only needed if llama-server.service changed
systemctl --user restart llama-server
```

If you edited `llama-server.service`, re-run `install.sh` to recopy it into `~/.config/systemd/user/` (or `cp` it manually).

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
git clone <repo> ~/home-ai-server
# build llama.cpp at ~/llama.cpp, place models at ~/models/
~/home-ai-server/model-switching/install.sh
```

---

## Caveat: Vision Support Differences

If a model variant doesn't support vision, you'd want to drop `MMPROJ_NAME` from its config — but the service unit always passes `--mmproj %h/models/${MMPROJ_NAME}`, which fails on an empty value. Two options:

**Option A — per-model service units:** create `llama-server@.service` (templated) with one ExecStart per variant, and have the switcher start/stop the right instance.

**Option B — wrapper script:** replace `ExecStart` with `ExecStart=%h/home-ai-server/model-switching/run.sh`, where `run.sh` builds the argument list and only appends `--mmproj` when `MMPROJ_NAME` is set.

Skip this entirely if both models keep vision support.

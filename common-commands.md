# Common commands (run on the AI server — `ssh local-ai`)

The llama server runs as a **user-level** systemd service (`llama-server`, user `daryl`) — no `sudo` needed.

## Model switching

```bash
# Switch model (restarts the service with the selected config)
~/home-ai-server/model-switching/switch-model 27b   # dense, more accurate
~/home-ai-server/model-switching/switch-model 35b   # MoE, faster

# Check which model is active
~/home-ai-server/model-switching/switch-model status
```

Per-model flags live in `~/home-ai-server/model-switching/configs/{27b,35b}.conf`; `active.conf` is a symlink to the currently active one. Edit a `.conf` file, then `systemctl --user restart llama-server` to apply without switching models.

## Service management

```bash
# Status
systemctl --user status llama-server

# Restart (after editing a config)
systemctl --user restart llama-server

# Live logs
journalctl --user -u llama-server -f

# Today's logs
journalctl --user -u llama-server --since today

# Logs from the previous run (after a crash/restart)
journalctl --user -u llama-server -b -1
```

## API

```bash
curl -s http://100.89.219.6:8080/health
curl -s http://100.89.219.6:8080/v1/models
```

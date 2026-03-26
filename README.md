# Ubuntu SSH Dev Container (VS Code)

This project runs an Ubuntu container with SSH enabled, then connects from VS Code using Remote SSH.
The container installs Docker CLI and uses the host Docker daemon via `/var/run/docker.sock`.

## Prerequisites

- Docker with Compose support
- VS Code
- VS Code extension: `Remote - SSH` (by Microsoft)

## 1. Configure credentials

1. Copy the example env file:

```bash
cp .example.env .env
```

2. Create the password secret file:

```bash
mkdir -p .secrets
printf '%s\n' 'your-strong-password' > .secrets/dev_password.txt
chmod 600 .secrets/dev_password.txt
```

3. If needed, update `.env`:

- `USERNAME=dev`
- `PASSWORD_FILE=./.secrets/dev_password.txt`

## 2. Build and start the container

```bash
docker compose --env-file .env up --build -d
```

Container exposes SSH on `127.0.0.1:2222`.

## 3. Verify SSH login from terminal

```bash
ssh dev@127.0.0.1 -p 2222
```

Use the password from your secret file when prompted.

At login, you will see a reminder for the setup CLI:

```bash
onboard
```

Run it (recommended on first login) and choose optional packages to install. Current options:

- `curl`
- `gh` (GitHub CLI)
- `tmux`
- `jq`
- `telnet`
- `nvm` with default Node.js set to `22`
- `@openai/codex` (global npm install)
- `agent-browser` (global npm install) plus `agent-browser install --with-deps`
- `claude-code` (`curl -fsSL https://claude.ai/install.sh | bash`)
- generate SSH key at `~/.ssh/id_ed25519`

You can also verify host Docker access from inside the container:

```bash
docker version
docker ps
```

### Test host connectivity from inside the container

`/var/run/docker.sock` and `telnet` test different things:

- Docker socket test validates Docker daemon access.
- `telnet` test validates TCP connectivity to a host port.

Run these checks after SSHing into the container:

1. Confirm Docker socket access:

```bash
docker version
docker ps
```

2. Ensure `telnet` is installed (if not already installed by `onboard`):

```bash
which telnet || (sudo apt-get update && sudo apt-get install -y telnet)
```

3. Test host service connectivity through Docker host gateway mapping:

```bash
telnet host.docker.internal <port>
```

Example:

```bash
telnet host.docker.internal 3306
```

If this fails, verify the host service is running and listening on a reachable interface (not only loopback).

## 4. Connect from VS Code

1. Open Command Palette: `Ctrl+Shift+P`
2. Run: `Remote-SSH: Open SSH Configuration File...`
3. Add this host entry:

```sshconfig
Host sandbox-dev
    HostName 127.0.0.1
    User dev
    Port 2222
```

4. Open Command Palette again and run: `Remote-SSH: Connect to Host...`
5. Choose `sandbox-dev`
6. Enter password when prompted

## Useful commands

Start/rebuild:

```bash
docker compose --env-file .env up --build -d
```

Stop:

```bash
docker compose down
```

View logs:

```bash
docker compose logs -f
```

## Troubleshooting

### SSH warning: `REMOTE HOST IDENTIFICATION HAS CHANGED`

This usually means your SSH client has a stale key in `known_hosts` (common after container rebuild/recreate).

- Linux/WSL OpenSSH uses `~/.ssh/known_hosts`.
- Windows OpenSSH (used by VS Code Remote-SSH by default) uses `C:\Users\<you>\.ssh\known_hosts`.

If SSH works from WSL but fails in VS Code on Windows, clean the Windows key cache.

1. Verify the new host key fingerprint (optional but recommended):

```bash
ssh-keyscan -p 2222 127.0.0.1 | ssh-keygen -lf -
```

2. Remove the old key entry:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R '[127.0.0.1]:2222'
```

On Windows PowerShell (for VS Code Remote-SSH):

```powershell
ssh-keygen -R "[localhost]:2222"
ssh-keygen -R "localhost"
```

3. Reconnect and accept the new key:

```bash
ssh sandbox-dev
```

From Windows, run `ssh sandbox-dev` once in PowerShell to re-trust the new key, then reconnect from VS Code.

Only accept the new key if the fingerprint matches what you expect for your environment.

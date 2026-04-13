# Testing the bootstrap

End-to-end verification that `install.sh` still provisions a working
workspace from scratch. Run this whenever you touch `install.sh` or
any file under `lib/`.

## Clean-room integration test (Docker)

Use `ubuntu:24.04` (noble), **not** 22.04. Noble ships a deliberately
minimal base image (no `gnupg`, no `unzip`) that catches missing-dep
bugs older bases mask — the `gnupg` requirement for mise's Node signature
verification was originally surfaced on a real Coder workspace running
noble and the integration test missed it while running on 22.04.

Launch a container with the working tree bind-mounted read-only:

```bash
docker run --rm -it \
  -v ~/dotfiles:/mnt/dotfiles:ro \
  ubuntu:24.04 bash
```

Inside the container, create an unprivileged user with passwordless
sudo and copy the repo into their home (bind mount is read-only, and
`install.sh` writes into `$DOTFILES`):

```bash
apt-get update && apt-get install -y sudo curl git ca-certificates
useradd -m -s /bin/bash test
echo "test ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
cp -r /mnt/dotfiles /home/test/dotfiles
chown -R test:test /home/test/dotfiles
su - test
```

As the `test` user, run the bootstrap:

```bash
~/dotfiles/install.sh
```

## Verification checks

**1. Every managed CLI is reachable in a fresh zsh:**

```bash
zsh -i -c '
echo "ZSH_VERSION=$ZSH_VERSION"
echo "plugins=$plugins"
which starship mise claude gh
starship --version
mise --version
claude --version
gh --version
'
```

Expected:

- `ZSH_VERSION` set (5.x)
- `plugins=git zsh-autosuggestions zsh-syntax-highlighting`
- Every `which` line resolves, every `--version` prints a version
- `which claude` resolves to `~/.local/bin/claude` (the native binary),
  not a mise shim

**2. Symlinks point back into `$DOTFILES`:**

```bash
ls -la ~/.zshrc ~/.zshenv ~/.config/mise/config.toml ~/.config/starship.toml
```

Every entry should be a symlink (`l` in mode) targeting a path under
`/home/test/dotfiles/`.

**3. Idempotency — re-run must be a silent no-op:**

```bash
~/dotfiles/install.sh 2>&1 | tee /tmp/run2.log
find ~ -name "*.backup.*" 2>/dev/null
```

The second run should exit 0 with only `[info] ok ...` lines from the
symlink step, and `find` should return nothing (no new backup files).

**4. Interactive smoke:**

```bash
zsh
```

Starship prompt renders. Typing a wrong command (e.g. `fooo`) shows red
syntax highlighting until Enter. Typing a real command shows a ghost
autosuggestion from history if any exists.

## macOS

The Docker test covers Linux + apt. For macOS, run `./install.sh`
directly on a clean user account and verify the Homebrew path in
`lib/install-system.sh` resolves (`has_cmd brew` short-circuits on
re-runs).

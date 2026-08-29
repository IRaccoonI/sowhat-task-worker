# sowhat task worker

The task worker connects to sowhat over outbound HTTPS and starts one fresh, isolated container for
each accepted automation task. It opens no inbound port. The sowhat server supplies the model,
timeouts, approved preparation and verification commands, and one short-lived repository-specific
GitHub token. Codex uses one device login stored in a private Docker volume.

Published `linux/amd64` image:

```text
docker.io/iraccooni/sowhat-task-worker:0.3.21
docker.io/iraccooni/sowhat-task-worker@sha256:5984d64570ba051e26e0794ffdbb84219c49ca3b5d495b4faa8d61a94325e1b6
```

Use the digest form. There is deliberately no `latest` tag. Versions `0.2.0` through `0.3.18` are
superseded.

Before every claim and again before every task child, the coordinator requires at least 32 GiB and
10% free on its backing filesystem. It waits without claiming work when either reserve is missing.
Every task child, sandbox probe and run-scoped companion also uses bounded `json-file` rotation of
three 10 MiB files, independently from daemon defaults.

The standalone setup files are public at
[`IRaccoonI/sowhat-task-worker`](https://github.com/IRaccoonI/sowhat-task-worker).

## Requirements

- Ubuntu 24.04 `amd64` host;
- dedicated non-root operator account with `sudo` access;
- Git;
- official Docker Engine, Docker Compose plugin and `docker-ce-rootless-extras`;
- server-administrator access to the sowhat API/worker environment;
- one Codex device-code login.

Install missing host software by following Docker's official
[Ubuntu installation guide](https://docs.docker.com/engine/install/ubuntu/) and
[rootless-mode guide](https://docs.docker.com/engine/security/rootless/). Confirm the required
commands before continuing:

```bash
git --version
docker --version
docker compose version
command -v dockerd-rootless-setuptool.sh
```

## Complete setup with the repository scripts

This is the recommended path. It is written for a dedicated non-root operator account on a clean
Ubuntu 24.04 `amd64` host with `sudo` access.

### 1. Download the setup scripts

```bash
git clone --branch v0.3.21 --depth 1 \
  https://github.com/IRaccoonI/sowhat-task-worker.git
cd sowhat-task-worker
```

Tag `v0.3.21` pins the scripts, AppArmor profiles and Compose file used by worker image `0.3.21`.
No access to the private sowhat product repository is required.

### 2. Create the protected configuration

```bash
install -d -m 0700 ~/.config/sowhat
cp .env.example ~/.config/sowhat/task-worker.env
chmod 0600 ~/.config/sowhat/task-worker.env
nano ~/.config/sowhat/task-worker.env
```

The file contains three required operator-owned values, two safe diagnostic controls and one
optional proxy setting:

```dotenv
TASK_WORKER_SITE_URL=https://sowhat-ai.com
TASK_WORKER_REGISTRATION_TOKEN=replace-with-the-production-registration-secret-at-least-32-characters
TASK_WORKER_ALLOWED_REPOSITORIES=owner/repository
LOG_LEVEL=debug
TASK_WORKER_DIAGNOSTICS_INTERVAL_MS=5000
TASK_WORKER_RETAIN_FAILURE_DIAGNOSTICS=false
TASK_WORKER_HTTP_PROXY=
```

- `TASK_WORKER_SITE_URL` is the public HTTPS origin shown in the browser address bar, without a
  path. For the hosted product it is `https://sowhat-ai.com`.
- `TASK_WORKER_REGISTRATION_TOKEN` is a dedicated bootstrap secret. A sowhat server administrator
  generates it once with `openssl rand -hex 32`, stores the result as the production-worker value
  `TASK_AUTOMATION_WORKER_REGISTRATION_TOKEN`, and gives the same value to the worker operator for
  this file. It is not a GitHub token or an OpenAI API key. Never display it in the product UI,
  commit it, or paste it into logs.
- `TASK_WORKER_ALLOWED_REPOSITORIES` is the exact local allowlist. Copy the ready-made value from
  **Space settings → Automation**, or enter the connected repository names as comma-separated
  `owner/repository` values. Every allowed repository also needs an exact server-owned execution
  profile.
- `LOG_LEVEL=debug` enables content-free run diagnostics, and
  `TASK_WORKER_DIAGNOSTICS_INTERVAL_MS=5000` records one bounded resource sample every five
  seconds. Samples include run/attempt/phase, elapsed time, CPU, current and peak memory, memory
  limit and PID count. They never include task text, prompts, source paths, command output,
  credentials, tokens or proxy values. Set `LOG_LEVEL=info` later to reduce verbosity without
  changing task behavior.
- `TASK_WORKER_RETAIN_FAILURE_DIAGNOSTICS=false` is the safe default. Set it to `true` only while an
  operator diagnoses a final task failure. The separate local volume then retains at most three
  24-hour bundles containing a bounded staged diff and the already-redacted final gate diagnostic.
  Bundles never enter sowhat, the browser, results or logs; treat the volume as private source
  material and switch retention off after diagnosis.
- `TASK_WORKER_HTTP_PROXY` is optional. Leave it empty for direct access. If Codex or GitHub is
  blocked from this host, set an HTTP or HTTPS proxy origin such as
  `http://user:password@proxy.example:8080`. It covers worker registration and claims, Codex device
  login and model requests, GitHub clone/API/push traffic, and trusted preparation commands.
  Percent-encode the username and password before putting them in the URL. Paths, query strings,
  fragments and non-HTTP proxy protocols are rejected.

The proxy value remains in the mode-`0600` operator file and local worker containers. It is not sent
to the sowhat server, browser, task payload, prompt, logs or offline verification commands. Docker
image pulls are performed by the separate rootless Docker daemon; if Docker Hub is also blocked,
configure the same proxy separately for that user's rootless Docker service before `bootstrap`.

Never add a GitHub token, `CODEX_API_KEY`, Codex `auth.json`, model name, task commands or task
budgets to this file. Those values either remain server-owned or are issued only for one task.

### 3. Run the one-time host setup

```bash
sudo scripts/setup-host.sh
```

The script performs the host operations that a normal container cannot perform safely:

- verifies Ubuntu 24.04 and that it was started with `sudo` by a non-root operator;
- installs `uidmap` for subordinate user/group mappings;
- installs and loads the checked-in `bwrap-userns-restrict` and `sowhat-task-runner` AppArmor
  profiles;
- enables user lingering so the worker survives logout and reboot;
- installs and starts a dedicated rootless Docker daemon for the current operator account;
- verifies that `/run/user/<uid>/docker.sock` exists and reports rootless security mode.

The final line should look like:

```text
Task-worker host setup is ready for <user> (/run/user/<uid>/docker.sock).
```

Do not replace that socket with `/var/run/docker.sock`. The latter is the rootful daemon and gives a
container root-equivalent control of the host; the worker rejects it.

### 4. Start the worker and authorize Codex once

Run this as the same non-root operator, without `sudo`:

```bash
scripts/worker.sh bootstrap
```

`bootstrap` does all container-level setup in order:

1. selects only the current account's rootless Docker socket;
2. resolves the rootless socket's Docker group without adding another value to the operator env;
3. pulls the exact image digest from this page;
4. creates and initializes the private Codex-auth and worker-state volumes;
5. starts the coordinator;
6. runs `codex login --device-auth` inside the coordinator;
7. waits for you to open the displayed OpenAI URL and enter the one-time code;
8. restarts the coordinator, checks Codex login status and prints Compose status.

The device login is stored in the rootless-Docker volume
`sowhat-task-worker-codex-auth`. It survives container replacement and image upgrades and is reused
by each disposable task container. Do not print, copy or mount its `auth.json` anywhere else.

### 5. Verify the result

```bash
scripts/worker.sh status
scripts/worker.sh logs
```

`status` should show `sowhat-task-worker` as running and healthy. `logs` follows the newest 200
metadata-only log lines; press `Ctrl+C` to stop following logs without stopping the worker.

The worker can remain healthy and idle when automation is disabled. Before it can receive work, the
sowhat server operator must configure an exact execution profile for the allowed repository and
enable global task automation. A space manager must then enable its policy in **Space settings →
Automation**. Start with pull-request delivery and a disposable accepted card.

## Daily operation

Run these commands from the cloned repository as the same non-root operator:

```bash
# Pull the pinned image and start or update the coordinator.
scripts/worker.sh start

# Show container and health state.
scripts/worker.sh status

# Follow the newest 200 log lines.
scripts/worker.sh logs

# Stop the coordinator but keep its identity and Codex login.
scripts/worker.sh stop
```

The helper reads `~/.config/sowhat/task-worker.env` by default. To use another protected file for
one command:

```bash
SOWHAT_TASK_WORKER_ENV_FILE=/absolute/path/task-worker.env \
  scripts/worker.sh status
```

## Manual Docker Compose setup

The scripts above use the checked-in Compose file. If you prefer to manage the coordinator with
Docker Compose directly after the one-time repository-based host setup, save the following as
`compose.yaml` and create a `.env` beside it with the same three required values and optional proxy.

```yaml
name: sowhat-task-worker

x-task-worker-image: &task-worker-image docker.io/iraccooni/sowhat-task-worker@sha256:5984d64570ba051e26e0794ffdbb84219c49ca3b5d495b4faa8d61a94325e1b6

x-logging: &default-logging
  driver: json-file
  options:
    max-file: "3"
    max-size: 10m

services:
  task-worker-state-init:
    image: *task-worker-image
    pull_policy: always
    cap_add: [CHOWN]
    cap_drop: [ALL]
    entrypoint: ["/bin/sh", "-c", "exec chown 1000:1000 /state /codex-auth /failure-diagnostics"]
    logging: *default-logging
    mem_limit: 32m
    network_mode: none
    read_only: true
    restart: "no"
    security_opt: [no-new-privileges:true]
    user: "0:0"
    volumes:
      - codex-auth:/codex-auth
      - failure-diagnostics:/failure-diagnostics
      - worker-state:/state

  task-worker:
    container_name: sowhat-task-worker
    image: *task-worker-image
    pull_policy: always
    cap_drop: [ALL]
    depends_on:
      task-worker-state-init:
        condition: service_completed_successfully
    group_add:
      - ${TASK_WORKER_DOCKER_SOCKET_GID:?TASK_WORKER_DOCKER_SOCKET_GID is required}
    environment:
      CODEX_HOME: /codex-auth
      DOCKER_HOST: unix:///run/docker.sock
      HTTP_PROXY: ${TASK_WORKER_HTTP_PROXY:-}
      HTTPS_PROXY: ${TASK_WORKER_HTTP_PROXY:-}
      LOG_LEVEL: ${LOG_LEVEL:-debug}
      NODE_ENV: production
      NODE_OPTIONS: --enable-source-maps --max-old-space-size=256
      NODE_USE_ENV_PROXY: "1"
      NO_PROXY: 127.0.0.1,localhost,::1
      TASK_WORKER_ALLOWED_REPOSITORIES: ${TASK_WORKER_ALLOWED_REPOSITORIES:?TASK_WORKER_ALLOWED_REPOSITORIES is required}
      TASK_WORKER_EXECUTION_IMAGE: *task-worker-image
      TASK_WORKER_RETAIN_FAILURE_DIAGNOSTICS: ${TASK_WORKER_RETAIN_FAILURE_DIAGNOSTICS:-false}
      TASK_WORKER_HTTP_PROXY: ${TASK_WORKER_HTTP_PROXY:-}
      TASK_WORKER_DIAGNOSTICS_INTERVAL_MS: ${TASK_WORKER_DIAGNOSTICS_INTERVAL_MS:-5000}
      TASK_WORKER_PROCESS_MODE: coordinator
      TASK_WORKER_REGISTRATION_TOKEN: ${TASK_WORKER_REGISTRATION_TOKEN:?TASK_WORKER_REGISTRATION_TOKEN is required}
      TASK_WORKER_SITE_URL: ${TASK_WORKER_SITE_URL:?TASK_WORKER_SITE_URL is required}
      TASK_WORKER_VERSION: 0.3.21
      http_proxy: ${TASK_WORKER_HTTP_PROXY:-}
      https_proxy: ${TASK_WORKER_HTTP_PROXY:-}
      no_proxy: 127.0.0.1,localhost,::1
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3004/health/ready').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))",
        ]
      interval: 15s
      timeout: 3s
      retries: 5
      start_period: 10s
    logging: *default-logging
    mem_limit: 512m
    networks: [outbound]
    pids_limit: 128
    read_only: true
    restart: unless-stopped
    security_opt: [no-new-privileges:true]
    tmpfs:
      - /tmp:size=64m,mode=1777,noexec,nosuid
    volumes:
      - codex-auth:/codex-auth
      - failure-diagnostics:/failure-diagnostics
      - ${TASK_WORKER_DOCKER_SOCKET_PATH:-${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/docker.sock}:/run/docker.sock
      - worker-state:/state

networks:
  outbound:

volumes:
  codex-auth:
    name: sowhat-task-worker-codex-auth
  failure-diagnostics:
    name: sowhat-task-worker-failure-diagnostics
  worker-state:
    name: sowhat-task-worker-state
```

The one-time host setup from step 3 is still required. Then run:

```bash
chmod 0600 .env
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
export TASK_WORKER_DOCKER_SOCKET_PATH="${XDG_RUNTIME_DIR}/docker.sock"
export TASK_WORKER_DOCKER_SOCKET_GID="$(getent group docker | cut -d: -f3)"
docker info --format '{{json .SecurityOptions}}'
docker compose pull
docker compose up -d
docker compose exec task-worker \
  /app/node_modules/.bin/codex \
  -c 'cli_auth_credentials_store="file"' \
  login --device-auth
docker compose restart task-worker
docker compose exec task-worker \
  /app/node_modules/.bin/codex \
  -c 'cli_auth_credentials_store="file"' \
  login status
docker compose ps
```

The `docker info` output must include `rootless`. `TASK_WORKER_DOCKER_SOCKET_GID` is derived from
the host's Docker group and is not an operator secret or a fifth persisted setting. Keep all three
runtime exports set in every shell used to manage this manual Compose project.

## Troubleshooting

- **`Docker rootless extras are missing`** — install `docker-ce-rootless-extras`, then rerun the
  host setup.
- **`Missing rootless Docker socket`** — rerun the host setup as the operator that will own the
  worker, then check `systemctl --user status docker` from a real login session for that user.
- **`permission denied` for `/run/docker.sock`** — use tag `v0.3.4` or newer. Its helper adds the
  coordinator to the rootless socket group while keeping the application process non-root.
- **A dependency CLI such as `prettier` reports `Permission denied` below `/runs`** — use tag
  `v0.3.16` or newer. It pins worker `0.3.16`, which explicitly mounts the disposable task tmpfs with
  `exec`, and includes the matching AppArmor profile. Rerun `sudo scripts/setup-host.sh`, then
  bootstrap the worker again.
- **Environment file mode error** — run `chmod 0600 ~/.config/sowhat/task-worker.env`.
- **Worker is unhealthy after bootstrap** — rerun `bootstrap` and complete the device-code login,
  then inspect `scripts/worker.sh logs`.
- **Codex, GitHub or worker registration cannot connect** — set a validated HTTP/HTTPS origin in
  `TASK_WORKER_HTTP_PROXY`, rerun `scripts/worker.sh bootstrap`, and configure the rootless Docker
  service separately if the failure happens while pulling an image.
- **Repository is refused** — use the exact `owner/repository` spelling in the local allowlist and
  ask the sowhat server operator to configure the same repository execution profile.
- **Healthy worker receives no task** — verify server-wide automation, the space's Automation
  policy, the configured source column, repository access, and that the card is accepted rather
  than still proposed.

The coordinator stores no permanent GitHub credential, exposes no home port and removes each task
container after the attempt finishes.

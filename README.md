# sowhat task worker

Public, standalone setup files for
[`docker.io/iraccooni/sowhat-task-worker`](https://hub.docker.com/r/iraccooni/sowhat-task-worker).
The worker connects to a sowhat installation over outbound HTTPS and starts one isolated container
for each accepted automation task. It opens no inbound port.

This repository contains only operator setup files. It does not contain the private sowhat product
repository, application source, credentials or production configuration.

## Supported release

```text
Version: 0.2.3
Platform: linux/amd64
Image: docker.io/iraccooni/sowhat-task-worker@sha256:ed837d98549022cd21bb40b50e9c9d24f47f7407746c345998594a1a70c76f0c
```

There is deliberately no `latest` tag. Versions `0.2.0` through `0.2.2` are superseded.

## Requirements

- Ubuntu 24.04 `amd64` host;
- dedicated non-root operator account with `sudo` access;
- Git;
- official Docker Engine, Docker Compose plugin and `docker-ce-rootless-extras`;
- server-administrator access to the sowhat API/worker environment;
- one Codex device-code login.

Follow Docker's official [Ubuntu installation guide](https://docs.docker.com/engine/install/ubuntu/)
and [rootless-mode guide](https://docs.docker.com/engine/security/rootless/) if Docker is not
installed yet. Confirm the required commands before continuing:

```bash
git --version
docker --version
docker compose version
command -v dockerd-rootless-setuptool.sh
```

## Install

Clone the setup repository at the version matching the image:

```bash
git clone --branch v0.2.3 --depth 1 \
  https://github.com/IRaccoonI/sowhat-task-worker.git
cd sowhat-task-worker
```

Create the protected configuration:

```bash
install -d -m 0700 ~/.config/sowhat
cp .env.example ~/.config/sowhat/task-worker.env
chmod 0600 ~/.config/sowhat/task-worker.env
nano ~/.config/sowhat/task-worker.env
```

Set:

```dotenv
TASK_WORKER_SITE_URL=https://sowhat-ai.com
TASK_WORKER_REGISTRATION_TOKEN=replace-with-the-server-registration-secret-at-least-32-characters
TASK_WORKER_ALLOWED_REPOSITORIES=owner/repository
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
- `TASK_WORKER_HTTP_PROXY` is optional. Leave it empty for direct access. If Codex or GitHub is
  blocked from this host, set an HTTP or HTTPS proxy origin such as
  `http://user:password@proxy.example:8080`. It covers worker registration and claims, Codex device
  login and model requests, GitHub clone/API/push traffic, and trusted preparation commands.
  Percent-encode the username and password. Paths, query strings, fragments and non-HTTP proxy
  protocols are rejected.

The proxy remains in the mode-`0600` operator file and local worker containers. It is not sent to
the sowhat server, browser, task payload, prompt, logs or offline verification commands. Docker
image pulls are performed by the separate rootless Docker daemon; if Docker Hub is also blocked,
configure the proxy separately for that user's rootless Docker service before `bootstrap`.

Never add a GitHub token, `CODEX_API_KEY`, Codex `auth.json`, model name, task commands or task
budgets to this file. Those values either remain server-owned or are issued only for one task.

Run the one-time host setup:

```bash
sudo scripts/setup-host.sh
```

The script installs `uidmap`, loads the two checked-in AppArmor profiles, enables user lingering,
creates the operator's dedicated rootless Docker daemon and verifies its socket. Do not replace the
rootless socket with `/var/run/docker.sock`.

Start the worker and authorize Codex once, as the same non-root operator:

```bash
scripts/worker.sh bootstrap
```

The helper derives the rootless Docker socket group at runtime and adds only that supplementary
group to the non-root coordinator. It does not add another persisted environment setting.

If logs show `permission denied` for `/run/docker.sock`, make sure this checkout is on `v0.2.3` or
newer and rerun `scripts/worker.sh start`.

Open the displayed OpenAI verification URL and enter the one-time code. The login is stored only in
the rootless-Docker volume `sowhat-task-worker-codex-auth`; it survives image upgrades and is shared
with disposable task containers.

Verify the result:

```bash
scripts/worker.sh status
scripts/worker.sh logs
```

`status` should show `sowhat-task-worker` as running and healthy. Press `Ctrl+C` to stop following
logs without stopping the worker.

## Operation

```bash
scripts/worker.sh start
scripts/worker.sh status
scripts/worker.sh logs
scripts/worker.sh stop
```

`start` pulls the pinned image before starting. `stop` preserves the worker identity, pending
delivery state and Codex login volumes.

The helper reads `~/.config/sowhat/task-worker.env` by default. Override it for one command with:

```bash
SOWHAT_TASK_WORKER_ENV_FILE=/absolute/path/task-worker.env \
  scripts/worker.sh status
```

## Server-side activation

A healthy worker can remain idle. Before it receives tasks, the sowhat server operator must:

1. configure an exact execution profile for every locally allowed repository;
2. set `TASK_AUTOMATION_ENABLED=true` for API and worker;
3. configure `TASK_AUTOMATION_WORKER_REGISTRATION_TOKEN` with the value used by the operator worker;
4. approve the required GitHub App repository permissions;
5. enable a space policy in **Space settings → Automation**.

Start with pull-request delivery and a disposable accepted card. Proposed assistant cards are not
eligible until a person accepts them.

## Troubleshooting

- **`Docker rootless extras are missing`** — install `docker-ce-rootless-extras`, then rerun
  `sudo scripts/setup-host.sh`.
- **`Missing rootless Docker socket`** — rerun host setup as the operator who will own the worker,
  then check `systemctl --user status docker` from that user's real login session.
- **Environment file mode error** — run `chmod 0600 ~/.config/sowhat/task-worker.env`.
- **Worker is unhealthy after bootstrap** — rerun `bootstrap`, complete device login and inspect
  `scripts/worker.sh logs`.
- **Codex, GitHub or worker registration cannot connect** — set a validated HTTP/HTTPS origin in
  `TASK_WORKER_HTTP_PROXY`, rerun `scripts/worker.sh bootstrap`, and configure the rootless Docker
  service separately if the failure happens while pulling an image.
- **Repository is refused** — use exact `owner/repository` spelling locally and configure the same
  repository execution profile on the sowhat server.
- **Healthy worker receives no task** — verify global automation, the space policy, source column,
  repository access and that the card is accepted rather than proposed.

The coordinator stores no permanent GitHub credential, exposes no home port and removes each task
container after the attempt finishes.

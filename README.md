# sowhat task worker

Public, standalone setup files for
[`docker.io/iraccooni/sowhat-task-worker`](https://hub.docker.com/r/iraccooni/sowhat-task-worker).
The worker connects to a sowhat installation over outbound HTTPS and starts one isolated container
for each accepted automation task. It opens no inbound port.

This repository contains only operator setup files. It does not contain the private sowhat product
repository, application source, credentials or production configuration.

## Supported release

```text
Version: 0.2.1
Platform: linux/amd64
Image: docker.io/iraccooni/sowhat-task-worker@sha256:0195f6f3e71dad5e0dfcfe75c9681aea81a51dfbd92e34c1ec252b3e8dd78b47
```

There is deliberately no `latest` tag. Do not use the superseded `0.2.0` image.

## Requirements

- Ubuntu 24.04 `amd64` host;
- dedicated non-root operator account with `sudo` access;
- Git;
- official Docker Engine, Docker Compose plugin and `docker-ce-rootless-extras`;
- a worker-registration secret from the sowhat server operator;
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
git clone --branch v0.2.1 --depth 1 \
  https://github.com/IRaccoonI/sowhat-task-worker.git
cd sowhat-task-worker
```

Create the protected three-value configuration:

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
```

`TASK_WORKER_REGISTRATION_TOKEN` must exactly match the server-side
`TASK_AUTOMATION_WORKER_REGISTRATION_TOKEN`. Use comma-separated exact `owner/repository` names when
several repositories are allowed.

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
- **Repository is refused** — use exact `owner/repository` spelling locally and configure the same
  repository execution profile on the sowhat server.
- **Healthy worker receives no task** — verify global automation, the space policy, source column,
  repository access and that the card is accepted rather than proposed.

The coordinator stores no permanent GitHub credential, exposes no home port and removes each task
container after the attempt finishes.

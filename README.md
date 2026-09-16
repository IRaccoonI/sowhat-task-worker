# sowhat task worker

The task worker connects to sowhat over outbound HTTPS and starts fresh isolated containers for
explicitly authorized work. It opens no inbound port. A person owns the worker, pairs it once, and
may connect it to several spaces where that same account has worker-management permission. A space
may connect several personal or system-owned workers.

Public setup files are published at
[`IRaccoonI/sowhat-task-worker`](https://github.com/IRaccoonI/sowhat-task-worker). Use tag
`v0.4.27`; the checked-in Compose file pins the matching image by immutable digest. There is no
`latest` tag.

Do not install `v0.4.20`: its launcher used the host-side subordinate GID of a rootless Docker
socket and could fail before startup. Releases from `v0.4.21` resolve the container-visible socket
GID through the same rootless daemon before starting the worker. `v0.4.22` adds the read-only
`preset_runtime_v1` capability used by explicitly pinned AI operation routes. `v0.4.23` keeps an
operator-approved outbound proxy in the protected worker connection document so authenticated
Codex traffic can cross networks that block direct access. `v0.4.24` migrates already-paired
workers to that document without requiring a new pairing code. `v0.4.25` requires repository
feature maps to cite tracked implementation evidence instead of relying only on documentation or
deployment files. `v0.4.26` adds a complete capability inventory and claim-level evidence
self-review before a repository feature map is returned. `v0.4.27` makes application-level claims
atomic, treats material contract constraints, workload hardening and separately delivered artifacts
as map coverage, and requires evidence to cite the exact implementing helper or branch.

## Authority and privacy boundary

Worker authentication proves only the worker identity. It grants no space access. Sowhat leases a
run only when the worker has an active binding to that exact space and the binding enables the exact
capability. Repository access is resolved from that authorized space/run and passed to one
disposable child; there is no worker-global repository allowlist.

The public package defaults to the read-only Task Agent, Epic Agent and preset-runtime
capabilities. Writable task execution and external automation stay separate, visible opt-ins in
the space and retain their explicit start, policy, approval, repository and lease checks. Pairing a
worker does not start work or enable automation.

The worker never receives database, Redis, session, transcript, MCP, LiveKit or GitHub App
private-key credentials. It never records audio. Short-lived repository credentials travel only in
the authorized run and are removed before read-only Codex starts. Codex auth stays in a private
rootless-Docker volume and is never sent to sowhat.

## Requirements

- Ubuntu 24.04 `amd64` host;
- dedicated non-root operator account with `sudo` access;
- Git;
- official Docker Engine, Docker Compose plugin and `docker-ce-rootless-extras`;
- membership and `workers.manage` in at least one sowhat space;
- one Codex device-code login.

The rootless daemon must host no unrelated workloads. Never mount `/var/run/docker.sock`; the
worker rejects a rootful daemon. Install Docker using the official
[Ubuntu guide](https://docs.docker.com/engine/install/ubuntu/) and
[rootless guide](https://docs.docker.com/engine/security/rootless/).

## Setup

### 1. Download the immutable package

```bash
git clone --branch v0.4.27 --depth 1 \
  https://github.com/IRaccoonI/sowhat-task-worker.git
cd sowhat-task-worker
```

No access to the private sowhat product repository is required.

### 2. Prepare the host once

```bash
sudo scripts/setup-host.sh
```

The script installs the reviewed AppArmor profiles, enables user lingering, provisions a dedicated
rootless Docker daemon for the invoking non-root account and verifies its socket/security mode. Run
all remaining commands as that same account without `sudo`.

### 3. Pair the worker

Open **Space settings → Workers**, enter a recognizable worker name and create a pairing code. The
code expires after ten minutes and is accepted once. Then run:

```bash
scripts/worker.sh pair 'https://sowhat-ai.com'
```

Paste the code into the hidden prompt. The code is read from standard input, never from an argument
or environment variable. The helper writes a mode-`0600` connection document in the private
`sowhat-task-worker-state` volume. On the first successful registration the code is consumed and
removed from local state; only the issued worker credential remains, with only its hash stored by
sowhat.

The public worker has no `.env` file. Do not create one. Site URL, registration secret, repository
allowlist, model list, runtime profile and diagnostic toggles are not environment settings. Safe
runtime defaults live in the pinned package; exact repository scope arrives with each authorized
run.

If authenticated Codex traffic requires an outbound HTTP(S) proxy, store it through the hidden
prompt instead of creating an environment file:

```bash
scripts/worker.sh proxy
```

The proxy URL is retained only in the mode-`0600` worker connection document and is passed to each
isolated child at launch. Run the command again with an empty value to clear it. Treat a proxy URL
containing credentials as a password and never print or commit it.

### 4. Authorize Codex once

```bash
scripts/worker.sh login
```

Open the displayed OpenAI URL and enter the one-time code. The resulting credential is stored in
the rootless-Docker volume `sowhat-task-worker-codex-auth`. Treat it as a password: never print,
copy, commit or mount `auth.json` elsewhere.

### 5. Start and connect

```bash
scripts/worker.sh start
scripts/worker.sh status
```

Return to **Space settings → Workers**. The owned worker appears after registration. Connect it to
the space and review the enabled capabilities. Read-only Task Agent, Epic Agent and preset runtime
are the safe default; do not enable a writable capability unless the space's execution policy has
been separately reviewed.

## Daily operation

Run from the cloned public package as the same non-root owner:

```bash
# Pull the pinned image and start or update the coordinator.
scripts/worker.sh start

# Show container and health state.
scripts/worker.sh status

# Follow the newest metadata-only log lines; Ctrl+C stops following only.
scripts/worker.sh logs

# Stop the coordinator but retain pairing and Codex login.
scripts/worker.sh stop
```

To use the worker in another space, do not pair again. Join that space with the same sowhat account,
obtain `workers.manage`, and connect the existing owned worker from that space's Workers settings.

To move to a different sowhat installation or owner, revoke the worker in the current UI, create a
new pairing code under the intended account, and run `pair` again. Revocation disconnects every
active space binding. Repeat `login` only if the separate Codex credential should also change.

## Isolation details

Before each claim and child the coordinator verifies rootless Docker, the exact AppArmor profile,
the pinned image and bounded free disk. Every run starts a fresh non-root child with read-only root
filesystem, dropped capabilities, bounded CPU/RAM/PIDs, rotated logs and fresh tmpfs state. Task
input and short-lived repository credentials enter through standard input rather than process
arguments, image layers or persistent state. Model-authored commands have no network. The child is
removed after success or failure.

Read-only Task Agent and Epic Agent check out server-snapshotted exact SHAs, remove repository
credentials, mount repositories read-only and run Codex with approval disabled and a read-only
sandbox. Results are reports or proposed tasks, never patches. Code claims require repository,
commit SHA, regular path and valid line bounds. Writable accepted-card execution remains a distinct
capability and uses only a server-owned immutable execution profile plus its independent gates.

Content-free logs may contain worker/run identifiers, phase, elapsed time, CPU/memory and bounded
failure codes. They never contain task text, prompts, source paths, command output, pairing values,
worker/Codex/GitHub credentials or proxy values. The public package does not retain local failure
bundles.

## Troubleshooting

- **Pairing code rejected** — create a fresh code, confirm it is less than ten minutes old and has
  not already been used, then run `pair` again.
- **Worker does not appear in the space** — confirm it registered under the same account, then use
  **Connect** in that exact space; registration alone grants no space.
- **Worker is offline** — run `scripts/worker.sh status`, then `logs`; confirm the rootless Docker
  service and outbound HTTPS are available.
- **Codex login missing** — run `scripts/worker.sh login`, complete device authorization and then
  restart with `scripts/worker.sh start`.
- **Rootless socket missing** — rerun `sudo scripts/setup-host.sh` as the same operator account and
  check `systemctl --user status docker` from a real login session.
- **`permission denied` for `/run/docker.sock`** — do not substitute the rootful socket; rerun the
  pinned host setup so the helper can derive the rootless socket group.
- **Repository refused** — connect the repository to the space and start a new authorized run. Do
  not add a local allowlist; the exact scope comes from sowhat.
- **Healthy worker receives no writable task** — verify the binding explicitly enables the
  writable capability, global and space policy are enabled, the card is accepted with no blockers,
  an exact execution profile exists and an authorized manager used **Start worker**.

The coordinator stores no permanent GitHub credential, exposes no home port and removes each run
container after the attempt finishes.

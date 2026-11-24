[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/harnessrouter-3?utm_medium=integration&utm_source=button&utm_campaign=harnessrouter)

# HarnessRouter on Railway

One-click Railway template for [HarnessRouter](https://github.com/HarnessRouter/harnessrouter) Community Edition: one web console and one OpenAI Responses-compatible API for agent harnesses (Pi, OpenCode, Codex, Claude Code, Hermes and more), running on your own provider keys.

- **Version:** HarnessRouter `0.41.26`, upstream's official image `harnessrouter/harnessrouter:0.41.26@sha256:d7710cf7e6b7621fae51d18b973111075a0faab726419f021bb2e314117cdee6` (Apache-2.0).
- **Services:** one, `HarnessRouter`, built from this repo's `Dockerfile`, with a volume on `/data` (SQLite databases, task files, the encrypted secret store and the agent CLIs).
- **Login:** user `harnessrouter`, password = the generated `HR_AUTH_PASSWORD` variable (Railway → HarnessRouter → Variables). The service refuses to start with an empty or short password, or with `HR_AUTH_DISABLED=1`.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `HR_AUTH_PASSWORD` | `${{secret(32)}}` | Console password, generated. You can change it later under Profile. |
| `HR_AUTH_USER` | `harnessrouter` | Console user name. |
| `HR_SECRET_KEY` | `${{secret(48)}}` | Encrypts stored provider keys and tokens on the volume. Don't change it after the first start. |
| `PORT` | `3000` | Console port (Railway's domain points here). |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY` | empty, optional | A provider key, if you'd rather set it here than in the console. |
| `HR_BACKENDS` | empty, optional | Agent CLIs to install, comma-separated. Empty = chosen from the service's RAM and volume (see below). |

Provider keys can also be added after deploy in the console: account menu → **Bring your own key**. They're stored encrypted on the volume.

## Agent CLIs and plan size

Upstream installs the agent CLIs into the volume on first start (not into the image), so the first boot takes 20 s to 2 min. The start script picks a set that fits the service:

| Service | Agents installed by default |
|---|---|
| under 1 GB RAM, or a volume under 1.5 GB (Free/Trial plan) | Pi (about 260 MB on disk, a turn peaks near 215 MB RAM) |
| 1 GB RAM or more, volume under 4 GB | Pi, OpenCode, Codex, Claude Code |
| 1 GB RAM or more, larger volume (Hobby/Pro) | Pi, OpenCode, Codex, Claude Code, Hermes (about 2.2 GB on disk) |

OpenCode, Codex and Claude Code need **1 GB of RAM or more** per running task (OpenCode was OOM-killed at 0.5 GB). Set `HR_BACKENDS` to choose your own list from upstream's 30 bases. Turn concurrency is sized from the service's RAM and CPU (`HARNESS_GLOBAL_CONCURRENCY` overrides it).

Agent sandboxes that need Docker (upstream's "Environments" builder and the optional memory engines) are not available on Railway.

## Updates

This template builds from this repository. When the pinned version is bumped on `main`, Railway shows deployers an update notice; read `CHANGELOG.md` first, then apply it. Your data stays on the `/data` volume.

## Files

- `Dockerfile`: the pinned upstream image plus the start wrapper.
- `railway-start.sh`: password check, uid mapping, sizing, agent choice, provider keys, and a non-zero exit on any stop so Railway restarts the service.
- `CHANGELOG.md`: one entry per version, breaking changes first.

This is a community template, not affiliated with HarnessRouter.

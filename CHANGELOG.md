# Changelog

## 0.41.26 (2026-11-24)

First release of this Railway template.

- HarnessRouter Community Edition `0.41.26` (`harnessrouter/harnessrouter:0.41.26@sha256:d7710cf7…`).
- Console password from the template's generated `HR_AUTH_PASSWORD`; the service refuses to start without a password of 16+ characters or with `HR_AUTH_DISABLED=1`.
- Agent CLIs chosen from the volume size (0.5 GB volume: OpenCode only), turn concurrency sized from the service's RAM and CPU.
- Optional `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` and `OPENROUTER_API_KEY` become upstream's environment connections.

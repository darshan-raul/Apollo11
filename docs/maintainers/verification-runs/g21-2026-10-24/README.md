---
title: "G21 — identity graceful shutdown made real (2026-10-24)"
description: "Before/after evidence that identity now drains and exits on SIGTERM in Stages 4–7."
---

# G21 — identity graceful shutdown (2026-10-24)

## Defect (worse than the audit recorded)

The audit found that the `uvicorn` CLI in the Dockerfile skipped the
`timeout_graceful_shutdown=30` setting in `main.py`. A live test on the
G17 Stage 7 identity image showed more: the module-level
`signal.signal(SIGTERM, _log_sigterm)` **replaced** uvicorn's handler. On
SIGTERM, identity logged "Received SIGTERM, shutting down gracefully" and then
kept running, so in Kubernetes every identity Pod deletion waited out the
grace period and ended in SIGKILL. This affected Stages 4–7. Launchpad–Stage 3
do not have the handler.

## Fix (Stages 4, 5, 6 and 7)

- `main.py`: the module-level handler is removed. Under `__main__`, a
  `uvicorn.Server` subclass overrides `handle_exit` to log the same line, then
  calls uvicorn's own handler; it runs with `timeout_graceful_shutdown=30`.
  The unused `import signal` is removed.
- `Dockerfile`: `CMD ["python", "main.py"]` instead of the `uvicorn` CLI, so
  those settings apply.

## Evidence (`sigterm.txt`)

| Test | Result |
|---|---|
| Stage 4 image, idle, SIGTERM | SIGTERM line → uvicorn "Shutting down" → lifespan shutdown → "Finished server process"; exit 0 in 0.52 s |
| Stage 7 image, idle, SIGTERM | same sequence; exit 0 in 0.58 s |
| Stage 7 image, SIGTERM 1 s into a slow `/readyz` (DB pointed at an unreachable address, 5 s connect timeout) | the in-flight request still got its response (HTTP 503 after 5.1 s); the process then exited by itself 11.7 s after SIGTERM, within the 30 s budget |

Before the fix, the same idle SIGTERM test logged the line and the container
was still running seconds later (it had to be force-removed).

The Stage 4 verifier and the Stage 5–7 lifecycles on these images are covered
by G1f and the Stage 4 re-run recorded with it.

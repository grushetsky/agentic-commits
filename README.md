# Agentic Commits

Conventions for commits made with AI agents.

v0.1 defines **attribution**: a small, enforceable convention for recording the
agent and model that produced a commit — without an agent-specific extension
and without abusing `Co-authored-by:`.

```text
feat: reject duplicate idempotency keys

Body as usual.

Assisted-by: omp 18.18.0 (opencode-go/deepseek-v4.1-flash)
```

The trailer is written by a git `commit-msg` hook, so it works for **any**
agent that exports four environment variables before running `git commit`.
The normative contract is in [SPEC.md](./SPEC.md).

## Why

- `Co-authored-by:` is a human authorship trailer. It needs a real
  `Name <email>`, and GitHub links it to an account. Agents invent addresses
  for it; at least one such address was registered by an unrelated person and
  mis-attributed commits ([claude-code#1653](https://github.com/anthropics/claude-code/issues/1653)).
- Existing `Assisted-by:` uses incompatible values: `<tool>`, `<tool>:<model>`,
  `<agent>/<model>`, `Name <email>`.
- Agent extensions only cover their own agent. A git hook covers all of them,
  including agents that do not exist yet.

## Format

```text
Assisted-by: <AGENT_NAME> <AGENT_VERSION> (<AGENT_MODEL_PROVIDER_SLUG>/<AGENT_MODEL_SLUG>)
```

| Variable | Example | Grammar |
| --- | --- | --- |
| `AGENT_NAME` | `omp` | lowercase dash-case |
| `AGENT_VERSION` | `18.18.0` | `[0-9A-Za-z][0-9A-Za-z.+-]*` |
| `AGENT_MODEL_PROVIDER_SLUG` | `opencode-go` | lowercase dash-case |
| `AGENT_MODEL_SLUG` | `deepseek-v4.1-flash` | lowercase dash-case; dots allowed in version segments |

Rules that matter:

- All four variables or none. None means "human commit" and produces no trailer.
  A partial set is a broken integration and fails the commit.
- Values are verified runtime metadata. Do not ask the model to name itself.
- One `Assisted-by:` trailer per commit. Merges, cherry-picks, reverts, and
  rebases are skipped.
- The hook is idempotent: if the message already has an `Assisted-by:` trailer,
  it does nothing.
- `ASSISTED_BY=0` opts a single commit out.

## Quick start

```sh
git clone <this repo> agentic-commits
cd agentic-commits
mise install            # hk 2.11.1
hk install              # register the commit-msg hook
```

To adopt it in an existing repository, copy `hk.pkl` and `hooks/` into it (or
merge the `commit-msg` hook into your `hk.pkl`) and run `hk install`.

Prefer plain git? The script is a normal `commit-msg` hook:

```sh
ln -s ../../hooks/assisted-by-commit-msg .git/hooks/commit-msg
```

Or, with Git ≥ 2.54, install it globally without touching repositories:

```sh
git config --global hook.assisted-by.event commit-msg
git config --global hook.assisted-by.command ~/path/to/assisted-by-commit-msg
```

## For agent authors

Export the four variables into the environment of every tool subprocess that
can run `git`, and update them when the model changes:

```sh
export AGENT_NAME=omp
export AGENT_VERSION=18.18.0
export AGENT_MODEL_PROVIDER_SLUG=opencode-go
export AGENT_MODEL_SLUG=deepseek-v4.1-flash
git commit -m "feat: ..."
```

Agents that do not set these variables can still be attributed by an adapter,
but the standard itself is the environment contract. Do not add
`Co-authored-by:` for the agent; do not fabricate values the runtime cannot
provide.

## Verify

```sh
git log -1 --format=%B
git log -1 --format='%(trailers:key=Assisted-by,valueonly)'
```

## Repository layout

```text
SPEC.md                          normative specification
hk.pkl                           hk commit-msg hook
hooks/assisted-by-commit-msg     reference hook (also usable as a git hook)
examples/hk-config.pkl           user-level hk configuration
tests/run.sh                     hook and hk integration tests
```

Run the tests with `./tests/run.sh`.

## Status

Draft 0.1.0. The trailer key and variable names are stable; the value grammar
may still change before 1.0.0. Changes are versioned with SemVer.

Prior art and the disagreements between projects (Fedora, LLVM, OpenInfra,
HyperSpy, the Linux kernel, Kubernetes, Apache) are summarized in
[SPEC.md §12](./SPEC.md#12-prior-art).

# AGENTS.md

This repository defines the Assisted-by Standard. `SPEC.md` is normative;
everything else is an implementation of it.

When working here:

1. Read `SPEC.md` before changing the hook, the grammar, or the variable names.
2. Any change to the trailer grammar, variable names, or hook behavior is a
   breaking change: bump the version in `SPEC.md` and `README.md`, and update
   `tests/run.sh`.
3. When committing in this repository, export the four variables so the
   repository's own hook attributes the commit:

   ```sh
   AGENT_NAME=omp \
   AGENT_VERSION=18.18.0 \
   AGENT_MODEL_PROVIDER_SLUG=opencode-go \
   AGENT_MODEL_SLUG=deepseek-v4.1-flash \
   git commit -m "..."
   ```

   Use your real runtime values; do not copy these blindly.
4. Never add `Co-authored-by:` for an agent. This standard uses `Assisted-by:`.
5. Run `./tests/run.sh` before committing. If `hk` is available, also run
   `hk check --all`.
6. Keep `README.md` examples in sync with `SPEC.md`. Examples must be executable
   as written.

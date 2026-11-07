# Assisted-by Standard

**Version:** 0.1.0 (Draft) · **Status:** Proposal for adoption · **Trailer key:** `Assisted-by`

## 0. Abstract

This document defines a commit-message trailer and an environment contract that
let any coding agent identify itself and the model that produced a commit,
independently of the agent's implementation. A git `commit-msg` hook — shipped
here as an `hk` step — turns the environment contract into exactly one trailer
line:

```text
Assisted-by: <agent-name> <agent-version> (<provider-slug>/<model-slug>)
```

The standard is enforced by git, so it works for any current or future agent
that sets four environment variables before running `git commit`.

## 1. Motivation

Existing agent attribution is inconsistent and often abusive:

- `Co-authored-by:` is a **human** authorship trailer. It requires
  `Name <email>`, and GitHub links it to an account. Agents invent addresses
  for it; one such address was registered by an unrelated person and caused
  commits to be attributed to them
  ([anthropics/claude-code#1653](https://github.com/anthropics/claude-code/issues/1653)).
- Existing `Assisted-by:` usage has no common value grammar: `<tool>`,
  `<tool>:<model>`, `<agent>/<model>`, and `Name <email>` all appear in the
  wild (Fedora, LLVM, HyperSpy, the Linux kernel, KubeVirt).
- Attribution implemented as an agent extension only works for that agent and
  is lost when the tool changes.

This standard fixes the value grammar, the environment contract, and the
enforcement point.

## 2. Conformance

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL are to be interpreted as described in RFC 2119.

An implementation is conformant when it satisfies §5 (hook behavior) and §6
(agent requirements). The reference implementation in `hooks/` and the `hk.pkl`
config are informative examples of a conformant implementation.

## 3. The trailer

### 3.1 Syntax

```text
Assisted-by: <agent-name> <agent-version> (<provider-slug>/<model-slug>)
```

Exactly one space separates each token. The provider and model are enclosed in
parentheses and separated by `/`.

### 3.2 Grammar

```abnf
trailer      = "Assisted-by" ":" SP agent SP version SP "(" provider "/" model ")"
agent        = dash-slug
version      = vchar1 *( "." / "+" / "-" / ALPHA / DIGIT )
provider     = dash-slug
model        = model-slug
dash-slug    = lc-alnum *( "-" lc-alnum )
model-slug   = lc-alnum *( ( "-" / "." ) lc-alnum )
lc-alnum     = %x61-7A / DIGIT
vchar1       = ALPHA / DIGIT
SP           = %x20
```

Dots are permitted in `model-slug` only, for version segments such as
`deepseek-v4.1-flash`. This is the "dash case" used by omp's model identifiers.
No token may contain whitespace or control characters.

### 3.3 Position and count

- The line MUST be a Git trailer: the final paragraph of the commit message,
  separated from the body by one blank line.
- The trailer block MAY contain other trailers (for example
  `Signed-off-by:`); the hook appends `Assisted-by:` to the end of that block.
- A commit MUST contain at most one `Assisted-by:` trailer.
- Implementations MUST NOT rewrite the message body or existing trailers.

### 3.4 Case

The canonical key is `Assisted-by`. Git trailer matching is case-insensitive
(verified: `%(trailers:key=Assisted-by)` matches `Assisted-By:`), so readers
MUST match case-insensitively. Writers MUST emit the canonical spelling.

### 3.5 Examples

```text
Assisted-by: omp 18.18.0 (opencode-go/deepseek-v4.1-flash)
Assisted-by: claude-code 2.0.14 (anthropic/claude-sonnet-4-6)
Assisted-by: opencode 1.18.28 (opencode/ling-3.0-flash-fin-free)
Assisted-by: pi 1.5.0 (opencode/ling-3.0-flash-fin-free)
```

## 4. Environment contract

### 4.1 Variables

| Variable | REQUIRED | Grammar | Example |
| --- | --- | --- | --- |
| `AGENT_NAME` | yes | `dash-slug` | `omp` |
| `AGENT_VERSION` | yes | `version` | `18.18.0` |
| `AGENT_MODEL_PROVIDER_SLUG` | yes | `dash-slug` | `opencode-go` |
| `AGENT_MODEL_SLUG` | yes | `model-slug` | `deepseek-v4.1-flash` |

### 4.2 Requirements

1. An agent that contributes commits MUST export all four variables into the
   environment of every child process that can invoke `git`.
2. The values MUST describe the agent and model of the turn making the commit.
   The agent MUST update them when the active model changes.
3. The four variables are **all-or-none**. Setting any one of them REQUIRES
   setting all four. Setting none means "not an agent commit" and MUST produce
   no trailer.
4. Values MUST match §3.2. The agent MUST NOT rely on the hook to normalize
   names, versions, or slugs.
5. The variables MUST be inherited by tool subprocesses. A wrapper that starts
   the agent MAY set them once if the model cannot change; otherwise the agent's
   tool runner MUST set them per call.

### 4.3 Slugs

- Slugs are lowercase and dash-cased: `claude-code`, `opencode-go`,
  `deepseek-v4.1-flash`. Uppercase, underscores, spaces, and slashes are
  invalid.
- `AGENT_NAME` is the tool's canonical short name (`omp`, `pi`, `opencode`),
  not the model name.
- `AGENT_VERSION` is the agent's version, not the model's.
- The model version belongs in `AGENT_MODEL_SLUG`.

### 4.4 Precedence

If the commit message already contains an `Assisted-by:` trailer, the hook MUST
leave it untouched. This allows an agent to pass its own
`git commit --trailer ...` and keeps the hook idempotent.

## 5. Hook behavior

A conformant `commit-msg` hook receives the message file as its first argument
and MUST implement this order:

1. If `ASSISTED_BY=0`, exit 0 without changes (per-commit opt-out).
2. If the message already contains an `Assisted-by:` trailer
   (case-insensitive), exit 0.
3. If the commit is a merge, cherry-pick, revert, or rebase, exit 0.
4. Count the four variables:
   - none set → exit 0 (human commit);
   - some but not all → fail with a diagnostic naming the missing variables;
   - all set → continue.
5. Validate every value against §3.2. Invalid values MUST fail the commit with
   a diagnostic naming the variable.
6. Append exactly one trailer:

   ```text
   Assisted-by: <name> <version> (<provider>/<model>)
   ```

   using a trailer-aware mechanism (`git interpret-trailers --in-place`), then
   exit 0.

A failing hook MUST leave the message file unchanged. The hook MUST NOT use
shell evaluation on environment values and MUST NOT accept control characters;
this prevents trailer injection.

## 6. Agent requirements

An agent adopting this standard:

1. MUST export the four variables per §4.
2. SHOULD set them from verified runtime state, never from a model-generated
   string. The model id is runtime metadata, not something the model reports.
3. MUST NOT add `Co-authored-by:` for itself. That trailer is reserved for
   humans; projects that accept it for tools may still receive it, but this
   standard does not use it.
4. MAY pass its own `--trailer`; the hook is idempotent.
5. MUST NOT fabricate an identity when the runtime cannot provide one. Omit the
   variables rather than guessing.

## 7. Adoption

### 7.1 hk

Copy `hk.pkl` and `hooks/` into the repository and run `hk install` (or add the
hook to an existing `hk.pkl`). The repository config runs the reference hook:

```pkl
hooks {
  ["commit-msg"] {
    steps {
      ["assisted-by"] {
        check = "./hooks/assisted-by-commit-msg '{{commit_msg_file}}'"
      }
    }
  }
}
```

For a user-level setup, install the script on `PATH` and put the same hook in
`~/.config/hk/config.pkl` (see `examples/hk-config.pkl`). Note that
`hk install --global` only runs in repositories that have an hk configuration.

### 7.2 Plain git

The same script works as a Git hook directly:

```sh
ln -s ../../hooks/assisted-by-commit-msg .git/hooks/commit-msg
```

or, on Git ≥ 2.54, without touching the repository:

```sh
git config --global hook.assisted-by.event commit-msg
git config --global hook.assisted-by.command ~/path/to/assisted-by-commit-msg
```

### 7.3 Verification

```sh
git log -1 --format=%B
git log -1 --format='%(trailers:key=Assisted-by,valueonly)'
```

## 8. Compatibility

- The trailer is ordinary Git trailer syntax and works with
  `git interpret-trailers`, `git log --format='%(trailers:key=Assisted-by)'`,
  and any tool that parses trailers.
- The value contains no email address, so GitHub will not attribute the commit
  to an account. That is intentional: this is tool provenance, not human
  co-authorship.
- The format is intentionally machine-parsable: agent, version, provider, and
  model are separate tokens.

## 9. Security considerations

- Environment values are untrusted input. A conformant hook MUST validate them
  against §3.2 before interpolation.
- Values MUST NOT contain newlines, carriage returns, tabs, or other control
  characters; otherwise they could inject additional trailers.
- `AGENT_*` variables are advisory metadata, not an authentication mechanism.
  Anyone can set them.
- The hook is not a substitute for human review, DCO sign-off, or the
  `Signed-off-by:` trailer.

## 10. Versioning

This specification uses SemVer. Changes to the trailer grammar, variable names,
or required behavior are breaking (major). Adding examples or clarifying text
is minor or patch.

## 11. Non-goals

- Legal attestation or proof of authorship.
- GitHub co-author credit or contribution graphs.
- Recording every model that touched a branch (see §3.3: one trailer per
  commit).
- Replacing `Signed-off-by:` or the Developer Certificate of Origin.

## 12. Prior art

- **Fedora** and **LLVM** recommend `Assisted-by: <name of code assistant>`
  in their AI contribution policies.
- **OpenInfra** recommends the `Assisted-By` label.
- **HyperSpy** requires `Assisted-by: <tool>:<model>`.
- The **Linux kernel** uses `Assisted-by: <Tool>:<model>` in commit practice;
  its process documents do not define the format.
- **Kubernetes** forbids AI attribution trailers; **Apache** prefers
  `Generated-by:`/`Co-authored-by:`. This standard deliberately picks one
  grammar instead of following each project's variant.

## 13. References

- [Git trailer documentation](https://git-scm.com/docs/git-interpret-trailers)
- [Fedora AI-Assisted Contributions policy](https://communityblog.fedoraproject.org/council-policy-proposal-policy-on-ai-assisted-contributions/)
- [LLVM AI Tool Use Policy](https://llvm.org/docs/AIToolPolicy.html)
- [OpenInfra AI policy](https://openinfra.org/legal/ai-policy/)
- [HyperSpy AI attribution guide](https://hyperspy.org/hyperspy-doc/current/dev_guide/coding_with_ai.html)
- [hk commit-message hooks](https://hk.jdx.dev/hooks#commit-message-hooks)

# Verification matrix

Single source of truth for **which test suites must run when**. The
canonical commands live here; **build-story**, **build-epic**, and
**finish-epic** reference this file rather than inlining commands.

## Trigger matrix

| Trigger | Required commands |
|---------|-------------------|
| **Any story** (always) | `cd compiler && npm run build && npm test` |
| **Any story** (always) | `./scripts/kestrel test` |
| **JVM runtime touched** (`runtime/jvm/src/**`) | `cd runtime/jvm && bash build.sh` |
| **User-visible behaviour or new E2E case** (`tests/e2e/**`, CLI output, codegen) | `./scripts/run-e2e.sh` |
| **Epic close** (`finish-epic`) | All of the above |

## Decision rule

A trigger is "hit" if the diff modifies any path matching the trigger's
predicate. When in doubt, run the suite — false positives cost time;
false negatives cost correctness.

## Order

Run in this order so failures surface from cheapest first:

1. `cd compiler && npm run build && npm test`
2. `./scripts/kestrel test`
3. `cd runtime/jvm && bash build.sh` (if triggered)
4. `./scripts/run-e2e.sh` (if triggered)

## Failure protocol

If any required suite fails, follow
[`failure-protocol.md`](failure-protocol.md): halt, paste the failing
output verbatim, do not advance the story or epic phase, do not commit.

## When tasks reference these commands

When **plan-story** writes the `## Tasks` list, each required command
becomes its own `- [ ]` task so that **build-story** ticks them
explicitly.

# 12 – Agent Enablement and Knowledge Distribution

Version: 1.0

---

This document specifies how Kestrel enables coding agents to reliably write, read, and evolve Kestrel code. It defines distribution requirements, agent-oriented language documentation, public documentation hosting, and repository-level agent behavior.

This spec complements:
- Core language semantics in 01-language.md
- CLI and tooling in 09-tools.md
- Bootstrap and self-hosting in 11-bootstrap.md

---

## 1. Problem Statement

Kestrel is a new language, so general-purpose agents often fail due to:
- Incomplete language knowledge
- No stable, concise machine-oriented language reference
- Limited access to current stdlib documentation
- Environment setup friction during first use

The project needs a first-class agent enablement surface so agents can produce correct Kestrel code with predictable behavior.

---

## 2. Goals

1. Provide a one-stop install and run path for users and agents with minimal host dependencies.
2. Provide a definitive, concise language definition designed for agent consumption.
3. Provide publicly reachable stdlib and module documentation that agents can query.
4. Provide repository-level agent instructions so agent behavior is consistent across tools.
5. Keep normative truth in existing specs while publishing an operational agent profile.

---

## 3. Non-Goals

- Replacing normative language specs.
- Introducing a separate language dialect for agents.
- Requiring internet connectivity for all workflows.
- Coupling core compiler correctness to any single external AI platform.

---

## 4. Architecture Overview

Agent enablement consists of four surfaces:

1. Distribution Surface
- A minimal bootstrap/install flow for execution and compilation.
- Runtime and compiler artifacts are consumable without local source builds for standard usage.

2. Agent Language Profile Surface
- A concise, stable, machine-oriented language reference derived from normative specs.

3. Documentation Surface
- Hosted documentation for stdlib and project API shape, including machine-readable index/search.

4. Agent Behavior Surface
- Repository-level instructions that direct agents to preferred references, conventions, and checks.

---

## 5. Distribution Requirements

### 5.1 Baseline Runtime

The baseline user-agent experience must support:
- Running Kestrel CLI commands after installation with Java present.
- Network retrieval of signed or checksummed artifacts.

Intended minimal dependency target:
- Java runtime
- curl-compatible HTTP client

### 5.2 Artifact Strategy

The project must publish versioned artifacts sufficient for bootstrap and runtime usage:
- Runtime artifact
- Bootstrap compiler artifact
- Integrity metadata (checksums and optionally signatures)
- Version manifest mapping CLI version to artifact versions

### 5.3 Installer Contract

A one-command installer flow must:
- Detect platform prerequisites.
- Download artifacts from a stable release location.
- Verify integrity before install.
- Install artifacts into Kestrel cache layout compatible with bootstrap spec.
- Print clear remediation on failure.

### 5.4 Build Toolchain Separation

Maintainer build dependencies may remain broader, but end-user and agent install path must not require building from source for normal usage.

---

## 6. Agent Language Profile (ALP)

### 6.1 Purpose

The ALP is a concise agent-facing language definition optimized for generation correctness.

### 6.2 Normative Relationship

- Normative rules remain in 01-language.md, 06-typesystem.md, and 07-modules.md.
- ALP is derivative, not normative.
- Any conflict is resolved in favor of normative specs.

### 6.3 Required ALP Content

The ALP must include:
- Lexical and syntax quick rules used most in generation
- Expression and statement forms
- Function, type, and pattern conventions
- Module import/export patterns
- Error handling and async model essentials
- Common gotchas and invalid patterns
- Canonical short examples for major constructs
- Stdlib usage patterns for high-frequency modules

### 6.4 Machine-Readability

ALP must be published in:
- Human-readable markdown
- Machine-oriented structured format (for example JSON) with stable keys and version field

### 6.5 Versioning

ALP version must track language/spec revisions and include:
- Effective version
- Source spec revisions
- Compatibility notes

---

## 7. Documentation Hosting Requirements

### 7.1 Scope

Hosted docs must include:
- Stdlib module docs
- Declaration-level docs
- Search and index APIs suitable for agent querying
- Stable URLs and versioned snapshots

### 7.2 Source of Data

Primary source is the existing documentation pipeline implemented by `kestrel doc` and doc extraction/render/index modules.

### 7.3 API Stability

Public doc APIs must provide:
- Search endpoint with deterministic ranking behavior
- Full index endpoint with declaration metadata
- Version marker identifying language and stdlib snapshot
- Backward-compatible evolution policy for at least one major cycle

### 7.4 Offline and Local Fallback

Agents in restricted environments must still be able to:
- Use local docs via existing local doc server
- Resolve against checked-in specs if hosted docs are unavailable

---

## 8. Repository Agent Instructions

### 8.1 Required Instruction Surfaces

Repository must include agent guidance defining:
- Preferred reference order for Kestrel tasks
- Required validation and test commands by task type
- Style and documentation conventions
- Safety and scope constraints

### 8.2 Reference Order

For generation tasks, instructions must direct agents to consult:
1. ALP
2. Relevant normative specs
3. Hosted or local docs index
4. Existing project examples and tests

### 8.3 Conventions

Instruction content must reinforce project conventions and testing/spec update requirements.

---

## 9. Quality Gates and Acceptance Criteria

### 9.1 Agent Task Accuracy Gate

Define an evaluation set of representative Kestrel tasks with expected outputs. Measure:
- Parse success rate
- Typecheck success rate
- Runtime correctness rate
- Edit success with existing tests

Target: monotonic improvement release-over-release.

### 9.2 Documentation Freshness Gate

Hosted docs and ALP must be regenerated on release and when relevant specs or stdlib signatures change.

### 9.3 Install Experience Gate

Fresh-machine install must be validated in CI for supported platforms using only baseline dependencies.

### 9.4 Regression Gate

Changes to language semantics or stdlib APIs must trigger:
- ALP update check
- Docs snapshot update check
- Release manifest consistency check

---

## 10. Security and Integrity

- All downloaded artifacts must be integrity-checked.
- Release manifests must be tamper-evident.
- Public docs endpoints must not expose local filesystem paths or sensitive runtime metadata.
- Hosted docs generation must sanitize rendered content and preserve escaping guarantees.

---

## 11. Rollout Plan (Normative Phases)

Phase 1: Documentation Publication
- Publish stable hosted docs and machine-readable index from current doc pipeline.

Phase 2: Agent Language Profile
- Publish ALP v1 derived from current normative specs.

Phase 3: Minimal Dependency Installer
- Deliver one-command installer with integrity verification and artifact manifest.

Phase 4: Repository Agent Integration
- Add and validate repository instruction files for consistent agent behavior.

Phase 5: Evaluation and Hardening
- Introduce agent benchmark tasks and enforce quality gates in CI.

---

## 12. Epic Decomposition Guidance (Informative)

Recommended epic tracks:
1. Distribution and installer
2. Agent language profile and schema
3. Docs hosting and API stability
4. Repository agent instructions and workflows
5. Agent quality evaluation and CI gates

Each epic should include:
- Story-level acceptance criteria tied to sections 5 through 9
- Explicit spec and docs update tasks
- End-to-end validation commands

---

## 13. Change Management

Any change to this spec affecting runtime behavior, API contracts, or compatibility requirements must update:
- Tools spec when CLI or route contracts change
- Bootstrap spec when bootstrap/install behavior changes
- README when user-facing setup requirements change
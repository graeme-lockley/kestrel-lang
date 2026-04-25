# Commit messages

Used by **build-story** and **build-epic**. Kestrel follows
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

## Shape

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Allowed types

`feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`, `style`.

## Allowed scopes

`parser`, `typecheck`, `codegen`, `jvm`, `stdlib`, `cli`, `vm`, `e2e`,
`kanban`, `skills`.

## Patterns by skill phase

### Story plan committed (build-epic step 3b)

```
docs(kanban): plan S##-## <slug>
```

### Story implementation committed (build-story / build-epic step 3e)

Use the dominant change type — never a generic "build story S##-##".

```
feat(typecheck): infer return type of recursive functions
fix(codegen): emit correct opcode for nested let bindings
refactor(jvm): consolidate intrinsic dispatch
docs(kanban): close S##-## <slug>     # only if doc-only
```

### Epic plan refresh (build-epic step 2)

```
docs(kanban): refresh EXX epic plan before build
```

### Epic close (finish-epic step 6)

```
docs(kanban): close epic EXX <slug>
```

## Breaking changes

Append `!` after the type/scope and add a `BREAKING CHANGE:` footer:

```
feat(parser)!: remove support for legacy syntax

BREAKING CHANGE: the `=>` arrow form is no longer accepted; use `->` instead.
```

## Forbidden

- Generic messages: `update`, `wip`, `build story S##-##`.
- Multi-purpose commits: split unrelated changes.
- `git push --force` — never use without explicit author approval.

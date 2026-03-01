# Deep review: Block var and nested-function codegen changes

## Scope of the change

All edits are in **`compiler/src/codegen/codegen.ts`**, in the `BlockExpr` case of `emitExpr` (approx. lines 599–677), plus the fix for closure slot reservation.

---

## 1. Workarounds and fragile patterns

### 1.1 Placeholder entries to pad `blockEnv` (lines 611–612)

```ts
for (let i = blockEnv.size; i < blockLocalStart + 1; i++) blockEnv.set(`\x00_${i}`, i);
```

**What it does:** When inside a closure and we reserve `blockLocalStart = 2` for `$discard`, we add synthetic map entries so that the *next* slot assigned to a VarStmt/ValStmt is `blockLocalStart + 1`, avoiding `$discard` and the first block var sharing the same slot.

**Why it’s a workaround:** We’re overloading `blockEnv` for two roles:

- Name → slot for **lookup** (real names: `$discard`, `x`, etc.).
- **Slot allocation** by “next index” = `blockEnv.size`.

Padding forces the next index to be `blockLocalStart + 1` by stuffing the map with extra entries. So the map is no longer “only names that are looked up”; it’s also used as a counter.

**Risks:**

- **Name collision:** Keys are `\x00_0`, `\x00_1`, … so they’re not valid user identifiers and won’t appear in the AST. `IdentExpr` and `getFreeVars` only use names from the AST, so they won’t resolve these. Low risk.
- **Maintainability:** A later change that iterates `blockEnv` or assumes “every key is a real binding” could be surprised. The intent is non-obvious without the comment.

**Cleaner alternative:** Track “next block-local slot” explicitly (e.g. a variable `nextBlockSlot`) instead of deriving it from `blockEnv.size`, and stop using the map as the source of slot counts. Then no placeholder entries are needed.

---

### 1.2 Magic number `2` for closure slot reservation (line 608)

```ts
const blockLocalStart = captures != null ? Math.max(blockEnv.size, 2) : blockEnv.size;
```

**What it does:** When we’re inside a lambda that has captures (`captures != null`), we force block-local slots to start at least at index 2, so we don’t use slot 0 (closure env) or slot 1 (first parameter in the lifted layout).

**Why it’s fragile:**

- **Assumption:** Lifted layout is always `[__env, param0, param1, ...]`, so the smallest “used” range is 2 slots. That matches the current closure convention (`liftedEnv.set('__env', 0); ... liftedEnv.set(expr.params[i]!.name, i + 1)`).
- **Over-reservation:** A 0-arity closure still has `blockEnv.size === 1` (only `__env`). We still set `blockLocalStart = 2`, so we reserve slot 1 even though nothing uses it. Harmless but magic.
- **Tight coupling:** If closure conversion ever changes (e.g. env at a different index, or multiple env slots), this `2` becomes wrong and would need to be updated in sync.

**Cleaner alternative:** Derive the “first block-local slot” from the actual closure layout (e.g. “1 + number of params” when `captures != null`) or from a shared constant that describes the lifted frame layout, instead of the literal `2`.

---

### 1.3 Using `captures != null` as “inside a closure” (line 608)

**What it does:** We use `captures != null` to decide whether to apply the “reserve 2 slots” rule.

**Limitation:** A **non-capturing** lambda still has a single parameter (e.g. `(sg) => ...`). Its frame is only 1 slot (the param at 0). So we don’t reserve slot 1, and we use `$discard` at 1 and the var at 2. That’s correct because the param is at 0. So the bug we fixed was specifically “capturing lambda: env at 0, param at 1”. So the heuristic “when captures != null, reserve 2 slots” is correct for the current design; it’s just a bit opaque and tied to that layout.

---

## 2. Suspicious or inconsistent code

### 2.1 No discard after `AssignStmt` to a record field (lines 639–643)

For `r.x := value` we do:

```ts
emitExpr(target.object, ...);
emitExpr(stmt.value, ...);
emitSetField(fieldSlot);
// no discard
```

`SET_FIELD` leaves Unit on the stack. We don’t store it into `$discard`, unlike ident assignment and ExprStmt.

**Impact:** The next statement or `expr.result` pushes on top, and `RET` pops only the top, so the block still returns the right value. Stack depth is one higher than necessary in the block. So behaviour is correct, but it’s **inconsistent** with:

- ExprStmt: we discard.
- AssignStmt to ident (block var or capture): we discard.

**Recommendation:** If `needsDiscard` is true and we’re in the FieldExpr branch, also get `$discard` and emit `emitStoreLocal(discardSlot)` after `emitSetField(fieldSlot)` for consistency and to avoid unnecessary stack growth.

---

### 2.2 AssignStmt to ident: non-var branch doesn’t discard (lines 661–669)

When the target is an ident but *not* a block var (e.g. top-level or local `val`), we do:

```ts
emitExpr(stmt.value, ...);
if (localSlot !== undefined) emitStoreLocal(localSlot);
else if (gSlot !== undefined) emitStoreGlobal(gSlot);
```

We push the value and store it; we don’t push Unit. So we don’t need a discard there. Only the branches that use `SET_FIELD` (block var or captured var) push Unit and need discarding. So this is **consistent**; no change needed.

---

### 2.3 `$discard` and `\x00_*` as special names

- **`$discard`:** Used only in codegen; never in AST or typecheck. All uses are `blockEnv.get('$discard')` and `blockEnv.set('$discard', ...)`. Safe as long as no user code can bind `$discard` (parser/ast don’t expose it).
- **`\x00_${i}`:** Only used as map keys to pad `blockEnv`. Not used for lookup from AST. Safe but undocumented; a short comment above the loop would help.

---

## 3. Correctness notes (no change suggested)

- **VarStmt order:** Emit initial value, then `ALLOC_RECORD`, then `STORE_LOCAL(slot)`. Matches VM (ALLOC_RECORD pops one value per field). Correct.
- **AssignStmt (block var) order:** `LOAD_LOCAL(slot)` then value then `SET_FIELD(0)`. Matches VM (record at `sp-2`, value at `sp-1`). Correct.
- **Discard when `needsDiscard`:** We allocate `$discard` when there is any ExprStmt or AssignStmt and use it after each such statement that leaves Unit on the stack. Correct for the branches that currently push Unit (ExprStmt, block-var/capture AssignStmt).
- **nextVarNames:** Built from `varNames` and all block `VarStmt` names so that both “is this a var?” and “assign to block var” are consistent. Correct.

---

## 4. Summary table

| Item | Type | Severity | Action |
|------|------|----------|--------|
| Placeholder padding `\x00_${i}` | Workaround | Medium | Prefer explicit `nextBlockSlot` (or similar) instead of overloading `blockEnv.size`. |
| Magic number `2` for closure reserve | Fragile | Medium | Derive from actual closure layout or shared constant. |
| `captures != null` as “in closure” | Implicit contract | Low | Document or replace with a clearer predicate if the layout rule is ever generalized. |
| No discard after FieldExpr AssignStmt | Inconsistency | Low | Add discard when `needsDiscard` and target is FieldExpr (optional, for consistency and stack depth). |
| Special names `$discard`, `\x00_*` | Convention | Low | Add a one-line comment that blockEnv may contain internal keys not from the AST. |

---

## 5. Suggested follow-ups (optional)

1. **Refactor slot allocation:** Introduce a single “next block-local slot” variable (or a small helper) so that `$discard` and each VarStmt/ValStmt get a slot from that counter and the map is only used for name→slot lookup. Then remove the placeholder loop.
2. **Centralize closure layout:** Define the layout (e.g. “env at 0, params at 1, 2, …”) in one place and use it both in LambdaExpr codegen and in BlockExpr when computing `blockLocalStart`.
3. **Document internal keys:** At the top of the BlockExpr case or in a shared comment, state that `blockEnv` may contain internal keys (e.g. `$discard`, padding) that are not user-defined and are only used by codegen.

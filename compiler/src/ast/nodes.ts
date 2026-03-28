/**
 * AST node types (spec 01 §3). All nodes have kind and optional span.
 */
import type { Span } from '../lexer/types.js';

export interface NodeBase {
  span?: Span;
}

export interface Program extends NodeBase {
  kind: 'Program';
  imports: ImportDecl[];
  body: (TopLevelDecl | TopLevelStmt)[];
}

export type ImportDecl = NamedImport | NamespaceImport | SideEffectImport;

export interface NamedImport extends NodeBase {
  kind: 'NamedImport';
  spec: string;
  specs: { external: string; local: string }[];
}

export interface NamespaceImport extends NodeBase {
  kind: 'NamespaceImport';
  spec: string;
  name: string;
}

export interface SideEffectImport extends NodeBase {
  kind: 'SideEffectImport';
  spec: string;
}

export type TopLevelDecl = FunDecl | TypeDecl | ExceptionDecl | ExportDecl | ValDecl | VarDecl;

export interface ValDecl extends NodeBase {
  kind: 'ValDecl';
  name: string;
  type?: Type;
  value: Expr;
}

export interface VarDecl extends NodeBase {
  kind: 'VarDecl';
  name: string;
  type?: Type;
  value: Expr;
}

export interface ExportDecl extends NodeBase {
  kind: 'ExportDecl';
  inner: TopLevelDecl | ExportStar | ExportNamed;
}

export interface ExportStar extends NodeBase {
  kind: 'ExportStar';
  spec: string;
}

export interface ExportNamed extends NodeBase {
  kind: 'ExportNamed';
  spec: string;
  specs: { external: string; local: string }[];
}

export interface FunDecl extends NodeBase {
  kind: 'FunDecl';
  exported: boolean;
  async: boolean;
  name: string;
  typeParams?: string[];
  params: Param[];
  returnType: Type;
  body: Expr;
}

export interface Param extends NodeBase {
  kind: 'Param';
  name: string;
  type?: Type;
}

export type TypeVisibility = 'local' | 'opaque' | 'export';

export interface TypeDecl extends NodeBase {
  kind: 'TypeDecl';
  visibility: TypeVisibility;
  name: string;
  typeParams?: string[];
  body: TypeDeclBody;
}

export type TypeDeclBody = TypeAliasBody | ADTBody;

export interface TypeAliasBody extends NodeBase {
  kind: 'TypeAliasBody';
  type: Type;
}

export interface ADTBody extends NodeBase {
  kind: 'ADTBody';
  constructors: ConstructorDef[];
}

export interface ConstructorDef extends NodeBase {
  name: string;
  params: Type[];
}

export interface ExceptionDecl extends NodeBase {
  kind: 'ExceptionDecl';
  name: string;
  fields?: TypeField[];
}

export interface TypeField extends NodeBase {
  kind: 'TypeField';
  name: string;
  mut: boolean;
  type: Type;
}

export type Type =
  | IdentType
  | QualifiedType
  | PrimType
  | ArrowType
  | RecordType
  | RowVarType
  | AppType
  | UnionType
  | InterType
  | TupleType;

export interface IdentType extends NodeBase {
  kind: 'IdentType';
  name: string;
}

export interface QualifiedType extends NodeBase {
  kind: 'QualifiedType';
  namespace: string;
  name: string;
}

export interface PrimType extends NodeBase {
  kind: 'PrimType';
  name: 'Int' | 'Float' | 'Bool' | 'String' | 'Unit' | 'Char' | 'Rune';
}

export interface ArrowType extends NodeBase {
  kind: 'ArrowType';
  params: Type[];
  return: Type;
}

export interface RecordType extends NodeBase {
  kind: 'RecordType';
  fields: TypeField[];
}

export interface RowVarType extends NodeBase {
  kind: 'RowVarType';
  name: string;
}

export interface AppType extends NodeBase {
  kind: 'AppType';
  name: string;
  args: Type[];
}

export interface UnionType extends NodeBase {
  kind: 'UnionType';
  left: Type;
  right: Type;
}

export interface InterType extends NodeBase {
  kind: 'InterType';
  left: Type;
  right: Type;
}

export interface TupleType extends NodeBase {
  kind: 'TupleType';
  elements: Type[];
}

export type TopLevelStmt = ValStmt | VarStmt | AssignStmt | ExprStmt;

export interface ValStmt extends NodeBase {
  kind: 'ValStmt';
  name: string;
  type?: Type;
  value: Expr;
}

export interface VarStmt extends NodeBase {
  kind: 'VarStmt';
  name: string;
  type?: Type;
  value: Expr;
}

export interface AssignStmt extends NodeBase {
  kind: 'AssignStmt';
  target: Expr;
  value: Expr;
}

export interface ExprStmt extends NodeBase {
  kind: 'ExprStmt';
  expr: Expr;
}

export interface FunStmt extends NodeBase {
  kind: 'FunStmt';
  name: string;
  typeParams?: string[];
  params: Param[];
  returnType: Type;
  body: Expr;
}

export interface BreakStmt extends NodeBase {
  kind: 'BreakStmt';
}

export interface ContinueStmt extends NodeBase {
  kind: 'ContinueStmt';
}

/** Synthetic block result when an expression-oriented block ends with `break`/`continue`: no value is produced (control never reaches the tail). Infers as a fresh type variable so the block unifies with any expected type. */
export interface NeverExpr extends NodeBase {
  kind: 'NeverExpr';
}

export type Expr =
  | IfExpr
  | WhileExpr
  | MatchExpr
  | TryExpr
  | LambdaExpr
  | PipeExpr
  | TemplateExpr
  | LiteralExpr
  | IdentExpr
  | CallExpr
  | FieldExpr
  | ListExpr
  | RecordExpr
  | ThrowExpr
  | AwaitExpr
  | BinaryExpr
  | UnaryExpr
  | ConsExpr
  | TupleExpr
  | BlockExpr
  | NeverExpr;

export interface IfExpr extends NodeBase {
  kind: 'IfExpr';
  cond: Expr;
  then: Expr;
  else?: Expr;
}

export interface WhileExpr extends NodeBase {
  kind: 'WhileExpr';
  cond: Expr;
  body: BlockExpr;
}

export interface MatchExpr extends NodeBase {
  kind: 'MatchExpr';
  scrutinee: Expr;
  cases: Case[];
}

export interface Case extends NodeBase {
  kind: 'Case';
  pattern: Pattern;
  body: Expr;
}

export interface TryExpr extends NodeBase {
  kind: 'TryExpr';
  body: BlockExpr;
  /** If present, the exception value is bound to this name in the catch block; if null, `catch { ... }` with no variable. */
  catchVar: string | null;
  cases: Case[];
}

export interface LambdaExpr extends NodeBase {
  kind: 'LambdaExpr';
  typeParams?: string[];
  params: Param[];
  body: Expr;
}

export interface PipeExpr extends NodeBase {
  kind: 'PipeExpr';
  left: Expr;
  op: '|>' | '<|';
  right: Expr;
}

/** String with interpolation: parts are literal segments and expressions. */
export type TemplatePart =
  | { type: 'literal'; value: string }
  | { type: 'interp'; expr: Expr };

export interface TemplateExpr extends NodeBase {
  kind: 'TemplateExpr';
  parts: TemplatePart[];
}

export interface LiteralExpr extends NodeBase {
  kind: 'LiteralExpr';
  literal: 'int' | 'float' | 'string' | 'char' | 'true' | 'false' | 'unit';
  value: string;
}

export interface IdentExpr extends NodeBase {
  kind: 'IdentExpr';
  name: string;
}

export interface CallExpr extends NodeBase {
  kind: 'CallExpr';
  callee: Expr;
  args: Expr[];
}

export interface FieldExpr extends NodeBase {
  kind: 'FieldExpr';
  object: Expr;
  field: string;
}

export interface ListExpr extends NodeBase {
  kind: 'ListExpr';
  elements: (Expr | { spread: true; expr: Expr })[];
}

export interface RecordExpr extends NodeBase {
  kind: 'RecordExpr';
  spread?: Expr;
  fields: { name: string; mut?: boolean; value: Expr }[];
}

export interface ThrowExpr extends NodeBase {
  kind: 'ThrowExpr';
  value: Expr;
}

export interface AwaitExpr extends NodeBase {
  kind: 'AwaitExpr';
  value: Expr;
}

export interface BinaryExpr extends NodeBase {
  kind: 'BinaryExpr';
  op: string;
  left: Expr;
  right: Expr;
}

export interface UnaryExpr extends NodeBase {
  kind: 'UnaryExpr';
  op: string;
  operand: Expr;
}

export interface ConsExpr extends NodeBase {
  kind: 'ConsExpr';
  head: Expr;
  tail: Expr;
}

export interface TupleExpr extends NodeBase {
  kind: 'TupleExpr';
  elements: Expr[];
}

export interface BlockExpr extends NodeBase {
  kind: 'BlockExpr';
  stmts: (ValStmt | VarStmt | AssignStmt | ExprStmt | FunStmt | BreakStmt | ContinueStmt)[];
  result: Expr;
}

export type Pattern =
  | WildcardPattern
  | VarPattern
  | LiteralPattern
  | ConstructorPattern
  | ListPattern
  | ConsPattern
  | TuplePattern;

export interface WildcardPattern extends NodeBase {
  kind: 'WildcardPattern';
}

export interface VarPattern extends NodeBase {
  kind: 'VarPattern';
  name: string;
}

export interface LiteralPattern extends NodeBase {
  kind: 'LiteralPattern';
  literal: 'int' | 'float' | 'string' | 'char' | 'unit' | 'true' | 'false';
  value: string;
}

export interface ConstructorPattern extends NodeBase {
  kind: 'ConstructorPattern';
  name: string;
  fields?: { name: string; pattern?: Pattern }[];
}

export interface ListPattern extends NodeBase {
  kind: 'ListPattern';
  elements: Pattern[];
  rest?: string;
}

export interface ConsPattern extends NodeBase {
  kind: 'ConsPattern';
  head: Pattern;
  tail: Pattern;
}

export interface TuplePattern extends NodeBase {
  kind: 'TuplePattern';
  elements: Pattern[];
}

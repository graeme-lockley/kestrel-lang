/**
 * Recursive descent parser (spec 01 §3). Token stream -> AST.
 */
import type { Token, Span } from '../lexer/types.js';
import type {
  Program,
  ImportDecl,
  TopLevelDecl,
  TopLevelStmt,
  Expr,
  TemplatePart,
  Pattern,
  Type,
  Case,
  BlockExpr,
  Param,
  TypeField,
} from '../ast/nodes.js';
import { tokenize } from '../lexer/tokenize.js';

export class ParseError extends Error {
  constructor(
    message: string,
    public offset: number,
    public line: number,
    public column: number
  ) {
    super(message);
    this.name = 'ParseError';
  }
}

export function parse(tokens: Token[]): Program {
  const p = new Parser(tokens);
  return p.parseProgram();
}

/** Parse a single expression from a token array (e.g. for interpolation). */
export function parseExpression(tokens: Token[]): Expr {
  const p = new Parser(tokens);
  return p.parseOneExpr();
}

class Parser {
  private i = 0;
  constructor(private readonly tokens: Token[]) {}

  private pos(): number {
    return this.i;
  }

  private current(): Token {
    return this.tokens[this.i] ?? this.tokens[this.tokens.length - 1]!;
  }

  private at(kind: Token['kind'], value?: string): boolean {
    const t = this.current();
    if (t.kind !== kind) return false;
    if (value !== undefined && t.value !== value) return false;
    return true;
  }

  private advance(): Token {
    const t = this.current();
    if (t.kind !== 'eof') this.i++;
    return t;
  }

  private expect(kind: Token['kind'], value?: string): Token {
    const t = this.current();
    if (t.kind !== kind || (value !== undefined && t.value !== value)) {
      throw new ParseError(
        `Expected ${value ?? kind}, got ${t.value ?? t.kind}`,
        t.span.start,
        t.span.line,
        t.span.column
      );
    }
    this.advance();
    return t;
  }

  private span(): { start: number; end: number; line: number; column: number } | undefined {
    const t = this.current();
    return t.span;
  }

  parseProgram(): Program {
    const start = this.pos();
    const imports: ImportDecl[] = [];
    while (this.at('keyword', 'import')) {
      imports.push(this.parseImport());
    }
    const body: (TopLevelDecl | TopLevelStmt)[] = [];
    while (!this.at('eof')) {
      if (this.at('keyword', 'export')) {
        body.push(this.parseExport());
      } else if (
        this.at('keyword', 'fun') ||
        this.at('keyword', 'type') ||
        (this.at('keyword', 'export') && this.tokens[this.i + 1]?.value === 'exception')
      ) {
        body.push(this.parseTopLevelDecl());
      } else if (
        this.at('keyword', 'val') ||
        this.at('keyword', 'var') ||
        (this.isExprStart() && !this.at('keyword'))
      ) {
        body.push(this.parseTopLevelStmt());
      } else {
        this.advance();
      }
    }
    return {
      kind: 'Program',
      imports,
      body,
      span: { ...this.current().span, start: this.tokens[start]?.span.start ?? 0, end: this.current().span.end },
    };
  }

  private parseImport(): ImportDecl {
    this.expect('keyword', 'import');
    if (this.at('op', '*')) {
      this.advance();
      this.expect('keyword', 'as');
      const name = this.expect('ident').value!;
      this.expect('keyword', 'from');
      const spec = this.expect('string').value!;
      return { kind: 'NamespaceImport', spec, name };
    }
    if (this.at('string')) {
      const spec = this.expect('string').value!;
      return { kind: 'SideEffectImport', spec };
    }
    this.expect('lbrace');
    const specs: { external: string; local: string }[] = [];
    do {
      const external = this.expect('ident').value!;
      let local = external;
      if (this.at('keyword', 'as')) {
        this.advance();
        local = this.expect('ident').value!;
      }
      specs.push({ external, local });
    } while (this.at('comma') && this.advance());
    this.expect('rbrace');
    this.expect('keyword', 'from');
    const spec = this.expect('string').value!;
    return { kind: 'NamedImport', spec, specs };
  }

  private parseExport(): TopLevelDecl {
    this.expect('keyword', 'export');
    if (this.at('op', '*')) {
      this.advance();
      this.expect('keyword', 'from');
      const spec = this.expect('string').value!;
      return { kind: 'ExportDecl', inner: { kind: 'ExportStar', spec } };
    }
    if (this.at('lbrace')) {
      this.advance();
      const specs: { external: string; local: string }[] = [];
      do {
        const external = this.expect('ident').value!;
        let local = external;
        if (this.at('keyword', 'as')) {
          this.advance();
          local = this.expect('ident').value!;
        }
        specs.push({ external, local });
      } while (this.at('comma') && this.advance());
      this.expect('rbrace');
      this.expect('keyword', 'from');
      const spec = this.expect('string').value!;
      return { kind: 'ExportDecl', inner: { kind: 'ExportNamed', spec, specs } };
    }
    return this.parseTopLevelDecl(true);
  }

  private parseTopLevelDecl(exported = false): TopLevelDecl {
    if (this.at('keyword', 'export')) {
      this.advance();
      this.expect('keyword', 'exception');
      const name = this.expect('ident').value!;
      let fields: TypeField[] | undefined;
      if (this.at('lbrace')) {
        this.advance();
        fields = this.parseTypeFieldList();
        this.expect('rbrace');
      }
      return { kind: 'ExceptionDecl', name, fields };
    }
    if (this.at('keyword', 'fun')) {
      return this.parseFunDecl(exported);
    }
    if (this.at('keyword', 'type')) {
      this.advance();
      const name = this.expect('ident').value!;
      let typeParams: string[] | undefined;
      if (this.at('op', '<')) {
        this.advance();
        typeParams = [this.expect('ident').value!];
        while (this.at('comma')) {
          this.advance();
          typeParams.push(this.expect('ident').value!);
        }
        this.expect('op', '>');
      }
      this.expect('op', '=');
      
      // Check if this is an ADT (multiple constructors) or type alias
      // ADT: starts with UPPER_IDENT, possibly followed by | for more constructors
      if (this.at('ident') && this.current().value![0] === this.current().value![0].toUpperCase()) {
        const constructors = this.parseConstructorList();
        return { kind: 'TypeDecl', exported, name, typeParams, body: { kind: 'ADTBody', constructors } };
      } else {
        // Type alias
        const type = this.parseType();
        return { kind: 'TypeDecl', exported, name, typeParams, body: { kind: 'TypeAliasBody', type } };
      }
    }
    if (this.at('keyword', 'val')) {
      this.advance();
      const name = this.expect('ident').value!;
      let type: Type | undefined;
      if (this.at('colon')) {
        this.advance();
        type = this.parseType();
      }
      this.expect('op', '=');
      const value = this.parseExpr();
      return { kind: 'ValDecl', name, type, value };
    }
    if (this.at('keyword', 'var')) {
      this.advance();
      const name = this.expect('ident').value!;
      let type: Type | undefined;
      if (this.at('colon')) {
        this.advance();
        type = this.parseType();
      }
      this.expect('op', '=');
      const value = this.parseExpr();
      return { kind: 'VarDecl', name, type, value };
    }
    throw new ParseError('Expected fun, type, export exception, val, or var', this.current().span.start, this.current().span.line, this.current().span.column);
  }

  private parseFunDecl(exported = false): import('../ast/nodes.js').FunDecl {
    const async = this.at('keyword', 'async');
    if (async) this.advance();
    this.expect('keyword', 'fun');
    const name = this.expect('ident').value!;
    let typeParams: string[] | undefined;
    if (this.at('op', '<')) {
      this.advance();
      typeParams = [this.expect('ident').value!];
      while (this.at('comma')) {
        this.advance();
        typeParams.push(this.expect('ident').value!);
      }
      this.expect('op', '>');
    }
    this.expect('lparen');
    const params = this.parseParamList(); // consumes closing )
    this.expect('colon');
    const returnType = this.parseType();
    this.expect('op', '=');
    const body = this.parseExpr();
    return { kind: 'FunDecl', exported, async, name, typeParams, params, returnType, body };
  }

  private parseParamList(): Param[] {
    const params: Param[] = [];
    while (!this.at('rparen')) {
      const name = this.expect('ident').value!;
      let type: Type | undefined;
      if (this.at('colon')) {
        this.advance();
        type = this.parseType();
      }
      params.push({ kind: 'Param', name, type });
      if (!this.at('rparen')) this.expect('comma');
    }
    this.expect('rparen');
    return params;
  }

  /** Parse param list but do not consume closing ). Returns null if not a valid param list. */
  private parseParamListOptional(): Param[] | null {
    const params: Param[] = [];
    while (!this.at('rparen')) {
      if (!this.at('ident')) return null;
      const name = this.advance().value!;
      let type: Type | undefined;
      if (this.at('colon')) {
        this.advance();
        type = this.parseType();
      }
      params.push({ kind: 'Param', name, type });
      if (!this.at('rparen')) this.expect('comma');
    }
    return params;
  }

  private parseTypeFieldList(): TypeField[] {
    const fields: TypeField[] = [];
    while (!this.at('rbrace')) {
      const name = this.expect('ident').value!;
      this.expect('colon');
      let mut = false;
      if (this.at('keyword', 'mut')) {
        this.advance();
        mut = true;
      }
      const type = this.parseType();
      fields.push({ kind: 'TypeField', name, mut, type });
      if (!this.at('rbrace')) this.expect('comma');
    }
    return fields;
  }

  private parseConstructorList(): { name: string; params: Type[] }[] {
    const constructors: { name: string; params: Type[] }[] = [];
    constructors.push(this.parseConstructor());
    while (this.at('op', '|')) {
      this.advance();
      constructors.push(this.parseConstructor());
    }
    return constructors;
  }

  private parseConstructor(): { name: string; params: Type[] } {
    const name = this.expect('ident').value!;
    let params: Type[] = [];
    if (this.at('lparen')) {
      this.advance();
      if (!this.at('rparen')) {
        params.push(this.parseType());
        while (this.at('comma')) {
          this.advance();
          params.push(this.parseType());
        }
      }
      this.expect('rparen');
    }
    return { name, params };
  }

  private parseType(): Type {
    return this.parseOrType();
  }

  private parseOrType(): Type {
    let left = this.parseAndType();
    while (this.at('op', '|')) {
      this.advance();
      const right = this.parseAndType();
      left = { kind: 'UnionType', left, right };
    }
    return left;
  }

  private parseAndType(): Type {
    let left = this.parseArrowType();
    while (this.at('op', '&')) {
      this.advance();
      const right = this.parseArrowType();
      left = { kind: 'InterType', left, right };
    }
    return left;
  }

  private parseArrowType(): Type {
    const left = this.parseAppType();
    if (this.at('op') && this.current().value === '->') {
      this.advance();
      const returnType = this.parseType();
      const params = left.kind === 'TupleType' ? left.elements : [left];
      return { kind: 'ArrowType', params, return: returnType };
    }
    return left;
  }

  private parseAppType(): Type {
    let base = this.parseAtomType();
    if (this.at('op', '*')) {
      const elements: Type[] = [base];
      while (this.at('op', '*')) {
        this.advance();
        elements.push(this.parseAtomType());
      }
      return { kind: 'TupleType', elements };
    }
    if (base.kind === 'IdentType' && this.at('op', '<')) {
      this.advance();
      const args: Type[] = [this.parseType()];
      while (this.at('comma')) {
        this.advance();
        args.push(this.parseType());
      }
      this.expect('op', '>');
      return { kind: 'AppType', name: base.name, args };
    }
    return base;
  }

  private parseAtomType(): Type {
    if (this.at('lparen')) {
      this.advance();
      const first = this.parseType();
      if (this.at('comma')) {
        const elements: Type[] = [first];
        while (this.at('comma')) {
          this.advance();
          elements.push(this.parseType());
        }
        this.expect('rparen');
        if (this.at('op') && this.current().value === '->') {
          this.advance();
          return { kind: 'ArrowType', params: elements, return: this.parseType() };
        }
        return { kind: 'TupleType', elements };
      }
      this.expect('rparen');
      return first;
    }
    if (this.at('lbrace')) {
      this.advance();
      if (this.at('op', '...')) {
        this.advance();
        const name = this.expect('ident').value!;
        this.expect('rbrace');
        return { kind: 'RowVarType', name };
      }
      const fields = this.parseTypeFieldList();
      this.expect('rbrace');
      return { kind: 'RecordType', fields };
    }
    const prims = ['Int', 'Float', 'Bool', 'String', 'Unit', 'Char', 'Rune'] as const;
    const name = this.expect('ident').value!;
    if (prims.includes(name as any)) {
      return { kind: 'PrimType', name: name as any };
    }
    if (this.at('op', '<')) {
      this.advance();
      const args: Type[] = [this.parseType()];
      while (this.at('comma')) {
        this.advance();
        args.push(this.parseType());
      }
      this.expect('op', '>');
      return { kind: 'AppType', name, args };
    }
    return { kind: 'IdentType', name };
  }

  private parseTopLevelStmt(): TopLevelStmt {
    if (this.at('keyword', 'val')) {
      this.advance();
      const name = this.expect('ident').value!;
      this.expect('op', '=');
      const value = this.parseExpr();
      return { kind: 'ValStmt', name, value };
    }
    if (this.at('keyword', 'var')) {
      this.advance();
      const name = this.expect('ident').value!;
      this.expect('op', '=');
      const value = this.parseExpr();
      return { kind: 'VarStmt', name, value };
    }
    const expr = this.parseExpr();
    // Check if it's an assignment statement
    if (this.at('op', ':=')) {
      this.advance();
      const value = this.parseExpr();
      return { kind: 'AssignStmt', target: expr, value };
    }
    // Otherwise it's an expression statement
    return { kind: 'ExprStmt', expr };
  }

  private isExprStart(): boolean {
    return (
      this.at('keyword', 'if') ||
      this.at('keyword', 'match') ||
      this.at('keyword', 'try') ||
      this.at('lparen') ||
      this.at('ident') ||
      this.at('int') ||
      this.at('float') ||
      this.at('string') ||
      this.at('char') ||
      this.at('true') ||
      this.at('false') ||
      this.at('lbrack') ||
      this.at('lbrace') ||
      this.at('keyword', 'throw') ||
      this.at('keyword', 'await')
    );
  }

  parseExpr(): Expr {
    const startIdx = this.i;
    const expr = this.parsePipeExpr();
    const endIdx = this.i - 1;
    if (endIdx >= startIdx && expr && typeof expr === 'object') {
      const startSpan = this.tokens[startIdx]!.span;
      const endSpan = this.tokens[endIdx]!.span;
      (expr as Expr & { span: Span }).span = {
        start: startSpan.start,
        end: endSpan.end,
        line: startSpan.line,
        column: startSpan.column,
      };
    }
    return expr;
  }

  /** Public entry to parse a single expression (used for interpolation). */
  parseOneExpr(): Expr {
    return this.parseExpr();
  }

  atEof(): boolean {
    return this.at('eof');
  }

  private parsePipeExpr(): Expr {
    let left = this.parseConsExpr();
    while (this.at('op', '|>') || this.at('op', '<|')) {
      const op = this.advance().value as '|>' | '<|';
      const right = this.parseConsExpr();
      left = { kind: 'PipeExpr', left, op, right };
    }
    return left;
  }

  private parseConsExpr(): Expr {
    const left = this.parseOrExpr();
    if (this.at('op', '::')) {
      this.advance();
      const right = this.parseConsExpr();
      return { kind: 'ConsExpr', head: left, tail: right };
    }
    return left;
  }

  private parseOrExpr(): Expr {
    let left = this.parseAndExpr();
    while (this.at('op', '|')) {
      this.advance();
      left = { kind: 'BinaryExpr', op: '|', left, right: this.parseAndExpr() };
    }
    return left;
  }

  private parseAndExpr(): Expr {
    let left = this.parseRelExpr();
    while (this.at('op', '&')) {
      this.advance();
      left = { kind: 'BinaryExpr', op: '&', left, right: this.parseRelExpr() };
    }
    return left;
  }

  private parseRelExpr(): Expr {
    let left = this.parseAddExpr();
    const relOps = ['==', '!=', '<', '>', '<=', '>='];
    while (this.at('op') && relOps.includes(this.current().value ?? '')) {
      const op = this.advance().value!;
      left = { kind: 'BinaryExpr', op, left, right: this.parseAddExpr() };
    }
    return left;
  }

  private parseAddExpr(): Expr {
    let left = this.parseMulExpr();
    while (this.at('op', '+') || this.at('op', '-')) {
      const op = this.advance().value!;
      left = { kind: 'BinaryExpr', op, left, right: this.parseMulExpr() };
    }
    return left;
  }

  private parseMulExpr(): Expr {
    let left = this.parsePowExpr();
    while (this.at('op', '*') || this.at('op', '/') || this.at('op', '%')) {
      const op = this.advance().value!;
      left = { kind: 'BinaryExpr', op, left, right: this.parsePowExpr() };
    }
    return left;
  }

  private parsePowExpr(): Expr {
    const left = this.parseUnary();
    if (this.at('op', '**')) {
      this.advance();
      return { kind: 'BinaryExpr', op: '**', left, right: this.parsePowExpr() };
    }
    return left;
  }

  private parseUnary(): Expr {
    if (this.at('op', '-') || this.at('op', '+') || this.at('op', '!')) {
      const op = this.current().value!;
      this.advance();
      const operand = this.parseUnary();
      return { kind: 'UnaryExpr', op, operand };
    }
    return this.parsePrimary();
  }

  private parsePrimary(): Expr {
    let awaitPrefix = false;
    if (this.at('keyword', 'await')) {
      this.advance();
      awaitPrefix = true;
    }
    let expr = this.parseAtom();
    const isTupleIndexFloat = (): boolean =>
      this.at('float') && /^\.\d+$/.test(this.current().value ?? '');
    while (this.at('lparen') || this.at('dot') || isTupleIndexFloat()) {
      if (this.at('lparen')) {
        this.advance();
        const args: Expr[] = [];
        while (!this.at('rparen')) {
          args.push(this.parseExpr());
          if (!this.at('rparen')) this.expect('comma');
        }
        this.expect('rparen');
        expr = { kind: 'CallExpr', callee: expr, args };
      } else {
        if (this.at('dot')) this.advance(); // consume . (when token is "." not ".0")
        let field: string;
        if (this.at('ident')) {
          field = this.advance().value!;
        } else if (this.at('int')) {
          field = String(this.advance().value ?? 0);
        } else if (isTupleIndexFloat()) {
          const raw = this.current().value!;
          field = raw.slice(1); // ".0" -> "0"
          this.advance();
        } else if (this.at('float')) {
          const v = parseFloat(this.advance().value ?? '0');
          if (!Number.isInteger(v) || v < 0) this.expect('ident');
          field = String(Math.floor(v));
        } else {
          field = this.expect('ident').value!;
        }
        expr = { kind: 'FieldExpr', object: expr, field };
      }
    }
    if (awaitPrefix && expr.kind === 'CallExpr') {
      return { kind: 'AwaitExpr', value: expr };
    }
    if (awaitPrefix) {
      return { kind: 'AwaitExpr', value: expr };
    }
    return expr;
  }

  private parseAtom(): Expr {
    if (this.at('keyword', 'if')) {
      this.advance();
      this.expect('lparen');
      const cond = this.parseExpr();
      this.expect('rparen');
      const then = this.parseExpr();
      const elseBranch = this.at('keyword', 'else') ? (this.advance(), this.parseExpr()) : undefined;
      return { kind: 'IfExpr', cond, then, else: elseBranch };
    }
    if (this.at('keyword', 'match')) {
      this.advance();
      this.expect('lparen');
      const scrutinee = this.parseExpr();
      this.expect('rparen');
      this.expect('lbrace');
      const cases: Case[] = [];
      while (!this.at('rbrace')) {
        cases.push(this.parseCase());
        if (this.at('comma')) this.advance();
      }
      this.expect('rbrace');
      return { kind: 'MatchExpr', scrutinee, cases };
    }
    if (this.at('keyword', 'try')) {
      this.advance();
      const body = this.parseBlock();
      this.expect('keyword', 'catch');
      this.expect('lparen');
      const catchVar = this.expect('ident').value!;
      this.expect('rparen');
      this.expect('lbrace');
      const cases: Case[] = [];
      while (!this.at('rbrace')) cases.push(this.parseCase());
      this.expect('rbrace');
      return { kind: 'TryExpr', body, catchVar, cases };
    }
    if (this.at('lparen')) {
      this.advance();
      if (this.at('rparen')) {
        this.advance();
        return { kind: 'LiteralExpr', literal: 'unit', value: '()' };
      }
      const pos = this.pos();
      const params = this.parseParamListOptional();
      if (params && this.at('rparen')) {
        this.advance();
        if (this.at('op', '=>')) {
          this.advance();
          return { kind: 'LambdaExpr', params, body: this.parseExpr() };
        }
      }
      this.i = pos;
      const first = this.parseExpr();
      if (this.at('comma')) {
        const elements = [first];
        while (this.at('comma')) {
          this.advance();
          elements.push(this.parseExpr());
        }
        this.expect('rparen');
        return { kind: 'TupleExpr', elements };
      }
      this.expect('rparen');
      return first;
    }
    if (this.at('true') || this.at('false')) {
      const v = this.advance().value!;
      return { kind: 'LiteralExpr', literal: v === 'True' ? 'true' : 'false', value: v };
    }
    if (this.at('int')) {
      const value = this.advance().value!;
      return { kind: 'LiteralExpr', literal: 'int', value };
    }
    if (this.at('float')) {
      const value = this.advance().value!;
      return { kind: 'LiteralExpr', literal: 'float', value };
    }
    if (this.at('string')) {
      const tok = this.advance();
      const partsRaw = tok.templateParts;
      if (partsRaw != null && partsRaw.length > 0) {
        const parts: TemplatePart[] = [];
        for (const p of partsRaw) {
          if (p.type === 'literal') {
            parts.push({ type: 'literal', value: p.value });
          } else {
            const subTokens = tokenize(p.source);
            const subParser = new Parser(subTokens);
            const expr = subParser.parseOneExpr();
            if (!subParser.atEof()) {
              const cur = subParser.current();
              throw new ParseError(
                'Expected single expression in interpolation',
                cur.span.start,
                cur.span.line,
                cur.span.column
              );
            }
            parts.push({ type: 'interp', expr });
          }
        }
        return { kind: 'TemplateExpr', parts };
      }
      return { kind: 'LiteralExpr', literal: 'string', value: tok.value ?? '' };
    }
    if (this.at('char')) {
      const value = this.advance().value!;
      return { kind: 'LiteralExpr', literal: 'char', value };
    }
    if (this.at('ident')) {
      const name = this.advance().value!;
      return { kind: 'IdentExpr', name };
    }
    if (this.at('lbrack')) {
      this.advance();
      const elements: (Expr | { spread: true; expr: Expr })[] = [];
      while (!this.at('rbrack')) {
        if (elements.length > 0) this.expect('comma');
        if (this.at('op', '...')) {
          this.advance();
          elements.push({ spread: true, expr: this.parseExpr() });
        } else {
          elements.push(this.parseExpr());
        }
      }
      this.expect('rbrack');
      return { kind: 'ListExpr', elements };
    }
    if (this.at('lbrace')) {
      return this.parseRecordOrBlock();
    }
    if (this.at('keyword', 'throw')) {
      this.advance();
      return { kind: 'ThrowExpr', value: this.parseExpr() };
    }
    throw new ParseError('Expected expression', this.current().span.start, this.current().span.line, this.current().span.column);
  }

  private parseRecordOrBlock(): Expr {
    // Distinguish { ident = expr, ... } (record) from { stmt; ...; expr } (block).
    // Record: { ident = ..., ... } or { mut ident = ..., ... } or { ...spread, ... } or { }
    // Block: { val ...; ... } or { var ...; ... } or { expr; ... }
    const saved = this.i;
    const next1 = this.tokens[this.i + 1];
    if (next1 && next1.kind === 'rbrace') {
      // empty { } — record
      return this.parseRecordExpr();
    }
    if (next1 && (next1.value === 'val' || next1.value === 'var' || next1.value === 'fun')) {
      // { val ... or { var ... or { fun ... — block
      return this.parseBlock();
    }
    if (next1 && next1.value === '...') {
      // { ...spread — record
      return this.parseRecordExpr();
    }
    if (next1 && next1.value === 'mut') {
      // { mut ident = ... — record
      return this.parseRecordExpr();
    }
    // Check: { ident = ... — if the token after ident is '=', it's a record
    if (next1 && next1.kind === 'ident') {
      const next2 = this.tokens[this.i + 2];
      if (next2 && next2.kind === 'op' && next2.value === '=') {
        return this.parseRecordExpr();
      }
    }
    // Otherwise, treat as block
    return this.parseBlock();
  }

  private parseRecordExpr(): Expr {
    this.expect('lbrace');
    let spread: Expr | undefined;
    const fields: { name: string; mut?: boolean; value: Expr }[] = [];
    while (!this.at('rbrace')) {
      if (this.at('op', '...')) {
        this.advance();
        spread = this.parseExpr();
      } else {
        let mut = false;
        if (this.at('keyword', 'mut')) {
          this.advance();
          mut = true;
        }
        const name = this.expect('ident').value!;
        this.expect('op', '=');
        fields.push({ name, mut: mut || undefined, value: this.parseExpr() });
      }
      if (!this.at('rbrace')) this.expect('comma');
    }
    this.expect('rbrace');
    return { kind: 'RecordExpr', spread, fields };
  }

  private parseBlock(): BlockExpr {
    this.expect('lbrace');
    const stmts: BlockExpr['stmts'] = [];
    let result: Expr;
    while (true) {
      if (this.at('keyword', 'val')) {
        this.advance();
        const name = this.expect('ident').value!;
        this.expect('op', '=');
        stmts.push({ kind: 'ValStmt', name, value: this.parseExpr() });
      } else if (this.at('keyword', 'var')) {
        this.advance();
        const name = this.expect('ident').value!;
        this.expect('op', '=');
        stmts.push({ kind: 'VarStmt', name, value: this.parseExpr() });
      } else if (this.at('keyword', 'fun')) {
        this.advance();
        const name = this.expect('ident').value!;
        let typeParams: string[] | undefined;
        if (this.at('op', '<')) {
          this.advance();
          typeParams = [this.expect('ident').value!];
          while (this.at('comma')) {
            this.advance();
            typeParams.push(this.expect('ident').value!);
          }
          this.expect('op', '>');
        }
        this.expect('lparen');
        const params = this.parseParamList();
        this.expect('colon');
        const returnType = this.parseType();
        this.expect('op', '=');
        const body = this.parseExpr();
        stmts.push({ kind: 'FunStmt', name, typeParams, params, returnType, body });
      } else {
        const expr = this.parseExpr();
        if (this.at('op', ':=')) {
          this.advance();
          stmts.push({ kind: 'AssignStmt', target: expr, value: this.parseExpr() });
        } else if (this.at('rbrace')) {
          result = expr;
          break;
        } else {
          stmts.push({ kind: 'ExprStmt', expr });
        }
      }
      if (this.at('semicolon')) this.advance();
    }
    this.expect('rbrace');
    return { kind: 'BlockExpr', stmts, result: result! };
  }

  private parseCase(): Case {
    const pattern = this.parsePattern();
    this.expect('op', '=>');
    const body = this.parseExpr();
    return { kind: 'Case', pattern, body };
  }

  private parsePattern(): Pattern {
    let pattern = this.parsePatternPrimary();

    // Check for cons pattern (::)
    if (this.at('op', '::')) {
      this.advance();
      const tail = this.parsePattern();
      return { kind: 'ConsPattern', head: pattern, tail };
    }

    return pattern;
  }

  private parsePatternPrimary(): Pattern {
    if (this.at('ident') && this.current().value === '_') {
      this.advance();
      return { kind: 'WildcardPattern' };
    }
    if (this.at('ident') && /[A-Z]/.test(this.current().value![0] ?? '')) {
      const name = this.advance().value!;
      // Check for record-style pattern { field = pattern } or positional (arg)
      if (this.at('lbrace')) {
        this.advance();
        const fields: { name: string; pattern?: Pattern }[] = [];
        while (!this.at('rbrace')) {
          const n = this.expect('ident').value!;
          let pattern: Pattern | undefined;
          if (this.at('op', '=')) {
            this.advance();
            pattern = this.parsePattern();
          }
          fields.push({ name: n, pattern });
          if (!this.at('rbrace')) this.expect('comma');
        }
        this.expect('rbrace');
        return { kind: 'ConstructorPattern', name, fields };
      }
      // Positional constructor pattern: Some(x) or Node(left, right)
      if (this.at('lparen')) {
        this.advance();
        const fields: { name: string; pattern?: Pattern }[] = [];
        let index = 0;
        while (!this.at('rparen')) {
          const pattern = this.parsePattern();
          fields.push({ name: `__field_${index}`, pattern });
          index++;
          if (!this.at('rparen')) this.expect('comma');
        }
        this.expect('rparen');
        return { kind: 'ConstructorPattern', name, fields };
      }
      return { kind: 'ConstructorPattern', name };
    }
    if (this.at('lbrack')) {
      this.advance();
      const elements: Pattern[] = [];
      let rest: string | undefined;
      while (!this.at('rbrack')) {
        if (this.at('op', '...')) {
          this.advance();
          rest = this.expect('ident').value!;
          break;
        }
        elements.push(this.parsePattern());
        if (!this.at('rbrack')) this.expect('comma');
      }
      this.expect('rbrack');
      return { kind: 'ListPattern', elements, rest };
    }
    if (this.at('ident')) {
      const name = this.advance().value!;
      return { kind: 'VarPattern', name };
    }
    // Treat True/False as constructor patterns for boolean ADT
    if (this.at('true')) {
      this.advance();
      return { kind: 'ConstructorPattern', name: 'True' };
    }
    if (this.at('false')) {
      this.advance();
      return { kind: 'ConstructorPattern', name: 'False' };
    }
    if (this.at('int') || this.at('string')) {
      const literal = this.current().kind === 'int' ? 'int' : 'string';
      const value = this.advance().value!;
      return { kind: 'LiteralPattern', literal, value };
    }
    if (this.at('lparen')) {
      this.advance();
      const elements: Pattern[] = [];
      while (!this.at('rparen')) {
        elements.push(this.parsePattern());
        if (!this.at('rparen')) this.expect('comma');
      }
      this.expect('rparen');
      return { kind: 'TuplePattern', elements };
    }
    throw new ParseError('Expected pattern', this.current().span.start, this.current().span.line, this.current().span.column);
  }
}

#!/usr/bin/env node
'use strict';

// Schema conformance guard for Phase 9.
//
// Diffs the frozen remote schema in ../personal-os/src/lib/schema.ts
// (REMOTE_SCHEMAS) against the local drift schema in
// lib/core/data/drift/tables.dart, per table: column names, types,
// nullability, defaults, primary keys, UNIQUE constraints, CHECK constraint
// expressions, foreign keys (including ON DELETE CASCADE), and index
// names/columns/uniqueness.
//
// It also diffs the committed generated DDL in
// lib/core/data/drift/database.g.dart, which is what actually creates the
// on-device database. That catches a stale `.g.dart` left behind after a
// `tables.dart` edit, and it fails if the tables.dart and database.g.dart table
// sets differ. CHECK constraints are table-level and are not embedded in the
// generated file, so they are validated against tables.dart only.
//
// Treats the `ALTER TABLE ... ADD COLUMN` statements as redundant when the
// column already exists in the `CREATE TABLE` body (they are additive
// migrations for pre-existing remote databases; a fresh local DB already has
// the columns).
//
// Normalizes away constraint names, whitespace, parenthesis placement, and
// index column sort direction. On sort direction: the reference declares some
// indexes `DESC`, while drift's `@TableIndex` emits ascending index columns.
// SQLite can reverse-scan an ascending index for an ORDER BY on that column, so
// the two are semantically equivalent and the direction is treated as equal.
//
// Also diffs a future Phase 10 remote-DDL Dart port if one can be located. Its
// absence is not an error in Phase 9.
//
// Exits non-zero on any mismatch and fails loudly on drift DSL it cannot parse.

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const REFERENCE_SCHEMA = path.resolve(
  REPO_ROOT,
  '..',
  'personal-os',
  'src',
  'lib',
  'schema.ts'
);
const TABLES_DART = path.resolve(
  REPO_ROOT,
  'lib',
  'core',
  'data',
  'drift',
  'tables.dart'
);
const GENERATED_DATABASE = path.resolve(
  REPO_ROOT,
  'lib',
  'core',
  'data',
  'drift',
  'database.g.dart'
);
const SYNC_DIR = path.resolve(REPO_ROOT, 'lib', 'core', 'sync');

// ---------------------------------------------------------------------------
// Generic scanning helpers
// ---------------------------------------------------------------------------

function readFileOrThrow(file) {
  if (!fs.existsSync(file)) {
    throw new Error(`Required file not found: ${file}`);
  }
  return fs.readFileSync(file, 'utf8');
}

/**
 * Finds the index of the bracket matching the one at `openIndex`.
 * Skips over single, double and backtick quoted strings.
 */
function findMatching(source, openIndex, open, close) {
  if (source[openIndex] !== open) {
    throw new Error(`Expected '${open}' at ${openIndex}`);
  }
  let depth = 0;
  let quote = null;
  for (let i = openIndex; i < source.length; i++) {
    const ch = source[i];
    if (quote) {
      if (ch === '\\') {
        i++;
      } else if (ch === quote) {
        quote = null;
      }
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') {
      quote = ch;
      continue;
    }
    if (ch === open) depth++;
    else if (ch === close) {
      depth--;
      if (depth === 0) return i;
    }
  }
  throw new Error(`Unbalanced '${open}' starting at ${openIndex}`);
}

/** Splits `text` on top-level `separator` characters (respecting brackets and quotes). */
function splitTopLevel(text, separator) {
  const parts = [];
  let depth = 0;
  let quote = null;
  let current = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      current += ch;
      if (ch === '\\') {
        if (i + 1 < text.length) current += text[++i];
      } else if (ch === quote) {
        quote = null;
      }
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') {
      quote = ch;
      current += ch;
      continue;
    }
    if (ch === '(' || ch === '[' || ch === '{') {
      depth++;
      current += ch;
      continue;
    }
    if (ch === ')' || ch === ']' || ch === '}') {
      depth--;
      current += ch;
      continue;
    }
    if (ch === separator && depth === 0) {
      parts.push(current);
      current = '';
      continue;
    }
    current += ch;
  }
  parts.push(current);
  return parts.map((p) => p.trim()).filter((p) => p.length > 0);
}

function stripOuterParens(value) {
  let s = value.trim();
  while (s.startsWith('(') && s.endsWith(')')) {
    const match = findMatching(s, 0, '(', ')');
    if (match !== s.length - 1) break;
    s = s.slice(1, -1).trim();
  }
  return s;
}

function normalizeWhitespace(value) {
  return value.replace(/\s+/g, ' ').trim();
}

function stripIdentifierQuotes(value) {
  return value.replace(/^["`\[]/, '').replace(/["`\]]$/, '').trim();
}

function camelToSnake(name) {
  return name
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')
    .toLowerCase();
}

// ---------------------------------------------------------------------------
// schema.ts parsing
// ---------------------------------------------------------------------------

function extractRemoteSchemas(source) {
  const marker = /export\s+const\s+REMOTE_SCHEMAS\s*=\s*\[/.exec(source);
  if (!marker) {
    throw new Error('Could not find REMOTE_SCHEMAS in schema.ts');
  }
  const openIndex = marker.index + marker[0].length - 1;
  const closeIndex = findMatching(source, openIndex, '[', ']');
  const body = source.slice(openIndex + 1, closeIndex);

  const statements = [];
  let i = 0;
  while (i < body.length) {
    if (body[i] === '`') {
      const close = body.indexOf('`', i + 1);
      if (close === -1) throw new Error('Unterminated template literal in REMOTE_SCHEMAS');
      const text = body.slice(i + 1, close);
      if (text.includes('${')) {
        throw new Error('REMOTE_SCHEMAS template literals with interpolation are not supported');
      }
      statements.push(text.trim());
      i = close + 1;
    } else {
      i++;
    }
  }
  if (statements.length === 0) {
    throw new Error('No SQL statements found in REMOTE_SCHEMAS');
  }
  return statements;
}

function extractDefaultClause(rest) {
  const match = /\bDEFAULT\b/i.exec(rest);
  if (!match) return null;
  let i = match.index + match[0].length;
  while (i < rest.length && /\s/.test(rest[i])) i++;
  if (i >= rest.length) throw new Error(`DEFAULT with no expression in: ${rest}`);
  const first = rest[i];
  if (first === "'" || first === '"') {
    const quote = first;
    let j = i + 1;
    let value = quote;
    while (j < rest.length) {
      value += rest[j];
      if (rest[j] === quote) {
        if (rest[j + 1] === quote) {
          value += rest[++j];
        } else {
          break;
        }
      }
      j++;
    }
    return value;
  }
  if (first === '(') {
    const close = findMatching(rest, i, '(', ')');
    return rest.slice(i, close + 1);
  }
  const token = /^[^\s,]+/.exec(rest.slice(i));
  return token ? token[0] : null;
}

function extractReferencesClause(rest) {
  const match =
    /REFERENCES\s+["`]?(\w+)["`]?\s*\(\s*["`]?(\w+)["`]?\s*\)(?:\s+ON\s+DELETE\s+([A-Za-z]+(?:\s+[A-Za-z]+)?))?/i.exec(
      rest
    );
  if (!match) return null;
  return {
    refTable: match[1],
    refColumn: match[2],
    onDelete: normalizeAction(match[3]),
  };
}

function parseColumnDef(def) {
  const match = /^["`]?(\w+)["`]?\s+([A-Za-z]+)/.exec(def);
  if (!match) {
    throw new Error(`Could not parse column definition: ${def}`);
  }
  const name = match[1];
  const type = normalizeType(match[2]);
  const rest = def.slice(match[0].length);
  const isPrimaryKey = /\bPRIMARY\s+KEY\b/i.test(rest);
  const notNull = isPrimaryKey || /\bNOT\s+NULL\b/i.test(rest);
  return {
    name,
    type,
    notNull,
    primaryKey: isPrimaryKey,
    default: extractDefaultClause(rest),
    references: extractReferencesClause(rest),
  };
}

function parseTableConstraint(def) {
  let text = def.trim();
  const named = /^CONSTRAINT\s+\w+\s+/i.exec(text);
  if (named) text = text.slice(named[0].length).trim();

  const pk = /^PRIMARY\s+KEY\s*\(([\s\S]*)\)/i.exec(text);
  if (pk) {
    return { kind: 'primaryKey', columns: parseColumnList(pk[1]) };
  }
  const unique = /^UNIQUE\s*\(([\s\S]*)\)/i.exec(text);
  if (unique) {
    return { kind: 'unique', columns: parseColumnList(unique[1]) };
  }
  const check = /^CHECK\s*\(/i.exec(text);
  if (check) {
    const open = text.indexOf('(', check.index);
    const close = findMatching(text, open, '(', ')');
    return { kind: 'check', expression: text.slice(open + 1, close) };
  }
  const fk = /^FOREIGN\s+KEY\s*\(([\s\S]*?)\)\s*REFERENCES\s+["`]?(\w+)["`]?\s*\(([\s\S]*?)\)(?:\s+ON\s+DELETE\s+([A-Za-z]+(?:\s+[A-Za-z]+)?))?/i.exec(
    text
  );
  if (fk) {
    return {
      kind: 'foreignKey',
      columns: parseColumnList(fk[1]),
      refTable: fk[2],
      refColumns: parseColumnList(fk[3]),
      onDelete: normalizeAction(fk[4]),
    };
  }
  throw new Error(`Unsupported table constraint: ${def}`);
}

function parseColumnList(text) {
  return splitTopLevel(text, ',')
    .map((entry) => entry.replace(/\s+(ASC|DESC)\s*$/i, '').trim())
    .map(stripIdentifierQuotes)
    .filter((entry) => entry.length > 0);
}

function parseReferenceTables(statements) {
  const tables = new Map();
  const indexes = new Map();
  const alters = [];

  for (const statement of statements) {
    const normalized = stripSqlComments(statement).trim();
    if (/^CREATE\s+TABLE/i.test(normalized)) {
      const match =
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s*\(/i.exec(
          normalized
        );
      if (!match) throw new Error(`Unsupported CREATE TABLE: ${statement}`);
      const open = normalized.indexOf('(', match.index);
      const close = findMatching(normalized, open, '(', ')');
      const body = normalized.slice(open + 1, close);
      tables.set(match[1], parseTableBody(match[1], body));
    } else if (/^CREATE\s+(UNIQUE\s+)?INDEX/i.test(normalized)) {
      const match =
        /CREATE\s+(UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s+ON\s+["`]?(\w+)["`]?\s*\(([\s\S]*?)\)\s*$/i.exec(
          normalized
        );
      if (!match) throw new Error(`Unsupported CREATE INDEX: ${statement}`);
      indexes.set(match[2], {
        name: match[2],
        unique: Boolean(match[1]),
        table: match[3],
        columns: parseColumnList(match[4]),
      });
    } else if (/^ALTER\s+TABLE/i.test(normalized)) {
      const match =
        /ALTER\s+TABLE\s+["`]?(\w+)["`]?\s+ADD\s+COLUMN\s+([\s\S]+)$/i.exec(
          normalized
        );
      if (!match) throw new Error(`Unsupported ALTER TABLE: ${statement}`);
      alters.push({ table: match[1], column: parseColumnDef(match[2].trim()) });
    } else if (normalized.length === 0) {
      continue;
    } else {
      throw new Error(`Unsupported schema statement: ${statement}`);
    }
  }

  return { tables, indexes, alters };
}

function parseTableBody(tableName, body) {
  const parts = splitTopLevel(body, ',');
  const columns = new Map();
  const primaryKey = [];
  const uniques = [];
  const checks = [];
  const foreignKeys = [];

  for (const part of parts) {
    const firstWord = /^(CONSTRAINT|PRIMARY|UNIQUE|CHECK|FOREIGN)\b/i.exec(part);
    if (firstWord) {
      const constraint = parseTableConstraint(part);
      if (constraint.kind === 'primaryKey') primaryKey.push(...constraint.columns);
      else if (constraint.kind === 'unique') uniques.push(constraint.columns);
      else if (constraint.kind === 'check') checks.push(normalizeCheck(constraint.expression));
      else if (constraint.kind === 'foreignKey') foreignKeys.push(constraint);
      continue;
    }
    const column = parseColumnDef(part);
    if (columns.has(column.name)) {
      throw new Error(`Duplicate column ${column.name} in ${tableName}`);
    }
    columns.set(column.name, column);
    if (column.primaryKey) primaryKey.push(column.name);
  }

  return { name: tableName, columns, primaryKey, uniques, checks, foreignKeys };
}

function stripSqlComments(sql) {
  return sql
    .replace(/--[^\n]*/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '');
}

function normalizeType(type) {
  return type.trim().toUpperCase();
}

function normalizeAction(action) {
  if (!action) return 'NO ACTION';
  return normalizeWhitespace(action).toUpperCase();
}

function normalizeDefault(value) {
  if (value === null || value === undefined) return null;
  return normalizeWhitespace(stripOuterParens(value));
}

function normalizeCheck(expression) {
  // CHECK expressions here contain only identifiers, operators, and string
  // literals without embedded spaces, so removing whitespace is a safe
  // canonicalization that ignores parenthesis spacing differences.
  return expression.replace(/\s+/g, '');
}

// ---------------------------------------------------------------------------
// tables.dart parsing
// ---------------------------------------------------------------------------

function stripDartComments(source) {
  let out = '';
  let quote = null;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (quote) {
      out += ch;
      if (ch === '\\') {
        if (i + 1 < source.length) out += source[++i];
      } else if (ch === quote) {
        quote = null;
      }
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      out += ch;
      continue;
    }
    if (ch === '/' && source[i + 1] === '/') {
      while (i < source.length && source[i] !== '\n') i++;
      out += '\n';
      continue;
    }
    if (ch === '/' && source[i + 1] === '*') {
      const end = source.indexOf('*/', i + 2);
      if (end === -1) throw new Error('Unterminated block comment in tables.dart');
      i = end + 1;
      continue;
    }
    out += ch;
  }
  return out;
}

function unquoteDart(value) {
  const trimmed = value.trim();
  const match = /^(['"])([\s\S]*)\1$/.exec(trimmed);
  if (!match) {
    throw new Error(`Expected a Dart string literal, got: ${trimmed}`);
  }
  return match[2].replace(new RegExp(`\\\\${match[1]}`, 'g'), match[1]).replace(/\\\\/g, '\\');
}

function parseDefaultArgument(args, context) {
  const constant = /^(?:const\s+)?Constant\(([\s\S]*)\)$/.exec(args.trim());
  if (constant) {
    return constant[1].trim();
  }
  const custom = /^(?:const\s+)?CustomExpression\(([\s\S]*)\)$/.exec(args.trim());
  if (custom) {
    return unquoteDart(custom[1].trim());
  }
  throw new Error(`Unsupported withDefault(...) argument in ${context}: ${args}`);
}

function parseColumnChain(chain, classToTable, context) {
  let rest = chain.trim();
  const base = /^(text|integer)\s*\(\s*\)/.exec(rest);
  if (!base) {
    throw new Error(`Unsupported drift column base in ${context}: ${chain}`);
  }
  const type = base[1] === 'text' ? 'TEXT' : 'INTEGER';
  rest = rest.slice(base[0].length);

  let nullable = false;
  let named = null;
  let defaultValue = null;
  let references = null;

  while (rest.startsWith('.')) {
    const methodMatch = /^\.(\w+)\s*\(/.exec(rest);
    if (!methodMatch) {
      throw new Error(`Unparsed drift column DSL in ${context}: ${rest}`);
    }
    const method = methodMatch[1];
    const open = rest.indexOf('(', methodMatch[0].length - 1);
    const close = findMatching(rest, open, '(', ')');
    const args = rest.slice(open + 1, close).trim();
    rest = rest.slice(close + 1).trim();

    switch (method) {
      case 'nullable':
        if (args.length > 0) throw new Error(`nullable() takes no arguments in ${context}`);
        nullable = true;
        break;
      case 'named':
        named = unquoteDart(args);
        break;
      case 'withDefault':
        defaultValue = parseDefaultArgument(args, context);
        break;
      case 'references': {
        const match =
          /^(\w+)\s*,\s*#(\w+)\s*(?:,\s*onDelete\s*:\s*KeyAction\.(\w+))?\s*$/.exec(
            args
          );
        if (!match) {
          throw new Error(`Unsupported references(...) call in ${context}: ${args}`);
        }
        const refClass = match[1];
        if (!classToTable.has(refClass)) {
          throw new Error(
            `references(${refClass}, ...) in ${context} points at an unknown table class`
          );
        }
        references = {
          refTable: classToTable.get(refClass),
          refColumn: camelToSnake(match[2]),
          onDelete: normalizeAction(match[3] ? match[3].replace(/([a-z])([A-Z])/g, '$1 $2') : null),
        };
        break;
      }
      default:
        throw new Error(`Unsupported drift column method '${method}' in ${context}`);
    }
  }

  if (rest !== '()') {
    throw new Error(`Unexpected trailing drift column DSL in ${context}: ${rest}`);
  }

  return { type, nullable, named, default: defaultValue, references };
}

function parseTableIndexAnnotations(prefix, classToTable, context) {
  const indexes = [];
  const total = (prefix.match(/@TableIndex/g) || []).length;
  const regex = /@TableIndex\s*\(/g;
  let match;
  let matched = 0;
  while ((match = regex.exec(prefix)) !== null) {
    matched++;
    const open = match.index + match[0].length - 1;
    const close = findMatching(prefix, open, '(', ')');
    const args = prefix.slice(open + 1, close);

    const nameMatch = /\bname:\s*('(?:[^'\\]|\\.)*')/.exec(args);
    if (!nameMatch) {
      throw new Error(`@TableIndex without a name near ${context}`);
    }
    const name = unquoteDart(nameMatch[1]);

    const columnsMatch = /\bcolumns:\s*\{([^}]*)\}/.exec(args);
    if (!columnsMatch) {
      throw new Error(`@TableIndex '${name}' without a columns set near ${context}`);
    }
    const columns = [];
    const columnRegex = /#(\w+)/g;
    let columnMatch;
    while ((columnMatch = columnRegex.exec(columnsMatch[1])) !== null) {
      columns.push(camelToSnake(columnMatch[1]));
    }

    const uniqueMatch = /\bunique:\s*(true|false)\b/.exec(args);
    indexes.push({
      name,
      columns,
      unique: uniqueMatch ? uniqueMatch[1] === 'true' : false,
    });
  }
  // `@TableIndex.sql(...)` and IndexedColumn-based annotations are not used;
  // fail loudly rather than silently drop an index. This also catches a
  // `@TableIndex` whose arguments are not the supported named form.
  if (matched !== total) {
    throw new Error(
      `Could not parse every @TableIndex annotation near ${context}; ` +
        'only the name/columns/unique form is supported'
    );
  }
  return indexes;
}

function parseTablesDart(source) {
  const stripped = stripDartComments(source);
  const classRegex = /class\s+(\w+)\s+extends\s+Table\s*\{/g;
  const parsed = new Map();
  const classToTable = new Map();
  const classOrder = [];

  let match;
  let previousEnd = 0;
  while ((match = classRegex.exec(stripped)) !== null) {
    const className = match[1];
    const openBrace = match.index + match[0].length - 1;
    const closeBrace = findMatching(stripped, openBrace, '{', '}');
    const body = stripped.slice(openBrace + 1, closeBrace);
    const prefix = stripped.slice(previousEnd, match.index);
    previousEnd = closeBrace + 1;

    const tableNameMatch = /String\s+get\s+tableName\s*=>\s*'([^']*)'/.exec(body);
    const tableName = tableNameMatch ? tableNameMatch[1] : camelToSnake(className);
    classToTable.set(className, tableName);
    classOrder.push({ className, tableName, body, prefix });
  }

  if (classOrder.length === 0) {
    throw new Error('No drift Table classes found in tables.dart');
  }

  for (const { className, tableName, body, prefix } of classOrder) {
    const context = `table ${tableName}`;
    const columns = new Map();
    const columnRegex = /(TextColumn|IntColumn)\s+get\s+(\w+)\s*=>\s*([\s\S]*?\(\))\s*;/g;
    let columnMatch;
    let declaredColumns = 0;
    const declaredCount = (body.match(/(TextColumn|IntColumn)\s+get\s+/g) || []).length;
    while ((columnMatch = columnRegex.exec(body)) !== null) {
      declaredColumns++;
      const getter = columnMatch[2];
      const chain = parseColumnChain(columnMatch[3], classToTable, `${context}.${getter}`);
      const name = chain.named || camelToSnake(getter);
      if (columns.has(name)) {
        throw new Error(`Duplicate column ${name} in ${context}`);
      }
      columns.set(name, {
        name,
        type: chain.type,
        notNull: !chain.nullable,
        default: normalizeDefault(chain.default),
        references: chain.references,
      });
    }
    if (declaredColumns !== declaredCount) {
      throw new Error(`Could not parse every column declaration in ${context}`);
    }

    const primaryKeyMatch = /Set<Column>\s+get\s+primaryKey\s*=>\s*\{([^}]*)\}/.exec(body);
    const primaryKey = primaryKeyMatch
      ? primaryKeyMatch[1]
          .split(',')
          .map((v) => v.trim())
          .filter((v) => v.length > 0)
          .map(camelToSnake)
      : [];
    if (!primaryKeyMatch) {
      throw new Error(`Missing primaryKey in ${context}`);
    }

    const uniqueMatch = /List<Set<Column>>\s+get\s+uniqueKeys\s*=>\s*\[([\s\S]*?)\];/.exec(
      body
    );
    const uniques = [];
    if (uniqueMatch) {
      const setRegex = /\{([^}]*)\}/g;
      let setMatch;
      while ((setMatch = setRegex.exec(uniqueMatch[1])) !== null) {
        const cols = setMatch[1]
          .split(',')
          .map((v) => v.trim())
          .filter((v) => v.length > 0)
          .map(camelToSnake);
        uniques.push(cols);
      }
    }

    const checks = [];
    const customConstraintsMatch =
      /List<String>\s+get\s+customConstraints\s*=>\s*(?:const\s*)?\[([\s\S]*?)\]/.exec(body);
    if (customConstraintsMatch) {
      const stringRegex = /"((?:[^"\\]|\\.)*)"/g;
      let stringMatch;
      while ((stringMatch = stringRegex.exec(customConstraintsMatch[1])) !== null) {
        const raw = stringMatch[1];
        const checkIndex = /CHECK\s*\(/i.exec(raw);
        if (!checkIndex) {
          throw new Error(`Unsupported customConstraint in ${context}: ${raw}`);
        }
        const open = raw.indexOf('(', checkIndex.index);
        const close = findMatching(raw, open, '(', ')');
        checks.push(normalizeCheck(raw.slice(open + 1, close)));
      }
    } else if (/customConstraints/.test(body)) {
      throw new Error(`Could not parse customConstraints in ${context}`);
    }

    const indexes = parseTableIndexAnnotations(prefix, classToTable, context);

    parsed.set(tableName, {
      name: tableName,
      columns,
      primaryKey,
      uniques,
      checks,
      indexes,
    });
  }

  return { tables: parsed, indexes: collectIndexes(parsed, 'tables.dart') };
}

/**
 * Flattens each table's `indexes` list into a name-keyed map and fails on a
 * duplicate index name. `sourceLabel` names the file in error messages.
 */
function collectIndexes(tables, sourceLabel) {
  const indexes = new Map();
  for (const table of tables.values()) {
    for (const index of table.indexes || []) {
      if (indexes.has(index.name)) {
        throw new Error(`Duplicate index '${index.name}' in ${sourceLabel}`);
      }
      indexes.set(index.name, {
        name: index.name,
        unique: index.unique === true,
        table: table.name,
        columns: index.columns,
      });
    }
  }
  return indexes;
}

// ---------------------------------------------------------------------------
// database.g.dart parsing
// ---------------------------------------------------------------------------

/**
 * Parses the committed generated DDL. Each `class $XTable extends X with
 * TableInfo<$XTable, XRow>` becomes a table; its columns, `$columns` order,
 * `$primaryKey`, `uniqueKeys`, and FKs (`defaultConstraints`) are read. The
 * `late final Index` declarations become the index set.
 *
 * The generated shape is stable drift output; anything that does not match the
 * expected form fails loudly rather than being silently skipped.
 */
function parseGeneratedDatabase(source) {
  const classRegex =
    /class \$(\w+)Table extends [\w$]+\s+with\s+TableInfo<\$(\w+)Table,\s*(\w+)>\s*\{/g;
  const tables = new Map();
  let match;
  while ((match = classRegex.exec(source)) !== null) {
    const className = match[1];
    const openBrace = match.index + match[0].length - 1;
    const closeBrace = findMatching(source, openBrace, '{', '}');
    const body = source.slice(openBrace + 1, closeBrace);
    const context = `generated class $${className}Table`;

    const tableNameMatch = /static\s+const\s+String\s+\$name\s*=\s*'([^']*)'/.exec(
      body
    );
    if (!tableNameMatch) {
      throw new Error(`Could not find the $name constant in ${context}`);
    }
    const tableName = tableNameMatch[1];
    if (tables.has(tableName)) {
      throw new Error(`Duplicate generated table '${tableName}'`);
    }

    const columns = new Map();
    const getterToColumn = new Map();
    const colRegex =
      /late final GeneratedColumn<[\w?<>]+>\s+(\w+)\s*=\s*GeneratedColumn<[\w?<>]+>\(/g;
    let colMatch;
    while ((colMatch = colRegex.exec(body)) !== null) {
      const getter = colMatch[1];
      const open = colMatch.index + colMatch[0].length - 1;
      const close = findMatching(body, open, '(', ')');
      const column = parseGeneratedColumn(
        body.slice(open + 1, close),
        `${context}.${getter}`
      );
      if (columns.has(column.name)) {
        throw new Error(`Duplicate generated column '${column.name}' in ${context}`);
      }
      if (getterToColumn.has(getter)) {
        throw new Error(`Duplicate generated getter '${getter}' in ${context}`);
      }
      columns.set(column.name, column);
      getterToColumn.set(getter, column.name);
    }
    if (columns.size === 0) {
      throw new Error(`No GeneratedColumn declarations found in ${context}`);
    }

    // `$columns` is the authoritative ordered column list.
    const columnsOrderMatch =
      /List<GeneratedColumn>\s+get\s+\$columns\s*=>\s*\[([\s\S]*?)\]\s*;/.exec(body);
    if (!columnsOrderMatch) {
      throw new Error(`Missing $columns in ${context}`);
    }
    const orderedNames = [];
    for (const rawGetter of splitTopLevel(columnsOrderMatch[1], ',')) {
      const getterMatch = /^(\w+)$/.exec(rawGetter.trim());
      if (!getterMatch) {
        throw new Error(`Unexpected $columns entry '${rawGetter}' in ${context}`);
      }
      const sqlName = getterToColumn.get(getterMatch[1]);
      if (!sqlName) {
        throw new Error(
          `$columns in ${context} references unknown getter '${getterMatch[1]}'`
        );
      }
      orderedNames.push(sqlName);
    }
    if (orderedNames.length !== columns.size) {
      throw new Error(
        `$columns in ${context} lists ${orderedNames.length} columns but ${columns.size} are declared`
      );
    }
    const orderedColumns = new Map();
    for (const name of orderedNames) orderedColumns.set(name, columns.get(name));

    const primaryKeyMatch =
      /Set<GeneratedColumn>\s+get\s+\$primaryKey\s*=>\s*\{([^}]*)\}/.exec(body);
    if (!primaryKeyMatch) {
      throw new Error(`Missing $primaryKey in ${context}`);
    }
    const primaryKey = mapGeneratedGetters(
      primaryKeyMatch[1],
      getterToColumn,
      `${context}.$primaryKey`
    );

    const uniques = [];
    const uniqueKeysMatch =
      /List<Set<GeneratedColumn>>\s+get\s+uniqueKeys\s*=>\s*\[([\s\S]*?)\]\s*;/.exec(
        body
      );
    if (uniqueKeysMatch) {
      const setRegex = /\{([^}]*)\}/g;
      let setMatch;
      while ((setMatch = setRegex.exec(uniqueKeysMatch[1])) !== null) {
        uniques.push(
          mapGeneratedGetters(setMatch[1], getterToColumn, `${context}.uniqueKeys`)
        );
      }
    }

    tables.set(tableName, {
      name: tableName,
      columns: orderedColumns,
      primaryKey,
      uniques,
      indexes: [],
    });
  }

  if (tables.size === 0) {
    throw new Error('No generated table classes found in database.g.dart');
  }

  const indexes = parseGeneratedIndexes(source);
  for (const index of indexes.values()) {
    const table = tables.get(index.table);
    if (!table) {
      throw new Error(
        `Generated index '${index.name}' references unknown table '${index.table}'`
      );
    }
    table.indexes.push(index);
  }

  return { tables, indexes };
}

/** Maps a comma-separated list of generated getters to their SQL column names. */
function mapGeneratedGetters(text, getterToColumn, context) {
  const names = [];
  for (const rawGetter of splitTopLevel(text, ',')) {
    const getterMatch = /^(\w+)$/.exec(rawGetter.trim());
    if (!getterMatch) {
      throw new Error(`Unexpected entry '${rawGetter}' in ${context}`);
    }
    const sqlName = getterToColumn.get(getterMatch[1]);
    if (!sqlName) {
      throw new Error(`Unknown getter '${getterMatch[1]}' in ${context}`);
    }
    names.push(sqlName);
  }
  return names;
}

/**
 * Parses one generated `GeneratedColumn(...)` argument list:
 * `'sql_name', aliasedName, <isNullable>, type: DriftSqlType.x,
 * requiredDuringInsert: <bool>[, defaultValue: ...][, defaultConstraints: ...]`.
 */
function parseGeneratedColumn(args, context) {
  const parts = splitTopLevel(args, ',');
  if (parts.length < 3) {
    throw new Error(`Unexpected generated column arguments in ${context}: ${args}`);
  }
  const name = unquoteDart(parts[0]);
  const nullability = /^(true|false)$/.exec(parts[2]);
  if (!nullability) {
    throw new Error(
      `Unexpected generated nullability '${parts[2]}' in ${context}`
    );
  }
  const notNull = nullability[1] === 'false';

  let type = null;
  let defaultValue = null;
  let references = null;
  for (let i = 3; i < parts.length; i++) {
    const named = /^(\w+)\s*:\s*([\s\S]*)$/.exec(parts[i]);
    if (!named) {
      throw new Error(`Unexpected generated argument '${parts[i]}' in ${context}`);
    }
    const key = named[1];
    const value = named[2].trim();
    if (key === 'type') {
      if (value === 'DriftSqlType.string') type = 'TEXT';
      else if (value === 'DriftSqlType.int') type = 'INTEGER';
      else throw new Error(`Unsupported DriftSqlType '${value}' in ${context}`);
    } else if (key === 'requiredDuringInsert') {
      // Nullability is carried by the positional flag; nothing to compare.
    } else if (key === 'defaultValue') {
      defaultValue = normalizeDefault(parseDefaultArgument(value, context));
    } else if (key === 'defaultConstraints') {
      references = parseGeneratedReferences(value, context);
    } else {
      throw new Error(`Unsupported generated argument '${key}' in ${context}`);
    }
  }
  if (type === null) {
    throw new Error(`Missing generated column type in ${context}`);
  }
  return { name, type, notNull, default: defaultValue, references };
}

/** Parses `GeneratedColumn.constraintIsAlways('REFERENCES ...')` into an FK. */
function parseGeneratedReferences(value, context) {
  const match = /^GeneratedColumn\.constraintIsAlways\(\s*('(?:[^'\\]|\\.)*')\s*,?\s*\)$/.exec(
    value
  );
  if (!match) {
    throw new Error(`Unsupported defaultConstraints in ${context}: ${value}`);
  }
  const references = extractReferencesClause(unquoteDart(match[1]));
  if (!references) {
    throw new Error(
      `Could not parse a REFERENCES clause in ${context}: ${match[1]}`
    );
  }
  return references;
}

/** Parses every `late final Index <dart> = Index('<name>', '<CREATE ...>')`. */
function parseGeneratedIndexes(source) {
  const indexes = new Map();
  const regex =
    /late final Index\s+(\w+)\s*=\s*Index\(\s*('(?:[^'\\]|\\.)*')\s*,\s*('(?:[^'\\]|\\.)*')\s*,?\s*\)/g;
  let match;
  while ((match = regex.exec(source)) !== null) {
    const declaredName = unquoteDart(match[2]);
    const sql = unquoteDart(match[3]).trim();
    const sqlMatch =
      /^CREATE\s+(UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s+ON\s+["`]?(\w+)["`]?\s*\(([\s\S]*)\)\s*$/i.exec(
        sql
      );
    if (!sqlMatch) {
      throw new Error(`Unsupported generated index SQL: ${sql}`);
    }
    const name = sqlMatch[2];
    if (name !== declaredName) {
      throw new Error(
        `Generated index name '${declaredName}' does not match its SQL '${name}'`
      );
    }
    if (indexes.has(name)) {
      throw new Error(`Duplicate generated index '${name}'`);
    }
    indexes.set(name, {
      name,
      unique: Boolean(sqlMatch[1]),
      table: sqlMatch[3],
      columns: parseColumnList(sqlMatch[4]),
    });
  }
  if (indexes.size === 0) {
    throw new Error('No generated Index declarations found in database.g.dart');
  }
  return indexes;
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

function columnKey(column) {
  return JSON.stringify({
    type: column.type,
    notNull: column.notNull,
    refTable: column.references ? column.references.refTable : null,
    refColumn: column.references ? column.references.refColumn : null,
    onDelete: column.references ? column.references.onDelete : null,
  });
}

function arraysEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function setsOfArraysEqual(a, b) {
  if (a.length !== b.length) return false;
  const key = (arr) => [...arr].sort().join(',');
  const sortedA = a.map(key).sort();
  const sortedB = b.map(key).sort();
  return arraysEqual(sortedA, sortedB);
}

/**
 * Appends reference-vs-local differences to [differences]. [local] is
 * `{ tables, indexes }` as returned by the tables.dart or database.g.dart
 * parser; [label] names that file in messages. [compareChecks] is set only for
 * tables.dart, whose table-level CHECK constraints are not embedded in the
 * generated DDL.
 */
function compareSchemas(reference, local, label, differences, { compareChecks }) {
  const refTables = reference.tables;
  const localTables = local.tables;

  const allTables = new Set([...refTables.keys(), ...localTables.keys()]);
  for (const tableName of [...allTables].sort()) {
    const ref = refTables.get(tableName);
    const localTable = localTables.get(tableName);
    if (!ref) {
      differences.push(
        `Table '${tableName}': present in ${label} but not in reference schema.ts`
      );
      continue;
    }
    if (!localTable) {
      differences.push(`Table '${tableName}': missing from ${label}`);
      continue;
    }

    // Ordered column list: the contract is a straight copy with no mapping
    // layer, so a reorder is a divergence even when names/types match.
    const refColumnOrder = [...ref.columns.keys()];
    const localColumnOrder = [...localTable.columns.keys()];
    if (!arraysEqual(refColumnOrder, localColumnOrder)) {
      differences.push(
        `Table '${tableName}': column order [${localColumnOrder}] (${label}) != [${refColumnOrder}] (reference)`
      );
    }

    const allColumns = new Set([...ref.columns.keys(), ...localTable.columns.keys()]);
    for (const columnName of [...allColumns].sort()) {
      const refColumn = ref.columns.get(columnName);
      const localColumn = localTable.columns.get(columnName);
      if (!refColumn) {
        differences.push(
          `Table '${tableName}': column '${columnName}' exists only in ${label}`
        );
        continue;
      }
      if (!localColumn) {
        differences.push(
          `Table '${tableName}': column '${columnName}' missing from ${label}`
        );
        continue;
      }
      if (refColumn.type !== localColumn.type) {
        differences.push(
          `Table '${tableName}' column '${columnName}': type ${localColumn.type} (${label}) != ${refColumn.type} (reference)`
        );
      }
      if (refColumn.notNull !== localColumn.notNull) {
        differences.push(
          `Table '${tableName}' column '${columnName}': nullability ${localColumn.notNull} (${label} notNull) != ${refColumn.notNull} (reference notNull)`
        );
      }
      const refDefault = normalizeDefault(refColumn.default);
      const localDefault = normalizeDefault(localColumn.default);
      if (refDefault !== localDefault) {
        differences.push(
          `Table '${tableName}' column '${columnName}': default ${JSON.stringify(localDefault)} (${label}) != ${JSON.stringify(refDefault)} (reference)`
        );
      }
      const refRef = refColumn.references
        ? {
            refTable: refColumn.references.refTable,
            refColumn: refColumn.references.refColumn,
            onDelete: refColumn.references.onDelete,
          }
        : null;
      const localRef = localColumn.references
        ? {
            refTable: localColumn.references.refTable,
            refColumn: localColumn.references.refColumn,
            onDelete: localColumn.references.onDelete,
          }
        : null;
      if (JSON.stringify(refRef) !== JSON.stringify(localRef)) {
        differences.push(
          `Table '${tableName}' column '${columnName}': foreign key ${JSON.stringify(localRef)} (${label}) != ${JSON.stringify(refRef)} (reference)`
        );
      }
    }

    if (
      !arraysEqual([...ref.primaryKey].sort(), [...localTable.primaryKey].sort())
    ) {
      differences.push(
        `Table '${tableName}': primary key [${localTable.primaryKey}] (${label}) != [${ref.primaryKey}] (reference)`
      );
    }

    if (!setsOfArraysEqual(ref.uniques, localTable.uniques)) {
      differences.push(
        `Table '${tableName}': UNIQUE constraints ${JSON.stringify(localTable.uniques)} (${label}) != ${JSON.stringify(ref.uniques)} (reference)`
      );
    }

    if (compareChecks) {
      const refChecks = [...new Set(ref.checks)].sort();
      const localChecks = [...new Set(localTable.checks)].sort();
      if (!arraysEqual(refChecks, localChecks)) {
        differences.push(
          `Table '${tableName}': CHECK constraints ${JSON.stringify(localChecks)} (${label}) != ${JSON.stringify(refChecks)} (reference)`
        );
      }
    }
  }

  // Indexes: name, table, ordered columns, and UNIQUE.
  const refIndexes = reference.indexes;
  const localIndexes = local.indexes;
  const allIndexes = new Set([...refIndexes.keys(), ...localIndexes.keys()]);
  for (const indexName of [...allIndexes].sort()) {
    const ref = refIndexes.get(indexName);
    const localIndex = localIndexes.get(indexName);
    if (!ref) {
      differences.push(
        `Index '${indexName}': present in ${label} but not in reference schema.ts`
      );
      continue;
    }
    if (!localIndex) {
      differences.push(`Index '${indexName}': missing from ${label}`);
      continue;
    }
    if (ref.table !== localIndex.table) {
      differences.push(
        `Index '${indexName}': table '${localIndex.table}' (${label}) != '${ref.table}' (reference)`
      );
    }
    if (!arraysEqual(ref.columns, localIndex.columns)) {
      differences.push(
        `Index '${indexName}': columns [${localIndex.columns}] (${label}) != [${ref.columns}] (reference)`
      );
    }
    if (ref.unique !== localIndex.unique) {
      differences.push(
        `Index '${indexName}': unique ${localIndex.unique} (${label}) != ${ref.unique} (reference)`
      );
    }
  }

  // ALTER TABLE ADD COLUMN: redundant when the column exists in CREATE TABLE.
  for (const alter of reference.alters) {
    const table = reference.tables.get(alter.table);
    if (!table) {
      differences.push(`ALTER TABLE references unknown table '${alter.table}'`);
      continue;
    }
    if (!table.columns.has(alter.column.name)) {
      differences.push(
        `ALTER TABLE ${alter.table} ADD COLUMN ${alter.column.name}: not present in the reference CREATE TABLE`
      );
    }
  }
}

/** Fails if the two local sources declare different table sets. */
function compareTableSets(tablesDart, generated, differences) {
  const dartNames = [...tablesDart.keys()].sort();
  const generatedNames = [...generated.keys()].sort();
  if (!arraysEqual(dartNames, generatedNames)) {
    differences.push(
      `tables.dart tables [${dartNames}] != database.g.dart tables [${generatedNames}]`
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 10 remote-DDL Dart port (optional)
// ---------------------------------------------------------------------------

function findRemoteDdlPort() {
  if (!fs.existsSync(SYNC_DIR)) return null;
  const files = fs.readdirSync(SYNC_DIR).filter((file) => file.endsWith('.dart'));
  for (const file of files) {
    const filePath = path.join(SYNC_DIR, file);
    const source = fs.readFileSync(filePath, 'utf8');
    if (
      /CREATE\s+TABLE/i.test(source) &&
      /(REMOTE_SCHEMAS|remoteDdl|remoteSchema|remote_schema)/i.test(source)
    ) {
      return { file: filePath, source };
    }
  }
  return null;
}

function extractDartSqlStrings(source) {
  const strings = [];
  const regex = /('''[\s\S]*?'''|"""[\s\S]*?"""|'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")/g;
  let match;
  while ((match = regex.exec(source)) !== null) {
    let value = match[1];
    if (value.startsWith("'''") || value.startsWith('"""')) {
      value = value.slice(3, -3);
    } else {
      value = value.slice(1, -1);
    }
    if (/\b(CREATE\s+TABLE|CREATE\s+(UNIQUE\s+)?INDEX|ALTER\s+TABLE)\b/i.test(value)) {
      strings.push(value);
    }
  }
  return strings;
}

function canonicalSql(value) {
  return normalizeWhitespace(stripSqlComments(value))
    .replace(/;+\s*$/, '')
    .replace(/\s*\(\s*/g, '(')
    .replace(/\s*\)\s*/g, ')')
    .replace(/\s*,\s*/g, ',')
    .replace(/\s+(ASC|DESC)\b/gi, '')
    .toUpperCase();
}

function checkRemoteDdlPort(differences) {
  const port = findRemoteDdlPort();
  if (!port) {
    console.log(
      '[schema_conformance] Remote-DDL Dart port not found (Phase 10); skipped.'
    );
    return;
  }
  console.log(`[schema_conformance] Checking remote-DDL Dart port at ${path.relative(REPO_ROOT, port.file)}`);
  const portStatements = extractDartSqlStrings(port.source);
  if (portStatements.length === 0) {
    differences.push(
      `Remote-DDL port ${path.relative(REPO_ROOT, port.file)} was located but no SQL statements were parsed`
    );
    return;
  }

  const referenceStatements = extractRemoteSchemas(readFileOrThrow(REFERENCE_SCHEMA));
  const referenceSet = new Set(referenceStatements.map(canonicalSql));
  const portSet = new Set(portStatements.map(canonicalSql));

  for (const statement of referenceSet) {
    if (!portSet.has(statement)) {
      differences.push(`Remote-DDL port is missing statement: ${statement}`);
    }
  }
  for (const statement of portSet) {
    if (!referenceSet.has(statement)) {
      differences.push(`Remote-DDL port has extra statement: ${statement}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const referenceStatements = extractRemoteSchemas(readFileOrThrow(REFERENCE_SCHEMA));
  const reference = parseReferenceTables(referenceStatements);
  const driftDart = parseTablesDart(readFileOrThrow(TABLES_DART));
  const generated = parseGeneratedDatabase(readFileOrThrow(GENERATED_DATABASE));

  const differences = [];
  // CHECK constraints live in tables.dart only; the generated DDL does not
  // embed them.
  compareSchemas(reference, driftDart, 'tables.dart', differences, {
    compareChecks: true,
  });
  compareSchemas(reference, generated, 'database.g.dart', differences, {
    compareChecks: false,
  });
  compareTableSets(driftDart.tables, generated.tables, differences);
  checkRemoteDdlPort(differences);

  if (differences.length === 0) {
    const tableCount = reference.tables.size;
    const indexCount = reference.indexes.size;
    console.log(
      `[schema_conformance] OK: ${tableCount} tables and ${indexCount} indexes match schema.ts in tables.dart and database.g.dart.`
    );
    return;
  }

  console.error('[schema_conformance] Schema drift detected:');
  for (const difference of differences) {
    console.error(`  - ${difference}`);
  }
  process.exitCode = 1;
}

try {
  main();
} catch (error) {
  console.error(`[schema_conformance] Fatal: ${error.message}`);
  process.exitCode = 1;
}

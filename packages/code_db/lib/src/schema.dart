/// The code database schema (version 1). See SCHEMA.md in this package.
library;

/// SQLite `application_id` of a code database file ("IRDB").
const int codeDbApplicationId = 0x49524442;

/// Schema version, stored as `PRAGMA user_version` and in `meta`.
const int codeDbSchemaVersion = 1;

/// Meta key holding the content hash. It is the only row the hash excludes.
const String metaContentHash = 'content_hash';

/// Meta key holding the schema version.
const String metaSchemaVersion = 'schema_version';

/// A table, its columns in canonical order and its canonical row order.
final class TableSpec {
  /// Creates a table spec.
  const TableSpec(this.name, this.columns, this.orderBy);

  /// Table name.
  final String name;

  /// Column names in canonical (hash and insert) order.
  final List<String> columns;

  /// `ORDER BY` clause giving a total order over the rows.
  final String orderBy;
}

/// Every table, in the order the content hash visits them.
const List<TableSpec> codeDbTables = [
  TableSpec('meta', ['key', 'value'], 'key'),
  TableSpec('source', [
    'name',
    'url',
    'commit_sha',
    'license',
    'imported_at',
    'notice',
  ], 'name'),
  TableSpec('brand', ['id', 'name', 'search_key'], 'id'),
  TableSpec('brand_category', [
    'category',
    'brand_id',
    'position',
    'primary_market',
    'code_set_count',
  ], 'category, brand_id'),
  TableSpec('code_set', [
    'id',
    'uid',
    'brand_id',
    'category',
    'rank',
    'label',
    'protocol',
    'key_count',
    'merged_duplicates',
    'source',
    'source_url',
    'source_commit',
    'license',
    'imported_at',
    'path',
  ], 'id'),
  TableSpec('code_set_alias', ['uid', 'code_set_id'], 'uid'),
  TableSpec('key_code', [
    'code_set_id',
    'ord',
    'key',
    'protocol',
    'params',
    'carrier_hz',
    'durations',
    'repeat_frame',
    'repeat_lead_in_us',
    'repeat_gap_us',
    'repeat_min',
  ], 'code_set_id, ord'),
];

/// DDL for schema version 1. Every provenance column is NOT NULL and
/// non-empty (gate L1), enforced again by the writer before insert.
const String codeDbDdl = '''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE source (
  name TEXT PRIMARY KEY NOT NULL CHECK (name <> ''),
  url TEXT NOT NULL CHECK (url <> ''),
  commit_sha TEXT NOT NULL CHECK (commit_sha <> ''),
  license TEXT NOT NULL CHECK (license <> ''),
  imported_at TEXT NOT NULL CHECK (imported_at <> ''),
  notice TEXT NOT NULL CHECK (notice <> '')
) WITHOUT ROWID;

CREATE TABLE brand (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE CHECK (name <> ''),
  search_key TEXT NOT NULL
);

CREATE TABLE brand_category (
  category TEXT NOT NULL,
  brand_id INTEGER NOT NULL REFERENCES brand (id),
  position INTEGER NOT NULL,
  primary_market INTEGER NOT NULL CHECK (primary_market IN (0, 1)),
  code_set_count INTEGER NOT NULL CHECK (code_set_count > 0),
  PRIMARY KEY (category, brand_id)
) WITHOUT ROWID;

CREATE UNIQUE INDEX brand_category_order ON brand_category (category, position);

CREATE TABLE code_set (
  id INTEGER PRIMARY KEY,
  uid TEXT NOT NULL UNIQUE CHECK (uid <> ''),
  brand_id INTEGER NOT NULL REFERENCES brand (id),
  category TEXT NOT NULL,
  rank INTEGER NOT NULL,
  label TEXT,
  protocol TEXT,
  key_count INTEGER NOT NULL CHECK (key_count > 0),
  merged_duplicates INTEGER NOT NULL CHECK (merged_duplicates >= 0),
  source TEXT NOT NULL REFERENCES source (name) CHECK (source <> ''),
  source_url TEXT NOT NULL CHECK (source_url <> ''),
  source_commit TEXT NOT NULL CHECK (source_commit <> ''),
  license TEXT NOT NULL CHECK (license <> ''),
  imported_at TEXT NOT NULL CHECK (imported_at <> ''),
  path TEXT
);

CREATE UNIQUE INDEX code_set_order ON code_set (category, brand_id, rank);

CREATE TABLE code_set_alias (
  uid TEXT PRIMARY KEY NOT NULL,
  code_set_id INTEGER NOT NULL REFERENCES code_set (id)
) WITHOUT ROWID;

CREATE TABLE key_code (
  code_set_id INTEGER NOT NULL REFERENCES code_set (id),
  ord INTEGER NOT NULL,
  key TEXT NOT NULL,
  protocol TEXT,
  params TEXT,
  carrier_hz INTEGER,
  durations BLOB,
  repeat_frame BLOB,
  repeat_lead_in_us INTEGER,
  repeat_gap_us INTEGER,
  repeat_min INTEGER,
  PRIMARY KEY (code_set_id, ord),
  CHECK (
    (protocol IS NOT NULL AND params IS NOT NULL
      AND carrier_hz IS NULL AND durations IS NULL)
    OR (protocol IS NULL AND params IS NULL
      AND carrier_hz IS NOT NULL AND durations IS NOT NULL)
  )
) WITHOUT ROWID;
''';

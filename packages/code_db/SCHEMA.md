# Code database schema (version 1)

The bundled IR code database is one SQLite file, `assets/codes.sqlite`, built
by `tools/db_build` and opened read-only by `CodeDb.open`. It holds only
published code sets with their provenance. **User data never lives here**:
saved remotes, learned codes and AC state live in the app's own database, and
a saved remote keeps a snapshot of each resolved signal, so a database update
never silently changes a working remote.

Files in `assets/`:

| File | Content |
| --- | --- |
| `codes.sqlite` | The database. |
| `codes.sqlite.sha256` | One line: the content hash (see below). |
| `codes.manifest.json` | Schema version, content hash, file SHA-256 and size, sources, counts. No timestamps. |
| `codes.report.json` | Build report: per-source file and signal counts, skipped signals by reason, duplicates merged, sizes. |

## Identification

- `PRAGMA application_id` = `0x49524442` ("IRDB").
- `PRAGMA user_version` = schema version (`1`), also in `meta.schema_version`.

`CodeDb.open` rejects any other file with `CodeDbSchemaException`.

## Tables

All text is UTF-8. Brand names are plain text; there are no logos.

### `meta` (key TEXT PK, value TEXT)

| Key | Value |
| --- | --- |
| `content_hash` | Content hash, lower-case hex SHA-256. Excluded from the hash itself. |
| `schema_version` | `1` |
| `code_set_count`, `brand_count`, `key_code_count` | Counts. |
| `build_tool` | `tools/db_build <version>` |
| `subset` | `primary-market` for the bundled file. |
| `irdb_announcement_issue` | Present only when irdb data is included (gate L4). |

### `source` (name TEXT PK)

One row per source the file was built from: `url`, `commit_sha` (pinned),
`license` (SPDX id or `LicenseRef-*`), `imported_at` (ISO date), `notice`
(text the licences screen must show verbatim, gate L3; for MIT the full
licence). All columns are NOT NULL and non-empty.

### `brand` (id INTEGER PK)

`name` (unique display name) and `search_key` (lower case, spaces and
punctuation removed) used by brand search.

### `brand_category` (PK category, brand_id)

One row per brand that has code sets in a category: `position` (listing
order, 0 first: primary-market brands in ranking order, then the rest
alphabetically), `primary_market` (0/1) and `code_set_count`. Unique index
`(category, position)`.

### `code_set` (id INTEGER PK)

| Column | Meaning |
| --- | --- |
| `uid` | Stable public ID (`fz-<12 hex>` for flipperdevices/irdb, `irdb-<12 hex>` for probonopd/irdb: SHA-256 of `source:path`). This is `CodeSet.id`. |
| `brand_id`, `category` | Brand and `DeviceCategory.name`. |
| `rank` | Matching order within (brand, category), dense from 0. Unique index `(category, brand_id, rank)`. |
| `label` | Model or file label from the source. |
| `protocol` | Protocol shared by every key, or NULL when mixed or raw. |
| `key_count`, `merged_duplicates` | Keys; duplicate code sets merged into this one. |
| `source`, `source_url`, `source_commit`, `license`, `imported_at` | Gate L1 provenance: NOT NULL and non-empty (CHECK constraints, and the writer refuses the build before inserting). |
| `path` | File path inside the source repository. |

### `code_set_alias` (uid TEXT PK, code_set_id)

IDs of duplicates that were merged at build time, so `codeSetById` still
resolves them.

### `key_code` (PK code_set_id, ord)

One row per key, `ord` in canonical key order (the fixed vocabulary order of
`Keys.all`, then `custom:` keys by code unit order). `key` is a normalized
name or `custom:<original>`. Exactly one of two shapes (CHECK constraint):

- Protocol: `protocol` (canonical ir_core ID such as `NEC1`, `NECx2`,
  `Sony20`, `RC5`, `Panasonic`) and `params` as `D=4,S=251,F=8` in the
  codec's parameter order, defaults filled, without the session toggle `T`.
- Raw: `carrier_hz` and `durations`, the mark-first, mark-last durations in
  microseconds as unsigned LEB128 varints. Optional repeat: `repeat_lead_in_us`,
  `repeat_gap_us`, `repeat_min`, and `repeat_frame` (varints; NULL means the
  repeat frame equals the main frame).

## Content hash

SHA-256 over a canonical serialization of every row: tables in the order
`meta, source, brand, brand_category, code_set, code_set_alias, key_code`, rows
in primary-key order, columns in declared order. A row is the table name and
its values separated by `0x1F` and ended by `0x0A`; a value is `~` (NULL),
`i<decimal>` (integer), `s<n>:<utf8>` (text) or `b<n>:<bytes>` (blob), `<n>`
being the byte length. The `content_hash` meta row is excluded. See
`computeContentHash`.

The hash covers rows, not bytes, so it does not depend on page layout or the
SQLite version. The writer is also byte-deterministic for a given SQLite
library (canonical insert order into an in-memory database, then
`VACUUM INTO`; nothing time-dependent is stored), so two builds from the same
inputs give the same hash and the same file. `fileSha256` in the manifest is
for verifying downloads (the CDN path for other markets).

## Loading and verification

```dart
final manifest = CodeDbManifest.parse(manifestText);
final db = CodeDb.open(path, expectedContentHash: manifest.contentSha256);
```

`CodeDbVerification.full` (default) recomputes the hash over every row:
about 0.3 s for the bundled file on a desktop JIT, so do it once after
copying the asset out of the bundle (or after a download), off the UI thread,
and open later with `CodeDbVerification.storedHashOnly` plus the expected
hash (under 1 ms). Mismatches throw `CodeDbIntegrityException` with the
expected and actual hashes; a missing or foreign file throws
`CodeDbOpenException` or `CodeDbSchemaException`.

## Queries

| API | Order |
| --- | --- |
| `categories()` | `DeviceCategory` order, with code-set and brand counts. |
| `brands(category, search:)` | `brand_category.position`; `search` matches `search_key` as a substring. |
| `codeSets(brand, category)` | `rank`: try the first set first. |
| `codeSetById(id)` | Direct, then alias. |
| `totals()`, `sources()` | Counts; sources with notices. |

All return ir_core types (`CodeSet`, `KeyCode`, `Provenance`). Lookups use the
unique indexes above; brand listing and code-set loading take well under
10 ms on the bundled file.

/// The bundled, read-only IR code database: schema, deterministic writer,
/// loader with content-hash verification and the query API used by the
/// add-device flow. See SCHEMA.md.
library;

export 'src/code_db.dart';
export 'src/content_hash.dart' show computeContentHash;
export 'src/encoding.dart' show brandSearchKey, compareKeys;
export 'src/errors.dart';
export 'src/manifest.dart';
export 'src/schema.dart' show codeDbSchemaVersion;
export 'src/writer.dart';

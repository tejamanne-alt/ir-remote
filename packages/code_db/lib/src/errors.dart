/// Typed errors of the code database.
library;

/// Base class of every code database error.
sealed class CodeDbException implements Exception {
  const CodeDbException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => '$_name: $message';

  String get _name;
}

/// The file could not be opened as a code database.
final class CodeDbOpenException extends CodeDbException {
  /// Creates the exception.
  const CodeDbOpenException(super.message);

  @override
  String get _name => 'CodeDbOpenException';
}

/// The file is a SQLite database but not a code database of a supported
/// schema version.
final class CodeDbSchemaException extends CodeDbException {
  /// Creates the exception.
  const CodeDbSchemaException(super.message);

  @override
  String get _name => 'CodeDbSchemaException';
}

/// The content hash does not match: the file is corrupt, was modified, or is
/// not the expected build.
final class CodeDbIntegrityException extends CodeDbException {
  /// Creates the exception.
  const CodeDbIntegrityException(
    super.message, {
    required this.expected,
    required this.actual,
  });

  /// The hash that was expected.
  final String expected;

  /// The hash that was found or computed.
  final String actual;

  @override
  String get _name => 'CodeDbIntegrityException';
}

/// A stored value could not be decoded.
final class CodeDbFormatException extends CodeDbException {
  /// Creates the exception.
  const CodeDbFormatException(super.message);

  @override
  String get _name => 'CodeDbFormatException';
}

/// The writer refused its input.
final class CodeDbBuildException extends CodeDbException {
  /// Creates the exception.
  const CodeDbBuildException(super.message);

  @override
  String get _name => 'CodeDbBuildException';
}

/// Gate L1: a code set or source lacks a provenance field.
final class CodeDbProvenanceException extends CodeDbException {
  /// Creates the exception.
  const CodeDbProvenanceException(super.message);

  @override
  String get _name => 'CodeDbProvenanceException';
}

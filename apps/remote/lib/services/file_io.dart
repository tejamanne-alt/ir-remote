/// Picking and sharing files, behind an interface so screens are testable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Largest file the app reads (backups and Flipper `.ir` imports).
const int maxImportBytes = 5 * 1024 * 1024;

/// Thrown when a picked file is too large.
final class FileTooLargeException implements Exception {
  /// Creates the exception.
  const FileTooLargeException(this.bytes);

  /// The file's size.
  final int bytes;

  @override
  String toString() => 'The file is larger than 5 MB.';
}

/// Thrown when a picked file is not UTF-8 text. It is a [FormatException],
/// so every import path reports it as a file-format error.
final class NotTextFileException extends FormatException {
  /// Creates the exception.
  const NotTextFileException() : super('the file is not UTF-8 text');
}

/// Decodes a picked file's [bytes] as UTF-8 (a leading byte-order mark is
/// dropped). Throws [NotTextFileException] for anything else.
String decodeImportText(List<int> bytes) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const NotTextFileException();
  }
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

/// Platform file operations.
abstract interface class FileIo {
  /// Lets the user pick a text file; returns its contents, or `null` if
  /// cancelled. Throws [FileTooLargeException] above [maxImportBytes] and
  /// [NotTextFileException] when the file is not UTF-8 text.
  Future<String?> pickText({List<String> extensions = const []});

  /// Writes [text] to a temporary file called [name] and opens the share
  /// sheet for it.
  Future<void> shareText(String name, String text);
}

/// The real implementation: file_selector and share_plus.
final class PlatformFileIo implements FileIo {
  /// Creates the implementation.
  const PlatformFileIo();

  @override
  Future<String?> pickText({List<String> extensions = const []}) async {
    final file = await openFile(
      acceptedTypeGroups: extensions.isEmpty
          ? const []
          : [
              XTypeGroup(
                label: extensions.join(', '),
                extensions: extensions,
                uniformTypeIdentifiers: extensions.contains('json')
                    ? const ['public.json']
                    : const ['public.data'],
              ),
            ],
    );
    if (file == null) return null;
    final size = await file.length();
    if (size > maxImportBytes) throw FileTooLargeException(size);
    // Bytes, then a checked decode: readAsString reports a non-UTF-8 file
    // as a FileSystemException that import paths would not expect.
    return decodeImportText(await file.readAsBytes());
  }

  @override
  Future<void> shareText(String name, String text) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(text, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path)], subject: name),
    );
  }
}

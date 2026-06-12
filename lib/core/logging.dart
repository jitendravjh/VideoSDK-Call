import 'package:logger/logger.dart';

/// Thin wrapper over [Logger] so the rest of the app depends on a single
/// logging surface rather than the package directly.
class AppLogger {
  AppLogger(this._tag);

  final String _tag;

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 80,
      printEmojis: false,
    ),
  );

  void debug(String message) => _logger.d('[$_tag] $message');

  void info(String message) => _logger.i('[$_tag] $message');

  void warn(String message) => _logger.w('[$_tag] $message');

  void error(String message, [Object? err, StackTrace? stackTrace]) =>
      _logger.e('[$_tag] $message', error: err, stackTrace: stackTrace);
}

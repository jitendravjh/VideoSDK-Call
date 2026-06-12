/// Helpers for the short shareable call codes the server assigns.
///
/// Codes are stored and routed as a raw 6-character string; they are shown
/// grouped as `ABC-DEF` and accepted in either form on input.
class CallCode {
  const CallCode._();

  static String format(String code) {
    if (code.length <= 3) return code;
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  static String normalize(String input) {
    return input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  }
}

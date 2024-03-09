/// Returned result for every `eval` calling, including importing code.
final class JsEvalResult {
  /// The result string of the last js statement.
  final String value;

  /// The standard output called by js, e.g. `console.log()`.
  final String? stdout;

  /// The standard error occurred in js.
  final String? stderr;

  /// If the last statement is a promise.
  final bool isPromise;

  const JsEvalResult({
    required this.value,
    this.stdout,
    this.stderr,
    this.isPromise = false,
  });

  bool get isError => stderr != null;
}

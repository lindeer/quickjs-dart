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

  factory JsEvalResult.from(Map<String, dynamic> data) {
    return JsEvalResult(
      value: data['value'] ?? '',
      stdout: data['stdout'],
      stderr: data['stderr'],
      isPromise: data['is_promise'] ?? false,
    );
  }

  bool get isError => stderr != null;

  Map<String, dynamic> get raw => {
        'value': value,
        if (stdout != null) 'stdout': stdout,
        if (stderr != null) 'stderr': stderr,
        'is_promise': isPromise,
      };
}

/// Renders `${var}` placeholders against a map of values.
///
/// Unknown placeholders cause a [TemplateException] so typos surface at build
/// time rather than producing files like `Appnull_...apk`.
String renderTemplate(String template, Map<String, String> values) {
  final pattern = RegExp(r'\$\{(\w+)\}');
  final unknown = <String>{};
  final rendered = template.replaceAllMapped(pattern, (m) {
    final key = m.group(1)!;
    final value = values[key];
    if (value == null) {
      unknown.add(key);
      return m.group(0)!;
    }
    return value;
  });
  if (unknown.isNotEmpty) {
    throw TemplateException(
      'Unknown placeholder(s) in output template: '
      '${unknown.map((k) => '\${$k}').join(', ')}. '
      'Known variables: ${values.keys.map((k) => '\${$k}').join(', ')}.',
    );
  }
  return rendered;
}

class TemplateException implements Exception {
  TemplateException(this.message);
  final String message;
  @override
  String toString() => message;
}

import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/builder/output_template.dart';
import 'package:test/test.dart';

void main() {
  group('renderTemplate', () {
    test('substitutes all known variables', () {
      final result = renderTemplate(
        r'App${appId}_${appname}_v${versionName}(${versionCode})_'
        r'${buildDate}_${flavor}_${buildType}.apk',
        {
          'appId': '780',
          'appname': 'Muslim',
          'versionName': '1.0.0',
          'versionCode': '1',
          'buildDate': '2026.05.07',
          'flavor': 'dev',
          'buildType': 'release',
        },
      );

      expect(result, 'App780_Muslim_v1.0.0(1)_2026.05.07_dev_release.apk');
    });

    test('the default template plus sample values matches the spec example',
        () {
      final result = renderTemplate(defaultOutputNameTemplate, {
        'appId': '780',
        'appname': 'Muslim',
        'versionName': '1.0.0',
        'versionCode': '1',
        'buildDate': '2026.05.07',
        'buildTime': '14.30',
        'flavor': 'pro',
        'buildType': 'release',
      });

      expect(result, 'App780_Muslim_v1.0.0(1)_2026.05.07_pro_release.apk');
    });

    test('substitutes the same variable multiple times', () {
      final result = renderTemplate(
        r'${name}-${name}.apk',
        {'name': 'foo'},
      );
      expect(result, 'foo-foo.apk');
    });

    test('leaves a template with no placeholders untouched', () {
      expect(renderTemplate('static.apk', {}), 'static.apk');
    });

    test('throws TemplateException on unknown placeholder', () {
      expect(
        () => renderTemplate(
          r'${unknown}.apk',
          {'appId': '1'},
        ),
        throwsA(
          isA<TemplateException>().having(
            (e) => e.message,
            'message',
            allOf(contains(r'${unknown}'), contains(r'${appId}')),
          ),
        ),
      );
    });

    test('reports every unknown placeholder, not just the first', () {
      expect(
        () => renderTemplate(r'${a}_${b}.apk', {}),
        throwsA(
          isA<TemplateException>().having(
            (e) => e.message,
            'message',
            allOf(contains(r'${a}'), contains(r'${b}')),
          ),
        ),
      );
    });

    test('does not substitute names containing non-word characters', () {
      // The grammar is `\w+` (letters/digits/underscore) — anything else is
      // a literal and should pass through unchanged.
      expect(
        renderTemplate(r'${foo-bar}', {'foo-bar': 'x'}),
        r'${foo-bar}',
      );
    });
  });
}

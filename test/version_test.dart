import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/app_version.dart';

void main() {
  group('app version', () {
    test('matches the version in pubspec.yaml', () {
      // kAppVersion is a hand-written constant so that showing the version
      // does not cost a native plugin. This is what stops the two drifting:
      // bump one without the other and the suite fails.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(line, isNotNull, reason: 'pubspec.yaml has no version');

      final full = line!.group(1)!; // e.g. 0.7.0+8
      final semver = full.split('+').first; // the build number is not shown
      expect(
        kAppVersion,
        semver,
        reason: 'lib/app_version.dart and pubspec.yaml disagree',
      );
    });

    test('stays below 1.0 until every planned feature is done', () {
      // 1.0.0 means finished, not "the default Flutter gives you". Reaching it
      // should be a decision, so this fails loudly when the major version is
      // raised and prompts a look at whether that is really true.
      final major = int.parse(kAppVersion.split('.').first);
      expect(
        major,
        0,
        reason:
            'Raising to 1.0 means every planned feature is built and '
            'debugged. If that is genuinely true, update this test.',
      );
    });

    test('a release build shows only the number', () {
      // Tests run in debug, so this pins the shape rather than the value.
      expect(kAppVersion, isNot(contains('·')));
      expect(versionLabel, startsWith(kAppVersion));
    });
  });
}

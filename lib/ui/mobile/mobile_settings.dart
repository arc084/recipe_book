import 'package:flutter/material.dart';

import '../settings/settings_page.dart';
import 'mobile_widgets.dart';

/// Settings on Android, as a tab of its own.
///
/// The page itself is the desktop's, in its phone shape — `isPhone` decides
/// what the two platforms do differently (the databases are listed for their
/// sizes only, and pairing types the six digits rather than showing them), so
/// there is one Settings to keep right rather than two.
///
/// It sits under a header like every other tab and not the back bar it used
/// to have, because there is nothing to go back to: it is no longer a screen
/// pushed from the Library.
class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileHeader(title: 'Settings', showSync: false),
        Expanded(child: SettingsPage(isPhone: true)),
      ],
    );
  }
}

/// Android check for targets that have `dart:io`.
library;

import 'dart:io' show Platform;

/// Whether this process is the Android operating system.
bool get isAndroidPlatform => Platform.isAndroid;

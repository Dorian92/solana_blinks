/// Android check for targets that do not have `dart:io`, including the web.
library;

/// Whether this process is the Android operating system.
///
/// Web and other targets without `dart:io` are not Android.
bool get isAndroidPlatform => false;

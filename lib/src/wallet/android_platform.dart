/// Picks the Android check for the current Dart target.
///
/// `dart:io` is imported only when the target provides it. The web uses the
/// stub, which reports that the process is not Android.
library;

export 'android_platform_stub.dart'
    if (dart.library.io) 'android_platform_io.dart';

/// The plaintext copies the platform's file dialogs leave in the app's own sandbox on iOS and
/// Android, and their removal (ADR-138). A web build has no such directory, so it gets a version that
/// does nothing. The device version is the default, so that it is the one the analyzer checks callers
/// against; `dart.library.js_interop` is true of a web build, WebAssembly included.
library;

export 'picker_copies_io.dart' if (dart.library.js_interop) 'picker_copies_stub.dart';

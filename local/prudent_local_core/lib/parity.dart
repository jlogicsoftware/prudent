/// The server/local parity harness (ADR-107): scenarios as data, an engine that runs one scenario
/// through two backends and compares every step exactly, and the readers both backends observe
/// answers with.
///
/// Neither backend is here. The server's needs `zen_transport` and `zen_identity`, which this package
/// must never import (ADR-101); it lives in `tools/prudent_parity_server`. The local one runs the
/// ledger over a real store, which depends on this package; it is `prudent_local_store`'s
/// `StoreBackend` (ADR-113), which replaced unit 3's in-memory stand-in.
library;

export 'src/parity/analytics_scenarios.dart';
export 'src/parity/parity_backend.dart';
export 'src/parity/parity_clock.dart';
export 'src/parity/parity_engine.dart';
export 'src/parity/parity_readers.dart';
export 'src/parity/parity_scenario.dart';

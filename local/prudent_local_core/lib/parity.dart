/// The server/local parity harness (ADR-107): scenarios as data, an engine that runs one scenario
/// through two backends and compares every step exactly, and the local backend.
///
/// The server backend is not here: it needs `zen_transport` and `zen_identity`, which this package
/// must never import (ADR-101). It lives in `tools/prudent_parity_server`, a test-only package.
library;

export 'src/parity/local_rules_backend.dart';
export 'src/parity/parity_backend.dart';
export 'src/parity/parity_engine.dart';
export 'src/parity/parity_scenario.dart';

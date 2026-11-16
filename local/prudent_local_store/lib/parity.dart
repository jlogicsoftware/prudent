/// The local side of Prudent's server/local parity suite (ADR-107, ADR-113): [StoreBackend] answers
/// every parity operation through the ledger over a real encrypted store. A library of its own, so
/// the Local app never links the harness.
library;

export 'src/parity/store_backend.dart';

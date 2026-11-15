/// The importer the client asks for. The server names importers by id and refuses an unknown one
/// (ADR-088); Erste Polska's CSV is the only format that exists.
const String erstePlCsvFormatId = 'erste-pl-csv';

/// The largest statement the server accepts (`ImportWorkflow.MAX_CONTENT_BYTES`, 5 MiB). Checked
/// before the file is read so a wrong file is refused without loading it, and again on the bytes.
const int maxStatementBytes = 5 * 1024 * 1024;

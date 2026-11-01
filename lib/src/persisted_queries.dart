/// Shortest query, in characters, worth sending as a hash. The persisted-query
/// extension costs about this much once percent-encoded for a GET, so anything
/// at or below it is smaller as plain text.
const persistedQueryMinLength = 144;

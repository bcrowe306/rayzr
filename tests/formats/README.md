# File format fixtures (#326)

One file per versioned kind per format, loaded by `engine/file_format_test.odin`.
When a kind's format is bumped (engine/file_format.odin), keep the old fixtures,
add one of the new format, and extend the test with what the migration changes.
Files are named `<kind>.f<format>.<extension>`.

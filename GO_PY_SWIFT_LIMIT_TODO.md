Wrong numbers. In the first summary table I wrote unit-test counts I hadn't actually counted.
- Go unit tests are 16, not 20.
- Go mock tests are 6 plus 1 REST-only, not 9.
- Swift unit tests are 15, not 21.
- The other counts (Python 111 real, Swift 101 real, Go 30 real, mocks of 22) are measured.

Go specifically
- Multipart buffers files in memory.
  - The Go multipart code calls io.ReadAll on each file part.
  - I just fixed exactly this for Python, but I never flagged it for Go.
  - Go raw uploads do stream.
  - TS, Kotlin and Swift also buffer multipart parts.
  - Swift buffers raw uploads too, because GLUpload holds Data. I mentioned that but didn't call it the same problem.
- Required-field checks are on the type itself.
  - Go checks for missing fields in a generated UnmarshalJSON on any type that REST operations reach.
  - If a GraphQL response decodes into one of those same types with a partial selection, it would now fail.
  - I haven't tested that overlap.
  - TS and Kotlin apply the same check to those types, and I haven't tested it there either.
- Argument names can still clash.
  - I only fixed the q clash with the receiver variable.
  - An argument named ctx, err or opts, or an <Op>Options type name that already exists, would still break the generated code.
  - I never tried any of these.
- Smaller points:
  - A cache read error is silently treated as a miss.
  - A provider header and an argument header with different casing both get sent.
  - The generated Go isn't gofmt-formatted.
  - I compiled with local Go 1.27, while CI pins 1.22.

Across all three
- Existing real-server suites not run.
  - I changed shared code: the Python serializer and GLUpload, the Swift fromJson dispatch, the Go serializer and client.
  - I re-ran only the mock suites and the Dart unit tests.
  - The existing Spring-server suites for these languages need the JAR, and I didn't run them.
  - I also didn't check whether the Python client in server_integration_tests uses GLUpload.
  - The GLUpload change is the riskiest, because it also affects the GraphQL upload path.
- Little coverage.
  - Go real tests are 30 and Kotlin's are 61, against Dart's 133 in the same areas.
  - I merged cases into larger tests, so they are less granular.
  - There is no mid-stream failure test for Go or Swift.
- CI. The new ci.yml jobs have not been run.
- Naming oddity. Swift's restHttpAdapter reuses the wsAdapter enum (urlsession|none) instead of having its own.
- Limit I didn't mention. Swift can't do chunked uploads at all, since the whole file is Data.
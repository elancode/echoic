---
paths:
  - "EchoicTests/**"
  - "*Tests.swift"
  - "*Test.swift"
---

# Testing Conventions

## Framework
- **XCTest** for all tests. No third-party test frameworks.
- Test targets: `EchoicTests` (unit + integration).

## Structure
- Mirror source directory structure: `EchoicTests/AudioTests/`, `EchoicTests/StorageTests/`, etc.
- One test class per source file under test.
- Test method names: `test_<methodName>_<scenario>_<expectedBehavior>`.

## TDD Workflow
- Write the failing test first, then implement.
- Each test must be independent — no shared mutable state between tests.
- Use `setUp()` and `tearDown()` for GRDB in-memory databases, temp directories, etc.

## Database Tests
- Always use an **in-memory** GRDB database for tests (`:memory:`).
- Run migrations in setUp to ensure schema is current.
- Test FTS5 queries with realistic transcript text.

## Audio Tests
- Use pre-recorded WAV fixtures in `EchoicTests/Fixtures/`.
- Never depend on ScreenCaptureKit permissions in unit tests — mock the audio source.
- Test ring buffer wrap-around, AAC encoding round-trip, sample rate conversion.

## API Tests
- Mock URLSession with `URLProtocol` subclass — never hit the real Anthropic API in tests.
- Test retry logic with simulated failures (429, 500, timeout).
- Test JSON response parsing with realistic fixture data.

## Assertions
- Use specific assertions (`XCTAssertEqual`, `XCTAssertThrowsError`) over generic `XCTAssert`.
- For floating-point comparisons (audio, confidence scores): use `XCTAssertEqual(_, _, accuracy:)`.
- For WER/DER measurements: use tolerance-based assertions.

## What NOT to Test
- SwiftUI view rendering (fragile, low value).
- CoreML model accuracy (benchmark separately, not in CI).
- macOS permission dialogs (can't automate).

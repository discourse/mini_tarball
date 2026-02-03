# Claude Code Guidelines for mini_tarball

## Project Overview

A minimal Ruby implementation of the GNU Tar format for writing tar archives with streaming support.

## Ruby Version

- **Target:** Ruby 3.2+
- **Assume YJIT is enabled** when optimizing for performance
- Use modern Ruby features (pattern matching, Data classes, keyword arguments)

## Code Style

### Principles

- **Performance matters:** Avoid unnecessary allocations, prefer frozen strings
- **Security matters:** Validate inputs, especially filenames (path traversal)
- **Maintainability matters:** Clear naming, small methods, minimal nesting

### Guidelines

- Use `frozen_string_literal: true` in all files
- Prefer `Data.define` over `Struct` for immutable value objects
- Use keyword arguments for methods with 3+ parameters
- Return `self` from mutating methods to enable chaining
- Use guard clauses to reduce nesting
- Freeze constants and their nested values

### Avoid

- Inline `rescue` for control flow (except simple fallbacks)
- `method_missing` unless absolutely necessary
- Monkey-patching core classes
- Creating strings in hot paths (pre-allocate and slice instead)

## Testing

- Every change must have corresponding specs
- Test edge cases and boundaries (e.g., filename at exactly 100 bytes)
- Test error conditions, not just happy paths
- Specs should be independent and not rely on execution order
- Unit specs live in `spec/unit` and should avoid external tar binaries; use fixtures in `spec/fixtures` for byte-level assertions
- Integration specs live in `spec/integration` and may use external extractors (GNU tar/bsdtar) via `spec/integration_helper.rb`
- Prefer fixtures for deterministic byte comparisons; prefer integration tests for extraction behavior or interoperability checks
- Regenerate fixtures with `bundle exec rake fixtures:generate` when output bytes change; CI uses `bundle exec rake fixtures:verify`
- Run `bundle exec rspec` after changes
- Format with `bundle exec rake fix` before committing

Prefer `let` over `let!` - eager evaluation wastes resources and hides test dependencies.

## Commit Messages

- `DEV:` prefix for development/tooling changes
- `FIX:` prefix for bug fixes
- `FEATURE:` prefix for new features
- Keep messages concise, explain "why" not just "what"

## Key Design Decisions

1. **Streaming-first:** No temporary files, handle arbitrary sizes
2. **GNU tar format:** Not POSIX pax, use GNU extensions for long filenames
3. **Security by default:** Reject path traversal, validate inputs
4. **Fail fast:** Raise errors early rather than producing corrupt output

## References

- [GNU Tar Internals](https://www.gnu.org/software/tar/manual/html_chapter/Tar-Internals.html)

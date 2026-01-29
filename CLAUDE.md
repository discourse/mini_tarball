# Claude Code Guidelines for mini_tarball

## Project Overview

A minimal Ruby implementation of the GNU Tar format for reading and writing tar archives with streaming support.

## Ruby Version

- **Target:** Ruby 3.2+
- **Assume YJIT is enabled** when optimizing for performance
- Use modern Ruby features (pattern matching, endless methods where clear, Data classes, etc.)
- No backward compatibility concerns - the gem isn't in production use yet

## Code Style

### General Principles

- **Performance matters:** Avoid unnecessary allocations, prefer frozen strings, use efficient data structures
- **Security matters:** Validate inputs, especially filenames (path traversal), handle untrusted data carefully
- **Maintainability matters:** Clear naming, small methods, minimal nesting

### Specific Guidelines

- Use `frozen_string_literal: true` in all files
- Prefer `Data.define` over `Struct` for immutable value objects (Ruby 3.2+)
- Use keyword arguments for methods with 3+ parameters
- Return `self` from mutating methods to enable chaining
- Use guard clauses to reduce nesting
- Freeze constants and their nested values

### Avoid

- Inline `rescue` for control flow (except simple fallbacks like `rescue nil`)
- `method_missing` unless absolutely necessary
- Monkey-patching core classes
- Creating strings in hot paths (pre-allocate and slice instead)

## Testing

- Every change must have corresponding specs
- Test edge cases and boundaries (e.g., filename at exactly 100 bytes)
- Test error conditions, not just happy paths
- Use `let` instead of `let!` unless eager evaluation is required
- Specs should be independent and not rely on execution order

## File Organization

```
lib/mini_tarball/
├── writer.rb           # Main Writer class
├── reader.rb           # Main Reader class
├── header.rb           # Tar header structure
├── header_fields.rb    # Header field encoding
├── header_formatter.rb # Number formatting (octal, base-256)
├── header_writer.rb    # Header writing logic
├── header_parser.rb    # Header parsing logic
├── entry.rb            # Archive entry representation
├── placeholder_ref.rb  # Placeholder for deferred file writing
├── version.rb          # Version constant
└── streams/            # IO wrapper classes
    ├── write_only_stream.rb
    ├── limited_size_stream.rb
    ├── placeholder_stream.rb
    ├── capped_write_stream.rb
    └── bounded_read_stream.rb
```

## Commit Messages

Follow the existing convention:
- `DEV:` prefix for development/tooling changes
- `FIX:` prefix for bug fixes
- `FEATURE:` prefix for new features
- Keep messages concise, explain "why" not just "what"

## Working in Chunks

- Maximum ~150 lines of code per change
- Each chunk should be self-contained and testable
- Write specs before or alongside implementation
- Run `bundle exec rspec` after each change
- Format code with `bundle exec rake fix` before committing and fix any issues

## Key Design Decisions

1. **Streaming-first:** No temporary files, handle arbitrary sizes
2. **GNU tar format:** Not POSIX pax, use GNU extensions for long filenames
3. **Security by default:** Reject path traversal, validate inputs
4. **Fail fast:** Raise errors early rather than producing corrupt output

## References

- [GNU Tar Internals](https://www.gnu.org/software/tar/manual/html_chapter/Tar-Internals.html)

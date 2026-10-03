# mini_tarball

See README.md for features and usage. This file has the rules that aren't written down anywhere else.

## Code

- Support all non-EOL MRI versions, JRuby and TruffleRuby. When an MRI version reaches EOL, raise `required_ruby_version`, `TargetRubyVersion` in `.rubocop.yml` and the CI matrix.
- Fail fast: raise an error instead of writing an entry that is wrong or corrupts the archive.
- Avoid allocations in code that runs for every entry or every write. Assume YJIT.
- Use keyword arguments for methods with 3+ parameters, and `Data.define` for value objects.

## Specs

- Every change needs specs, including error cases and boundaries.
- `spec/unit` doesn't use external tar binaries. Compare bytes against fixtures in `spec/fixtures`.
- `spec/integration` may run GNU tar and bsdtar.
- When output bytes change, regenerate fixtures with `bundle exec rake fixtures:generate`. CI checks them with `bundle exec rake fixtures:verify`.

## Before committing

Run `bundle exec rake fix`, `bundle exec rspec`, `bundle exec reek lib` and `bundle exec rake mutant`. Mutation coverage must stay at 100%. An entry in the ignore list of `mutant.yml` needs a comment that explains why the mutation can't be killed. Commit titles start with `DEV:`, `FIX:` or `FEATURE:`.

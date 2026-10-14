# Changelog

## Unreleased

### Changed

- `BipolarCache.read!` raises `ArgumentError` for missing, unknown or non-callable
  keywords. Before, a missing `actual:` surfaced as a `NoMethodError` that `rescue:` swallowed,
  and misspelled keywords were silently ignored.
- `BipolarCache.read!`: `if:` is optional (default: caching enabled) and every
  callable may be any object responding to `call`, not only a `Proc`.
- `BipolarCache.read!`: when only the cache write fails, the error goes to `rescue:` (or is
  re-raised without one) but the value that was read is still returned instead of the `rescue:` result.
- Sequel plugin: procs passed to `bipolar_count_cache` run in the scope of the model instance
  (`self` used to be the class), so they can call instance methods and associations directly.
- Sequel plugin: `if:`, `chance:` and `rescue:` accept a Symbol/String naming an instance method,
  like `actual:`, `cached:` and `update:` already did. `if: :method` used to be ignored,
  which left caching switched on.
- Sequel plugin: invalid options (wrong type, `chance` below 0, above 100 or `NaN`) raise
  `ArgumentError` when `bipolar_count_cache` is declared instead of on first use.
- Sequel plugin: for `Sequel::Model` instances the default cache write is a bare dataset `UPDATE`
  of the cache column. It no longer runs validations and hooks, saves other unsaved columns or
  inserts an unsaved record. `increment!`/`decrement!` use `coalesce(col, 0) + n` in SQL, so
  concurrent increments are not lost and a `NULL` column is handled. Your own `update:` is
  still called with the new value.
- Sequel plugin: the `bcsp_*` helper methods and `fetch_or_build_procs` are private.

### Fixed

- Sequel plugin: two `bipolar_count_cache` declarations with the same association name no longer
  share one set of procs.
- Sequel plugin: a `dup`/`clone` no longer reads and writes the original record's cache.
- Sequel plugin: reading a count on a frozen model no longer raises `FrozenError`.
- Sequel plugin: `refresh!` goes through `rescue:` like `increment!`/`decrement!`, and those two
  no longer replace the original error with a `NoMethodError`.

### Added

- Type signatures in `sig/bipolar_cache.rbs`.
- Tests against real `Sequel::Model` instances (Sequel's mock adapter); `sequel` is a development dependency.
- Ruby 4.0 in the CI matrix.

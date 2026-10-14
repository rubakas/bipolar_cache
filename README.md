# BipolarCache

Probabilistic caching toolkit for Ruby. Instead of always hitting the database or always returning a cached value, BipolarCache flips a coin — sometimes you get the cache, sometimes you get the real thing, and when the real thing differs, the cache gets updated.

Useful for caching database counters and other operations where occasional staleness is acceptable and you want to gradually reduce database load without explicit cache invalidation.

## How it works

```
BipolarCache.read!  →  should we cache?  (if)
                          │
                    no ────┘──── yes
                    │              │
               return actual    read cached value
                                   │
                              chance(cached) > rand?
                                   │
                             yes ──┘── no
                             │         │
                        return      compute actual
                        cached         │
                                  cached != actual?
                                       │
                                 yes ──┘── no
                                 │         │
                            update      return
                            cache       actual
                            return
                            actual
```

## Installation

Add to your Gemfile:

```ruby
gem "bipolar_cache"
```

Or install directly:

```
$ gem install bipolar_cache
```

## Usage

### Core API

`BipolarCache.read!` accepts six keyword arguments, all callables (procs, lambdas, or anything that responds to `call`):

```ruby
result = BipolarCache.read!(
  actual: -> { Post.where(user_id: user.id).count },  # the real value (expensive)
  cached: -> { user.posts_count_cache },               # the cached value (cheap)
  chance: ->(cached_value) { cached_value < 10 ? 0.1 : 0.9 },  # probability of cache hit
  if:     -> { user.caching_enabled? },                # enable/disable caching
  update: ->(value) { user.update(posts_count_cache: value) },  # write new value to cache
  rescue: ->(error) { Rails.logger.error(error); 0 }   # handle errors
)
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `actual`  | yes | Callable that returns the real value (e.g., a database query) |
| `cached`  | yes | Callable that returns the cached value |
| `chance`  | yes | Callable that receives the cached value and returns a float 0.0-1.0. Higher = more likely to use cache. |
| `if`      | no  | Callable that returns true/false. When false, always returns the actual value. Defaults to always enabled. |
| `update`  | yes | Callable that receives the actual value and persists it to the cache |
| `rescue`  | no  | Callable that receives a `StandardError`. Without it, errors re-raise. |

Missing, unknown (e.g. a misspelled `chnace:`) or non-callable arguments raise `ArgumentError`, even when `rescue` is given.

#### Errors

- An error while reading (`if`, `cached`, `chance` or `actual`) goes to `rescue`, and its return value becomes the result.
- An error while writing the cache (`update`) is also passed to `rescue`, but the result is still the actual value
  that was just read. A failed cache write never replaces a good answer.
- Without `rescue`, both kinds of error are re-raised.

### Sequel Plugin (alpha)

For [Sequel](https://github.com/jeremyevans/sequel) models, the plugin generates all the procs automatically. Your model needs a `_count_cache` column (e.g., `comments_count_cache`):

```ruby
require "bipolar_cache/sequel/plugin_alpha"

class User < Sequel::Model
  include BipolarCache::Sequel::PluginAlpha

  # Assumes:
  #   - association: user.comments_dataset
  #   - cache column: user.comments_count_cache
  bipolar_count_cache :comments
end
```

This generates four instance methods:

```ruby
user.comments_count            # probabilistic: returns cached or actual count
user.comments_count_refresh!   # force: computes actual and updates cache
user.comments_count_increment! # bump cache by 1 (or by: n), returns the new value
user.comments_count_decrement! # drop cache by 1 (or by: n), returns the new value
```

#### Options

```ruby
bipolar_count_cache :comments,
  method: "comment_total",           # custom method name (default: "{name}_count")
  chance: 75,                        # fixed probability as percentage (default: adaptive)
  actual: -> { comments_dataset.where(visible: true).count },  # custom actual proc
  cached: :my_cache_column,          # custom cache column/method name
  update: ->(v) { update(my_cache_column: v) },  # custom update proc
  rescue: ->(e) { log(e); nil },     # custom error handler
  if: -> { !new? }                   # disable caching for unsaved records
```

Procs run in the scope of the model instance, so they can call its methods and associations directly.
`actual`, `cached`, `update`, `if`, `chance` and `rescue` also accept a Symbol (or String) naming an
instance method, which receives the same arguments the proc would:

```ruby
bipolar_count_cache :comments, if: :caching_enabled?, chance: :hit_chance, rescue: :report_error
```

Options are checked when `bipolar_count_cache` is declared: a value of the wrong type, or a numeric `chance`
outside 0-100 (or `NaN`), raises `ArgumentError` at class-load time. A method name that the model doesn't
respond to raises `ArgumentError` the first time the cache is used.

#### How the cache is written

For a `Sequel::Model` the default write is a plain `UPDATE` of the cache column. It does not run validations or
hooks, does not save other unsaved changes on the record, and does nothing in the database for a record that
isn't saved yet (the new value only lives in memory). `increment!` and `decrement!` are done in SQL
(`cache = coalesce(cache, 0) + n`), so concurrent bumps don't overwrite each other and a `NULL` column counts as 0.

Passing your own `update:` replaces all of this: it is called with the new value, whatever it does.

By default errors are logged with `warn` and the method returns `0`; pass `rescue:` to change that.

#### Chance values

The `chance` option controls cache-hit probability:

| Value | Interpretation | Example |
|-------|---------------|---------|
| `0.0` - `1.0` (Float) | Direct probability | `chance: 0.9` = 90% cache hit |
| `1` (Integer) | Direct probability (1.0 = 100%) | `chance: 1` = always cache |
| `2` - `100` (Integer) | Percentage, divided by 100 | `chance: 75` = 75% cache hit |
| `0` | Never use cache | `chance: 0` = always compute actual |
| Proc | Dynamic, receives cached value | `chance: ->(v) { v > 100 ? 0.95 : 0.5 }` |
| _(omitted)_ | Adaptive default | < 10: 10% cache hit, >= 10: 90% cache hit |

## Development

```
bin/setup          # install dependencies
rake test          # run tests
rake rubocop       # lint
rake               # run both
bin/console        # interactive prompt
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rubakas/bipolar_cache.

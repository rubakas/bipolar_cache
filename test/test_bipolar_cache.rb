# frozen_string_literal: true

require "test_helper"

class TestBipolarCache < Minitest::Test
  def setup
    @value = 42
    @cache = 0

    @example_procs = {
      actual: -> { @value },
      cached: -> { @cache },
      chance: ->(_v) { 1 },
      if: -> { true },
      rescue: ->(e) { e },
      update: ->(v) { @cache = v }
    }

    @bipolar_cache = BipolarCache
  end

  def test_that_it_has_a_version_number
    refute_nil ::BipolarCache::VERSION
  end

  def test_it_hits_cache_when_chance_is_one
    actual_called = false
    procs = @example_procs.merge({
                                   chance: ->(_v) { 1 },
                                   actual: lambda {
                                     actual_called = true
                                     @value
                                   }
                                 })
    result = @bipolar_cache.read!(**procs)
    assert_equal 0, result
    refute actual_called, "actual should not be called on cache hit"
  end

  def test_it_misses_and_updates_cache_when_chance_is_zero
    procs = @example_procs.merge({ chance: ->(_v) { 0 } })
    result = @bipolar_cache.read!(**procs)
    assert_equal 42, result
    assert_equal 42, @cache
  end

  def test_it_misses_cache_when_if_is_false_does_not_update
    procs = @example_procs.merge({ chance: ->(_v) { 1 }, if: -> { false } })
    result = @bipolar_cache.read!(**procs)
    assert_equal 42, result
    assert_equal 0, @cache
  end

  def test_it_does_not_update_cache_when_chance_is_one
    procs = @example_procs.merge({ chance: ->(_v) { 1 } })
    result = @bipolar_cache.read!(**procs)
    assert_equal 0, result
    assert_equal 42, @value
    assert_equal 0, @cache
  end

  def test_it_raises_without_rescue_proc
    procs = {
      actual: -> { raise "boom" },
      cached: -> { 0 },
      chance: ->(_v) { 0 },
      if: -> { true },
      update: ->(_v) {}
    }
    assert_raises(RuntimeError) { @bipolar_cache.read!(**procs) }
  end

  def test_it_calls_rescue_proc_on_error
    error_caught = nil
    procs = {
      actual: -> { raise "boom" },
      cached: -> { 0 },
      chance: ->(_v) { 0 },
      if: -> { true },
      rescue: lambda { |e|
        error_caught = e
        -1
      },
      update: ->(_v) {}
    }
    result = @bipolar_cache.read!(**procs)
    assert_equal(-1, result)
    assert_equal "boom", error_caught.message
  end

  def test_it_does_not_update_cache_when_values_are_equal
    @cache = 42
    procs = @example_procs.merge({ chance: ->(_v) { 0 } })
    update_called = false
    procs[:update] = lambda { |v|
      update_called = true
      @cache = v
    }
    @bipolar_cache.read!(**procs)
    refute update_called
  end

  def test_if_proc_exception_routes_through_rescue
    error_caught = nil
    procs = @example_procs.merge(
      if: -> { raise "if failed" },
      rescue: lambda { |e|
        error_caught = e
        -1
      }
    )
    result = @bipolar_cache.read!(**procs)
    assert_equal(-1, result)
    assert_equal "if failed", error_caught.message
  end

  def test_if_proc_exception_raises_without_rescue
    procs = {
      actual: -> { @value },
      cached: -> { @cache },
      chance: ->(_v) { 1 },
      if: -> { raise "if failed" },
      update: ->(_v) {}
    }
    assert_raises(RuntimeError) { @bipolar_cache.read!(**procs) }
  end

  def test_missing_required_keyword_raises_argument_error_even_with_rescue
    procs = {
      cached: -> { @cache },
      chance: ->(_v) { 1 },
      if: -> { true },
      update: ->(_v) {},
      rescue: ->(_e) { :swallowed }
    }
    assert_raises(ArgumentError) { @bipolar_cache.read!(**procs) }
  end

  def test_if_defaults_to_true_when_omitted
    procs = {
      actual: -> { @value },
      cached: -> { @cache },
      chance: ->(_v) { 1 },
      update: ->(v) { @cache = v }
    }
    assert_equal 0, @bipolar_cache.read!(**procs)
  end

  def test_rescue_accepts_callable_object
    callable_rescue = Object.new
    def callable_rescue.call(error)
      "handled: #{error.message}"
    end

    procs = @example_procs.merge(
      chance: ->(_v) { 0 },
      actual: -> { raise "boom" },
      rescue: callable_rescue
    )
    assert_equal "handled: boom", @bipolar_cache.read!(**procs)
  end

  # Unknown keywords

  def test_unknown_keyword_raises_argument_error_even_with_rescue
    # a typo such as `chnace:` must not be silently ignored
    assert_raises(ArgumentError) do
      @bipolar_cache.read!(**@example_procs, chnace: ->(_v) { 0 })
    end
  end

  # Cache write failure after a successful actual read

  def test_failed_cache_update_still_returns_actual_value
    procs = @example_procs.merge(
      chance: ->(_v) { 0 },
      update: ->(_v) { raise "cache write failed" }
    )
    assert_equal 42, @bipolar_cache.read!(**procs)
  end

  # Boundary of the `chance > rand` comparison (rand pinned for determinism)

  def test_cache_hit_when_chance_is_above_rand
    with_rand(0.5) do
      procs = @example_procs.merge(chance: ->(_v) { 0.6 })
      assert_equal 0, @bipolar_cache.read!(**procs)
      assert_equal 0, @cache
    end
  end

  def test_cache_miss_when_chance_is_below_rand
    with_rand(0.5) do
      procs = @example_procs.merge(chance: ->(_v) { 0.4 })
      assert_equal 42, @bipolar_cache.read!(**procs)
      assert_equal 42, @cache
    end
  end

  def test_cache_miss_when_chance_equals_rand
    with_rand(0.5) do
      procs = @example_procs.merge(chance: ->(_v) { 0.5 })
      assert_equal 42, @bipolar_cache.read!(**procs)
    end
  end

  private

  def with_rand(value)
    @bipolar_cache.define_singleton_method(:rand) { value }
    yield
  ensure
    @bipolar_cache.singleton_class.remove_method(:rand)
  end
end

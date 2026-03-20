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
    procs = @example_procs.merge({ chance: ->(_v) { 1 } })
    assert_equal 0, @bipolar_cache.read!(**procs)
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
end

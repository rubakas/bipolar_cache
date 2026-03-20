# frozen_string_literal: true

require "test_helper"
require_relative "../lib/bipolar_cache/sequel/plugin_alpha"

class FakeModel
  include BipolarCache::Sequel::PluginAlpha

  attr_accessor :comments_count_cache

  def initialize(count_cache: nil)
    @comments_count_cache = count_cache
  end

  def comments_dataset
    self
  end

  def count
    42
  end

  def update(attrs)
    attrs.each { |k, v| send("#{k}=", v) }
  end

  bipolar_count_cache :comments
end

class AlwaysCacheModel
  include BipolarCache::Sequel::PluginAlpha

  attr_accessor :items_count_cache

  def initialize(count_cache: nil)
    @items_count_cache = count_cache
  end

  def items_dataset
    self
  end

  def count
    99
  end

  def update(attrs)
    attrs.each { |k, v| send("#{k}=", v) }
  end

  bipolar_count_cache :items, chance: 1
end

class NeverCacheModel
  include BipolarCache::Sequel::PluginAlpha

  attr_accessor :items_count_cache

  def initialize(count_cache: nil)
    @items_count_cache = count_cache
  end

  def items_dataset
    self
  end

  def count
    99
  end

  def update(attrs)
    attrs.each { |k, v| send("#{k}=", v) }
  end

  bipolar_count_cache :items, chance: 0
end

class TestSequelPluginAlpha < Minitest::Test
  def test_defines_count_method
    model = FakeModel.new(count_cache: 10)
    assert_respond_to model, :comments_count
  end

  def test_defines_refresh_method
    model = FakeModel.new(count_cache: 10)
    assert_respond_to model, :comments_count_refresh!
  end

  def test_defines_increment_method
    model = FakeModel.new(count_cache: 10)
    assert_respond_to model, :comments_count_increment!
  end

  def test_defines_decrement_method
    model = FakeModel.new(count_cache: 10)
    assert_respond_to model, :comments_count_decrement!
  end

  def test_refresh_updates_cache
    model = FakeModel.new(count_cache: 0)
    result = model.comments_count_refresh!
    assert_equal 42, result
    assert_equal 42, model.comments_count_cache
  end

  def test_refresh_skips_update_when_values_equal
    model = FakeModel.new(count_cache: 42)
    result = model.comments_count_refresh!
    assert_equal 42, result
    assert_equal 42, model.comments_count_cache
  end

  def test_increment_adds_to_cached_value
    model = FakeModel.new(count_cache: 10)
    model.comments_count_increment!
    assert_equal 11, model.comments_count_cache
  end

  def test_increment_by_custom_amount
    model = FakeModel.new(count_cache: 10)
    model.comments_count_increment!(by: 5)
    assert_equal 15, model.comments_count_cache
  end

  def test_decrement_subtracts_from_cached_value
    model = FakeModel.new(count_cache: 10)
    model.comments_count_decrement!
    assert_equal 9, model.comments_count_cache
  end

  def test_decrement_by_custom_amount
    model = FakeModel.new(count_cache: 10)
    model.comments_count_decrement!(by: 3)
    assert_equal 7, model.comments_count_cache
  end

  def test_increment_handles_nil_cached_value
    model = FakeModel.new(count_cache: nil)
    model.comments_count_increment!
    assert_equal 1, model.comments_count_cache
  end

  def test_decrement_handles_nil_cached_value
    model = FakeModel.new(count_cache: nil)
    model.comments_count_decrement!
    assert_equal(-1, model.comments_count_cache)
  end

  def test_chance_integer_division_normalizes_correctly
    model = FakeModel.new(count_cache: 10)
    chance_proc = model.send(:bcsp_proc_chance_from, chance: 50)
    assert_equal 0.5, chance_proc.call(10)
  end

  def test_chance_float_passes_through
    model = FakeModel.new(count_cache: 10)
    chance_proc = model.send(:bcsp_proc_chance_from, chance: 0.7)
    assert_equal 0.7, chance_proc.call(10)
  end

  def test_default_chance_for_small_count
    model = FakeModel.new(count_cache: 5)
    chance_proc = model.send(:bcsp_proc_chance_from, name: :comments)
    assert_equal 0.1, chance_proc.call(5)
  end

  def test_default_chance_for_large_count
    model = FakeModel.new(count_cache: 100)
    chance_proc = model.send(:bcsp_proc_chance_from, name: :comments)
    assert_equal 0.9, chance_proc.call(100)
  end

  def test_default_chance_handles_nil_value
    model = FakeModel.new(count_cache: nil)
    chance_proc = model.send(:bcsp_proc_chance_from, name: :comments)
    assert_equal 0.1, chance_proc.call(nil)
  end

  def test_update_with_symbol_passes_value
    model = FakeModel.new(count_cache: 0)
    update_proc = model.send(:bcsp_proc_update_from, name: :comments, update: :comments_count_cache=)
    update_proc.call(99)
    assert_equal 99, model.comments_count_cache
  end

  def test_if_with_false_disables_caching
    model = FakeModel.new(count_cache: 0)
    if_proc = model.send(:bcsp_proc_if_from, if: false)
    refute if_proc.call
  end

  def test_if_with_true_enables_caching
    model = FakeModel.new(count_cache: 0)
    if_proc = model.send(:bcsp_proc_if_from, if: true)
    assert if_proc.call
  end

  def test_default_rescue_returns_zero_and_warns
    model = FakeModel.new(count_cache: 0)
    rescue_proc = model.send(:bcsp_proc_rescue_from, name: :comments)
    assert_output(nil, /BipolarCache.*RuntimeError.*test/) do
      result = rescue_proc.call(RuntimeError.new("test"))
      assert_equal 0, result
    end
  end

  def test_custom_rescue_proc_is_used
    model = FakeModel.new(count_cache: 0)
    custom_rescue = ->(e) { "caught: #{e.message}" }
    rescue_proc = model.send(:bcsp_proc_rescue_from, rescue: custom_rescue)
    assert_equal "caught: boom", rescue_proc.call(RuntimeError.new("boom"))
  end

  def test_procs_are_cached_per_instance
    model = FakeModel.new(count_cache: 10)
    procs1 = model.send(:fetch_or_build_procs, name: :comments)
    procs2 = model.send(:fetch_or_build_procs, name: :comments)
    assert_same procs1, procs2
  end

  # Integration tests: full read path through BipolarCache.read!

  def test_count_returns_cached_value_when_chance_is_one
    model = AlwaysCacheModel.new(count_cache: 10)
    assert_equal 10, model.items_count
  end

  def test_count_returns_actual_and_updates_when_chance_is_zero
    model = NeverCacheModel.new(count_cache: 10)
    result = model.items_count
    assert_equal 99, result
    assert_equal 99, model.items_count_cache
  end

  def test_count_does_not_update_when_actual_equals_cached_and_chance_is_zero
    model = NeverCacheModel.new(count_cache: 99)
    result = model.items_count
    assert_equal 99, result
    assert_equal 99, model.items_count_cache
  end

  # Rescue wrapping on increment/decrement

  def test_increment_uses_rescue_on_error
    model = FakeModel.new(count_cache: 10)
    # Build procs, then sabotage the update proc to raise
    procs = model.send(:fetch_or_build_procs, name: :comments)
    procs[:update] = ->(_v) { raise "db error" }
    assert_output(nil, /BipolarCache.*db error/) do
      result = model.comments_count_increment!
      assert_equal 0, result
    end
  end

  def test_decrement_uses_rescue_on_error
    model = FakeModel.new(count_cache: 10)
    procs = model.send(:fetch_or_build_procs, name: :comments)
    procs[:update] = ->(_v) { raise "db error" }
    assert_output(nil, /BipolarCache.*db error/) do
      result = model.comments_count_decrement!
      assert_equal 0, result
    end
  end

  # Negative chance validation

  def test_negative_chance_raises_argument_error
    model = FakeModel.new(count_cache: 10)
    assert_raises(ArgumentError) do
      model.send(:bcsp_proc_chance_from, chance: -1)
    end
  end

  def test_negative_float_chance_raises_argument_error
    model = FakeModel.new(count_cache: 10)
    assert_raises(ArgumentError) do
      model.send(:bcsp_proc_chance_from, chance: -0.5)
    end
  end
end

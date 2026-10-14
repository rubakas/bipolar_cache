# frozen_string_literal: true

require "test_helper"
require_relative "../lib/bipolar_cache/sequel/plugin_alpha"

# Stands in for a Sequel model: the association dataset is the model itself,
# it counts to a fixed number, and #update assigns attributes.
class FakeCountModel
  include BipolarCache::Sequel::PluginAlpha

  class << self
    attr_reader :association

    def counts(association, count:)
      @association = association
      attr_accessor :"#{association}_count_cache"

      define_method(:"#{association}_dataset") { self }
      define_method(:count) { count }
    end
  end

  def initialize(count_cache: nil)
    send(:"#{self.class.association}_count_cache=", count_cache)
  end

  def update(attrs)
    attrs.each { |k, v| send("#{k}=", v) }
  end
end

class FakeModel < FakeCountModel
  counts :comments, count: 42

  bipolar_count_cache :comments
end

class AlwaysCacheModel < FakeCountModel
  counts :items, count: 99

  bipolar_count_cache :items, chance: 1
end

class NeverCacheModel < FakeCountModel
  counts :items, count: 99

  bipolar_count_cache :items, chance: 0
end

class BrokenUpdateModel < FakeCountModel
  counts :items, count: 99

  def update(_attrs)
    raise "db error"
  end

  bipolar_count_cache :items
end

class CustomProcsModel
  include BipolarCache::Sequel::PluginAlpha

  attr_accessor :comments_count_cache, :saved, :last_error

  def initialize(count_cache: nil, saved: true)
    @comments_count_cache = count_cache
    @saved = saved
    @last_error = nil
  end

  def visible_comments_count
    77
  end

  def custom_cached_value
    @comments_count_cache
  end

  def custom_write_cache(val)
    @comments_count_cache = val
  end

  def custom_hit_chance(_val)
    0
  end

  def handle_error(err)
    @last_error = err.message
    -1
  end

  def new?
    !@saved
  end

  bipolar_count_cache :comments,
                      actual: -> { visible_comments_count },
                      cached: -> { custom_cached_value },
                      update: ->(v) { custom_write_cache(v) },
                      chance: ->(v) { custom_hit_chance(v) },
                      rescue: ->(e) { handle_error(e) },
                      if: -> { !new? }
end

class MultiCacheSameNameModel < FakeCountModel
  counts :comments, count: 42

  bipolar_count_cache :comments, chance: 1
  bipolar_count_cache :comments, method: :live_comments_count, chance: 0
end

class SymbolOptionsModel < FakeCountModel
  counts :comments, count: 42

  attr_accessor :caching_enabled

  def initialize(count_cache: nil, caching_enabled: false)
    super(count_cache: count_cache)
    @caching_enabled = caching_enabled
  end

  def caching_enabled?
    @caching_enabled
  end

  def dynamic_chance(_val)
    1.0
  end

  def handle_error(err)
    "rescued: #{err.message}"
  end

  bipolar_count_cache :comments,
                      if: :caching_enabled?,
                      chance: :dynamic_chance,
                      rescue: :handle_error
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
    model = BrokenUpdateModel.new(count_cache: 10)
    assert_output(nil, /BipolarCache.*db error/) do
      result = model.items_count_increment!
      assert_equal 0, result
    end
  end

  def test_decrement_uses_rescue_on_error
    model = BrokenUpdateModel.new(count_cache: 10)
    assert_output(nil, /BipolarCache.*db error/) do
      result = model.items_count_decrement!
      assert_equal 0, result
    end
  end

  def test_frozen_procs_cannot_be_mutated
    model = FakeModel.new(count_cache: 10)
    procs = model.send(:fetch_or_build_procs, name: :comments)
    assert_raises(FrozenError) { procs[:update] = -> {} }
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

  def test_chance_over_100_raises_argument_error
    model = FakeModel.new(count_cache: 10)
    assert_raises(ArgumentError) do
      model.send(:bcsp_proc_chance_from, chance: 150)
    end
  end

  def test_chance_101_raises_argument_error
    model = FakeModel.new(count_cache: 10)
    assert_raises(ArgumentError) do
      model.send(:bcsp_proc_chance_from, chance: 101)
    end
  end

  def test_chance_100_is_valid
    model = FakeModel.new(count_cache: 10)
    chance_proc = model.send(:bcsp_proc_chance_from, chance: 100)
    assert_equal 1.0, chance_proc.call(10)
  end

  # Return value tests for increment/decrement

  def test_increment_returns_new_value
    model = FakeModel.new(count_cache: 10)
    result = model.comments_count_increment!
    assert_equal 11, result
  end

  def test_increment_by_amount_returns_new_value
    model = FakeModel.new(count_cache: 10)
    result = model.comments_count_increment!(by: 5)
    assert_equal 15, result
  end

  def test_decrement_returns_new_value
    model = FakeModel.new(count_cache: 10)
    result = model.comments_count_decrement!
    assert_equal 9, result
  end

  def test_decrement_by_amount_returns_new_value
    model = FakeModel.new(count_cache: 10)
    result = model.comments_count_decrement!(by: 3)
    assert_equal 7, result
  end

  # Instance scope, method-name options and option validation

  def test_custom_procs_execute_in_instance_scope
    model = CustomProcsModel.new(count_cache: 10, saved: true)
    assert_equal 77, model.comments_count
    assert_equal 77, model.comments_count_cache
  end

  def test_custom_if_proc_executes_in_instance_scope
    unsaved_model = CustomProcsModel.new(count_cache: 10, saved: false)
    assert_equal 77, unsaved_model.comments_count
    assert_equal 10, unsaved_model.comments_count_cache
  end

  def test_custom_rescue_proc_executes_in_instance_scope
    model = CustomProcsModel.new(count_cache: 10, saved: true)
    def model.visible_comments_count
      raise "query failed"
    end

    assert_equal(-1, model.comments_count)
    assert_equal "query failed", model.last_error
  end

  def test_dup_instance_does_not_read_or_update_original_instance
    model1 = NeverCacheModel.new(count_cache: 10)
    model1.items_count # initializes @bcsp_proc_store on model1

    model2 = model1.dup
    model2.items_count_cache = 20
    model2.items_count_increment!(by: 5)

    assert_equal 25, model2.items_count_cache
    assert_equal 99, model1.items_count_cache
  end

  def test_frozen_model_instance_can_read_cached_count
    model = AlwaysCacheModel.new(count_cache: 10).freeze
    assert_equal 10, model.items_count
  end

  def test_multiple_caches_for_same_name_with_different_methods_do_not_collide
    model = MultiCacheSameNameModel.new(count_cache: 10)
    assert_equal 10, model.comments_count
    assert_equal 42, model.live_comments_count
  end

  def test_if_with_symbol_calls_instance_method
    model = SymbolOptionsModel.new(count_cache: 10, caching_enabled: false)
    assert_equal 42, model.comments_count
    assert_equal 10, model.comments_count_cache
  end

  def test_chance_with_symbol_calls_instance_method
    model = SymbolOptionsModel.new(count_cache: 5, caching_enabled: true)
    chance_proc = model.send(:bcsp_proc_chance_from, name: :comments, chance: :dynamic_chance)
    assert_equal 1.0, chance_proc.call(5)
  end

  def test_rescue_with_symbol_calls_instance_method
    model = SymbolOptionsModel.new(count_cache: 10, caching_enabled: false)
    def model.count
      raise "db down"
    end

    assert_equal "rescued: db down", model.comments_count
  end

  def test_invalid_option_types_raise_argument_error
    model = FakeModel.new(count_cache: 10)
    assert_raises(ArgumentError) { model.send(:bcsp_proc_actual_from, name: :comments, actual: 123) }
    assert_raises(ArgumentError) { model.send(:bcsp_proc_cached_from, name: :comments, cached: 123) }
    assert_raises(ArgumentError) { model.send(:bcsp_proc_update_from, name: :comments, update: 123) }
    assert_raises(ArgumentError) { model.send(:bcsp_proc_if_from, name: :comments, if: 123) }
    assert_raises(ArgumentError) { model.send(:bcsp_proc_chance_from, name: :comments, chance: "50%") }
    assert_raises(ArgumentError) { model.send(:bcsp_proc_rescue_from, name: :comments, rescue: 123) }
  end

  def test_nan_chance_raises_argument_error
    model = FakeModel.new(count_cache: 10)
    assert_raises(ArgumentError) do
      model.send(:bcsp_proc_chance_from, chance: Float::NAN)
    end
  end

  def test_invalid_chance_raises_at_declaration_time
    assert_raises(ArgumentError) do
      Class.new do
        include BipolarCache::Sequel::PluginAlpha

        bipolar_count_cache :items, chance: -5
      end
    end
  end

  def test_refresh_uses_rescue_on_error
    model = BrokenUpdateModel.new(count_cache: 10)
    assert_output(nil, /BipolarCache.*db error/) do
      result = model.items_count_refresh!
      assert_equal 0, result
    end
  end

  def test_internal_helper_methods_are_private
    model = FakeModel.new(count_cache: 10)
    refute_respond_to model, :bcsp_cache
    refute_respond_to model, :fetch_or_build_procs
    refute_respond_to model, :bcsp_proc_actual_from
    refute_respond_to model, :bcsp_proc_cached_from
    refute_respond_to model, :bcsp_proc_update_from
    refute_respond_to model, :bcsp_proc_chance_from
    refute_respond_to model, :bcsp_proc_rescue_from
    refute_respond_to model, :bcsp_proc_if_from
  end

  # Failures while building procs must surface as themselves, not as a
  # NoMethodError from the increment/decrement rescue clause

  def test_increment_with_invalid_chance_reports_argument_error
    assert_raises(ArgumentError) do
      model = Class.new do
        include BipolarCache::Sequel::PluginAlpha

        bipolar_count_cache :items, chance: -5
      end.new
      model.items_count_increment!
    end
  end

  def test_decrement_with_invalid_chance_reports_argument_error
    assert_raises(ArgumentError) do
      model = Class.new do
        include BipolarCache::Sequel::PluginAlpha

        bipolar_count_cache :items, chance: -5
      end.new
      model.items_count_decrement!
    end
  end
end

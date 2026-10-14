# frozen_string_literal: true

require "test_helper"
require "sequel"
require_relative "../lib/bipolar_cache/sequel/plugin_alpha"

# Exercises the plugin on real Sequel::Model instances. The mock adapter
# records SQL instead of talking to a database.
module SequelIntegration
  DB = Sequel.mock(numrows: 1, columns: %i[id user_id name comments_count_cache])

  class Comment < Sequel::Model(DB[:comments]); end

  class MissUser < Sequel::Model(DB[:users])
    plugin :validation_helpers

    one_to_many :comments, class: "SequelIntegration::Comment", key: :user_id

    include BipolarCache::Sequel::PluginAlpha

    bipolar_count_cache :comments, chance: 0

    def validate
      super
      validates_presence :name
    end
  end

  class HitUser < Sequel::Model(DB[:users])
    one_to_many :comments, class: "SequelIntegration::Comment", key: :user_id

    include BipolarCache::Sequel::PluginAlpha

    bipolar_count_cache :comments, chance: 1
  end
end

class TestSequelIntegration < Minitest::Test
  DB = SequelIntegration::DB

  def setup
    DB.fetch = { count: 7 }
    DB.sqls # discard SQL recorded by earlier tests
  end

  def test_miss_counts_through_association_and_persists_cache
    user = SequelIntegration::MissUser.load(id: 1, name: "Ann", comments_count_cache: 3)

    assert_equal 7, user.comments_count

    sqls = DB.sqls
    assert(sqls.any? { |s| s.include?("count(*)") && s.include?("user_id") }, "expected a count query: #{sqls}")
    assert_includes sqls, "UPDATE users SET comments_count_cache = 7 WHERE (id = 1)"
  end

  def test_hit_returns_cached_value_without_touching_the_database
    user = SequelIntegration::HitUser.load(id: 1, comments_count_cache: 3)

    assert_equal 3, user.comments_count
    assert_empty DB.sqls
  end

  # The default update path goes through Model#update, i.e. the full save
  # pipeline: validations, hooks, and every other dirty column.

  def test_increment_persists_despite_unrelated_validation_failure
    user = SequelIntegration::MissUser.load(id: 1, name: nil, comments_count_cache: 10)

    result = nil
    capture_io { result = user.comments_count_increment! }

    assert_equal 11, result
    updates = DB.sqls.grep(/\AUPDATE/)
    assert(updates.any? { |s| s.start_with?("UPDATE users SET comments_count_cache") }, "no cache UPDATE: #{updates}")
  end

  def test_reading_a_count_does_not_persist_unrelated_unsaved_changes
    user = SequelIntegration::MissUser.load(id: 1, name: "Ann", comments_count_cache: 3)
    user.name = "Changed"

    user.comments_count

    updates = DB.sqls.grep(/\AUPDATE/)
    refute(updates.any? { |s| s.include?("name") }, "cache write persisted another column: #{updates}")
  end

  # Read-modify-write loses concurrent increments; an SQL expression does not.
  # coalesce keeps a NULL cache column from swallowing the increment.
  def test_increment_is_issued_as_an_atomic_null_safe_sql_expression
    user = SequelIntegration::MissUser.load(id: 1, name: "Ann", comments_count_cache: 10)

    user.comments_count_increment!

    assert_includes DB.sqls,
                    "UPDATE users SET comments_count_cache = (coalesce(comments_count_cache, 0) + 1) WHERE (id = 1)"
  end

  def test_increment_keeps_the_in_memory_value_in_step
    user = SequelIntegration::MissUser.load(id: 1, name: "Ann", comments_count_cache: nil)

    assert_equal 1, user.comments_count_increment!
    assert_equal 1, user.comments_count_cache
    refute_includes user.changed_columns, :comments_count_cache
  end
end

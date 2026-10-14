# frozen_string_literal: true

require "test_helper"
require "sequel"
require_relative "../lib/bipolar_cache/sequel/plugin_alpha"

# These regressions need persisted values, not just recorded SQL.
module SequelSqliteIntegration
  DB = Sequel.sqlite

  DB.create_table(:users) do
    primary_key :id
    String :name
    Integer :comments_count_cache
  end

  DB.create_table(:comments) do
    primary_key :id
    Integer :user_id
  end

  class Comment < Sequel::Model(DB[:comments]); end

  class User < Sequel::Model(DB[:users])
    one_to_many :comments, class: "SequelSqliteIntegration::Comment", key: :user_id

    include BipolarCache::Sequel::PluginAlpha

    bipolar_count_cache :comments
  end
end

class TestSequelSqliteIntegration < Minitest::Test
  DB = SequelSqliteIntegration::DB
  User = SequelSqliteIntegration::User

  def setup
    DB[:comments].delete
    DB[:users].delete
  end

  def test_saving_unrelated_changes_after_refresh_preserves_a_newer_increment
    user = User.create(name: "Ann", comments_count_cache: 0)
    DB[:comments].insert(user_id: user.id)
    user.comments_count_cache = 99
    user.name = "Updated"

    assert_equal 1, user.comments_count_refresh!
    assert_equal "Ann", User[user.id].name

    DB[:comments].insert(user_id: user.id)
    assert_equal 2, User[user.id].comments_count_increment!
    user.save_changes

    persisted = User[user.id]
    assert_equal 2, persisted.comments_count_cache,
                 "saving an unrelated change must not overwrite the newer increment"
    assert_equal "Updated", persisted.name
  end

  def test_default_chance_counts_and_populates_a_missing_cache
    user = User.create(name: "Ann")
    DB[:comments].insert(user_id: user.id)

    # This draw would select the cache under the default 10% hit chance.
    with_rand(0.05) do
      assert_equal 1, user.comments_count
    end

    assert_equal 1, User[user.id].comments_count_cache
  end

  def test_reading_a_count_preserves_model_marshalling
    user = User.create(name: "Ann", comments_count_cache: 1)
    DB[:comments].insert(user_id: user.id)
    assert_equal user.values, Marshal.load(Marshal.dump(user.marshallable!)).values

    with_rand(0.05) do
      assert_equal 1, user.comments_count
    end

    restored = Marshal.load(Marshal.dump(user.marshallable!))
    assert_equal user.values, restored.values
    with_rand(0.05) do
      assert_equal 1, restored.comments_count
    end
  end

  private

  def with_rand(value)
    BipolarCache.define_singleton_method(:rand) { value }
    yield
  ensure
    BipolarCache.singleton_class.remove_method(:rand)
  end
end

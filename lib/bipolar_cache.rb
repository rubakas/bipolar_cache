# frozen_string_literal: true

require_relative "bipolar_cache/version"

module BipolarCache
  class Error < StandardError; end

  ##
  # It may read actual value,
  # it may read cached value,
  # or it may write actual value into cache!
  # It depends on chance.
  # Call it at your peril.
  #
  # @param actual [Proc] callable to perform an operation (cacheable)
  # @param cached [Proc] callable to read cached value
  # @param chance [Proc(Object)] callable to compute chance of cache hit
  # @param if     [Proc] callable to enable/disable caching
  # @param rescue [Proc(StandardError)] callable to be invoked on exception
  # @param update [Proc(Object)] callable to update cached value
  # @return [Object]
  def self.read!(**procs)
    return procs[:actual].call unless procs[:if].call

    cached_value = procs[:cached].call

    if procs[:chance].call(cached_value) > rand
      cached_value
    else
      actual_value = procs[:actual].call
      procs[:update].call(actual_value) if cached_value != actual_value

      actual_value
    end
  rescue StandardError => e
    raise unless procs[:rescue].is_a?(Proc)

    procs[:rescue].call(e)
  end
end

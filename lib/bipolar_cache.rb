# frozen_string_literal: true

require_relative "bipolar_cache/version"

module BipolarCache
  class Error < StandardError; end

  REQUIRED_KEYS = %i[actual cached chance update].freeze
  OPTIONAL_KEYS = %i[if rescue].freeze
  ALWAYS = -> { true }
  private_constant :REQUIRED_KEYS, :OPTIONAL_KEYS, :ALWAYS

  ##
  # It may read actual value,
  # it may read cached value,
  # or it may write actual value into cache!
  # It depends on chance.
  # Call it at your peril.
  #
  # Errors raised while reading are passed to +rescue+ (re-raised without it).
  # An error raised while writing the cache is reported to +rescue+ the same
  # way, but the value that was read is still returned.
  #
  # @param actual [#call] callable to perform an operation (cacheable)
  # @param cached [#call] callable to read cached value
  # @param chance [#call(Object)] callable to compute chance of cache hit
  # @param if     [#call] callable to enable/disable caching (default: enabled)
  # @param rescue [#call(StandardError)] callable to be invoked on exception
  # @param update [#call(Object)] callable to update cached value
  # @return [Object]
  # @raise [ArgumentError] on missing, unknown or non-callable arguments
  def self.read!(**procs)
    procs = normalize!(procs)
    rescuer = procs[:rescue]

    begin
      return procs[:actual].call unless procs[:if].call

      cached_value = procs[:cached].call
      return cached_value if procs[:chance].call(cached_value) > rand

      actual_value = procs[:actual].call
    rescue StandardError => e
      raise unless rescuer

      return rescuer.call(e)
    end

    begin
      procs[:update].call(actual_value) if cached_value != actual_value
    rescue StandardError => e
      raise unless rescuer

      rescuer.call(e)
    end

    actual_value
  end

  def self.normalize!(procs)
    procs = procs.compact

    unknown = procs.keys - REQUIRED_KEYS - OPTIONAL_KEYS
    raise ArgumentError, "unknown keywords: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

    missing = REQUIRED_KEYS - procs.keys
    raise ArgumentError, "missing keywords: #{missing.map(&:inspect).join(", ")}" unless missing.empty?

    procs.each do |key, callable|
      raise ArgumentError, "#{key} must respond to #call, got #{callable.inspect}" unless callable.respond_to?(:call)
    end

    { if: ALWAYS }.merge(procs)
  end
  private_class_method :normalize!
end

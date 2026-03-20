# frozen_string_literal: true

require_relative "../../bipolar_cache"

module BipolarCache
  module Sequel
    module PluginAlpha
      module ClassMethods
        def bipolar_count_cache(name, **opts)
          opts = opts.merge({ name: name })
          method_name = opts[:method] || "#{name}_count"

          define_method method_name do
            bcsp_cache(**fetch_or_build_procs(**opts))
          end

          define_method "#{method_name}_refresh!" do
            procs = fetch_or_build_procs(**opts)
            actual_value = procs[:actual].call
            procs[:update].call(actual_value) if actual_value != procs[:cached].call
            actual_value
          end

          define_method "#{method_name}_increment!" do |by: 1|
            procs = fetch_or_build_procs(**opts)
            new_value = by + (procs[:cached].call || 0)
            procs[:update].call(new_value)
            new_value
          rescue StandardError => e
            raise unless procs[:rescue].is_a?(Proc)

            procs[:rescue].call(e)
          end

          define_method "#{method_name}_decrement!" do |by: 1|
            procs = fetch_or_build_procs(**opts)
            new_value = (-by) + (procs[:cached].call || 0)
            procs[:update].call(new_value)
            new_value
          rescue StandardError => e
            raise unless procs[:rescue].is_a?(Proc)

            procs[:rescue].call(e)
          end
        end
      end

      def self.included(base)
        base.extend ClassMethods
      end

      def bcsp_cache(**procs)
        BipolarCache.read!(**procs)
      end

      def fetch_or_build_procs(**opts)
        # create cached store for instance procs, if none
        instance_variable_set(:@bcsp_proc_store, {}) unless instance_variable_defined?(:@bcsp_proc_store)

        if instance_variable_get(:@bcsp_proc_store)[opts[:name]].nil?
          instance_variable_get(:@bcsp_proc_store)[opts[:name]] =
            {
              actual: bcsp_proc_actual_from(**opts),
              cached: bcsp_proc_cached_from(**opts),
              update: bcsp_proc_update_from(**opts),
              chance: bcsp_proc_chance_from(**opts),
              rescue: bcsp_proc_rescue_from(**opts),
              if: bcsp_proc_if_from(**opts)
            }
        end

        # stored procs
        instance_variable_get(:@bcsp_proc_store)[opts[:name]]
      end

      def bcsp_proc_actual_from(**opts)
        case opts[:actual]
        when Proc
          opts[:actual]
        when String, Symbol
          -> { send(opts[:actual]) }
        else
          -> { send("#{opts[:name]}_dataset").count }
        end
      end

      def bcsp_proc_cached_from(**opts)
        case opts[:cached]
        when Proc
          opts[:cached]
        when String, Symbol
          -> { send(opts[:cached]) }
        else
          -> { send("#{opts[:name]}_count_cache") }
        end
      end

      def bcsp_proc_update_from(**opts)
        cache_name = if opts[:cached].is_a?(String) || opts[:cached].is_a?(Symbol)
                       opts[:cached]
                     else
                       "#{opts[:name]}_count_cache"
                     end

        case opts[:update]
        when Proc
          opts[:update]
        when String, Symbol
          ->(value) { send(opts[:update], value) }
        else
          ->(value) { update({ cache_name => value }) }
        end
      end

      def bcsp_proc_chance_from(**opts)
        case opts[:chance]
        when Proc
          opts[:chance]
        when Integer, Float
          raise ArgumentError, "chance must be >= 0, got #{opts[:chance]}" if opts[:chance].negative?

          normalised_chance = if opts[:chance] > 1
                                opts[:chance] / 100.0
                              else
                                opts[:chance]
                              end
          ->(_value) { normalised_chance }
        else # default
          ->(value) { (value || 0) < 10 ? 0.1 : 0.9 }
        end
      end

      def bcsp_proc_rescue_from(**opts)
        if opts[:rescue].is_a? Proc
          opts[:rescue]
        else # default
          lambda { |e|
            warn "[BipolarCache] #{e.class}: #{e.message}"
            0
          }
        end
      end

      def bcsp_proc_if_from(**opts)
        case opts[:if]
        when Proc
          opts[:if]
        when TrueClass, FalseClass
          value = opts[:if]
          -> { value }
        else # default
          -> { true }
        end
      end
    end
  end
end

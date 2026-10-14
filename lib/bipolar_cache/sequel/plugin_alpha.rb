# frozen_string_literal: true

require_relative "../../bipolar_cache"

module BipolarCache
  # NOTE: inside this namespace a bare +Sequel+ is BipolarCache::Sequel;
  # reach the gem with +::Sequel+.
  module Sequel
    module PluginAlpha
      module ClassMethods
        def bipolar_count_cache(name, **opts)
          Options.validate!(opts)
          opts = opts.merge({ name: name })
          method_name = opts[:method] || "#{name}_count"

          define_method method_name do
            bcsp_cache(**bcsp_build_procs(**opts))
          end

          define_method "#{method_name}_refresh!" do
            procs = bcsp_build_procs(**opts)

            bcsp_guarded(procs) do
              actual_value = procs[:actual].call
              procs[:update].call(actual_value) if actual_value != procs[:cached].call
              actual_value
            end
          end

          define_method "#{method_name}_increment!" do |by: 1|
            bcsp_adjust_cache!(opts, by)
          end

          define_method "#{method_name}_decrement!" do |by: 1|
            bcsp_adjust_cache!(opts, -by)
          end
        end
      end

      module Options
        class << self
          # Checks everything about the options that can be checked without an
          # instance, so a bad declaration fails when the class is loaded.
          def validate!(opts)
            %i[actual cached update if rescue chance].each { |key| validate_option!(key, opts[key]) }
          end

          # Turns a numeric chance into a probability: 0..1 is taken as is,
          # anything above 1 is a percentage.
          def chance_probability(chance)
            raise ArgumentError, "chance must be a number, got NaN" if chance.is_a?(Float) && chance.nan?
            raise ArgumentError, "chance must be >= 0, got #{chance}" if chance.negative?
            raise ArgumentError, "chance must be <= 100, got #{chance}" if chance > 100

            chance > 1 ? chance / 100.0 : chance
          end

          private

          def validate_option!(key, value)
            return if value.nil? || value.is_a?(Proc) || value.is_a?(Symbol) || value.is_a?(String)
            return if key == :if && [true, false].include?(value)
            return chance_probability(value) if key == :chance && (value.is_a?(Integer) || value.is_a?(Float))

            raise ArgumentError, "#{key} has an unsupported value: #{value.inspect}"
          end
        end
      end

      # Turns the declaration options into the callables BipolarCache.read!
      # expects, all bound to the instance they are built on.
      module Builders
        private

        def bcsp_build_procs(**opts)
          {
            actual: bcsp_proc_actual_from(**opts),
            cached: bcsp_proc_cached_from(**opts),
            update: bcsp_proc_update_from(**opts),
            chance: bcsp_proc_chance_from(**opts),
            rescue: bcsp_proc_rescue_from(**opts),
            if: bcsp_proc_if_from(**opts)
          }.freeze
        end

        # Procs run in the scope of the instance; Symbols and Strings name a
        # method of the instance that receives the call arguments.
        def bcsp_bind(key, option)
          case option
          when Proc
            ->(*args) { instance_exec(*args, &option) }
          when Symbol, String
            unless respond_to?(option, true)
              raise ArgumentError, "#{key}: #{option.inspect} is not a method of #{self.class} " \
                                   "(expected a Proc or the name of an instance method)"
            end

            ->(*args) { send(option, *args) }
          else
            raise ArgumentError, "#{key} must be a Proc, Symbol or String, got #{option.inspect}"
          end
        end

        def bcsp_proc_actual_from(**opts)
          return bcsp_bind(:actual, opts[:actual]) unless opts[:actual].nil?

          -> { send("#{opts[:name]}_dataset").count }
        end

        def bcsp_proc_cached_from(**opts)
          return bcsp_bind(:cached, opts[:cached]) unless opts[:cached].nil?

          -> { send("#{opts[:name]}_count_cache") }
        end

        def bcsp_proc_update_from(**opts)
          return bcsp_bind(:update, opts[:update]) unless opts[:update].nil?

          column = bcsp_cache_column(opts)
          ->(value) { bcsp_write_cache(column, value) }
        end

        def bcsp_proc_chance_from(**opts)
          case opts[:chance]
          when nil # default
            lambda { |value|
              next 0 if value.nil? # a missing cache is never a hit: it would hand back nil

              value < 10 ? 0.1 : 0.9
            }
          when Integer, Float
            probability = Options.chance_probability(opts[:chance])
            ->(_value) { probability }
          else
            bcsp_bind(:chance, opts[:chance])
          end
        end

        def bcsp_proc_rescue_from(**opts)
          return bcsp_bind(:rescue, opts[:rescue]) unless opts[:rescue].nil?

          lambda { |e|
            warn "[BipolarCache] #{e.class}: #{e.message}"
            0
          }
        end

        def bcsp_proc_if_from(**opts)
          case opts[:if]
          when nil # default
            -> { true }
          when true, false
            value = opts[:if]
            -> { value }
          else
            bcsp_bind(:if, opts[:if])
          end
        end

        def bcsp_cache_column(opts)
          case opts[:cached]
          when String, Symbol then opts[:cached].to_sym
          else :"#{opts[:name]}_count_cache"
          end
        end
      end

      include Builders

      def self.included(base)
        base.extend ClassMethods
      end

      private

      def bcsp_cache(**procs)
        BipolarCache.read!(**procs)
      end

      def bcsp_guarded(procs)
        yield
      rescue StandardError => e
        procs[:rescue].call(e)
      end

      def bcsp_adjust_cache!(opts, delta)
        procs = bcsp_build_procs(**opts)

        bcsp_guarded(procs) do
          new_value = (procs[:cached].call || 0) + delta

          if opts[:update].nil? && bcsp_sequel_model?
            column = bcsp_cache_column(opts)
            relative = ::Sequel.function(:coalesce, ::Sequel[column], 0) + delta
            bcsp_write_cache(column, new_value, relative)
          else
            procs[:update].call(new_value)
          end

          new_value
        end
      end

      def bcsp_sequel_model?
        defined?(::Sequel::Model) && is_a?(::Sequel::Model)
      end

      # Default cache writer. A Sequel model gets a bare UPDATE of the cache
      # column: no validations, hooks or other unsaved columns are involved,
      # and +expression+ lets the database do the arithmetic. Anything else
      # is asked to #update itself.
      def bcsp_write_cache(column, value, expression = value)
        return update({ column => value }) unless bcsp_sequel_model?

        this.update(column => expression) unless new?
        return if frozen?

        values[column] = value
        # the value is now in the database; a later save must not write it again
        changed_columns.delete(column)
      end
    end
  end
end

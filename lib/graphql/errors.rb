# frozen_string_literal: true

require "graphql"
require "graphql/errors/version"

module GraphQL
  class Errors
    EmptyConfigurationError = Class.new(StandardError)
    EmptyRescueError = Class.new(StandardError)
    NotRescuableError = Class.new(StandardError)

    def self.configure(schema, &block)
      raise EmptyConfigurationError unless block

      instance = new(&block)
      schema.instrument(:field, instance)
    end

    def initialize(&block)
      @handler_by_class = {}
      self.instance_eval(&block)
    end

    def instrument(_type, field)
      old_resolve_proc = field.resolve_proc
      old_lazy_resolve_proc = field.lazy_resolve_proc
      errors = self
      field.redefine do
        resolve(ErrorWrapper.new(old_resolve_proc, errors))
        lazy_resolve(ErrorWrapper.new(old_lazy_resolve_proc, errors))
      end
    end

    def rescue_from(*classes, &block)
      raise EmptyRescueError unless block

      classes.each do |klass|
        raise NotRescuableError.new(klass.inspect) unless klass.is_a?(Class)
        @handler_by_class[klass] ||= block
      end
    end

    class ErrorWrapper
      def initialize(old_proc, errors)
        @old_proc = old_proc
        @errors = errors
      end

      def call(obj, args, ctx)
        @old_proc.call(obj, args, ctx)
      rescue => exception
        if handler = @errors.find_handler(exception)
          handler.call(exception, obj, args, ctx)
        else
          raise exception
        end
      end
    end


    def find_handler(exception)
      @handler_by_class.each do |klass, handler|
        return handler if exception.is_a?(klass)
      end

      nil
    end
  end
end

module Reform::Form::Validation
  # DSL object wrapping the ValidationSet.
  # Translates the "Reform" DSL to the target validator gem's language.
  # TODO: rename so everything is in Reform::Lotus ns

  # A Group is a set of native validations, targeting a validation backend (AM, Lotus, Veto).
  # The #call method will run those validations on the provided objects.
  module Lotus
    class Group
      def initialize
        @validations = ::Lotus::Validations::ValidationSet.new
      end

      def validates(*args)
        @validations.add(*args)
      end

      def call(fields, errors, form) # FIXME.
        private_errors = Reform::Form::Lotus::Errors.new # FIXME: damn, Lotus::Validator.validate does errors.clear.

        validator = ::Lotus::Validations::Validator.new(@validations, fields, private_errors)
        validator.validate

        # TODO: merge with AM.
        private_errors.each do |name, error| # TODO: handle with proper merge, or something. validator.errors is ALWAYS AM::Errors.
          errors.add(name, *error)
        end
      end
    end

    def validation_group_class
      Group
    end
  end

  module ActiveModel
    class Group
      def initialize
        @validations = Class.new(Reform::Form::ActiveModel::Validations::Validator)
      end

      def validates(*args)
        @validations.validates(*args)
      end

      def call(fields, errors, form) # FIXME.
        validator = @validations.new(form, form.model_name)
        validator.valid?

        validator.errors.each do |name, error| # TODO: handle with proper merge, or something. validator.errors is ALWAYS AM::Errors.
          errors.add(name, error)
        end
      end
    end

    def validation_group_class
      Group
    end
  end


  # Set of Validation::Group objects.
  # This implements adding, iterating, and finding groups, including "inheritance" and insertions.
  class Groups < Array
    def initialize(group_class)
      @group_class = group_class
    end

    def add(name, options)
      if options[:inherit]
        return self[name] if self[name]
      end

      i = index_for(options)

      self.insert(i, [name, group = @group_class.new, options]) # Group.new
      group
    end

  private

    def index_for(options)
      return find_index { |el| el.first == options[:after] } + 1 if options[:after]
      size # default index: append.
    end

    def [](name)
      cfg = find { |cfg| cfg.first == name }
      return unless cfg
      cfg[1]
    end


    # Runs all validations groups according to their rules and returns result.
    # Populates errors passed into #call.
    class Result # DISCUSS: could be in Groups.
      def initialize(groups)
        @groups = groups
      end

      def call(fields, errors, form)
        result = true
        results = {}

        @groups.each do |cfg|
          name, group, options = cfg
          depends_on = options[:if]

          if evaluate_if(depends_on, results, form)
            results[name] = group.(fields, errors, form).empty? # validate.
          end

          result &= errors.empty?
        end

        result
      end

      def evaluate_if(depends_on, results, form)
        return true if depends_on.nil?
        return results[depends_on] if depends_on.is_a?(Symbol)
        form.instance_exec(results, &depends_on)
      end
    end
  end

  module ClassMethods
    def validation_groups
      @groups ||= Groups.new(validation_group_class) # TODO: inheritable_attr with Inheritable::Hash
    end

    # DSL.
    def validation(name, options={}, &block)
      group = validation_groups.add(name, options)

      group.instance_exec(&block)
    end

    def validates(name, options)
      validation(:default, inherit: true) { validates name, options }
    end

    def validate(name, *args, &block)
      validation(:default, inherit: true) { validate name, *args, &block }
    end
  end

  def self.included(includer)
    includer.extend(ClassMethods)
  end

  def valid?
    Groups::Result.new(self.class.validation_groups).(@fields, errors, self)
  end
end
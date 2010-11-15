# Wrap method calls for a class of your choosing.
# Example:
# instrument = Minstrel::Instrument.new()
# instrument.wrap(String) do |point, klass, method, *args|
#   ...
# end
#
#  * point is either :enter or :exit depending if this function is about to be
#    called or has finished being called.
#  * klass is the class object (String, etc)
#  * method is the method (a Symbol)
#  * *args is the arguments passed
#
# You can also wrap from the command-line
#
# RUBY_INSTRUMENT=comma_separated_classnames ruby -rminstrel ./your/program.rb
#
module Minstrel; class Instrument
  attr_accessor :counter

  class << self
    @@deferred_wraps = {}
  end

  # Put methods we must not be wrapping here.
  #DONOTWRAP = #[Kernel, Object, Module, Class,
  DONOTWRAP = [Minstrel::Instrument].collect do |obj|
    obj.methods.collect { |m| m.to_sym }
  end.flatten
  DONOTWRAP << :to_sym
  DONOTWRAP << :respond_to?
  DONOTWRAP << :send

  # Wrap a class's instance methods with your block.
  # The block will be called with 4 arguments, and called
  # before and after the original method.
  # Arguments:
  #   * point - the point (symbol, :entry or :exit) of call
  #   * klass - the class (object) owning this method
  #   * method - the method (symbol) being called
  #   * *args - the arguments (array) passed to this method.
  def wrap(klass, &block)
    #puts "Instrumenting #{klass.name} with #{block.inspect}"
    instrumenter = self

    klass.instance_methods.each do |method|
      next if DONOTWRAP.include?(method.to_sym)
      klass.class_eval do
        orig_method = "#{method}_original(wrapped)".to_sym
        alias_method orig_method, method.to_sym
        method = method.to_sym
        #block.call(:wrap, klass, method)
        define_method(method) do |*args, &argblock|
          block.call(:enter, klass, method, *args)
          exception = false
          begin
            m = self.method(orig_method)
            val = m.call(*args, &argblock)
          rescue => e
            exception = e
          end
          if exception
            block.call(:exit_exception, klass, method, *args)
            raise e if exception
          else
            block.call(:exit, klass, method, *args)
          end
          return val
        end
      end # klass.class_eval
    end # klass.instance_methods.each

    klass.methods.each do |method|
      next if DONOTWRAP.include?(method.to_sym)
      klass.instance_eval do
        orig_method = "#{method}_original(classwrapped)".to_sym
        (class << self; self; end).instance_eval do
          begin
            alias_method orig_method, method.to_sym
          rescue NameError => e
            # No such method, strange but true.
            orig_method = self.method(method.to_sym)
          end
          method = method.to_sym
          define_method(method) do |*args, &argblock|
            block.call(:class_enter, klass, method, *args)
            exception = false
            begin
              if orig_method.is_a?(Symbol)
                val = send(orig_method, *args, &argblock)
              else
                val = orig_method.call(*args, &argblock)
              end
            rescue => e
              exception = e
            end
            if exception
              block.call(:class_exit_exception, klass, method, *args)
              raise e if exception
            else
              block.call(:class_exit, klass, method, *args)
            end
            return val
          end
        end
        #block.call(:class_wrap, klass, method, self.method(method))
      end # klass.class_eval
    end # klass.instance_methods.each
  end # def wrap

  def wrap_classname(klassname, &block)
    begin
      klass = eval(klassname)
      self.wrap(klass, &block) 
      return true
    rescue NameError => e
      @@deferred_wraps[klassname] = block
    end
    return false
  end

  def self.wrap_require
    Kernel.class_eval do
      alias_method :old_require, :require
      def require(*args)
        return Minstrel::Instrument::instrumented_require(*args)
      end
    end
  end

  def self.instrumented_require(*args)
    ret = old_require(*args)
    klasses = @@deferred_wraps.keys
    klasses.each do |klassname|
      block = @@deferred_wraps[klassname]
      instrument = Minstrel::Instrument.new
      if instrument.wrap_classname(klassname, &block)
        puts "Wrap of #{klassname} successful"
        @@deferred_wraps.delete(klassname)
      end
    end
    return ret
  end
end; end # class Minstrel::Instrument

Minstrel::Instrument.wrap_require

# Provide a way to instrument a class using the command line:
# RUBY_INSTRUMENT=String ruby -rminstrel ./your/program
if ENV["RUBY_INSTRUMENT"]
  ENV["RUBY_INSTRUMENT"].split(",").each do |klassname|
    instrument = Minstrel::Instrument.new 
    instrument.wrap_classname(klassname) do |point, klass, method, *args|
      puts "#{point} #{klass.name}##{method}(#{args.inspect})"
    end
  end
end

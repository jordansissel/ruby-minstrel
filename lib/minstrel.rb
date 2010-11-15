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

  # Put methods we must not be wrapping here.
  DONOTWRAP = [Kernel, Object, Module, Class, Minstrel::Instrument].collect do |obj|
    obj.methods.collect { |m| m.to_sym }
  end.flatten
  DONOTWRAP << :to_sym

  # Wrap a class's instance methods with your block.
  # The block will be called with 4 arguments, and called
  # before and after the original method.
  # Arguments:
  #   * point - the point (symbol, :entry or :exit) of call
  #   * klass - the class (object) owning this method
  #   * method - the method (symbol) being called
  #   * *args - the arguments (array) passed to this method.
  def wrap(klass, &block)
    instrumenter = self
    self.counter = 0

    klass.instance_methods.each do |method|
      next if DONOTWRAP.include?(method.to_sym)
      klass.class_eval do
        orig_method = "#{method}_original(wrapped)".to_sym
        alias_method orig_method, method.to_sym
        instrumenter.counter += 1
        method = method.to_sym
        define_method(method) do |*args, &argblock|
          block.call(:enter, klass, method, *args)
          val = send(orig_method, *args, &argblock)
          block.call(:exit, klass, method, *args)
          return val
        end
      end # klass.class_eval
    end # klass.instance_methods.each
  end # def wrap
end; end # class Minstrel::Instrument

# Provide a way to instrument a class using the command line:
# RUBY_INSTRUMENT=String ruby -rminstrel ./your/program
if ENV["RUBY_INSTRUMENT"]
  ENV["RUBY_INSTRUMENT"].split(",").each do |klassname|
    instrument = Minstrel::Instrument.new 
    klass = eval(klassname)
    instrument.wrap(klass) do |point, klass, method, *args|
      next if point == :end
      puts "#{point} #{klass.name}##{method}(#{args.inspect})"
    end
  end
end

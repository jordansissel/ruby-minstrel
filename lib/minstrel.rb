
module Minstrel; class Instrument
  attr_accessor :counter

  # Put methods we must not be wrapping here.
  DONOTWRAP = [Kernel, Object, Module, Class, Minstrel::Instrument].collect do |obj|
    obj.methods.collect { |m| m.to_sym }
  end.flatten
  DONOTWRAP << :to_sym

  def wrap(klass, &block)
    instrumenter = self
    self.counter = 0

    klass.instance_methods.each do |method|
      next if DONOTWRAP.include?(method.to_sym)
      klass.class_eval do
        orig_method = "#{method}_wrap_#{@counter}".to_sym
        alias_method orig_method, method.to_sym
        instrumenter.counter += 1
        method = method.to_sym
        define_method(method) do |*args|
          block.call(:start, klass, method, *args)
          val = send(orig_method, *args)
          block.call(:end, klass, method, *args)
          return val
        end
      end # klass.class_eval
    end # klass.instance_methods.each
  end # def wrap
end; end # class Minstrel::Instrument

# Provide a way to instrument a class using the command line:
# RUBY_INSTRUMENT=String ruby -rminstrel ./your/program
ENV["RUBY_INSTRUMENT"].split(",").each do |klassname|
  instrument = Minstrel::Instrument.new 
  klass = eval(klassname)
  instrument.wrap(klass) do |point, klass, method, *args|
    next if point == :end
    puts "#{klass.name}##{method}(#{args.length} args...)"
  end
end

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

require "set"

module Minstrel; class Instrument
  attr_accessor :counter

  class << self
    @@deferred_wraps = {}
    @@deferred_method_wraps = {}
    @@wrapped = Set.new
  end

  # Put methods we must not be wrapping here.
  DONOTWRAP = {
    "Minstrel::Instrument" => Minstrel::Instrument.instance_methods.collect { |m| m.to_sym },
    "Object" => [ :to_sym, :respond_to?, :send, :java_send, :method, :java_method,
                  :ancestors, :inspect, :to_s, :instance_eval, :instance_exec,
                  :class_eval, :class_exec, :module_eval, :module_exec],
  }

  # Wrap a class's instance methods with your block.
  # The block will be called with 4 arguments, and called
  # before and after the original method.
  # Arguments:
  #   * point - the point (symbol, :entry or :exit) of call,
  #   * this - the object instance in scope (use 'this.class' for the class)
  #   * method - the method (symbol) being called
  #   * *args - the arguments (array) passed to this method.
  def wrap(klass, method_to_wrap=nil, &block)
    return true if @@wrapped.include?(klass)
    instrumenter = self # save 'self' for scoping below
    @@wrapped << klass

    ancestors = klass.ancestors.collect {|k| k.to_s } 
    if ancestors.include?("Exception")
      return true
    end
    puts "Wrapping #{klass.class} #{klass}" if $DEBUG

    # Wrap class instance methods (like File#read)
    klass.instance_methods.each do |method|
      next if !method_to_wrap.nil? and method != method_to_wrap

      method = method.to_sym

      # If we shouldn't wrap a certain class method, skip it.
      skip = false
      (ancestors & DONOTWRAP.keys).each do |key|
        if DONOTWRAP[key].include?(method)
          skip = true 
          break
        end
      end
      if skip
        #puts "Skipping #{klass}##{method} (do not wrap)"
        next
      end

      klass.class_eval do
        orig_method = "#{method}_original(wrapped)".to_sym
        orig_method_proc = klass.instance_method(method)
        alias_method orig_method, method
        #block.call(:wrap, klass, method)
        puts "Wrapping #{klass.name}##{method} (method)" if $DEBUG
        define_method(method) do |*args, &argblock|
          exception = false
          puts "#{method}, #{self}"
          block.call(:enter, self, method, *args)
          begin
            # TODO(sissel): Not sure which is better:
            # * UnboundMethod#bind(self).call(...)
            # * self.method(orig_method).call(...)
            val = orig_method_proc.bind(self).call(*args, &argblock)
            #m = self.method(orig_method)
            #val = m.call(*args, &argblock)
          rescue => e
            exception = e
          end
          if exception
            # TODO(sissel): Include the exception
            block.call(:exit_exception, self, method, *args)
            raise e if exception
          else
            # TODO(sissel): Include the return value
            block.call(:exit, self, method, *args)
          end
          return val
        end # define_method(method)
      end # klass.class_eval
    end # klass.instance_methods.each

    # Wrap class methods (like File.open)
    klass.methods.each do |method|
      next if !method_to_wrap.nil? and method != method_to_wrap
      method = method.to_sym
      # If we shouldn't wrap a certain class method, skip it.
      skip = false
      ancestors = klass.ancestors.collect {|k| k.to_s} 
      (ancestors & DONOTWRAP.keys).each do |key|
        if DONOTWRAP[key].include?(method)
          skip = true 
          #break
        end
      end

      # Doubly-ensure certain methods are not wrapped.
      # Some classes like "Timeout" do not have ancestors.
      if DONOTWRAP["Object"].include?(method)
        #puts "!! Skipping #{klass}##{method} (do not wrap)"
        skip = true
      end

      if skip
        puts "Skipping #{klass}##{method} (do not wrap, not safe)" if $DEBUG
        next
      end

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
          #puts "Wrapping #{klass.name}.#{method} (classmethod)"
          define_method(method) do |*args, &argblock|
            block.call(:class_enter, self, method, *args)
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
              block.call(:class_exit_exception, self, method, *args)
              raise e if exception
            else
              block.call(:class_exit, self, method, *args)
            end
            return val
          end
        end
        #block.call(:class_wrap, self, method, self.method(method))
      end # klass.instance_eval
    end # klass.instance_methods.each

    return true
  end # def wrap

  def wrap_classname(klassname, &block)
    begin
      klass = eval(klassname)
      wrap(klass, &block) 
      return true
    rescue NameError => e
      @@deferred_wraps[klassname] = block
    end
    return false
  end

  def wrap_method(fullname, &block)
    puts "Want to wrap #{fullname}" if $DEBUG
    begin
      klassname, method = fullname.split(/[#.]/, 2)
      klass = eval(klassname)
      wrap(klass, method, &block)
      return true
    rescue NameError => e
      @@deferred_method_wraps[fullname] = block
      return false
    end
  end # def wrap_method

  def wrap_all(&block)
    @@deferred_wraps[:all] = block
    ObjectSpace.each_object do |obj|
      next unless obj.is_a?(Class)
      wrap(obj, &block)
    end
  end

  def self.wrap_require
    Kernel.class_eval do
      alias_method :old_require, :require
      def require(*args)
        return Minstrel::Instrument::instrumented_loader(:require, *args)
      end
    end
  end

  def self.wrap_load
    Kernel.class_eval do
      alias_method :old_load, :load
      def load(*args)
        return Minstrel::Instrument::instrumented_loader(:load, *args)
      end
    end
  end

  def self.instrumented_loader(method, *args)
    ret = self.send(:"old_#{method}", *args)
    if @@deferred_wraps.include?(:all)
      # try to wrap anything new that is not wrapped
      wrap_all(@@deferred_wraps[:all])
    else
      # look for deferred class wraps
      klasses = @@deferred_wraps.keys
      klasses.each do |klassname|
        if @@deferred_wraps.include?("ALL")
          all = true
        end
        block = @@deferred_wraps[klassname]
        instrument = Minstrel::Instrument.new
        if instrument.wrap_classname(klassname, &block)
          $stderr.puts "Wrap of #{klassname} successful"
          @@deferred_wraps.delete(klassname) if !all
        end
      end

      klassmethods = @@deferred_method_wraps.keys
      klassmethods.each do |fullname|
        block = @@deferred_method_wraps[fullname]
        instrument = Minstrel::Instrument.new
        if instrument.wrap_method(fullname, &block)
          $stderr.puts "Wrap of #{fullname} successful"
          @@deferred_method_wraps.delete(fullname)
        end
      end
    end
    return ret
  end
end; end # class Minstrel::Instrument

Minstrel::Instrument.wrap_require
Minstrel::Instrument.wrap_load

# Provide a way to instrument a class using the command line:
# RUBY_INSTRUMENT=String ruby -rminstrel ./your/program
if ENV["RUBY_INSTRUMENT"]
  klasses = ENV["RUBY_INSTRUMENT"].split(",")

  callback = proc do |point, this, method, *args|
    puts "#{point} #{this.class.to_s}##{method}(#{args.inspect}) (thread=#{Thread.current}, self=#{this.inspect})"
  end
  instrument = Minstrel::Instrument.new 
  if klasses.include?(":all:")
    instrument.wrap_all(&callback)
  else
    klasses.each do |klassname|
      if klassname =~ /[#.]/ # Someone's asking for a specific method to wrap
        # This will wrap one method as indicated by: ClassName#method
        # TODO(sissel): Maybe also allow ModuleName::method
        instrument.wrap_method(klassname, &callback) 
      else
        instrument.wrap_classname(klassname, &callback) 
      end
    end # klasses.each
  end 
end # if ENV["RUBY_INSTRUMENT"]

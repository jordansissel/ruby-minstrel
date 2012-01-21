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

TraceEvent = Struct.new(:action, :file, :line, :method, :binding, :class, :args)

module Minstrel; class Instrument
  attr_accessor :counter

  public
  def self.singleton
    @minstrel ||= Minstrel::Instrument.new
  end # def self.singleton

  public
  def initialize
    @observe = []
  end # def initialize

  public
  def observe(thing=nil, &block)
    if !thing.nil?
      p :observe => thing
      # Is thing a class name?
      @observe << lambda do |event| 
        if class?(thing)
          if event.class.to_s == thing
            block.call(event) 
          end
        else
          # assume it's a method?
          klass, method = thing.split(/[.#]/, 2)
          if (event.class.to_s == klass and event.method = method.to_sym)
            block.call(event)
          end
        end
      end
    elsif block_given?
      @observe << block
    else
      raise ArgumentError.new("No block given.")
    end
  end # def observe

  # Is the name here a class?
  private
  def class?(name)
    begin
      return false if name.include?("#")
      obj = eval(name)
      return obj.is_a?(Class)
    rescue => e
      false
    end
  end # def class?

  # Activate tracing
  public
  def enable
    set_trace_func(Proc.new { |*args| trace_callback(*args) })
  end # def enable

  # Disable tracing
  public
  def disable
    set_trace_func(nil)
  end # def disable

  # This method is invoked by the ruby tracer
  private
  def trace_callback(action, file, line, method, binding, klass)
    return unless action == "c-call"
    event = TraceEvent.new(action, file, line, method, binding, klass)
    # At the time of "c-call" there's no other local variables other than
    # the method arguments. Pull the args out of binding
    #eval('args = local_variables.collect { |v| "(#{v}) #{v.inspect}" }', binding)
    eval('p :local => local_variables', binding)
    #event.args = args

    @observe.each { |callback| callback.call(event) }
  end # def trace_callback
end; end # class Minstrel::Instrument

# Provide a way to instrument a class using the command line:
# RUBY_INSTRUMENT=String ruby -rminstrel ./your/program
if ENV["RUBY_INSTRUMENT"]
  klasses = ENV["RUBY_INSTRUMENT"].split(",")

  callback = proc do |event|
    puts "#{event.action} #{event.class.to_s}##{event.method}(#{event.args.inspect}) (thread=#{Thread.current})"
  end

  instrument = Minstrel::Instrument.new 
  if klasses.include?(":all:")
    instrument.observe(&callback)
  else
    klasses.each do |klassname|
      instrument.observe(klassname, &callback)
    end # klasses.each
  end 
  instrument.enable
end # if ENV["RUBY_INSTRUMENT"]

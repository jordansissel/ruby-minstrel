# Wrap method calls for a class of your choosing.
# Example:
#
#     instrument = Minstrel::Instrument.new()
#     instrument.observe(class_or_method) { |event| ... }
#
# The 'event' is a Minstrel::Event.
#
# You can also wrap from the command-line
#     RUBY_INSTRUMENT=comma_separated_classnames ruby -rminstrel ./your/program.rb
#

module Minstrel; end

class Minstrel::Event
  attr_accessor :action
  attr_accessor :file
  attr_accessor :line
  attr_accessor :method
  attr_accessor :binding
  attr_accessor :class
  attr_accessor :args_hash
  attr_accessor :args_order
  attr_accessor :timestamp

  # Duration is only valid for 'return' or 'c-return' events
  attr_accessor :duration

  # The call stack depth of this event
  attr_accessor :depth

  public
  def initialize(action, file, line, method, binding, klass)
    @action = action
    @file = file
    @line = line
    @method = method
    @binding = binding
    @class = klass
    @timestamp = Time.now

    if ["c-call", "call"].include?(@action)
      @args_hash = {}
      @args_order = eval('local_variables', binding)

      # In ruby 1.9, local_variables returns an array of symbols, not strings.
      @args_order.collect { |v| @args_hash[v] = eval(v.to_s, binding) }
    end

    @block_given = eval('block_given?', @binding)
  end # def initialize

  # Get the call args as an array in-order
  public
  def args
    return nil unless @args_order
    return @args_order.collect { |v| @args_hash[v] }
  end # def args

  public
  def use_related_event(event)
    @args_order = event.args_order
    @args_hash = event.args_hash
    @block_given = event.block_given?
    @duration = @timestamp - event.timestamp
  end # def use_related_event

  # Is this event a method entry?
  public
  def entry?
    return ["c-call", "call"].include?(action)
  end # def entry?

  # Is this event a method return?
  public
  def exit?
    return ["c-return", "return"].include?(action)
  end # def exit?

  # Was there a block given to this method?
  public
  def block_given?
    @block_given
  end # def block_given ?

  public
  def symbol
    case @action
      when "c-call", "call" ; return "=>"
      when "c-return", "return" ; return "<="
      when "raise"; return "<E"
      else return " +"
    end
  end # def symbol

  public
  def to_s
    return "#{"  " * @depth}#{symbol} #{@class.to_s}##{@method}(#{args.inspect}) #{block_given? ? "{ ... }" : ""} (thread=#{Thread.current}) #{@duration.nil? ? "" : sprintf("(%.5f seconds)", @duration)}"
  end # def to_s

end # class Minstrel::Event

class Minstrel::Instrument
  attr_accessor :counter

  public
  def self.singleton
    @minstrel ||= Minstrel::Instrument.new
  end # def self.singleton

  public
  def initialize
    @observe = []
    @stack = Hash.new { |h,k| h[k] = [] } # per thread
  end # def initialize

  public
  def stack
    return @stack
  end

  public
  def observe(thing=nil, &block)
    if !thing.nil?
      # Is thing a class name?
      @observe << lambda do |event| 
        if class?(thing)
          if event.class.to_s == thing.to_s
            block.call(event) 
          end
        else
          # assume it's a method?
          #p :observe => nil, :class => thing, :is => class?(thing)
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

  # Is the thing here a class?
  # Can be a string name of a class or a class object
  private
  def class?(thing)
    #p :method => "class?", :thing => thing, :class => thing.is_a?(Class), :foo => thing.inspect
    begin
      return true if thing.is_a?(Class)
      return false if (thing.is_a?(String) and thing.include?("#"))
      obj = eval(thing)
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
    begin
      event = Minstrel::Event.new(action, file, line, method, binding, klass)
      # At the time of "c-call" there's no other local variables other than
      # the method arguments. Pull the args out of binding
      #event.args = eval('local_variables.collect { |v| "(#{v}) #{v.inspect}" }', binding)
      if ["c-call", "call"].include?(action)
        @stack[Thread.current].push event
        event.depth = @stack[Thread.current].size
      elsif ["c-return", "return", "raise"].include?(action)
        # TODO(sissel): validate top of stack looks right?
        event.depth = @stack[Thread.current].size
        entry_event = @stack[Thread.current].pop
        if !entry_event.nil?
          event.use_related_event(entry_event)
        end
      else
        event.depth = @stack[Thread.current].size
      end

      # Call any observers
      @observe.each { |callback| callback.call(event) }
    rescue => e
      $stderr.puts "Exception in trace_callback: #{e}"
      $stderr.puts e.backtrace
      raise e
    end
  end # def trace_callback
end # class Minstrel::Instrument

# Provide a way to instrument a class using the command line:
# RUBY_INSTRUMENT=String ruby -rminstrel ./your/program
if ENV["RUBY_INSTRUMENT"]
  klasses = ENV["RUBY_INSTRUMENT"].split(",")

  callback = proc do |event|
    # Only show entry or exits
    next unless (event.entry? or event.exit?)
    puts event
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

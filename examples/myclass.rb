require "minstrel"
require "net/http"

instrument = Minstrel::Instrument.new 

callback = proc do |event|
  # Only show entry or exits
  next unless (event.entry? or event.exit?)
  puts event
end

class MyClass
  def foo(a,b,c, &block)
    # Do nothing
  end
end

instrument.observe(MyClass, &callback)
instrument.enable

a = MyClass.new
a.foo(1,2,3)
a.foo(1,2,3) { 123 }


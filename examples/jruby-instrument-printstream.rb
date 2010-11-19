require "rubygems"
require "java"
require "minstrel"

m = Minstrel::Instrument.new

# Wrap java.io.PrintStream
m.wrap(java.io.PrintStream) do |point, klass, method, *args|
  puts "#{point} #{klass.name || klassname}##{method}(#{args.inspect})"
end

# Try it.
java.lang.System.out.println("Testing")

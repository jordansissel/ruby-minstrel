require "minstrel"
require "net/http"

instrument = Minstrel::Instrument.new 

callback = proc do |event|
  # Only show entry or exits
  next unless (event.entry? or event.exit?)
  puts event
end

#instrument.observe(Net::HTTP, &callback)
instrument.observe(&callback)
instrument.enable

result = Net::HTTP.get("google.com", "/")

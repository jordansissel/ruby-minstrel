Gem::Specification.new do |spec|
  files = [
    "./lib",
    "./lib/minstrel.rb",
    "./README.textile",
    "./minstrel.gemspec",
  ]

  rev = Time.now.strftime("%Y%m%d%H%M%S")
  spec.name = "minstrel"
  spec.version = "0.1.#{rev}"
  spec.summary = "minstrel - a ruby instrumentation tool"
  spec.description = "Instrument class methods"
  spec.files = files
  spec.require_paths << "lib"

  spec.author = "Jordan Sissel"
  spec.email = "jls@semicomplete.com"
  spec.homepage = "https://github.com/jordansissel/ruby-minstrel"
end


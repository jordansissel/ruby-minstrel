Gem::Specification.new do |spec|
  files = [
    "./lib",
    "./lib/minstrel.rb",
    "./README.textile",
    "./minstrel.gemspec",
  ]

  spec.name = "minstrel"
  spec.version = "0.3.0"
  spec.summary = "minstrel - a ruby instrumentation tool"
  spec.description = "Instrument class methods"
  spec.files = files
  spec.require_paths << "lib"
  spec.bindir = "bin"
  spec.executables << "minstrel"

  spec.author = "Jordan Sissel"
  spec.email = "jls@semicomplete.com"
  spec.homepage = "https://github.com/jordansissel/ruby-minstrel"
end


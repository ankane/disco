require_relative "lib/disco/version"

Gem::Specification.new do |spec|
  spec.name          = "disco"
  spec.version       = Disco::VERSION
  spec.summary       = "Collaborative filtering for Ruby"
  spec.homepage      = "https://github.com/ankane/disco"
  spec.license       = "MIT"

  spec.author        = "Andrew Kane"
  spec.email         = "andrew@chartkick.com"

  spec.files         = Dir["*.{md,txt}", "{app,lib}/**/*"]
  spec.require_path  = "lib"

  spec.required_ruby_version = ">= 2.4"

  spec.add_dependency "libmf", ">= 0.1.3"
  spec.add_dependency "numo-narray"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", ">= 5"
  spec.add_development_dependency "activerecord"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "daru"
end

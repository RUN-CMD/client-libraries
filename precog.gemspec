# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "precog"
  s.version = "0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Kris Nuttycombe"]
  s.date = "2012-05-31"
  s.description = "Precog.io Ruby Client Library\n"
  s.email = ["kris [at] precog [dot] io"]
  s.files = ["Rakefile", "README.rdoc", "lib/precog.rb", "test/test_precog.rb"]
  s.homepage = "http://precog.io/ruby"
  s.require_paths = ["lib"]
  s.rubyforge_project = "precog"
  s.rubygems_version = "1.8.24"
  s.summary = "Ruby client library for Precog.io (http://precog.io)"

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<json>, [">= 0"])
    else
      s.add_dependency(%q<json>, [">= 0"])
    end
  else
    s.add_dependency(%q<json>, [">= 0"])
  end
end

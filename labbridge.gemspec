# frozen_string_literal: true

require_relative "lib/labbridge"

Gem::Specification.new do |spec|
  spec.name = "labbridge"
  spec.version = LabBridge::VERSION
  spec.authors = ["Hartwell Labs"]
  spec.email = ["bartosz.osiej2007@gmail.com"]
  spec.summary = "Rust <=> Ruby bridge for Hartwell Labs programs (talus / externum / Aurora)"
  spec.description = "Translates a defined subset of Hartwell Labs Rust into runnable Ruby " \
                     "and Ruby plugins back into Rust (LabPlugin trait). Translation targets " \
                     "are verified against the Hartwell Labs Products Registry."
  spec.homepage = "https://github.com/Hartwell-Labs/labbridge"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "bin/*", "examples/*", "LICENSE", "README.md"]
  spec.bindir = "bin"
  spec.executables = ["labbridge"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }
end

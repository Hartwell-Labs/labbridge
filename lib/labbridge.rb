# frozen_string_literal: true

require "digest"
require "json"

module LabBridge
  VERSION = "1.0.0"
  VENDOR = "Hartwell Labs"
  MANIFEST_MAGIC = "HARTWELL-LAB-PLUGIN"

  # Targets allowed by the Hartwell Labs plugin policy.
  TARGETS = %w[talus aurora externum].freeze

  class Error < StandardError; end
  class ManifestError < Error; end
end

require_relative "labbridge/rust2ruby"
require_relative "labbridge/ruby2rust"
require_relative "labbridge/manifest"
require_relative "labbridge/registry"

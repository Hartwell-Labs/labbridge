# frozen_string_literal: true

module LabBridge
  # Plugin manifest: a Hartwell Labs plugin is any Ruby file whose header
  # contains a magic line
  #
  #   # hartwell-lab-plugin: name=<name> target=<target> version=<semver>
  #
  # The manifest pins the plugin to exactly one supported lab target
  # (talus / aurora / externum) and is embedded into the generated Rust
  # registration constants.
  class Manifest
    ATTR_RE = /\A\s*#\s*hartwell-lab-plugin:\s*(.+)\z/.freeze
    KV_RE = /(\w+)=([^\s]+)/.freeze

    attr_reader :name, :target, :version

    def self.from_ruby(source)
      new(source)
    end

    def initialize(source)
      line = source.each_line(chomp: true).find { |l| l.match?(ATTR_RE) }
      raise ManifestError, "missing '# hartwell-lab-plugin: ...' manifest header" unless line

      kv = line.match(ATTR_RE)[1].scan(KV_RE).to_h
      @name = kv["name"]
      @target = kv["target"]
      @version = kv["version"] || "0.1.0"

      raise ManifestError, "manifest missing name=" unless @name
      raise ManifestError, "manifest missing target=" unless @target
      unless TARGETS.include?(@target)
        raise ManifestError,
              "unknown target '#{@target}' (allowed: #{TARGETS.join(', ')})"
      end
      unless /\A[a-zA-Z_][a-zA-Z0-9_-]*\z/.match?(@name)
        raise ManifestError, "invalid plugin name '#{@name}'"
      end
    end

    def to_h
      { name: @name, target: @target, version: @version, vendor: VENDOR, magic: MANIFEST_MAGIC }
    end

    def to_json(*_args)
      to_h.to_json
    end
  end
end

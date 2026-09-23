# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/labbridge"

class Rust2RubyTest < Minitest::Test
  def setup
    @t = LabBridge::Rust2Ruby.new
  end

  def test_fn_and_puts
    out = @t.translate(<<~RS)
      fn main() {
          println!("hello");
      }
    RS
    assert_includes out, "def main()"
    assert_includes out, 'puts "hello"'
  end

  def test_let_and_methods
    out = @t.translate(<<~RS)
      let v: Vec<u32> = Vec::new();
      v.push(3);
      let n = v.len() as u64;
    RS
    assert_includes out, "v = []"
    assert_includes out, "v.push(3)"
    assert_includes out, "n = v.length.to_i"
  end

  def test_struct_and_impl
    out = @t.translate(<<~RS)
      pub struct Counter {
          total: i64,
      }

      impl Counter {
          pub fn bump(&mut self) {
              self.total += 1;
          }
      }
    RS
    assert_includes out, "class Counter"
    assert_includes out, "def bump()"
    assert_includes out, "self.total += 1"
  end

  def test_for_loop_and_format
    out = @t.translate(<<~RS)
      for i in 0..10 {
          println!("i={}", i);
      }
    RS
    assert_includes out, "(0..10).each do |i|"
    assert_includes out, 'puts "i=#{i}"'
  end

  def test_match_to_case
    out = @t.translate(<<~RS)
      match code {
          1 => println!("one"),
          _ => println!("other"),
      }
    RS
    assert_includes out, "case code"
    assert_includes out, "when 1"
    assert_includes out, "else"
  end

  def test_unsupported_construct_becomes_todo
    out = @t.translate("let x = unsafe { 1 };")
    assert_includes out, "TODO(labbridge)"
  end
end

class Ruby2RustTest < Minitest::Test
  def setup
    @g = LabBridge::Ruby2Rust.new
  end

  def test_generates_struct_and_trait_impl
    out = @g.translate(File.read(File.expand_path("../examples/event_counter.rb", __dir__)))
    assert_includes out, "pub struct EventCounter;"
    assert_includes out, "impl LabPlugin for EventCounter {"
    assert_includes out, 'const NAME: &\'static str = "event-counter"'
    assert_includes out, 'const TARGET: &\'static str = "talus"'
    assert_includes out, 'println!("{}", event);'
  end

  def test_manifest_missing_header_raises
    assert_raises(LabBridge::ManifestError) do
      LabBridge::Manifest.from_ruby("class Foo\nend\n")
    end
  end

  def test_manifest_unknown_target_raises
    src = "# hartwell-lab-plugin: name=x target=nuclear-plant\n"
    assert_raises(LabBridge::ManifestError) { LabBridge::Manifest.from_ruby(src) }
  end
end

class RoundtripTest < Minitest::Test
  def test_ruby_plugin_survives_ruby_to_rust_to_ruby
    src = File.read(File.expand_path("../examples/event_counter.rb", __dir__))
    rust = LabBridge::Ruby2Rust.new.translate(src)
    back = LabBridge::Rust2Ruby.new.translate(rust)
    assert_includes back, "def handle_event"
    assert_includes back, "puts event"
    refute_includes back, "println!" # no raw Rust macros left in Ruby output
  end
end

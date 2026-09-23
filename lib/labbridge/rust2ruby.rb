# frozen_string_literal: true

module LabBridge
  # Rust -> Ruby translator for the Hartwell Labs toolchain subset.
  #
  # Line-oriented, deterministic translator. Maps Rust control flow,
  # functions, structs, enums, impls, traits (as modules), vectors/HashMaps
  # and the println!/eprintln!/format!/vec! macros onto idiomatic Ruby.
  # Constructs outside the supported subset are emitted as TODO comments
  # (never silently dropped), so generated plugins are always auditable.
  #
  # Lab rule: when a target is given, it must verify against
  # LabBridge::Registry (Hartwell Labs products only) before translating.
  class Rust2Ruby
    TYPE_MAP = {
      "i8" => "Integer", "i16" => "Integer", "i32" => "Integer", "i64" => "Integer",
      "i128" => "Integer", "isize" => "Integer",
      "u8" => "Integer", "u16" => "Integer", "u32" => "Integer", "u64" => "Integer",
      "u128" => "Integer", "usize" => "Integer",
      "f32" => "Float", "f64" => "Float",
      "bool" => "Boolean", "char" => "String", "String" => "String", "str" => "String"
    }.freeze

    CAST_MAP = {
      "i8" => "to_i", "i16" => "to_i", "i32" => "to_i", "i64" => "to_i", "isize" => "to_i",
      "u8" => "to_i", "u16" => "to_i", "u32" => "to_i", "u64" => "to_i", "usize" => "to_i",
      "f32" => "to_f", "f64" => "to_f"
    }.freeze

    ATTRS = /\A\s*#\s*\[\s*\w+.*?\]\s*$/.freeze
    FN_RE = /\A(\s*)(?:pub\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+([a-zA-Z_]\w*)\s*(?:<[^>]*>)?\s*\((.*)\)\s*(?:->\s*(.+?))?\s*\{\s*\z/.freeze
    FN_INLINE_RE = /\A\s*(?:pub\s+)?fn\s+([a-zA-Z_]\w*)\s*\((.*?)\)\s*(?:->\s*([\w<>&\s:]+?))?\s*\{\s*(.*)\}\s*;\s*\z/.freeze
    STRUCT_UNIT_RE = /\A\s*(?:pub\s+)?struct\s+([A-Z]\w*)\s*;\s*\z/.freeze
    STRUCT_RE = /\A\s*(?:pub\s+)?struct\s+([A-Z]\w*)(?:<[^>]*>)?\s*\{\s*\z/.freeze
    ENUM_RE = /\A\s*(?:pub\s+)?enum\s+([A-Z]\w*)(?:<[^>]*>)?\s*\{\s*\z/.freeze
    IMPL_RE = /\A\s*impl(?:<[^>]*>)?\s+(?:([A-Z]\w*)\s+for\s+)?([A-Z]\w*)(?:<[^>]*>)?\s*\{\s*\z/.freeze
    TRAIT_RE = /\A\s*(?:pub\s+)?trait\s+([A-Z]\w*)(?:<[^>]*>)?\s*(?::\s*[^{]+)?\{\s*\z/.freeze
    MOD_RE = /\A\s*(?:pub\s+)?mod\s+(\w+)[^;]*\{\s*\z/.freeze
    FIELD_RE = /\A\s*(?:pub\s+)?([a-z_]\w*)\s*:\s*([A-Za-z0-9_<>\[\]:,&\s]+?)\s*,?\s*\z/.freeze
    LET_RE = /\A\s*(?:pub\s+)?let\s+(?:mut\s+)?([a-z_]\w*)\s*(?::\s*[^=]+?)?\s*=\s*(.+?);\s*\z/.freeze
    IF_RE = /\A(\s*)\}\s*else\s+if\s+(.+?)\s*\{\s*\z/.freeze
    ELSE_RE = /\A(\s*)\}\s*else\s*\{\s*\z/.freeze
    IF_OPEN_RE = /\A(\s*)if\s+(.+?)\s*\{\s*\z/.freeze
    WHILE_RE = /\A(\s*)while\s+(.+?)\s*\{\s*\z/.freeze
    FOR_RE = /\A(\s*)for\s+([a-zA-Z_]\w*)\s+in\s+(.+?)\s*\{\s*\z/.freeze
    LOOP_RE = /\A(\s*)loop\s*\{\s*\z/.freeze
    MATCH_RE = /\A(\s*)match\s+(.+?)\s*\{\s*\z/.freeze
    ARM_RE = /\A(\s*)(.+?)\s*=>\s*(.+?)\s*\z/.freeze
    RET_RE = /\A(\s*)return\b\s*(.*?);\s*\z/.freeze
    BRACE_ONLY_RE = /\A\s*\};?\s*\z/.freeze
    STMT_RE = /\A\s*(.+?);\s*\z/m.freeze
    USE_RE = /\A\s*use\s+/.freeze
    UNSAFE_RE = /\bunsafe\b/.freeze

    # literal fragments used to build Ruby interpolation syntax in output
    INTERP_OPEN = "#" "{" # rubocop:disable Lint/RedundantStringConstructor
    INTERP_CLOSE = "}"

    def initialize
      @out = []
      @indent = 0
    end

    # target: optional Hartwell Labs product key (talus/aurora/externum).
    # When given, it is verified against the lab registry first.
    def translate(source, target: nil)
      Registry.verify!(target) if target
      @out.clear
      @indent = 0
      @blocks = []
      @klass = nil
      @has_main = false
      source.each_line do |line|
        emit_line(line.chomp)
      end
      if @has_main
        emit
        emit 'main if $PROGRAM_NAME == __FILE__'
      end
      @out.join("\n") + "\n"
    end
    alias call translate

    private

    def pad
      "  " * @indent
    end

    def emit(line = "")
      @out << (line.empty? ? "" : pad + line)
    end

    def todo(line)
      emit "# TODO(labbridge): unsupported Rust construct: #{line.strip}"
    end

    def open_block(ruby_line, kind)
      emit ruby_line
      @indent += 1
      @blocks << kind
    end

    def close_block
      kind = @blocks.pop
      @indent = [@indent - 1, 0].max
      emit "end" if kind
    end

    def emit_line(line)
      case line
      when /\A\s*\z/              then emit
      when ATTRS                  then emit "# #{line.strip}"
      when /\A\s*\/\/\//          then emit line.sub("///", "#")
      when /\A\s*\/\//            then emit line.sub("//", "#")
      when UNSAFE_RE              then todo(line)
      when STRUCT_UNIT_RE         then emit "# labbridge: struct #{Regexp.last_match[1]} (opaque, no fields translated)"
      when USE_RE                 then emit "# labbridge: use (Rust imports elided)"
      when FN_RE
        m = Regexp.last_match
        ret = m[4] ? " # returns: #{clean_type(m[4].strip)}" : ""
        @has_main = true if m[2] == "main"
        open_block("def #{m[2]}(#{parse_args(m[3])})#{ret}", :def)
      when FN_INLINE_RE
        m = Regexp.last_match
        ret = m[3] ? " # returns: #{clean_type(m[3].strip)}" : ""
        emit "def #{m[1]}(#{parse_args(m[2])})#{ret}"
        emit translate_expr(m[4].to_s) unless m[4].to_s.strip.empty?
        emit "end"
      when STRUCT_RE
        @klass = Regexp.last_match[1]
        open_block("class #{@klass}", :struct)
      when ENUM_RE
        @klass = Regexp.last_match[1]
        open_block("class #{@klass}", :class)
      when TRAIT_RE
        open_block("module #{Regexp.last_match[1]}", :class)
      when MOD_RE
        open_block("module #{Regexp.last_match[1]}", :class)
      when IMPL_RE
        m = Regexp.last_match
        if m[2] == @klass
          # impl of an already-emitted struct class: reuse the class block
          @indent += 1
          @blocks << :impl
          emit "include #{m[1]}" if m[1]
        else
          @klass = m[2]
          open_block("class #{@klass}", :class)
          emit "include #{m[1]}" if m[1]
        end
      when FIELD_RE
        if @blocks.last == :struct
          emit "attr_accessor :#{Regexp.last_match[1]}"
        else
          todo(line)
        end
      when LET_RE
        m = Regexp.last_match
        emit "#{m[1]} = #{translate_expr(m[2])}"
      when IF_RE
        m = Regexp.last_match
        @indent -= 1
        emit "elsif #{translate_cond(m[2])}"
        @indent += 1
      when ELSE_RE
        @indent -= 1
        emit "else"
        @indent += 1
      when IF_OPEN_RE
        open_block("if #{translate_cond(Regexp.last_match[2])}", :if)
      when WHILE_RE
        open_block("while #{translate_cond(Regexp.last_match[2])}", :while)
      when FOR_RE
        m = Regexp.last_match
        open_block("(#{translate_expr(m[3])}).each do |#{m[2]}|", :for)
      when LOOP_RE
        open_block("loop do", :loop)
      when MATCH_RE
        open_block("case #{translate_expr(Regexp.last_match[2])}", :match)
      when ARM_RE
        m = Regexp.last_match
        if m[2].strip == "_"
          emit "else"
        else
          emit "when #{match_pattern(m[2])}"
        end
        @indent += 1
        emit translate_expr(m[3].sub(/[,;]\s*\z/, ""))
        @indent -= 1
      when RET_RE
        m = Regexp.last_match
        emit(m[2].empty? ? "return" : "return #{translate_expr(m[2])}")
      when BRACE_ONLY_RE
        close_block
      when STMT_RE
        emit translate_expr(Regexp.last_match[1])
      else
        todo(line)
      end
    end

    def parse_args(argstr)
      return "" if argstr.nil? || argstr.strip.empty?

      argstr.split(",").map(&:strip).reject(&:empty?)
            .reject { |a| a.match?(/\A&?\s*(?:mut\s+)?self\z/) }
            .map { |a| a.sub(/\s*:\s*&?\s*(?:mut\s+)?[\w<>\[\]:,& ]+\z/, "").strip }
            .join(", ")
    end

    def clean_type(t)
      TYPE_MAP.fetch(t.strip, t.strip)
    end

    def translate_cond(cond)
      translate_expr(cond)
    end

    def match_pattern(pat)
      case pat.strip
      when /\A"(.*)"\z/ then Regexp.last_match[1]
      when /\A([A-Z]\w*)::([A-Z]\w*)\z/ then ":#{Regexp.last_match[2]}"
      else translate_expr(pat)
      end
    end

    def translate_expr(expr)
      e = expr.dup
      e = translate_macros(e)
      e = translate_constructors(e)
      e = translate_methods(e)
      e = translate_casts(e)
      e = translate_bools(e)
      e.strip
    end

    def translate_macros(s)
      s = s.gsub(/println!\s*\((.*)\)\s*(?:;\s*)?\z/m) do
        args = split_args(Regexp.last_match[1])
        case args.size
        when 0 then "puts"
        when 1 then "puts #{args[0]}"
        else
          fmt, rest = args[0], args[1..]
          if fmt.match?(/\A".*"\z/) && fmt.include?("{}")
            fmt == '"{}"' ? "puts #{rest.join(', ')}" : "puts #{fmt_interp(fmt, rest)}"
          else
            "puts #{[fmt, *rest].join(', ')}"
          end
        end
      end
      s = s.gsub(/eprintln!\s*\((.*)\)\s*(?:;\s*)?\z/m) do
        args = split_args(Regexp.last_match[1])
        args.size > 1 && args[0].include?("{}") ? "warn #{fmt_interp(args[0], args[1..])}" : "warn #{args.join(', ')}"
      end
      s = s.gsub(/eprint!\s*\((.*?)\)\s*(?:;\s*)?\z/m) { "print #{Regexp.last_match[1]}" }
      s = s.gsub(/print!\s*\((.*?)\)\s*(?:;\s*)?\z/m) { "print #{Regexp.last_match[1]}" }
      s = s.gsub(/format!\s*\((.*)\)\s*\z/m) do
        parts = split_args(Regexp.last_match[1])
        parts.size > 1 && parts[0].include?("{}") ? fmt_interp(parts[0], parts[1..]) : parts[0]
      end
      s = s.gsub(/vec!\s*\[(.*?)\]\s*\z/m) { "[#{Regexp.last_match[1]}]" }
      s = s.gsub(/assert!\s*\((.*?)\)\s*(?:;\s*)?\z/m) { "raise 'assertion failed' unless #{Regexp.last_match[1]}" }
      s = s.gsub(/unreachable!\s*\(.*?\)\s*(?:;\s*)?\z/m, "raise 'unreachable'")
      s = s.gsub(/todo!\s*\(.*?\)\s*(?:;\s*)?\z/m, "raise 'todo'")
      s
    end

    # 'i={}' + ['a'] -> 'i=#{a}'  (keeps surrounding quotes; builds Ruby
    # interpolation syntax without tripping this file's own parser)
    def fmt_interp(fmt, args)
      parts = fmt.split("{}")
      out = +""
      parts.each_with_index do |seg, idx|
        out << seg
        out << "#{INTERP_OPEN}#{args[idx] || ''}#{INTERP_CLOSE}" if idx < parts.size - 1
      end
      out
    end

    def split_args(s)
      out, depth, cur, instr = [], 0, +"", false
      s.each_char do |c|
        if c == '"' && !cur.end_with?("\\")
          instr = !instr
          cur << c
        elsif instr
          cur << c
        else
          case c
          when "(", "[", "{" then depth += 1
          when ")", "]", "}" then depth -= 1
          when ","
            if depth.zero?
              out << cur.strip
              cur = +""
              next
            end
          end
          cur << c
        end
      end
      out << cur.strip unless cur.strip.empty?
      out
    end

    def translate_constructors(s)
      s = s.gsub(/String::new\s*\(\s*\)/, '""')
      s = s.gsub(/String::from\s*\((.*?)\)/, '\1')
      s = s.gsub(/Vec::new\s*\(\s*\)/, "[]")
      s = s.gsub(/HashMap::new\s*\(\s*\)/, "{}")
      s = s.gsub(/Vec::with_capacity\s*\([^)]*\)/, "[]")
      s = s.gsub(/::default\s*\(\s*\)/, ".new")
      s
    end

    def translate_methods(s)
      s = s.gsub(/\.len\s*\(\s*\)/, ".length")
      s = s.gsub(/\.is_empty\s*\(\s*\)/, ".empty?")
      s = s.gsub(/\.contains\s*\(/, ".include?(")
      s = s.gsub(/\.to_string\s*\(\s*\)/, ".to_s")
      s = s.gsub(/\.clone\s*\(\s*\)/, ".dup")
      s = s.gsub(/\.iter\s*\(\s*\)/, ".each")
      s = s.gsub(/\.trim\s*\(\s*\)/, ".strip")
      s = s.gsub(/\.unwrap\s*\(\s*\)/, "")
      s = s.gsub(/\.expect\s*\([^)]*\)/, "")
      s = s.gsub(/\.sqrt\s*\(\s*\)/, ".**0.5")
      s = s.gsub(/\.starts_with\s*\(/, ".start_with?(")
      s = s.gsub(/\.ends_with\s*\(/, ".end_with?(")
      s = s.gsub(/\.insert\s*\(/, ".insert(")
      s = s.gsub(/\.remove\s*\(/, ".delete_at(")
      s = s.gsub(/\.retain\s*\(/, ".select!(")
      s = s.gsub(/\.to_lowercase\s*\(\s*\)/, ".downcase")
      s = s.gsub(/\.to_uppercase\s*\(\s*\)/, ".upcase")
      s = s.gsub(/\.parse\s*(?::<[^>]*>)?\s*\(\s*\)/, ".to_i")
      s
    end

    def translate_casts(s)
      CAST_MAP.each do |rust, ruby|
        s = s.gsub(/\s*\bas\s+#{Regexp.escape(rust)}\b/, ".#{ruby}")
      end
      s = s.gsub(/\s*\bas\s+bool\b/, " != 0")
      s
    end

    def translate_bools(s)
      s.gsub(/&&/, " && ").gsub(/\|\|/, " || ")
       .gsub(/!([a-zA-Z_(])/, '! \1')
       .gsub(/\s+&&\s+/, " && ").gsub(/\s+\|\|\s+/, " || ")
    end
  end
end

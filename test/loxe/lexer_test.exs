defmodule Loxe.LexerTest do
  use ExUnit.Case, async: true
  doctest Loxe.Lexer

  alias Loxe.Lexer
  alias Loxe.Lexer.Error
  alias Loxe.Span

  # Lexes `src` and drops the trailing `:eof` token.
  defp lex!(src, id \\ 0) do
    {:ok, tokens} = Lexer.lex(src, id)
    {{:eof, nil, _}, tokens} = List.pop_at(tokens, -1)
    tokens
  end

  defp kinds(src), do: src |> lex!() |> Enum.map(&elem(&1, 0))

  defp values(src), do: src |> lex!() |> Enum.map(&elem(&1, 1))

  defp pairs(src), do: src |> lex!() |> Enum.map(fn {kind, value, _} -> {kind, value} end)

  defp spans(src), do: src |> lex!() |> Enum.map(fn {_, _, s} -> {s.start, s.end} end)

  defp error(src) do
    {:error, %Error{} = err} = Lexer.lex(src, 0)
    err
  end

  describe "end of input" do
    test "empty source produces only :eof" do
      assert Lexer.lex("", 3) == {:ok, [{:eof, nil, %Span{source_id: 3, start: 0, end: 0}}]}
    end

    test "whitespace only produces only :eof" do
      assert {:ok, [{:eof, nil, %Span{start: 7, end: 7}}]} = Lexer.lex(" \t\r\n  \n", 0)
    end

    test ":eof is last and has an empty span at the end of the source" do
      {:ok, tokens} = Lexer.lex("a + b // done", 0)
      assert {:eof, nil, %Span{start: 13, end: 13}} = List.last(tokens)
    end
  end

  describe "trivia" do
    test "line comments are skipped up to the newline" do
      assert kinds("// a comment\n+") == [:plus]
    end

    test "line comment at end of input without newline" do
      assert kinds("+ // trailing") == [:plus]
    end

    test "block comments are skipped" do
      assert kinds("+ /* comment */ -") == [:plus, :minus]
    end

    test "block comments can span lines" do
      assert kinds("+ /* line one\nline two */ -") == [:plus, :minus]
    end

    test "block comments do not nest" do
      assert kinds("/* /* inner */ + */") == [:plus, :star, :slash]
    end

    test "unterminated block comment consumes the rest of the input" do
      assert kinds("+ /* never closed -") == [:plus]
    end

    test "comment markers inside strings are not comments" do
      assert values(~s("// not a comment")) == ["// not a comment"]
      assert values(~s("/* not a comment */")) == ["/* not a comment */"]
    end
  end

  describe "punctuation and operators" do
    test "single-character tokens" do
      assert kinds("(){},.;-+*/") == [
               :lparen,
               :rparen,
               :lbrace,
               :rbrace,
               :comma,
               :dot,
               :semicolon,
               :minus,
               :plus,
               :star,
               :slash
             ]
    end

    test "two-character tokens" do
      assert kinds("!= == <= >=") == [:bang_equal, :equal_equal, :less_equal, :greater_equal]
    end

    test "two-character tokens win over their one-character prefix" do
      assert kinds("!!====") == [:bang, :bang_equal, :equal_equal, :equal]
    end

    test "standalone one-character comparison tokens" do
      assert kinds("! = < >") == [:bang, :equal, :less, :greater]
    end

    test "slash is division when not followed by / or *" do
      assert kinds("a / b") == [:ident, :slash, :ident]
    end

    test "punctuation has a nil value" do
      assert values("+-") == [nil, nil]
    end
  end

  describe "identifiers and keywords" do
    test "identifiers" do
      assert pairs("foo _bar baz9 a_b_c") == [
               {:ident, "foo"},
               {:ident, "_bar"},
               {:ident, "baz9"},
               {:ident, "a_b_c"}
             ]
    end

    test "identifiers are case sensitive" do
      assert values("Foo FOO foo") == ["Foo", "FOO", "foo"]
    end

    test "keywords" do
      src = "and class else fun for if or print return super this var while"

      assert kinds(src) == [
               :and,
               :class,
               :else,
               :fun,
               :for,
               :if,
               :or,
               :print,
               :return,
               :super,
               :this,
               :var,
               :while
             ]

      assert Enum.all?(values(src), &is_nil/1)
    end

    test "nil keyword has kind :nil_lit" do
      assert [{:nil_lit, nil, %Span{}}] = lex!("nil")
    end

    test "true and false are bool tokens" do
      assert pairs("true false") == [
               {:bool, true},
               {:bool, false}
             ]
    end

    test "keywords are case sensitive" do
      assert kinds("Var WHILE True") == [:ident, :ident, :ident]
    end

    test "names that start with a keyword are identifiers" do
      assert values("classy orchid variable nil_ truely") ==
               ["classy", "orchid", "variable", "nil_", "truely"]
    end

    test "identifier followed directly by punctuation" do
      assert kinds("foo(bar)") == [:ident, :lparen, :ident, :rparen]
    end
  end

  describe "numbers" do
    test "integers are lexed as floats" do
      assert lex!("123") == [{:number, 123.0, %Span{source_id: 0, start: 0, end: 3}}]
    end

    test "decimal literals" do
      assert values("3.14 0.5 10.25") == [3.14, 0.5, 10.25]
    end

    test "zero and leading zeros" do
      assert values("0 007 0.0") == [0.0, 7.0, 0.0]
    end

    test "trailing dot is a separate token" do
      assert pairs("1.") == [{:number, 1.0}, {:dot, nil}]
    end

    test "leading dot is a separate token" do
      assert pairs(".5") == [{:dot, nil}, {:number, 5.0}]
    end

    test "only one decimal point is consumed" do
      assert pairs("1.2.3") ==
               [{:number, 1.2}, {:dot, nil}, {:number, 3.0}]
    end

    test "property access on a number" do
      assert kinds("1.foo") == [:number, :dot, :ident]
    end

    test "negative numbers are a minus followed by a number" do
      assert pairs("-1") == [{:minus, nil}, {:number, 1.0}]
    end

    test "number directly followed by an identifier" do
      assert pairs("123abc") ==
               [{:number, 123.0}, {:ident, "abc"}]
    end

    test "integer too large for a float is an error" do
      num = "1" <> String.duplicate("0", 400)

      assert %Error{kind: {:invalid_number, ^num}, span: %Span{start: 0, end: 401}} =
               error(num)
    end

    test "decimal too large for a float is an error" do
      num = "1" <> String.duplicate("0", 400) <> ".5"
      assert %Error{kind: {:invalid_number, ^num}} = error(num)
    end
  end

  describe "strings" do
    test "simple string" do
      assert lex!(~s("hello")) == [{:string, "hello", %Span{source_id: 0, start: 0, end: 7}}]
    end

    test "empty string" do
      assert values(~s("")) == [""]
    end

    test "strings can span multiple lines" do
      assert values(~s("line one\nline two")) == ["line one\nline two"]
    end

    test "supported escape sequences" do
      assert values(~S("a\nb\tc\rd\\e\"f")) == ["a\nb\tc\rd\\e\"f"]
    end

    test "escaped quote does not terminate the string" do
      assert values(~S("say \"hi\"" + 1)) == [~s(say "hi"), nil, 1.0]
    end

    test "non-ASCII characters in strings" do
      assert values(~s("héllo wörld 🦊")) == ["héllo wörld 🦊"]
    end

    test "span covers the raw source including escapes" do
      assert spans(~S("a\nb")) == [{0, 6}]
    end

    test "span counts bytes" do
      assert spans(~s("é" x)) == [{0, 4}, {5, 6}]
    end

    test "adjacent strings" do
      assert values(~s("a""b")) == ["a", "b"]
    end

    test "unterminated string" do
      assert %Error{kind: :unterminated_string, span: %Span{start: 2, end: 9}} =
               error(~s(+ "abcdef))
    end

    test "string ending in a backslash is unterminated" do
      assert %Error{kind: :unterminated_string} = error(~s("abc\\))
    end

    test "invalid escape sequence" do
      assert %Error{kind: {:invalid_escape, ?q}, span: %Span{start: 0, end: 5}} =
               error(~S("ab\q rest"))
    end

    test "invalid escape with a multibyte character" do
      assert %Error{kind: {:invalid_escape, ?é}} = error(~s("\\é"))
    end

    test "invalid UTF-8 byte inside a string" do
      assert %Error{kind: {:invalid_byte, 0xFF}, span: %Span{start: 0, end: 3}} =
               error(<<?", ?a, 0xFF, ?">>)
    end
  end

  describe "spans" do
    test "spans are byte offsets with exclusive end" do
      assert spans("var foo = 12.5;") == [{0, 3}, {4, 7}, {8, 9}, {10, 14}, {14, 15}]
    end

    test "two-character tokens span two bytes" do
      assert spans("a<=b") == [{0, 1}, {1, 3}, {3, 4}]
    end

    test "spans after comments and newlines" do
      assert spans("a // c\n/* d */ b") == [{0, 1}, {15, 16}]
    end

    test "source id is attached to every span" do
      assert lex!("a + b", 42) |> Enum.all?(fn {_, _, span} -> span.source_id == 42 end)
    end

    test "source id is attached to error spans" do
      assert {:error, %Error{span: %Span{source_id: 7}}} = Lexer.lex("@", 7)
    end
  end

  describe "unexpected input" do
    test "unexpected ASCII character" do
      assert %Error{kind: {:unexpected_char, ?@}, span: %Span{start: 2, end: 3}} =
               error("a @ b")
    end

    for c <- ~c"#$%^&|~?:[]'`" do
      test "#{inspect(<<c>>)} is unexpected" do
        assert %Error{kind: {:unexpected_char, unquote(c)}} = error(<<unquote(c)>>)
      end
    end

    test "non-ASCII letters are not identifiers" do
      assert %Error{kind: {:unexpected_char, ?é}, span: %Span{start: 0, end: 2}} =
               error("é")
    end

    test "emoji outside a string is unexpected" do
      assert %Error{kind: {:unexpected_char, 0x1F98A}, span: %Span{start: 0, end: 4}} =
               error("🦊")
    end

    test "invalid UTF-8 byte" do
      assert %Error{kind: {:invalid_byte, 0xFF}, span: %Span{start: 1, end: 2}} =
               error(<<?a, 0xFF>>)
    end

    test "lexing stops at the first error" do
      assert %Error{kind: {:unexpected_char, ?@}} = error("a @ # b")
    end
  end

  describe "error messages" do
    test "unexpected character" do
      assert Exception.message(error("  @")) == ~s(unexpected character "@" at 2..3)
    end

    test "invalid byte" do
      assert Exception.message(error(<<0xFF>>)) == "invalid UTF-8 byte 0xFF at 0..1"
    end

    test "unterminated string" do
      assert Exception.message(error(~s("abc))) == "unterminated string literal at 0..4"
    end

    test "invalid escape" do
      assert Exception.message(error(~S("\q"))) == ~S(invalid escape sequence "\\q" at 0..3)
    end

    test "invalid number" do
      num = "1" <> String.duplicate("0", 400)
      assert Exception.message(error(num)) =~ "number literal is invalid: "
    end
  end

  describe "programs" do
    test "a small program" do
      src = """
      fun add(a, b) {
        // sum two values
        return a + b;
      }

      print add(1, 2.5) >= 3 and !false;
      """

      assert pairs(src) == [
               {:fun, nil},
               {:ident, "add"},
               {:lparen, nil},
               {:ident, "a"},
               {:comma, nil},
               {:ident, "b"},
               {:rparen, nil},
               {:lbrace, nil},
               {:return, nil},
               {:ident, "a"},
               {:plus, nil},
               {:ident, "b"},
               {:semicolon, nil},
               {:rbrace, nil},
               {:print, nil},
               {:ident, "add"},
               {:lparen, nil},
               {:number, 1.0},
               {:comma, nil},
               {:number, 2.5},
               {:rparen, nil},
               {:greater_equal, nil},
               {:number, 3.0},
               {:and, nil},
               {:bang, nil},
               {:bool, false},
               {:semicolon, nil}
             ]
    end

    test "spans slice back to the token text" do
      src = ~S|class Foo < Bar { this.x = "a\tb"; } // done|
      slices = for {_, _, %Span{start: s, end: e}} <- lex!(src), do: binary_part(src, s, e - s)

      assert slices ==
               ~w(class Foo < Bar { this . x =) ++ [~S("a\tb")] ++ ~w(; })
    end
  end
end

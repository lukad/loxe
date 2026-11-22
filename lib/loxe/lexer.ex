defmodule Loxe.Lexer do
  @moduledoc """
  Lexer for Lox source code. Lexing stops at the first error.

  ## Tokens

  Every token is a three-element tuple `{kind, value, span}`:

    * `kind` is the token type, such as `:lparen`, `:equal_equal`,
      `:ident` or `:while`.
    * `value` is the name of an identifier, the contents of a string, the
      boolean for `true` and `false`, or the number as a float. Other
      tokens have `nil`.
    * `span` is the token's byte range in the source, as a `Loxe.Span`.
      `end` is exclusive.

  The last token is always `:eof`, with an empty span at the end of the
  source.

  ## Lexical rules

    * Spaces, tabs, carriage returns and newlines are skipped.
    * `//` starts a line comment that runs to the end of the line.
    * `/*` starts a block comment that runs to the next `*/`. Block
      comments do not nest, and an unterminated one runs to the end of
      the input.
    * Identifiers start with an ASCII letter or `_`, followed by ASCII
      letters, digits or `_`. Reserved words become keyword tokens.
      `true` and `false` become `:bool` tokens.
    * Numbers are digits, optionally followed by `.` and more digits.
      A leading or trailing `.` is a separate `:dot` token, so `1.` lexes
      as `1.0` then `:dot`.
    * Strings are delimited by `"` and may span lines. The escapes are
      `\\n`, `\\t`, `\\r`, `\\\\` and `\\"`.

  ## Errors

  On failure, `lex/2` returns a `Loxe.Lexer.Error` whose `kind` is one of:

    * `{:unexpected_char, codepoint}` - a character that can't start a token.
    * `{:invalid_byte, byte}` - a byte that isn't valid UTF-8, inside or
      outside a string.
    * `:unterminated_string` - a string with no closing `"`.
    * `{:invalid_escape, codepoint}` - an unknown escape in a string.
    * `{:invalid_number, literal}` - a number too large for a float.
  """

  defmodule Error do
    @moduledoc """
    Returned by `Loxe.Lexer.lex/2` when the source can't be lexed.

    `span` is the byte range of the bad input. The possible `kind`s are
    listed in `Loxe.Lexer`.
    """

    defexception [:kind, :span]

    @type t() :: %__MODULE__{
            kind:
              {:unexpected_char, char()}
              | {:invalid_byte, byte()}
              | :unterminated_string
              | {:invalid_escape, char()}
              | {:invalid_number, String.t()},
            span: Loxe.Span.t()
          }

    @impl true
    def message(%{kind: kind, span: span}) do
      "#{describe(kind)} at #{span.start}..#{span.end}"
    end

    defp describe({:unexpected_char, c}), do: "unexpected character #{inspect(<<c::utf8>>)}"
    defp describe({:invalid_byte, b}), do: "invalid UTF-8 byte 0x#{Integer.to_string(b, 16)}"
    defp describe(:unterminated_string), do: "unterminated string literal"

    defp describe({:invalid_escape, c}) do
      "invalid escape sequence #{inspect(<<?\\, c::utf8>>)}"
    end

    defp describe({:invalid_number, num}), do: "number literal is invalid: #{inspect(num)}"
  end

  alias __MODULE__.Error
  alias Loxe.Span

  @type tokenkind ::
          :lparen
          | :rparen
          | :lbrace
          | :rbrace
          | :comma
          | :dot
          | :semicolon
          | :minus
          | :plus
          | :star
          | :slash
          | :bang
          | :bang_equal
          | :equal
          | :equal_equal
          | :greater
          | :greater_equal
          | :less
          | :less_equal
          | :and
          | :break
          | :class
          | :continue
          | :else
          | :fun
          | :for
          | :if
          | :nil_lit
          | :or
          | :print
          | :return
          | :super
          | :this
          | :var
          | :while
          | :eof

  @type token ::
          {tokenkind(), nil, Span.t()}
          | {:ident | :string, String.t(), Span.t()}
          | {:bool, boolean(), Span.t()}
          | {:number, float(), Span.t()}

  @doc """
  Lexes `src` into tokens. Every span gets `source_id`.

  Returns `{:ok, tokens}` in source order, ending with an `:eof` token, or
  `{:error, error}` for the first error.

  ## Examples

      iex> Loxe.Lexer.lex("var x = 1;", 0)
      {:ok,
       [
         {:var, nil, %Loxe.Span{source_id: 0, start: 0, end: 3}},
         {:ident, "x", %Loxe.Span{source_id: 0, start: 4, end: 5}},
         {:equal, nil, %Loxe.Span{source_id: 0, start: 6, end: 7}},
         {:number, 1.0, %Loxe.Span{source_id: 0, start: 8, end: 9}},
         {:semicolon, nil, %Loxe.Span{source_id: 0, start: 9, end: 10}},
         {:eof, nil, %Loxe.Span{source_id: 0, start: 10, end: 10}}
       ]}

      iex> Loxe.Lexer.lex(~s("hi), 0)
      {:error,
       %Loxe.Lexer.Error{
         kind: :unterminated_string,
         span: %Loxe.Span{source_id: 0, start: 0, end: 3}
       }}

  """
  @spec lex(String.t(), non_neg_integer) :: {:ok, [token()]} | {:error, Error.t()}
  def lex(src, source_id) do
    lex(src, [], %{size: byte_size(src), id: source_id})
  end

  defguardp ident_start?(c) when c in ?a..?z or c in ?A..?Z or c == ?_

  defguardp ident_continue?(c) when ident_start?(c) or c in ?0..?9

  defp lex(<<>>, acc, ctx) do
    eof = token(:eof, nil, "", "", ctx)
    {:ok, Enum.reverse([eof | acc])}
  end

  defp lex(<<c, rest::binary>>, acc, ctx) when c in ~c" \t\r\n", do: lex(rest, acc, ctx)

  defp lex(<<"//", rest::binary>>, acc, ctx) do
    skip_until(rest, "\n", acc, ctx)
  end

  defp lex(<<"/*", rest::binary>>, acc, ctx) do
    skip_until(rest, "*/", acc, ctx)
  end

  @punct [
    bang_equal: "!=",
    equal_equal: "==",
    less_equal: "<=",
    greater_equal: ">=",
    bang: "!",
    equal: "=",
    less: "<",
    greater: ">",
    lparen: "(",
    rparen: ")",
    lbrace: "{",
    rbrace: "}",
    comma: ",",
    dot: ".",
    semicolon: ";",
    minus: "-",
    plus: "+",
    star: "*",
    slash: "/"
  ]

  for {kind, lit} <- @punct do
    defp lex(<<unquote(lit), rest::binary>> = input, acc, ctx) do
      lex(rest, [token(unquote(kind), nil, input, rest, ctx) | acc], ctx)
    end
  end

  @keywords %{
    "and" => {:and, nil},
    "break" => {:break, nil},
    "class" => {:class, nil},
    "continue" => {:continue, nil},
    "else" => {:else, nil},
    "fun" => {:fun, nil},
    "false" => {:bool, false},
    "for" => {:for, nil},
    "if" => {:if, nil},
    "nil" => {:nil_lit, nil},
    "or" => {:or, nil},
    "print" => {:print, nil},
    "return" => {:return, nil},
    "super" => {:super, nil},
    "this" => {:this, nil},
    "true" => {:bool, true},
    "var" => {:var, nil},
    "while" => {:while, nil}
  }

  defp lex(<<c::utf8, _::binary>> = input, acc, ctx) when ident_start?(c) do
    ident_length = count_ident_length(input)
    <<ident::binary-size(^ident_length), rest::binary>> = input

    {kind, value} = Map.get(@keywords, ident, {:ident, ident})

    lex(rest, [token(kind, value, input, rest, ctx) | acc], ctx)
  end

  defp lex(<<c, _::binary>> = input, acc, ctx) when c in ?0..?9 do
    {number_length, float?} = count_number_length(input, 0, false)
    <<num::binary-size(^number_length), rest::binary>> = input

    case to_number(num, float?) do
      {:ok, value} ->
        lex(rest, [token(:number, value, input, rest, ctx) | acc], ctx)

      :error ->
        {:error, %Error{kind: {:invalid_number, num}, span: span(input, rest, ctx)}}
    end
  end

  defp lex(<<?", rest::binary>> = input, acc, ctx) do
    case lex_string(rest, "") do
      {:ok, value, rest} ->
        lex(rest, [token(:string, value, input, rest, ctx) | acc], ctx)

      {:error, kind, rest} ->
        {:error, %Error{kind: kind, span: span(input, rest, ctx)}}
    end
  end

  defp lex(<<c::utf8, rest::binary>> = input, _acc, ctx) do
    {:error, %Error{kind: {:unexpected_char, c}, span: span(input, rest, ctx)}}
  end

  defp lex(<<b, rest::binary>> = input, _acc, ctx) do
    {:error, %Error{kind: {:invalid_byte, b}, span: span(input, rest, ctx)}}
  end

  defp token(kind, value, input, rest, ctx) do
    {kind, value, span(input, rest, ctx)}
  end

  defp span(input, rest, ctx) do
    %Span{
      source_id: ctx.id,
      start: ctx.size - byte_size(input),
      end: ctx.size - byte_size(rest)
    }
  end

  defp count_ident_length(input, count \\ 0)

  defp count_ident_length(<<c, rest::binary>>, count) when ident_continue?(c) do
    count_ident_length(rest, count + 1)
  end

  defp count_ident_length(_, count), do: count

  defp count_number_length(<<d, rest::binary>>, count, float?) when d in ?0..?9 do
    count_number_length(rest, count + 1, float?)
  end

  defp count_number_length(<<?., d, rest::binary>>, count, false) when d in ?0..?9 do
    count_number_length(rest, count + 2, true)
  end

  defp count_number_length(_, count, float?), do: {count, float?}

  defp to_number(num, float?) do
    value =
      if float?,
        do: String.to_float(num),
        else: :erlang.float(String.to_integer(num))

    {:ok, value}
  rescue
    ArgumentError -> :error
  end

  @escapes %{?n => ?\n, ?t => ?\t, ?r => ?\r, ?\\ => ?\\, ?" => ?"}

  defp lex_string(<<?", rest::binary>>, acc), do: {:ok, acc, rest}

  for {esc, char} <- @escapes do
    defp lex_string(<<?\\, unquote(esc), rest::binary>>, acc) do
      lex_string(rest, <<acc::binary, unquote(char)>>)
    end
  end

  defp lex_string(<<?\\, c::utf8, rest::binary>>, _acc) do
    {:error, {:invalid_escape, c}, rest}
  end

  defp lex_string(<<c::utf8, rest::binary>>, acc) do
    lex_string(rest, <<acc::binary, c::utf8>>)
  end

  defp lex_string(<<b, rest::binary>>, _acc), do: {:error, {:invalid_byte, b}, rest}

  defp lex_string(<<>>, _acc), do: {:error, :unterminated_string, <<>>}

  defp skip_until(input, sep, acc, ctx) do
    case :binary.split(input, sep) do
      [_, rest] -> lex(rest, acc, ctx)
      [_] -> lex(<<>>, acc, ctx)
    end
  end

  @lexemes Map.merge(
             Map.new(@punct),
             for({lit, {kind, nil}} <- @keywords, into: %{}, do: {kind, lit})
           )

  @doc """
  Returns the source text of a token kind with fixed text, or `nil` for
  kinds whose text varies (`:ident`, `:string`, `:number`, `:bool`) and
  for `:eof`.

  ## Examples

      iex> Loxe.Lexer.lexeme(:bang_equal)
      "!="

      iex> Loxe.Lexer.lexeme(:nil_lit)
      "nil"

      iex> Loxe.Lexer.lexeme(:ident)
      nil

  """
  @spec lexeme(tokenkind() | :ident | :string | :number | :bool) :: String.t() | nil
  def lexeme(kind), do: Map.get(@lexemes, kind)
end

defmodule Loxe.Parser do
  @moduledoc """
  Parses the tokens from `Loxe.Lexer.lex/2` into a list of `Loxe.Ast`
  declarations. Parsing stops at the first error.

  ## Grammar

      program     -> declaration* EOF
      declaration -> varDecl | funDecl | statement
      varDecl     -> "var" IDENT ( "=" expression )? ";"
      funDecl     -> "fun" IDENT "(" ( IDENT ( "," IDENT )* )? ")" block
      statement   -> printStmt | returnStmt | ifStmt | whileStmt | forStmt
                   | block | exprStmt
      printStmt   -> "print" expression ";"
      returnStmt  -> "return" expression? ";"
      ifStmt      -> "if" "(" expression ")" statement ( "else" statement )?
      whileStmt   -> "while" "(" expression ")" statement
      forStmt     -> "for" "(" forInit? ";" expression? ";" expression? ")"
                     statement
      forInit     -> "var" IDENT ( "=" expression )? | expression
      block       -> "{" declaration* "}"
      exprStmt    -> expression ";"

  ## Operators

  From loosest to tightest:

  | Operators         | Associativity |
  | :---------------- | :------------ |
  | `=`               | right         |
  | `or`              | left          |
  | `and`             | left          |
  | `==` `!=`         | left          |
  | `<` `<=` `>` `>=` | left          |
  | `+` `-`           | left          |
  | `*` `/`           | left          |
  | unary `-`         | prefix        |
  | calls, `.`        | left          |

  The target of `=` must be a variable or a property access. `a = 1`
  becomes `Loxe.Ast.Assign` and `a.b = 1` becomes `Loxe.Ast.Set`.
  There is no node for parentheses: `(1 + 2)` parses to a
  `Loxe.Ast.Binary`.
  """

  alias Loxe.Lexer
  alias Loxe.Span
  alias Loxe.Ast

  alias Loxe.Ast.{
    Assign,
    Binary,
    Block,
    Break,
    Call,
    ExprStmt,
    For,
    Fun,
    Get,
    Ident,
    If,
    Literal,
    Print,
    Return,
    Set,
    Unary,
    Var,
    VarDecl,
    While
  }

  defmodule Error do
    @moduledoc """
    Returned by `Loxe.Parser.parse/1` when parsing fails.

    `span` is the token where parsing failed. `kind` is one of:

      * `{:expected, expected, found}` - a token of kind `expected` was
        required, but the next token had kind `found`.
      * `{:expected_expression, found}` - an expression was required, but
        the next token had kind `found`.
      * `:invalid_assign_target` - the left side of `=` is not a variable or
        property. `span` covers the whole left side.
    """

    alias Loxe.Lexer

    defexception [:kind, :span]

    @typep token_kind :: Lexer.tokenkind() | :ident | :string | :number | :bool

    @type t() :: %__MODULE__{
            kind:
              {:expected, token_kind(), token_kind()}
              | {:expected_expression, token_kind()}
              | :invalid_assign_target,
            span: Loxe.Span.t()
          }

    @impl true
    def message(%{kind: kind, span: span}) do
      "#{describe(kind)} at #{span.start}..#{span.end}"
    end

    defp describe({:expected, expected, found}) do
      "expected #{describe_token(expected)}, found #{describe_token(found)}"
    end

    defp describe({:expected_expression, found}) do
      "expected expression, found #{describe_token(found)}"
    end

    defp describe(:invalid_assign_target), do: "invalid assignment target"

    defp describe_token(:eof), do: "end of input"
    defp describe_token(:ident), do: "identifier"
    defp describe_token(:string), do: "string"
    defp describe_token(:number), do: "number"
    defp describe_token(:bool), do: "boolean"
    defp describe_token(kind), do: inspect(Lexer.lexeme(kind))
  end

  @doc """
  Parses `tokens` into a list of declarations, in source order.

  `tokens` must end with the `:eof` token, as returned by
  `Loxe.Lexer.lex/2`. Returns `{:ok, decls}`, or `{:error, error}` with a
  `Loxe.Parser.Error` for the first error.

  ## Examples

      iex> {:ok, tokens} = Loxe.Lexer.lex("print 1;", 0)
      iex> Loxe.Parser.parse(tokens)
      {:ok,
       [
         %Loxe.Ast.Print{
           expr: %Loxe.Ast.Literal{value: 1.0, span: %Loxe.Span{source_id: 0, start: 6, end: 7}},
           span: %Loxe.Span{source_id: 0, start: 0, end: 8}
         }
       ]}

      iex> {:ok, tokens} = Loxe.Lexer.lex("print 1", 0)
      iex> Loxe.Parser.parse(tokens)
      {:error,
       %Loxe.Parser.Error{
         kind: {:expected, :semicolon, :eof},
         span: %Loxe.Span{source_id: 0, start: 7, end: 7}
       }}

  """
  @spec parse([Lexer.token()]) :: {:ok, [Ast.decl()]} | {:error, Error.t()}
  def parse(tokens) do
    with {:ok, decls, rest} <- parse_decls(tokens, :eof, []),
         {:ok, _span, _rest} <- expect(rest, :eof) do
      {:ok, decls}
    end
  end

  defp parse_decls([{stop, _, _} | _] = tokens, stop, acc), do: {:ok, Enum.reverse(acc), tokens}
  defp parse_decls([{:eof, _, _} | _] = tokens, _stop, acc), do: {:ok, Enum.reverse(acc), tokens}

  defp parse_decls(tokens, stop, acc) do
    with {:ok, decl, rest} <- parse_decl(tokens) do
      parse_decls(rest, stop, [decl | acc])
    end
  end

  defp parse_decl([{:var, _, _} | _] = tokens), do: parse_var_decl(tokens)
  defp parse_decl([{:fun, _, _} | _] = tokens), do: parse_fun_decl(tokens)
  defp parse_decl([{:class, _, _} | _] = _tokens), do: raise("Not implemented")
  defp parse_decl(tokens), do: parse_stmt(tokens)

  defp parse_var_decl(tokens) do
    with {:ok, var, rest} <- parse_var(tokens),
         {:ok, semi, rest} <- expect(rest, :semicolon) do
      {:ok, %{var | span: Span.join(var.span, semi)}, rest}
    end
  end

  defp parse_var([{:var, _, start} | rest]) do
    with {:ok, name, rest} <- parse_ident(rest),
         {:ok, value, rest} <- parse_initializer(rest) do
      {:ok, %VarDecl{name: name, value: value, span: Span.join(start, (value || name).span)},
       rest}
    end
  end

  defp parse_initializer([{:equal, _, _} | rest]), do: parse_expr(rest)
  defp parse_initializer(tokens), do: {:ok, nil, tokens}

  defp parse_fun_decl([{:fun, _, start_span} | rest]) do
    with {:ok, %Fun{} = fun, rest} <- parse_fun(rest, true) do
      span = Span.join(start_span, fun.span)
      fun = %Fun{fun | span: span}
      {:ok, fun, rest}
    end
  end

  defp parse_fun(tokens, with_params?) do
    with {:ok, name, rest} <- parse_ident(tokens),
         {:ok, params, rest} <- maybe_params(rest, with_params?),
         {:ok, body, rest} <- parse_block(rest) do
      fun = %Fun{name: name, params: params, body: body, span: Span.join(name.span, body.span)}
      {:ok, fun, rest}
    end
  end

  defp maybe_params(tokens, true), do: parse_params(tokens)
  defp maybe_params(tokens, false), do: {:ok, [], tokens}

  defp parse_params(tokens) do
    with {:ok, _, rest} <- expect(tokens, :lparen) do
      case rest do
        [{:rparen, _, _} | rest] -> {:ok, [], rest}
        _ -> parse_param_list(rest, [])
      end
    end
  end

  defp parse_param_list(tokens, acc) do
    with {:ok, param, rest} <- parse_ident(tokens) do
      case rest do
        [{:comma, _, _} | rest] ->
          parse_param_list(rest, [param | acc])

        _ ->
          with {:ok, _, rest} <- expect(rest, :rparen) do
            {:ok, Enum.reverse([param | acc]), rest}
          end
      end
    end
  end

  defp parse_stmt([{:print, _, _} | _] = tokens), do: parse_print(tokens)
  defp parse_stmt([{:return, _, _} | _] = tokens), do: parse_return(tokens)
  defp parse_stmt([{:break, _, _} | _] = tokens), do: parse_break(tokens)
  defp parse_stmt([{:if, _, _} | _] = tokens), do: parse_if(tokens)
  defp parse_stmt([{:while, _, _} | _] = tokens), do: parse_while(tokens)
  defp parse_stmt([{:for, _, _} | _] = tokens), do: parse_for(tokens)
  defp parse_stmt([{:lbrace, _, _} | _] = tokens), do: parse_block(tokens)
  defp parse_stmt(tokens), do: parse_expr_stmt(tokens)

  defp parse_print([{:print, _, start} | rest]) do
    with {:ok, expr, rest} <- parse_expr(rest),
         {:ok, stop, rest} <- expect(rest, :semicolon) do
      {:ok, %Print{expr: expr, span: Span.join(start, stop)}, rest}
    end
  end

  defp parse_return([{:return, _, start} | rest]) do
    with {:ok, expr, rest} <- parse_return_value(rest),
         {:ok, stop, rest} <- expect(rest, :semicolon) do
      {:ok, %Return{expr: expr, span: Span.join(start, stop)}, rest}
    end
  end

  defp parse_return_value([{:semicolon, _, _} | _] = tokens), do: {:ok, nil, tokens}
  defp parse_return_value(tokens), do: parse_expr(tokens)

  defp parse_break([{:break, _, start} | rest]) do
    with {:ok, stop, rest} <- expect(rest, :semicolon) do
      {:ok, %Break{span: Span.join(start, stop)}, rest}
    end
  end

  defp parse_if([{:if, _, start} | rest]) do
    with {:ok, _, rest} <- expect(rest, :lparen),
         {:ok, condition, rest} <- parse_expr(rest),
         {:ok, _, rest} <- expect(rest, :rparen),
         {:ok, then_branch, rest} <- parse_stmt(rest),
         {:ok, else_branch, rest} <- parse_else(rest) do
      last = else_branch || then_branch

      {:ok,
       %If{
         condition: condition,
         then_branch: then_branch,
         else_branch: else_branch,
         span: Span.join(start, last.span)
       }, rest}
    end
  end

  defp parse_while([{:while, _, start} | rest]) do
    with {:ok, _, rest} <- expect(rest, :lparen),
         {:ok, condition, rest} <- parse_expr(rest),
         {:ok, _, rest} <- expect(rest, :rparen),
         {:ok, body, rest} <- parse_stmt(rest) do
      {:ok,
       %While{
         condition: condition,
         body: body,
         span: Span.join(start, body.span)
       }, rest}
    end
  end

  defp parse_for([{:for, _, start} | rest]) do
    with {:ok, _, rest} <- expect(rest, :lparen),
         {:ok, init, rest} <- parse_for_init(rest),
         {:ok, _, rest} <- expect(rest, :semicolon),
         {:ok, condition, rest} <- parse_optional_expr(rest, :semicolon),
         {:ok, _, rest} <- expect(rest, :semicolon),
         {:ok, update, rest} <- parse_optional_expr(rest, :rparen),
         {:ok, _, rest} <- expect(rest, :rparen),
         {:ok, body, rest} <- parse_stmt(rest) do
      {:ok,
       %For{
         init: init,
         condition: condition,
         update: update,
         body: body,
         span: Span.join(start, body.span)
       }, rest}
    end
  end

  defp parse_for_init([{:semicolon, _, _} | _] = tokens), do: {:ok, nil, tokens}
  defp parse_for_init([{:var, _, _} | _] = tokens), do: parse_var(tokens)
  defp parse_for_init(tokens), do: parse_expr(tokens)

  defp parse_optional_expr([{stop, _, _} | _] = tokens, stop), do: {:ok, nil, tokens}
  defp parse_optional_expr(tokens, _stop), do: parse_expr(tokens)

  defp parse_else([{:else, _, _} | rest]), do: parse_stmt(rest)
  defp parse_else(tokens), do: {:ok, nil, tokens}

  defp parse_block(tokens) do
    with {:ok, start, rest} <- expect(tokens, :lbrace),
         {:ok, body, rest} <- parse_decls(rest, :rbrace, []),
         {:ok, stop, rest} <- expect(rest, :rbrace) do
      {:ok, %Block{body: body, span: Span.join(start, stop)}, rest}
    end
  end

  defp parse_expr_stmt(tokens) do
    with {:ok, expr, rest} <- parse_expr(tokens),
         {:ok, stop, rest} <- expect(rest, :semicolon) do
      {:ok, %ExprStmt{expr: expr, span: Span.join(expr.span, stop)}, rest}
    end
  end

  defp parse_expr(tokens), do: expr_bp(tokens, 0)

  defp expr_bp(tokens, min_bp) do
    with {:ok, lhs, rest} <- nud(tokens) do
      led(lhs, rest, min_bp)
    end
  end

  defp nud([{kind, value, span} | rest]) when kind in [:number, :string, :bool, :nil_lit] do
    {:ok, %Literal{value: value, span: span}, rest}
  end

  defp nud([{:ident, name, span} | rest]) do
    {:ok, %Var{name: name, span: span}, rest}
  end

  defp nud([{:minus, _, start} | rest]) do
    with {:ok, operand, rest} <- expr_bp(rest, 80) do
      {:ok, %Unary{op: :neg, expr: operand, span: Span.join(start, operand.span)}, rest}
    end
  end

  defp nud([{:lparen, _, _} | rest]) do
    with {:ok, expr, rest} <- expr_bp(rest, 0),
         {:ok, _, rest} <- expect(rest, :rparen) do
      {:ok, expr, rest}
    end
  end

  defp nud([{kind, _, span} | _]) do
    {:error, %Error{kind: {:expected_expression, kind}, span: span}}
  end

  # Call: `callee(args)`
  defp led(lhs, [{:lparen, _, _} | rest], min_bp) when min_bp <= 90 do
    with {:ok, {args, stop}, rest} <- parse_args(rest) do
      call = %Call{callee: lhs, args: args, span: Span.join(lhs.span, stop)}
      led(call, rest, min_bp)
    end
  end

  # Property access: `object.name`
  defp led(lhs, [{:dot, _, _} | rest], min_bp) when min_bp <= 90 do
    with {:ok, name, rest} <- parse_ident(rest) do
      get = %Get{object: lhs, name: name, span: Span.join(lhs.span, name.span)}
      led(get, rest, min_bp)
    end
  end

  # Assignment: `target = value`
  defp led(lhs, [{:equal, _, _} | rest], min_bp) when min_bp <= 10 do
    with {:ok, value, rest} <- expr_bp(rest, 10),
         {:ok, assign} <- to_assignment(lhs, value) do
      led(assign, rest, min_bp)
    end
  end

  defp led(lhs, [{kind, _, _} | rest] = tokens, min_bp) do
    case infix(kind) do
      {op, l_bp, r_bp} when l_bp >= min_bp ->
        with {:ok, rhs, rest} <- expr_bp(rest, r_bp) do
          binary = %Binary{op: op, left: lhs, right: rhs, span: Span.join(lhs.span, rhs.span)}
          led(binary, rest, min_bp)
        end

      _ ->
        {:ok, lhs, tokens}
    end
  end

  defp infix(:or), do: {:or, 20, 21}
  defp infix(:and), do: {:and, 30, 31}
  defp infix(:equal_equal), do: {:eq, 40, 41}
  defp infix(:bang_equal), do: {:ne, 40, 41}
  defp infix(:less), do: {:lt, 45, 46}
  defp infix(:less_equal), do: {:lt, 45, 46}
  defp infix(:greater), do: {:lt, 45, 46}
  defp infix(:greater_equal), do: {:lt, 45, 46}
  defp infix(:plus), do: {:add, 50, 51}
  defp infix(:minus), do: {:sub, 50, 51}
  defp infix(:star), do: {:mul, 60, 61}
  defp infix(:slash), do: {:div, 60, 61}
  defp infix(_), do: nil

  defp parse_args([{:rparen, _, stop} | rest]), do: {:ok, {[], stop}, rest}
  defp parse_args(tokens), do: parse_arg_list(tokens, [])

  defp parse_arg_list(tokens, acc) do
    with {:ok, arg, rest} <- parse_expr(tokens) do
      case rest do
        [{:comma, _, _} | rest] ->
          parse_arg_list(rest, [arg | acc])

        _ ->
          with {:ok, stop, rest} <- expect(rest, :rparen) do
            {:ok, {Enum.reverse([arg | acc]), stop}, rest}
          end
      end
    end
  end

  defp to_assignment(%Var{name: name} = target, value) do
    {:ok, %Assign{name: name, value: value, span: Span.join(target.span, value.span)}}
  end

  defp to_assignment(%Get{object: object, name: name} = target, value) do
    span = Span.join(target.span, value.span)
    {:ok, %Set{object: object, name: name, value: value, span: span}}
  end

  defp to_assignment(target, _value) do
    {:error, %Error{kind: :invalid_assign_target, span: target.span}}
  end

  defp parse_ident([{:ident, name, span} | rest]) do
    {:ok, %Ident{name: name, span: span}, rest}
  end

  defp parse_ident([{found, _, span} | _]) do
    {:error, %Error{kind: {:expected, :ident, found}, span: span}}
  end

  defp expect([{kind, _, span} | rest], kind), do: {:ok, span, rest}

  defp expect([{found, _, span} | _], expected) do
    {:error, %Error{kind: {:expected, expected, found}, span: span}}
  end
end

defmodule Loxe.Interpreter do
  @moduledoc """
  Runs Lox programs parsed by `Loxe.Parser`.

  Supported so far: expression statements, `print`, `var`, blocks, `if`,
  `while`, `break`, `continue`, and literal, grouping, variable,
  assignment, unary and binary expressions.

  ## Values

  Values are `nil`, booleans, floats and strings (`t:value/0`). `nil` and
  `false` are falsy. Everything else is truthy, including `0.0` and `""`.

  ## Operators

    * `+` adds two numbers or concatenates two strings.
    * `-`, `*`, `/`, `<`, `<=`, `>` and `>=` take two numbers.
    * `==` and `!=` take any two values. Values of different types are
      never equal.
    * `and` and `or` short-circuit and return one of their operands, not a
      boolean: `nil or "x"` is `"x"`.
    * Unary `-` takes a number. `!` takes any value and returns a boolean.

  Using an operator on the wrong types, dividing by zero, or getting a
  result too large for a float is an error. There is no infinity or NaN.

  ## Variables

  `var` declares a variable. Without an initializer its value is `nil`.
  Variables declared at the top level are globals; variables declared in a
  block are visible until the end of the block and can shadow outer ones.
  Reading or assigning a variable that was never declared is an error.

  Assignment is an expression that returns the assigned value, so
  `a = b = 1` sets both.

  ## Control flow

  `if` runs its then branch when the condition is truthy, and its `else`
  branch, if there is one, otherwise. The branch that isn't taken is never
  evaluated.

  `while` evaluates its condition before each iteration and runs the body
  while it is truthy. `break` leaves the innermost loop, and `continue`
  skips to its next iteration. Using either outside a loop is an error.

  ## Output

  `print` writes the value and a newline to `state.out` (see
  `Loxe.Interpreter.State`). Numbers with no fractional part are printed
  without a decimal point, so `print 3;` prints `3`. Strings are printed
  without quotes.
  """

  alias Loxe.Interpreter.Error
  alias Loxe.Interpreter.State
  alias Loxe.Interpreter.Env
  alias Loxe.Ast

  alias Loxe.Ast.{
    Assign,
    Block,
    Binary,
    Break,
    Continue,
    ExprStmt,
    Grouping,
    Ident,
    If,
    Literal,
    Print,
    Unary,
    Var,
    VarDecl,
    While
  }

  @typedoc "A Lox value."
  @type value() :: nil | boolean() | float() | String.t()

  @doc """
  Runs `decls` and returns `{:ok, state}` with the final state.

  Pass a `state` returned by an earlier call to keep its globals, for
  example in a REPL.

  Stops at the first error and returns `{:error, error}` with a
  `Loxe.Interpreter.Error`. Changes to the state made before the error are
  lost, but anything already printed stays printed.

  ## Examples

      iex> {:ok, tokens} = Loxe.Lexer.lex("var x = (1 + 2) * 3;", 0)
      iex> {:ok, decls} = Loxe.Parser.parse(tokens)
      iex> {:ok, state} = Loxe.Interpreter.run(decls)
      iex> state.globals["x"]
      9.0

      iex> {:ok, tokens} = Loxe.Lexer.lex(~s(1 + "a";), 0)
      iex> {:ok, decls} = Loxe.Parser.parse(tokens)
      iex> Loxe.Interpreter.run(decls)
      {:error,
       %Loxe.Interpreter.Error{
         kind: {:invalid_operands, :add},
         span: %Loxe.Span{source_id: 0, start: 0, end: 7}
       }}

  """
  @spec run([Ast.decl()], State.t()) :: {:ok, State.t()} | {:error, Error.t()}
  def run(decls, state \\ %State{}) do
    case exec_all(decls, :global, state) do
      {:ok, :global, state} ->
        {:ok, state}

      {{kind, span}, _env, _state} when kind in [:break, :continue] ->
        {:error, %Error{kind: {:outside_loop, kind}, span: span}}
    end
  rescue
    error in Error -> {:error, error}
  end

  defp exec_all(decls, env, state) do
    Enum.reduce_while(decls, {:ok, env, state}, fn decl, {:ok, env, state} ->
      case exec(decl, env, state) do
        {:ok, _, _} = ok -> {:cont, ok}
        other -> {:halt, other}
      end
    end)
  end

  defp exec(%ExprStmt{expr: expr}, env, state) do
    {_, env, state} = eval(expr, env, state)
    {:ok, env, state}
  end

  defp exec(%Print{expr: expr}, env, state) do
    {value, env, state} = eval(expr, env, state)
    IO.puts(state.out, stringify(value))
    {:ok, env, state}
  end

  defp exec(%VarDecl{name: %Ident{name: n}, value: expr}, env, state) do
    {value, env, state} = if expr, do: eval(expr, env, state), else: {nil, env, state}
    {env, state} = Env.declare(n, value, env, state)
    {:ok, env, state}
  end

  defp exec(%Block{body: decls}, env, state) do
    {tag, _inner, state} = exec_all(decls, Env.scope(env), state)
    {tag, env, state}
  end

  defp exec(%If{} = stmt, env, state) do
    {condition, env, state} = eval(stmt.condition, env, state)
    branch = if truthy?(condition), do: stmt.then_branch, else: stmt.else_branch

    if branch do
      exec(branch, env, state)
    else
      {:ok, env, state}
    end
  end

  defp exec(%While{} = loop, env, state) do
    {value, env, state} = eval(loop.condition, env, state)

    if truthy?(value) do
      case exec(loop.body, env, state) do
        {:ok, env, state} -> exec(loop, env, state)
        {{:continue, _}, env, state} -> exec(loop, env, state)
        {{:break, _}, env, state} -> {:ok, env, state}
        other -> other
      end
    else
      {:ok, env, state}
    end
  end

  defp exec(%Break{span: span}, env, state) do
    {{:break, span}, env, state}
  end

  defp exec(%Continue{span: span}, env, state) do
    {{:continue, span}, env, state}
  end

  @spec eval(Ast.expr(), Env.t(), State.t()) :: {value(), Env.t(), State.t()}
  defp eval(%Literal{value: value}, env, state) do
    {value, env, state}
  end

  defp eval(%Grouping{expr: expr}, env, state) do
    eval(expr, env, state)
  end

  defp eval(%Binary{op: :and, left: left, right: right}, env, state) do
    {left, env, state} = eval(left, env, state)
    if truthy?(left), do: eval(right, env, state), else: {left, env, state}
  end

  defp eval(%Binary{op: :or, left: left, right: right}, env, state) do
    {left, env, state} = eval(left, env, state)
    if truthy?(left), do: {left, env, state}, else: eval(right, env, state)
  end

  defp eval(%Binary{op: op, left: left, right: right, span: span}, env, state) do
    {a, env, state} = eval(left, env, state)
    {b, env, state} = eval(right, env, state)
    {binary(op, a, b, span), env, state}
  end

  defp eval(%Unary{op: op, expr: expr, span: span}, env, state) do
    {value, env, state} = eval(expr, env, state)
    {unary(op, value, span), env, state}
  end

  defp eval(%Assign{} = assign, env, state) do
    {value, env, state} = eval(assign.value, env, state)
    state = Env.assign(assign.name, value, assign.span, env, state)
    {value, env, state}
  end

  defp eval(%Var{name: name, span: span}, env, state) do
    value = Env.lookup(name, span, env, state)
    {value, env, state}
  end

  defp binary(:add, a, b, _) when is_binary(a) and is_binary(b), do: a <> b

  defp binary(op, a, b, s) when op in [:add, :sub, :mul, :div] and is_float(a) and is_float(b) do
    if op == :div and b == 0.0, do: raise(Error, kind: :division_by_zero, span: s)
    arith(op, a, b)
  rescue
    ArithmeticError -> reraise Error, [kind: :overflow, span: s], __STACKTRACE__
  end

  defp binary(:lt, a, b, _) when is_float(a) and is_float(b), do: a < b
  defp binary(:le, a, b, _) when is_float(a) and is_float(b), do: a <= b
  defp binary(:gt, a, b, _) when is_float(a) and is_float(b), do: a > b
  defp binary(:ge, a, b, _) when is_float(a) and is_float(b), do: a >= b
  defp binary(:eq, a, b, _), do: a == b
  defp binary(:ne, a, b, _), do: a != b
  defp binary(op, _, _, s), do: raise(Error, kind: {:invalid_operands, op}, span: s)

  defp arith(:add, a, b), do: a + b
  defp arith(:sub, a, b), do: a - b
  defp arith(:mul, a, b), do: a * b
  defp arith(:div, a, b), do: a / b

  defp unary(:neg, value, _) when is_float(value), do: -value
  defp unary(:not, value, _), do: not truthy?(value)
  defp unary(op, _, s), do: raise(Error, kind: {:invalid_operand, op}, span: s)

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_), do: true

  defp stringify(nil), do: "nil"
  defp stringify(b) when is_boolean(b), do: to_string(b)
  defp stringify(n) when is_float(n) and n == trunc(n), do: Integer.to_string(trunc(n))
  defp stringify(n) when is_float(n), do: Float.to_string(n)
  defp stringify(s) when is_binary(s), do: s
end

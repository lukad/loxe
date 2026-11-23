defmodule Loxe.Interpreter do
  @moduledoc """
  Runs Lox programs parsed by `Loxe.Parser`.

  Supported so far: expression statements, `print`, `var`, blocks, `if`,
  `while`, `for`, `break`, `continue`, functions, `return`, and literal,
  grouping, variable, assignment, call, unary and binary expressions.

  ## Values

  Values are `nil`, booleans, floats, strings and functions
  (`t:value/0`). `nil` and `false` are falsy. Everything else is truthy, including `0.0` and `""`.

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

  `for (init; condition; update) body` runs `init` once, then loops like
  `while`, evaluating `update` after each iteration, including one cut
  short by `continue`. Any of the three clauses can be left out. Without
  a condition, the loop runs until `break`. A variable declared in `init`
  is local to the loop.

  ## Functions

  `fun name(params) { body }` declares a function the same way `var`
  declares a variable, so it is a global at the top level and local in a
  block. Functions are values: they can be assigned, passed as arguments
  and returned.

  A call evaluates the callee, then the arguments from left to right, then
  runs the body with each parameter bound to its argument. Calling
  something that isn't a function, or passing the wrong number of
  arguments, is an error.

  `return expr;` ends the call, and the call evaluates to `expr`. A bare
  `return;`, or reaching the end of the body, returns `nil`. Using
  `return` outside a function is an error. So is using `break` or
  `continue` outside a loop in a function body, even when the function is
  called from inside a loop.

  Functions are closures: they can use the variables of the scope they
  were declared in, even after that scope has ended, and share them with
  it. They can't see variables declared after them in the same block, or
  the variables of the scope they're called from. Globals are looked up
  when they're used, so top-level functions can call functions declared
  after them.

  `fun (params) { body }` is an anonymous function. It evaluates to a
  function without declaring a name, and otherwise works like a declared
  one. It can only call itself through a variable that holds it. That
  works for a global, as in `var f = fun () { f(); };`, but not for a
  local, because the function captures its scope before the variable is
  declared.

  ## Output

  `print` writes the value and a newline to `state.out` (see
  `Loxe.Interpreter.State`). Numbers with no fractional part are printed
  without a decimal point, so `print 3;` prints `3`. Strings are printed
  without quotes. Functions are printed as `<fun name>`, or `<fun>` if
  they're anonymous.
  """

  alias Loxe.Ast

  alias Loxe.Ast.{
    Assign,
    Binary,
    Block,
    Break,
    Call,
    Continue,
    ExprStmt,
    For,
    Fun,
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

  alias Loxe.Ast.Lambda
  alias Loxe.Ast.Return
  alias Loxe.Interpreter.Closure
  alias Loxe.Interpreter.Env
  alias Loxe.Interpreter.Error
  alias Loxe.Interpreter.State

  @typedoc "A Lox value."
  @type value() :: nil | boolean() | float() | String.t() | Closure.t()

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
      {:ok, :global, state} -> {:ok, state}
      {tag, _env, _state} -> stray!(tag)
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

  # defp eval(nil, env)

  defp exec(%VarDecl{name: %Ident{name: n}, value: expr}, env, state) do
    {value, env, state} = if expr, do: eval(expr, env, state), else: {nil, env, state}
    {env, state} = Env.declare(n, value, env, state)
    {:ok, env, state}
  end

  defp exec(%Fun{name: name, span: span} = fun, env, state) do
    {env, state} = Env.declare(name.name, nil, env, state)
    closure = %Closure{fun: fun, env: env}
    state = Env.assign(name.name, closure, span, env, state)
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
    loop(loop.condition, loop.body, nil, env, state)
  end

  defp exec(%For{} = loop, env, state) do
    inner = Env.scope(env)

    {:ok, inner, state} =
      case loop.init do
        nil ->
          {:ok, inner, state}

        %VarDecl{} = decl ->
          exec(decl, inner, state)

        expr ->
          {_, inner, state} = eval(expr, inner, state)
          {:ok, inner, state}
      end

    {tag, _inner, state} = loop(loop.condition, loop.body, loop.update, inner, state)
    {tag, env, state}
  end

  defp exec(%Break{span: span}, env, state) do
    {{:break, span}, env, state}
  end

  defp exec(%Continue{span: span}, env, state) do
    {{:continue, span}, env, state}
  end

  defp exec(%Return{expr: expr, span: span}, env, state) do
    {value, env, state} = if expr, do: eval(expr, env, state), else: {nil, env, state}
    {{:return, value, span}, env, state}
  end

  @spec eval(Ast.expr(), Env.t(), State.t()) :: {value(), Env.t(), State.t()}
  defp eval(%Literal{value: value}, env, state) do
    {value, env, state}
  end

  defp eval(%Lambda{} = fun, env, state) do
    {%Closure{fun: fun, env: env}, env, state}
  end

  defp eval(%Call{} = call, env, state) do
    {fun, env, state} = eval(call.callee, env, state)

    {args, {env, state}} =
      Enum.map_reduce(call.args, {env, state}, fn arg, {env, state} ->
        {value, env, state} = eval(arg, env, state)
        {value, {env, state}}
      end)

    {value, state} = call(fun, args, call.span, state)
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
  defp stringify(%Closure{fun: %Fun{name: %Ident{name: name}}}), do: "<fun #{name}>"
  defp stringify(%Closure{fun: %Lambda{}}), do: "<fun>"

  defp loop(condition, body, update, env, state) do
    {value, env, state} =
      if condition do
        eval(condition, env, state)
      else
        {true, env, state}
      end

    if truthy?(value) do
      case exec(body, env, state) do
        {:ok, env, state} -> continue_loop(condition, body, update, env, state)
        {{:continue, _}, env, state} -> continue_loop(condition, body, update, env, state)
        {{:break, _}, env, state} -> {:ok, env, state}
        other -> other
      end
    else
      {:ok, env, state}
    end
  end

  defp continue_loop(condition, body, update, env, state) do
    {_, env, state} =
      if update do
        eval(update, env, state)
      else
        {nil, env, state}
      end

    loop(condition, body, update, env, state)
  end

  defp call(%Closure{} = closure, args, span, state) do
    expected = length(closure.fun.params)
    got = length(args)

    if expected != got do
      raise Error, kind: {:arity, expected, got}, span: span
    end

    {scope, state} =
      closure.fun.params
      |> Enum.zip(args)
      |> Enum.reduce({Env.scope(closure.env), state}, fn {%Ident{name: name}, value}, {scope, state} ->
        Env.declare(name, value, scope, state)
      end)

    case exec(closure.fun.body, scope, state) do
      {:ok, _scope, state} -> {nil, state}
      {{:return, value, _span}, _scope, state} -> {value, state}
      {tag, _scope, _state} -> stray!(tag)
    end
  end

  defp call(_callee, _args, span, _state) do
    raise Error, kind: :not_callable, span: span
  end

  defp stray!({kind, span}) when kind in [:break, :continue] do
    raise Error, kind: {:outside_loop, kind}, span: span
  end

  defp stray!({:return, _value, span}) do
    raise Error, kind: :outside_function, span: span
  end
end

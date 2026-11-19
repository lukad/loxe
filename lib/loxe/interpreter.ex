defmodule Loxe.Interpreter do
  @moduledoc """
  Evaluates `Loxe.Ast` expressions.

  Only `Loxe.Ast.Literal`, `Loxe.Ast.Binary` and `Loxe.Ast.Unary` are
  supported so far.

  ## Values

  Values are `nil`, booleans, floats and strings (`t:value/0`). `nil` and
  `false` are falsey. Everything else is truthy, including `0.0` and `""`.

  ## Operators

    * `+` adds two numbers or concatenates two strings.
    * `-`, `*`, `/`, `<`, `<=`, `>` and `>=` take two numbers.
    * `==` and `!=` take any two values. Values of different types are
      never equal.
    * `and` and `or` short-circuit and return one of their operands, not a
      boolean: `nil or "x"` is `"x"`.
    * Unary `-` takes a number. `!` takes any value and returns a boolean.

  Using an operator on the wrong types, dividing by zero, or getting a
  result too large for a float raises a `Loxe.Interpreter.Error`. There is
  no infinity or NaN.
  """

  alias Loxe.Interpreter.Error
  alias Loxe.Ast

  alias Loxe.Ast.{
    Binary,
    Literal,
    Unary
  }

  @typedoc "A Lox value."
  @type value() :: nil | boolean() | float() | String.t()

  @doc """
  Evaluates `expr` and returns its value.

  Raises `Loxe.Interpreter.Error` on a type error, division by zero or
  overflow.

  ## Examples

      iex> {:ok, tokens} = Loxe.Lexer.lex("(1 + 2) * 3;", 0)
      iex> {:ok, [%Loxe.Ast.ExprStmt{expr: expr}]} = Loxe.Parser.parse(tokens)
      iex> Loxe.Interpreter.eval(expr)
      9.0

      iex> {:ok, tokens} = Loxe.Lexer.lex(~s(1 + "a";), 0)
      iex> {:ok, [%Loxe.Ast.ExprStmt{expr: expr}]} = Loxe.Parser.parse(tokens)
      iex> Loxe.Interpreter.eval(expr)
      ** (Loxe.Interpreter.Error) invalid operands for + at 0..7

  """
  @spec eval(Ast.expr()) :: value()
  def eval(%Literal{value: value}) do
    value
  end

  def eval(%Binary{op: :and, left: left, right: right}) do
    left = eval(left)
    if truthy?(left), do: eval(right), else: left
  end

  def eval(%Binary{op: :or, left: left, right: right}) do
    left = eval(left)
    if truthy?(left), do: left, else: eval(right)
  end

  def eval(%Binary{op: op, left: left, right: right, span: span}) do
    a = eval(left)
    b = eval(right)
    binary(op, a, b, span)
  end

  def eval(%Unary{op: op, expr: expr, span: span}) do
    value = eval(expr)
    unary(op, value, span)
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
end

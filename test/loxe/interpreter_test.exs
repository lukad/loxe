defmodule Loxe.InterpreterTest do
  use ExUnit.Case, async: true
  doctest Loxe.Interpreter

  alias Loxe.{Interpreter, Lexer, Parser, Span}
  alias Loxe.Ast.{Binary, ExprStmt, Literal, Unary}
  alias Loxe.Interpreter.Error

  @span %Span{source_id: 0, start: 0, end: 0}

  defp lit(value), do: %Literal{value: value, span: @span}

  defp bin(op, l, r, span \\ @span),
    do: %Binary{op: op, left: to_node(l), right: to_node(r), span: span}

  defp unary(op, e, span \\ @span), do: %Unary{op: op, expr: to_node(e), span: span}

  defp to_node(%{span: _} = node), do: node
  defp to_node(value), do: lit(value)

  defp eval(expr), do: Interpreter.eval(to_node(expr))

  defp error(expr) do
    assert_raise Error, fn -> eval(expr) end
  end

  defp boom, do: unary(:neg, "boom")

  describe "literals" do
    test "evaluate to their value" do
      for value <- [nil, true, false, 0.0, 1.5, "", "hello"] do
        assert eval(lit(value)) === value
      end
    end
  end

  describe "arithmetic" do
    test "+ adds numbers" do
      assert eval(bin(:add, 1.0, 2.0)) == 3.0
    end

    test "+ concatenates strings" do
      assert eval(bin(:add, "foo", "bar")) == "foobar"
      assert eval(bin(:add, "", "")) == ""
    end

    test "-, * and /" do
      assert eval(bin(:sub, 5.0, 3.0)) == 2.0
      assert eval(bin(:mul, 4.0, 2.5)) == 10.0
      assert eval(bin(:div, 7.0, 2.0)) == 3.5
    end

    test "nested expressions" do
      # (1 + 2) * (10 - 4) / 3
      expr = bin(:div, bin(:mul, bin(:add, 1.0, 2.0), bin(:sub, 10.0, 4.0)), 3.0)
      assert eval(expr) == 6.0
    end

    test "+ with mixed types is an error" do
      for {a, b} <- [{1.0, "a"}, {"a", 1.0}, {nil, nil}, {true, 1.0}] do
        assert %Error{kind: {:invalid_operands, :add}} = error(bin(:add, a, b))
      end
    end

    test "-, * and / on non-numbers are errors" do
      for op <- [:sub, :mul, :div], {a, b} <- [{"a", "b"}, {1.0, nil}, {false, 2.0}] do
        assert %Error{kind: {:invalid_operands, ^op}} = error(bin(op, a, b))
      end
    end

    test "division by zero is an error" do
      assert %Error{kind: :division_by_zero} = error(bin(:div, 1.0, 0.0))
      assert %Error{kind: :division_by_zero} = error(bin(:div, 0.0, 0.0))
      assert %Error{kind: :division_by_zero} = error(bin(:div, 1.0, -0.0))
    end

    test "overflow is an error" do
      for {op, a, b} <- [
            {:add, 1.0e308, 1.0e308},
            {:sub, -1.0e308, 1.0e308},
            {:mul, 1.0e308, 10.0},
            {:div, 1.0e308, 1.0e-10}
          ] do
        assert %Error{kind: :overflow} = error(bin(op, a, b))
      end
    end

    test "underflow rounds to zero" do
      assert eval(bin(:mul, 1.0e-308, 1.0e-308)) == 0.0
    end

    test "a type error wins over division by zero" do
      assert %Error{kind: {:invalid_operands, :div}} = error(bin(:div, "a", 0.0))
    end
  end

  describe "comparison" do
    test "on numbers" do
      assert eval(bin(:lt, 1.0, 2.0)) == true
      assert eval(bin(:lt, 2.0, 2.0)) == false
      assert eval(bin(:le, 2.0, 2.0)) == true
      assert eval(bin(:le, 3.0, 2.0)) == false
      assert eval(bin(:gt, 3.0, 2.0)) == true
      assert eval(bin(:gt, 2.0, 2.0)) == false
      assert eval(bin(:ge, 2.0, 2.0)) == true
      assert eval(bin(:ge, 1.0, 2.0)) == false
    end

    test "on non-numbers is an error" do
      for op <- [:lt, :le, :gt, :ge], {a, b} <- [{"a", "b"}, {1.0, "a"}, {nil, nil}] do
        assert %Error{kind: {:invalid_operands, ^op}} = error(bin(op, a, b))
      end
    end
  end

  describe "equality" do
    test "values of the same type" do
      assert eval(bin(:eq, 1.0, 1.0)) == true
      assert eval(bin(:eq, 1.0, 2.0)) == false
      assert eval(bin(:eq, "a", "a")) == true
      assert eval(bin(:eq, "a", "b")) == false
      assert eval(bin(:eq, true, true)) == true
      assert eval(bin(:eq, true, false)) == false
      assert eval(bin(:eq, nil, nil)) == true
    end

    test "values of different types are never equal" do
      for {a, b} <- [{nil, false}, {0.0, false}, {"1", 1.0}, {"", nil}] do
        assert eval(bin(:eq, a, b)) == false
        assert eval(bin(:ne, a, b)) == true
      end
    end

    test "!= is the negation of ==" do
      assert eval(bin(:ne, 1.0, 1.0)) == false
      assert eval(bin(:ne, 1.0, 2.0)) == true
    end

    test "0 equals -0" do
      assert eval(bin(:eq, 0.0, -0.0)) == true
    end
  end

  describe "logical operators" do
    test "and returns the left operand if it is falsey" do
      assert eval(bin(:and, nil, "x")) == nil
      assert eval(bin(:and, false, "x")) == false
    end

    test "and returns the right operand if the left is truthy" do
      assert eval(bin(:and, 1.0, "x")) == "x"
      assert eval(bin(:and, true, nil)) == nil
    end

    test "or returns the left operand if it is truthy" do
      assert eval(bin(:or, "x", nil)) == "x"
      assert eval(bin(:or, 0.0, true)) == 0.0
    end

    test "or returns the right operand if the left is falsey" do
      assert eval(bin(:or, nil, "x")) == "x"
      assert eval(bin(:or, false, false)) == false
    end

    test "and does not evaluate the right side if the left is falsey" do
      assert eval(bin(:and, false, boom())) == false
    end

    test "or does not evaluate the right side if the left is truthy" do
      assert eval(bin(:or, true, boom())) == true
    end

    test "the right side is evaluated when needed" do
      assert_raise Error, fn -> eval(bin(:and, true, boom())) end
      assert_raise Error, fn -> eval(bin(:or, false, boom())) end
    end
  end

  describe "unary operators" do
    test "- negates a number" do
      assert eval(unary(:neg, 3.0)) == -3.0
      assert eval(unary(:neg, unary(:neg, 3.0))) == 3.0
    end

    test "- on a non-number is an error" do
      for value <- ["a", nil, true] do
        assert %Error{kind: {:invalid_operand, :neg}} = error(unary(:neg, value))
      end
    end

    test "! returns false for truthy values" do
      for value <- [true, 0.0, 1.0, "", "a"] do
        assert eval(unary(:not, value)) == false
      end
    end

    test "! returns true for nil and false" do
      assert eval(unary(:not, nil)) == true
      assert eval(unary(:not, false)) == true
    end

    test "!! converts a value to a boolean" do
      assert eval(unary(:not, unary(:not, "a"))) == true
      assert eval(unary(:not, unary(:not, nil))) == false
    end
  end

  describe "errors" do
    test "error span is the failing expression's span" do
      span = %Span{source_id: 0, start: 4, end: 11}
      expr = bin(:add, 1.0, bin(:mul, "a", 2.0, span))
      assert error(expr).span == span
    end

    test "unary error span" do
      span = %Span{source_id: 0, start: 2, end: 6}
      assert error(unary(:neg, "a", span)).span == span
    end

    test "operands are evaluated before the operator's type check" do
      assert %Error{kind: :division_by_zero} = error(bin(:add, "a", bin(:div, 1.0, 0.0)))
    end

    test "messages" do
      span = %Span{source_id: 0, start: 3, end: 9}

      assert Exception.message(error(bin(:add, 1.0, "a", span))) ==
               "invalid operands for + at 3..9"

      assert Exception.message(error(bin(:ge, "a", "b", span))) ==
               "invalid operands for >= at 3..9"

      assert Exception.message(error(unary(:neg, "a", span))) == "invalid operand for - at 3..9"
      assert Exception.message(error(bin(:div, 1.0, 0.0, span))) == "division by zero at 3..9"
      assert Exception.message(error(bin(:mul, 1.0e308, 10.0, span))) == "overflow at 3..9"
    end
  end

  describe "source code" do
    defp run(src) do
      {:ok, tokens} = Lexer.lex(src <> ";", 0)
      {:ok, [%ExprStmt{expr: expr}]} = Parser.parse(tokens)
      Interpreter.eval(expr)
    end

    test "precedence" do
      assert run("1 + 2 * 3") == 7.0
      assert run("(1 + 2) * 3") == 9.0
      assert run("10 - 4 - 3") == 3.0
      assert run("-2 * 3") == -6.0
    end

    test "string concatenation" do
      assert run(~s("a" + "b" + "c")) == "abc"
    end

    test "equality and logic" do
      assert run("1 + 1 == 2") == true
      assert run(~s(nil or "default")) == "default"
      assert run("1 == 1 and 2 != 2") == false
    end

    test "error span points at the source" do
      src = ~s|1 + (2 * "x")|
      error = assert_raise Error, fn -> run(src) end
      assert binary_part(src, error.span.start, error.span.end - error.span.start) == ~s(2 * "x")
    end
  end
end

defmodule Loxe.InterpreterTest do
  use ExUnit.Case, async: true
  doctest Loxe.Interpreter

  alias Loxe.{Interpreter, Lexer, Parser, Span}
  alias Loxe.Ast.{Binary, Ident, Literal, Unary, VarDecl}
  alias Loxe.Interpreter.{Error, State}

  @span %Span{source_id: 0, start: 0, end: 0}

  defp lit(value), do: %Literal{value: value, span: @span}

  defp bin(op, l, r, span \\ @span),
    do: %Binary{op: op, left: to_node(l), right: to_node(r), span: span}

  defp unary(op, e, span \\ @span), do: %Unary{op: op, expr: to_node(e), span: span}

  defp to_node(%{span: _} = node), do: node
  defp to_node(value), do: lit(value)

  # Evaluates `expr` by running `var result = expr;`.
  defp run_expr(expr) do
    decl = %VarDecl{name: %Ident{name: "result", span: @span}, value: to_node(expr), span: @span}
    Interpreter.run([decl])
  end

  defp eval(expr) do
    {:ok, state} = run_expr(expr)
    state.globals["result"]
  end

  defp error(expr) do
    {:error, %Error{} = error} = run_expr(expr)
    error
  end

  defp parse!(src) do
    {:ok, tokens} = Lexer.lex(src, 0)
    {:ok, decls} = Parser.parse(tokens)
    decls
  end

  # Runs `src` and returns what it printed.
  defp output(src) do
    {:ok, io} = StringIO.open("")
    {:ok, _state} = Interpreter.run(parse!(src), %State{out: io})
    {:ok, {"", out}} = StringIO.close(io)
    out
  end

  defp run_error(src) do
    {:error, %Error{} = error} = Interpreter.run(parse!(src))
    error
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
    test "and returns the left operand if it is falsy" do
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

    test "or returns the right operand if the left is falsy" do
      assert eval(bin(:or, nil, "x")) == "x"
      assert eval(bin(:or, false, false)) == false
    end

    test "and does not evaluate the right side if the left is falsy" do
      assert eval(bin(:and, false, boom())) == false
    end

    test "or does not evaluate the right side if the left is truthy" do
      assert eval(bin(:or, true, boom())) == true
    end

    test "the right side is evaluated when needed" do
      assert %Error{} = error(bin(:and, true, boom()))
      assert %Error{} = error(bin(:or, false, boom()))
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

  describe "expressions from source" do
    defp run(src) do
      {:ok, state} = Interpreter.run(parse!("var result = #{src};"))
      state.globals["result"]
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

    test "comparison" do
      assert run("1 < 2") == true
      assert run("2 <= 2") == true
      assert run("1 > 2") == false
      assert run("2 >= 3") == false
      assert run("1 + 1 >= 2 == true") == true
    end

    test "equality and logic" do
      assert run("1 + 1 == 2") == true
      assert run(~s(nil or "default")) == "default"
      assert run("1 == 1 and 2 != 2") == false
    end

    test "error span points at the source" do
      src = ~s|print 1 + (2 * "x");|
      error = run_error(src)

      assert binary_part(src, error.span.start, error.span.end - error.span.start) ==
               ~s|(2 * "x")|
    end
  end

  describe "print" do
    test "numbers without a fractional part have no decimal point" do
      assert output("print 3; print -2; print 1000000; print 0;") == "3\n-2\n1000000\n0\n"
    end

    test "numbers with a fractional part" do
      assert output("print 2.5; print -0.25; print 1 / 4;") == "2.5\n-0.25\n0.25\n"
    end

    test "strings are printed without quotes" do
      assert output(~s(print "hello"; print "";)) == "hello\n\n"
    end

    test "nil and booleans" do
      assert output("print nil; print true; print false;") == "nil\ntrue\nfalse\n"
    end

    test "output is in program order" do
      assert output("print 1; print 2; print 3;") == "1\n2\n3\n"
    end

    test "nothing after an error runs" do
      {:ok, io} = StringIO.open("")
      decls = parse!(~s(print 1; print -"a"; print 2;))
      assert {:error, %Error{}} = Interpreter.run(decls, %State{out: io})
      assert StringIO.contents(io) == {"", "1\n"}
    end
  end

  describe "global variables" do
    test "declaration with an initializer" do
      assert output("var a = 1 + 2; print a;") == "3\n"
    end

    test "declaration without an initializer is nil" do
      assert output("var a; print a;") == "nil\n"
    end

    test "globals can be redeclared" do
      assert output("var a = 1; var a = 2; print a;") == "2\n"
    end

    test "assignment" do
      assert output("var a = 1; a = a + 1; print a;") == "2\n"
    end

    test "assignment evaluates to the assigned value" do
      assert output("var a; print a = 3;") == "3\n"
    end

    test "chained assignment" do
      assert output("var a; var b; a = b = 5; print a; print b;") == "5\n5\n"
    end

    test "globals are returned in the state" do
      {:ok, state} = Interpreter.run(parse!(~s(var a = 1; var b = "x";)))
      assert state.globals == %{"a" => 1.0, "b" => "x"}
    end

    test "running with an earlier state keeps its globals" do
      {:ok, state} = Interpreter.run(parse!("var a = 1;"))
      {:ok, state} = Interpreter.run(parse!("a = a + 1;"), state)
      assert state.globals["a"] == 2.0
    end

    test "empty program" do
      assert {:ok, %State{}} = Interpreter.run([])
    end
  end

  describe "undefined variables" do
    test "reading" do
      assert %Error{kind: {:undefined_variable, "a"}} = run_error("print a;")
    end

    test "assigning" do
      assert %Error{kind: {:undefined_variable, "a"}} = run_error("a = 1;")
    end

    test "using a variable in its own initializer" do
      assert %Error{kind: {:undefined_variable, "a"}} = run_error("var a = a;")
    end

    test "read span covers the name" do
      src = "print 1 + foo;"
      assert run_error(src).span == %Span{source_id: 0, start: 10, end: 13}
    end

    test "assignment span covers the assignment" do
      src = "foo = 1 + 2;"
      assert run_error(src).span == %Span{source_id: 0, start: 0, end: 11}
    end

    test "message" do
      assert Exception.message(run_error("print foo;")) == "undefined variable foo at 6..9"
    end
  end

  describe "blocks" do
    test "run their statements in order" do
      assert output("{ print 1; print 2; }") == "1\n2\n"
    end

    test "empty block" do
      assert output("{} print 1;") == "1\n"
    end

    test "locals are not visible after the block" do
      assert %Error{kind: {:undefined_variable, "a"}} = run_error("{ var a = 1; } print a;")
    end

    test "locals are not added to the globals" do
      {:ok, state} = Interpreter.run(parse!("{ var a = 1; }"))
      assert state.globals == %{}
    end

    test "can read and assign globals" do
      assert output("var a = 1; { print a; a = 2; } print a;") == "1\n2\n"
    end

    test "a local shadows a global" do
      assert output(~s(var a = "global"; { var a = "local"; print a; } print a;)) ==
               "local\nglobal\n"
    end

    test "a local shadows an outer local" do
      src = ~s({ var a = "outer"; { var a = "inner"; print a; } print a; })
      assert output(src) == "inner\nouter\n"
    end

    test "nested blocks see outer locals" do
      assert output("{ var a = 1; { { print a; } } }") == "1\n"
    end

    test "assigning an outer local from a nested block" do
      assert output("{ var a = 1; { a = 2; } print a; }") == "2\n"
    end

    test "assigning a shadowing local leaves the outer one unchanged" do
      assert output("{ var a = 1; { var a = 2; a = 3; } print a; }") == "1\n"
    end

    test "an initializer can read the shadowed variable" do
      assert output("var a = 1; { var a = a + 1; print a; } print a;") == "2\n1\n"
    end

    test "locals can be redeclared in the same block" do
      assert output("{ var a = 1; var a = 2; print a; }") == "2\n"
    end
  end
end

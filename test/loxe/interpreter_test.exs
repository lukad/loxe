defmodule Loxe.InterpreterTest do
  use ExUnit.Case, async: true

  alias Loxe.Ast.{Binary, Grouping, Ident, Literal, Unary, VarDecl}
  alias Loxe.{Interpreter, Lexer, Parser, Span}
  alias Loxe.Interpreter.{Error, State}

  doctest Loxe.Interpreter

  @span %Span{source_id: 0, start: 0, end: 0}

  defp lit(value), do: %Literal{value: value, span: @span}

  defp bin(op, l, r, span \\ @span), do: %Binary{op: op, left: to_node(l), right: to_node(r), span: span}

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

  describe "grouping" do
    test "evaluates to the inner expression" do
      assert eval(%Grouping{expr: bin(:add, 1.0, 2.0), span: @span}) == 3.0
      assert eval(%Grouping{expr: %Grouping{expr: lit("a"), span: @span}, span: @span}) == "a"
    end

    test "errors inside keep the inner span" do
      span = %Span{source_id: 0, start: 1, end: 8}
      group = %Grouping{expr: bin(:add, 1.0, "a", span), span: @span}
      assert error(group).span == span
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

      assert binary_part(src, error.span.start, error.span.end - error.span.start) == ~s(2 * "x")
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

  describe "if" do
    test "runs the then branch when the condition is true" do
      assert output("if (true) print 1; else print 2;") == "1\n"
    end

    test "runs the else branch when the condition is false" do
      assert output("if (false) print 1; else print 2;") == "2\n"
    end

    test "does nothing when the condition is false and there is no else" do
      assert output("if (false) print 1; print 2;") == "2\n"
    end

    test "falsy conditions" do
      for condition <- ["nil", "false"] do
        assert output("if (#{condition}) print 1; else print 2;") == "2\n", condition
      end
    end

    test "truthy conditions" do
      for condition <- ["true", "0", ~s(""), ~s("a"), "1 - 1"] do
        assert output("if (#{condition}) print 1; else print 2;") == "1\n", condition
      end
    end

    test "condition with logical operators" do
      assert output(~s|if (nil or "x") print 1;|) == "1\n"
      assert output("if (true and nil) print 1; else print 2;") == "2\n"
    end

    test "the condition is evaluated once" do
      assert output("var a = 0; if (a = a + 1) print a; print a;") == "1\n1\n"
    end

    test "the branch not taken is not evaluated" do
      assert output(~s|if (true) print 1; else print -"a";|) == "1\n"
      assert output(~s|if (false) print -"a"; else print 2;|) == "2\n"
    end

    test "else belongs to the nearest if" do
      assert output("if (true) if (false) print 1; else print 2;") == "2\n"
      assert output("if (false) if (true) print 1; else print 2;") == ""
    end

    test "else if chains" do
      src = fn n ->
        "var n = #{n}; if (n == 1) print 1; else if (n == 2) print 2; else print 3;"
      end

      assert output(src.(1)) == "1\n"
      assert output(src.(2)) == "2\n"
      assert output(src.(5)) == "3\n"
    end

    test "branches can assign outer variables" do
      assert output("var a = 1; if (true) a = 2; print a;") == "2\n"
      assert output("{ var a = 1; if (false) {} else { a = 3; } print a; }") == "3\n"
    end

    test "a block branch has its own scope" do
      assert %Error{kind: {:undefined_variable, "a"}} =
               run_error("if (true) { var a = 1; } print a;")
    end

    test "an error in the condition is returned" do
      assert %Error{kind: {:invalid_operand, :neg}} = run_error(~s|if (-"a") print 1;|)
    end

    test "an error in the taken branch is returned" do
      assert %Error{kind: :division_by_zero} = run_error("if (true) print 1 / 0;")
    end
  end

  describe "while" do
    test "runs the body while the condition is truthy" do
      assert output("var i = 0; while (i < 3) { print i; i = i + 1; }") == "0\n1\n2\n"
    end

    test "never runs the body if the condition starts false" do
      assert output("while (false) print 1; print 2;") == "2\n"
    end

    test "the condition is evaluated before each iteration" do
      assert output("var i = 0; while ((i = i + 1) < 3) print i; print i;") == "1\n2\n3\n"
    end

    test "each iteration gets a fresh block scope" do
      src = "var i = 0; while (i < 2) { var x; print x; x = i; i = i + 1; }"
      assert output(src) == "nil\nnil\n"
    end

    test "body locals are not visible after the loop" do
      assert %Error{kind: {:undefined_variable, "x"}} =
               run_error("var i = 0; while (i < 1) { var x = 1; i = i + 1; } print x;")
    end

    test "an error in the body stops the loop" do
      {:ok, io} = StringIO.open("")
      decls = parse!(~s|var i = 0; while (true) { print i; i = i + 1; if (i == 2) -"a"; }|)

      assert {:error, %Error{kind: {:invalid_operand, :neg}}} =
               Interpreter.run(decls, %State{out: io})

      assert StringIO.contents(io) == {"", "0\n1\n"}
    end

    test "many iterations" do
      src = "var i = 0; while (i < 100000) i = i + 1; print i;"
      assert output(src) == "100000\n"
    end
  end

  describe "for" do
    test "with all clauses" do
      assert output("for (var i = 0; i < 3; i = i + 1) print i;") == "0\n1\n2\n"
    end

    test "runs neither the body nor the update if the condition starts false" do
      assert output("var a = 0; for (; false; a = 1) print 1; print a;") == "0\n"
    end

    test "the initializer runs once, before the condition" do
      src = "var n = 0; for (n = n + 1; n < 3; n = n + 1) print n; print n;"
      assert output(src) == "1\n2\n3\n"
    end

    test "the update runs after the body and before the condition" do
      src = """
      var log = "";
      for (var i = 0; (log = log + "c") and i < 2; log = log + "u") {
        log = log + "b";
        i = i + 1;
      }
      print log;
      """

      assert output(src) == "cbucbuc\n"
    end

    test "without an initializer" do
      assert output("var i = 0; for (; i < 2; i = i + 1) print i;") == "0\n1\n"
    end

    test "without an update" do
      assert output("for (var i = 0; i < 2;) { print i; i = i + 1; }") == "0\n1\n"
    end

    test "without a condition loops until break" do
      src = "for (var i = 0;; i = i + 1) { if (i == 3) break; print i; }"
      assert output(src) == "0\n1\n2\n"
    end

    test "with every clause left out" do
      assert output("var i = 0; for (;;) { i = i + 1; if (i == 3) break; } print i;") == "3\n"
    end

    test "falsy and truthy conditions" do
      assert output("for (; nil;) print 1; for (; false;) print 2; print 3;") == "3\n"
      assert output(~s|for (; "";) { print 1; break; }|) == "1\n"
      assert output("for (; 0;) { print 1; break; }") == "1\n"
    end

    test "the loop variable is not visible after the loop" do
      assert %Error{kind: {:undefined_variable, "i"}} =
               run_error("for (var i = 0; i < 1; i = i + 1) {} print i;")
    end

    test "the loop variable is not a global" do
      {:ok, state} = Interpreter.run(parse!("for (var i = 0; i < 2; i = i + 1) {}"))
      assert state.globals == %{}
    end

    test "the loop variable shadows an outer variable" do
      src = "var i = 10; for (var i = 0; i < 2; i = i + 1) print i; print i;"
      assert output(src) == "0\n1\n10\n"

      src = "{ var i = 10; for (var i = 0; i < 2; i = i + 1) print i; print i; }"
      assert output(src) == "0\n1\n10\n"
    end

    test "the loop variable's initializer can read the shadowed variable" do
      assert output("var i = 5; for (var i = i + 1; i < 8; i = i + 1) print i;") == "6\n7\n"
    end

    test "an assignment initializer changes the outer variable" do
      assert output("var i; for (i = 0; i < 3; i = i + 1) {} print i;") == "3\n"
      assert output("{ var i; for (i = 0; i < 3; i = i + 1) {} print i; }") == "3\n"
    end

    test "the body can assign outer variables" do
      src = "var sum = 0; for (var i = 1; i <= 4; i = i + 1) sum = sum + i; print sum;"
      assert output(src) == "10\n"
    end

    test "each iteration gets a fresh block scope" do
      src = "for (var i = 0; i < 2; i = i + 1) { var x; print x; x = i; }"
      assert output(src) == "nil\nnil\n"
    end

    test "body locals are not visible after the loop" do
      assert %Error{kind: {:undefined_variable, "x"}} =
               run_error("for (var i = 0; i < 1; i = i + 1) { var x = 1; } print x;")
    end

    test "the body can shadow the loop variable" do
      src = "for (var i = 0; i < 2; i = i + 1) { var i = 9; print i; }"
      assert output(src) == "9\n9\n"
    end

    test "nested loops" do
      src = """
      for (var i = 0; i < 2; i = i + 1)
        for (var j = 0; j < 2; j = j + 1)
          print i * 10 + j;
      """

      assert output(src) == "0\n1\n10\n11\n"
    end

    test "an error in the initializer is returned" do
      assert %Error{kind: {:invalid_operand, :neg}} = run_error(~s|for (var i = -"a";;) {}|)
      assert %Error{kind: {:invalid_operand, :neg}} = run_error(~s|for (-"a";;) {}|)
    end

    test "an error in the condition is returned" do
      assert %Error{kind: {:invalid_operand, :neg}} = run_error(~s|for (; -"a";) {}|)
    end

    test "an error in the update stops the loop" do
      {:ok, io} = StringIO.open("")
      decls = parse!(~s|for (var i = 0; i < 5; i = i - "a") print i;|)

      assert {:error, %Error{kind: {:invalid_operands, :sub}}} =
               Interpreter.run(decls, %State{out: io})

      assert StringIO.contents(io) == {"", "0\n"}
    end

    test "an error in the body stops the loop" do
      {:ok, io} = StringIO.open("")
      decls = parse!(~s|for (var i = 0;; i = i + 1) { print i; if (i == 1) -"a"; }|)

      assert {:error, %Error{kind: {:invalid_operand, :neg}}} =
               Interpreter.run(decls, %State{out: io})

      assert StringIO.contents(io) == {"", "0\n1\n"}
    end

    test "many iterations" do
      src = "var n = 0; for (var i = 0; i < 100000; i = i + 1) n = n + 1; print n;"
      assert output(src) == "100000\n"
    end

    test "break leaves the loop without running the update" do
      src = "var i; for (i = 0; i < 5; i = i + 1) { if (i == 2) break; } print i;"
      assert output(src) == "2\n"
    end

    test "break only leaves the innermost loop" do
      src = """
      for (var i = 0; i < 2; i = i + 1) {
        for (;;) { print i; break; }
      }
      """

      assert output(src) == "0\n1\n"
      assert output("for (var i = 0; i < 2; i = i + 1) { while (true) break; print i; }") == "0\n1\n"
    end

    test "break does not leak the loop variable or body locals" do
      assert %Error{kind: {:undefined_variable, "i"}} =
               run_error("for (var i = 0;;) { break; } print i;")

      assert %Error{kind: {:undefined_variable, "x"}} =
               run_error("for (;;) { var x = 1; break; } print x;")
    end

    test "globals declared after the loop are still globals" do
      {:ok, state} = Interpreter.run(parse!("for (var i = 0;;) { break; } var y = 2;"))
      assert state.globals == %{"y" => 2.0}
    end

    test "continue runs the update" do
      src = "for (var i = 0; i < 4; i = i + 1) { if (i == 1) continue; print i; }"
      assert output(src) == "0\n2\n3\n"
    end

    test "continue from a nested block" do
      src = "for (var i = 0; i < 2; i = i + 1) { { { continue; } } print i; } print 9;"
      assert output(src) == "9\n"
    end

    test "continue only affects the innermost loop" do
      src = """
      for (var i = 0; i < 2; i = i + 1) {
        for (var j = 0; j < 2; j = j + 1) { continue; print j; }
        print i;
      }
      """

      assert output(src) == "0\n1\n"
    end

    test "break after the loop is an error" do
      assert %Error{kind: {:outside_loop, :break}} =
               run_error("for (var i = 0; i < 1; i = i + 1) {} break;")
    end
  end

  describe "break" do
    test "leaves the loop" do
      assert output("while (true) { print 1; break; print 2; } print 3;") == "1\n3\n"
    end

    test "from inside an if" do
      src = "var i = 0; while (true) { if (i == 2) break; print i; i = i + 1; }"
      assert output(src) == "0\n1\n"
    end

    test "from a nested block" do
      assert output("while (true) { { { break; } } print 1; } print 2;") == "2\n"
    end

    test "only leaves the innermost loop" do
      src = """
      var i = 0;
      while (i < 2) {
        while (true) { print i; break; }
        i = i + 1;
      }
      """

      assert output(src) == "0\n1\n"
    end

    test "keeps changes made before it" do
      assert output("var a = 1; while (true) { a = 2; break; } print a;") == "2\n"
    end

    test "does not leak block locals" do
      # Regression: `break` used to carry the block's scope out of the loop.
      assert %Error{kind: {:undefined_variable, "x"}} =
               run_error("while (true) { var x = 1; break; } print x;")

      assert output("var x = 0; { while (true) { var x = 1; break; } print x; }") == "0\n"
    end

    test "globals declared after the loop are still globals" do
      {:ok, state} = Interpreter.run(parse!("while (true) { var x = 1; break; } var y = 2;"))
      assert state.globals == %{"y" => 2.0}
    end
  end

  describe "continue" do
    test "skips the rest of the body" do
      src = "var i = 0; while (i < 4) { i = i + 1; if (i == 2) continue; print i; }"
      assert output(src) == "1\n3\n4\n"
    end

    test "from a nested block" do
      src = "var i = 0; while (i < 2) { i = i + 1; { { continue; } } print i; } print 9;"
      assert output(src) == "9\n"
    end

    test "only affects the innermost loop" do
      src = """
      var i = 0;
      while (i < 2) {
        var j = 0;
        while (j < 2) { j = j + 1; continue; print j; }
        print i;
        i = i + 1;
      }
      """

      assert output(src) == "0\n1\n"
    end

    test "re-evaluates the condition" do
      assert output("var i = 0; while (i < 3) { i = i + 1; continue; } print i;") == "3\n"
    end
  end

  describe "break and continue outside a loop" do
    test "at the top level" do
      assert %Error{kind: {:outside_loop, :break}} = run_error("break;")
      assert %Error{kind: {:outside_loop, :continue}} = run_error("continue;")
    end

    test "in a block or if" do
      assert %Error{kind: {:outside_loop, :break}} = run_error("{ { break; } }")
      assert %Error{kind: {:outside_loop, :continue}} = run_error("if (true) continue;")
    end

    test "after a loop" do
      assert %Error{kind: {:outside_loop, :break}} = run_error("while (false) {} break;")
    end

    test "statements before it still run" do
      {:ok, io} = StringIO.open("")

      assert {:error, %Error{}} =
               Interpreter.run(parse!("print 1; break; print 2;"), %State{out: io})

      assert StringIO.contents(io) == {"", "1\n"}
    end

    test "span covers the statement" do
      src = "print 1; { break; }"
      assert run_error(src).span == %Span{source_id: 0, start: 11, end: 17}
    end

    test "messages" do
      assert Exception.message(run_error("break;")) == "break outside a loop at 0..6"
      assert Exception.message(run_error("continue;")) == "continue outside a loop at 0..9"
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

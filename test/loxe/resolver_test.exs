defmodule Loxe.ResolverTest do
  use ExUnit.Case, async: true

  alias Loxe.{Lexer, Parser, Resolver, Span}
  alias Loxe.Resolver.Error

  doctest Loxe.Resolver

  defp check(src) do
    {:ok, tokens} = Lexer.lex(src, 0)
    {:ok, decls} = Parser.parse(tokens)
    Resolver.check(decls)
  end

  defp error(src) do
    {:error, %Error{} = error} = check(src)
    error
  end

  defp span(src, text) do
    {start, len} = :binary.match(src, text)
    %Span{source_id: 0, start: start, end: start + len}
  end

  describe "valid programs" do
    test "empty program" do
      assert check("") == :ok
    end

    test "a program using every kind of node" do
      src = """
      var g = 1;
      fun f(a, b) {
        var c = -(a + b) * 2;
        c = f(c, fun (d) { return -d; });
        if (c == nil or false) print c; else print "x";
        while (c) { c = nil; break; }
        for (var i = 0; i < 2; i = i + 1) { continue; }
        return c;
      }
      """

      assert check(src) == :ok
    end

    test "globals can be redeclared" do
      assert check("var a = 1; var a = 2; fun a() {} fun a() {}") == :ok
    end

    test "global initializers are not checked" do
      assert check("var a = a;") == :ok
      assert check("var a = 1; var a = a + 1;") == :ok
    end

    test "a local can shadow an outer local or a global" do
      assert check("var a; { var a; { var a; } }") == :ok
    end

    test "parameters can shadow outer variables" do
      assert check("var a; fun f(a) {}") == :ok
      assert check("{ var a; fun f(a) {} }") == :ok
    end

    test "a nested block in a function body can shadow a parameter" do
      assert check("fun f(a) { { var a; } }") == :ok
    end

    test "an initializer can read other variables" do
      assert check("{ var a = 1; var b = a; }") == :ok
      assert check("{ var a = 1; { var b = a; } }") == :ok
    end

    test "local functions can call themselves" do
      assert check("{ fun f() { f(); } }") == :ok
    end

    test "unknown names are left to the interpreter" do
      assert check("fun f() { print x; x = 1; }") == :ok
      assert check("{ fun f() { g(); } fun g() {} }") == :ok
    end

    test "for loop variables are scoped to the loop" do
      assert check("for (var i = 0;;) {} for (var i = 0;;) {}") == :ok
      assert check("{ var i; for (var i = 0;;) {} }") == :ok
      assert check("{ for (var i = 0;;) {} for (var i = 0;;) {} }") == :ok
    end

    test "a for body can shadow the loop variable" do
      assert check("for (var i = 0;;) { var i; }") == :ok
    end

    test "break and continue in loops" do
      assert check("while (true) break;") == :ok
      assert check("while (true) { { continue; } }") == :ok
      assert check("for (;;) if (true) break; else continue;") == :ok
      assert check("while (true) { while (true) break; break; }") == :ok
    end

    test "break and continue in a loop in a function" do
      assert check("fun f() { while (true) { break; } }") == :ok
      assert check("var f = fun () { for (;;) continue; };") == :ok
    end

    test "return in functions" do
      assert check("fun f() { return; }") == :ok
      assert check("fun f() { while (true) { if (true) return 1; } }") == :ok
      assert check("var f = fun () { return 1; };") == :ok
      assert check("fun f() { fun g() { return; } return g; }") == :ok
    end
  end

  describe "already declared" do
    test "two variables in a block" do
      assert %Error{kind: {:already_declared, "a"}} = error("{ var a = 1; var a = 2; }")
    end

    test "a variable and a function" do
      assert %Error{kind: {:already_declared, "a"}} = error("{ var a; fun a() {} }")
      assert %Error{kind: {:already_declared, "a"}} = error("{ fun a() {} var a; }")
    end

    test "two parameters" do
      assert %Error{kind: {:already_declared, "a"}} = error("fun f(a, a) {}")
      assert %Error{kind: {:already_declared, "a"}} = error("var f = fun (a, b, a) {};")
    end

    test "a parameter and a local in the function body" do
      assert %Error{kind: {:already_declared, "a"}} = error("fun f(a) { var a; }")
      assert %Error{kind: {:already_declared, "a"}} = error("fun f(a) { fun a() {} }")
    end

    test "two locals in a function body" do
      assert %Error{kind: {:already_declared, "b"}} = error("fun f() { var b; var b; }")
    end

    test "span covers the second name" do
      src = "{ var a; var a = 1; }"
      assert error(src).span == %Span{source_id: 0, start: 13, end: 14}
    end
  end

  describe "own initializer" do
    test "reading a local in its own initializer" do
      assert %Error{kind: {:own_initializer, "a"}} = error("{ var a = a; }")
      assert %Error{kind: {:own_initializer, "a"}} = error("{ var a = 1 + (a * 2); }")
    end

    test "even when an outer variable has the same name" do
      assert %Error{kind: {:own_initializer, "a"}} = error("var a = 1; { var a = a + 1; }")
      assert %Error{kind: {:own_initializer, "a"}} = error("{ var a = 1; { var a = a; } }")
    end

    test "from an anonymous function in the initializer" do
      assert %Error{kind: {:own_initializer, "f"}} = error("{ var f = fun () { f(); }; }")
    end

    test "in a for initializer, even at the top level" do
      assert %Error{kind: {:own_initializer, "i"}} = error("for (var i = i;;) {}")
    end

    test "span covers the read" do
      assert error("{ var abc = 1 + abc; }").span == %Span{source_id: 0, start: 16, end: 19}
    end
  end

  describe "break and continue outside a loop" do
    test "at the top level or in a block" do
      assert %Error{kind: {:outside_loop, :break}} = error("break;")
      assert %Error{kind: {:outside_loop, :continue}} = error("{ { continue; } }")
    end

    test "in either branch of an if" do
      assert %Error{kind: {:outside_loop, :break}} = error("if (true) break;")
      assert %Error{kind: {:outside_loop, :continue}} = error("if (true) {} else continue;")
    end

    test "after a loop" do
      assert %Error{kind: {:outside_loop, :break}} = error("while (true) {} break;")
      assert %Error{kind: {:outside_loop, :break}} = error("for (;;) {} break;")
    end

    test "in a function called from a loop" do
      assert %Error{kind: {:outside_loop, :break}} = error("while (true) { fun f() { break; } }")

      assert %Error{kind: {:outside_loop, :continue}} =
               error("for (;;) { fun () { continue; }(); }")
    end

    test "in a function that is never called" do
      assert %Error{kind: {:outside_loop, :break}} = error("fun f() { break; }")
    end

    test "span covers the statement" do
      src = "print 1; { break; }"
      assert error(src).span == span(src, "break;")
    end
  end

  describe "return outside a function" do
    test "at the top level" do
      assert %Error{kind: :outside_function} = error("return;")
      assert %Error{kind: :outside_function} = error("return 1;")
    end

    test "in a block, loop or if" do
      assert %Error{kind: :outside_function} = error("{ return; }")
      assert %Error{kind: :outside_function} = error("while (true) return;")
      assert %Error{kind: :outside_function} = error("if (true) {} else return;")
    end

    test "after a function" do
      assert %Error{kind: :outside_function} = error("fun f() {} return;")
    end

    test "the returned value is checked" do
      assert %Error{kind: {:own_initializer, "f"}} = error("{ var f = fun () { return f; }; }")
    end

    test "span covers the statement" do
      src = "print 1; return 2;"
      assert error(src).span == span(src, "return 2;")
    end
  end

  test "the first error is returned" do
    assert %Error{kind: {:outside_loop, :break}} = error("break; return;")
    assert %Error{kind: :outside_function} = error("return; break;")
  end

  test "messages" do
    assert Exception.message(error("{ var a; var a; }")) ==
             "a is already declared in this scope at 13..14"

    assert Exception.message(error("{ var a = a; }")) ==
             "can't read a in its own initializer at 10..11"

    assert Exception.message(error("break;")) == "break outside a loop at 0..6"
    assert Exception.message(error("continue;")) == "continue outside a loop at 0..9"
    assert Exception.message(error("return;")) == "return outside a function at 0..7"
  end
end

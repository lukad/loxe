defmodule Loxe.ParserTest do
  use ExUnit.Case, async: true
  doctest Loxe.Parser

  alias Loxe.{Lexer, Parser, Span}
  alias Loxe.Parser.Error

  alias Loxe.Ast.{
    Assign,
    Binary,
    Block,
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

  defp parse(src) do
    {:ok, tokens} = Lexer.lex(src, 0)
    Parser.parse(tokens)
  end

  defp parse!(src) do
    {:ok, decls} = parse(src)
    decls
  end

  defp error(src) do
    {:error, %Error{} = err} = parse(src)
    err
  end

  # Parses `src` as a single expression statement and returns the
  # expression as an S-expression string, ignoring spans.
  defp sexp(src) do
    [%ExprStmt{expr: expr}] = parse!(src <> ";")
    to_sexp(expr)
  end

  defp to_sexp(%Literal{value: nil}), do: "nil"
  defp to_sexp(%Literal{value: v}) when is_binary(v), do: inspect(v)
  defp to_sexp(%Literal{value: v}), do: to_string(v)
  defp to_sexp(%Var{name: name}), do: name
  defp to_sexp(%Unary{op: op, expr: e}), do: "(#{op} #{to_sexp(e)})"
  defp to_sexp(%Binary{op: op, left: l, right: r}), do: "(#{op} #{to_sexp(l)} #{to_sexp(r)})"
  defp to_sexp(%Assign{name: name, value: v}), do: "(= #{name} #{to_sexp(v)})"
  defp to_sexp(%Get{object: o, name: n}), do: "(get #{to_sexp(o)} #{n.name})"

  defp to_sexp(%Set{object: o, name: n, value: v}),
    do: "(set #{to_sexp(o)} #{n.name} #{to_sexp(v)})"

  defp to_sexp(%Call{callee: c, args: args}) do
    "(call #{Enum.map_join([c | args], " ", &to_sexp/1)})"
  end

  defp span(src, text) do
    {start, len} = :binary.match(src, text)
    %Span{source_id: 0, start: start, end: start + len}
  end

  test "empty program" do
    assert parse("") == {:ok, []}
    assert parse("// only a comment") == {:ok, []}
  end

  describe "literals and variables" do
    test "literals" do
      assert sexp("1") == "1.0"
      assert sexp("2.5") == "2.5"
      assert sexp(~s("hi")) == ~s("hi")
      assert sexp("true") == "true"
      assert sexp("false") == "false"
      assert sexp("nil") == "nil"
    end

    test "variable" do
      assert sexp("x") == "x"
    end
  end

  describe "operators" do
    test "arithmetic" do
      assert sexp("a + b") == "(add a b)"
      assert sexp("a - b") == "(sub a b)"
      assert sexp("a * b") == "(mul a b)"
      assert sexp("a / b") == "(div a b)"
    end

    test "comparison" do
      assert sexp("a < b") == "(lt a b)"
      assert sexp("a <= b") == "(le a b)"
      assert sexp("a > b") == "(gt a b)"
      assert sexp("a >= b") == "(ge a b)"
    end

    test "equality" do
      assert sexp("a == b") == "(eq a b)"
      assert sexp("a != b") == "(ne a b)"
    end

    test "logical" do
      assert sexp("a and b") == "(and a b)"
      assert sexp("a or b") == "(or a b)"
    end

    test "* binds tighter than +" do
      assert sexp("a + b * c") == "(add a (mul b c))"
      assert sexp("a * b + c") == "(add (mul a b) c)"
    end

    test "+ binds tighter than <" do
      assert sexp("a < b + c") == "(lt a (add b c))"
    end

    test "< binds tighter than ==" do
      assert sexp("a == b < c") == "(eq a (lt b c))"
    end

    test "== binds tighter than and" do
      assert sexp("a and b == c") == "(and a (eq b c))"
    end

    test "and binds tighter than or" do
      assert sexp("a or b and c") == "(or a (and b c))"
      assert sexp("a and b or c") == "(or (and a b) c)"
    end

    test "binary operators are left associative" do
      assert sexp("a - b - c") == "(sub (sub a b) c)"
      assert sexp("a / b / c") == "(div (div a b) c)"
      assert sexp("a < b < c") == "(lt (lt a b) c)"
      assert sexp("a == b == c") == "(eq (eq a b) c)"
      assert sexp("a or b or c") == "(or (or a b) c)"
    end

    test "parentheses override precedence" do
      assert sexp("(a + b) * c") == "(mul (add a b) c)"
      assert sexp("a - (b - c)") == "(sub a (sub b c))"
      assert sexp("((a))") == "a"
    end

    test "unary minus" do
      assert sexp("-a") == "(neg a)"
      assert sexp("--a") == "(neg (neg a))"
    end

    test "unary minus binds tighter than binary operators" do
      assert sexp("-a * b") == "(mul (neg a) b)"
      assert sexp("a - -b") == "(sub a (neg b))"
    end

    test "unary minus binds looser than calls and property access" do
      assert sexp("-f()") == "(neg (call f))"
      assert sexp("-a.b") == "(neg (get a b))"
    end
  end

  describe "calls and property access" do
    test "calls" do
      assert sexp("f()") == "(call f)"
      assert sexp("f(a)") == "(call f a)"
      assert sexp("f(a, b + c)") == "(call f a (add b c))"
    end

    test "chained calls" do
      assert sexp("f(a)(b)") == "(call (call f a) b)"
    end

    test "property access" do
      assert sexp("a.b") == "(get a b)"
      assert sexp("a.b.c") == "(get (get a b) c)"
    end

    test "method calls" do
      assert sexp("a.b(c)") == "(call (get a b) c)"
      assert sexp("a.b().c") == "(get (call (get a b)) c)"
    end

    test "property access on a grouped expression" do
      assert sexp("(a + b).c") == "(get (add a b) c)"
    end
  end

  describe "assignment" do
    test "variable assignment" do
      assert sexp("a = 1") == "(= a 1.0)"
    end

    test "assignment is right associative" do
      assert sexp("a = b = c") == "(= a (= b c))"
    end

    test "assignment binds looser than or" do
      assert sexp("a = b or c") == "(= a (or b c))"
    end

    test "property assignment" do
      assert sexp("a.b = 1") == "(set a b 1.0)"
      assert sexp("a.b.c = 1") == "(set (get a b) c 1.0)"
      assert sexp("f().x = 1") == "(set (call f) x 1.0)"
    end

    test "assignment inside call arguments" do
      assert sexp("f(a = 1)") == "(call f (= a 1.0))"
    end

    test "invalid targets" do
      for src <- ["1 = 2;", "a + b = c;", "f() = 1;", "-a = 1;"] do
        assert %Error{kind: :invalid_assign_target} = error(src), src
      end
    end

    test "invalid target span covers the left side" do
      src = "a + b = c;"
      assert error(src).span == span(src, "a + b")
    end
  end

  describe "statements" do
    test "expression statement" do
      assert [%ExprStmt{expr: %Call{}}] = parse!("f();")
    end

    test "print" do
      assert [%Print{expr: %Literal{value: 1.0}}] = parse!("print 1;")
    end

    test "return with a value" do
      assert [%Return{expr: %Var{name: "x"}}] = parse!("return x;")
    end

    test "return without a value" do
      assert [%Return{expr: nil}] = parse!("return;")
    end

    test "empty block" do
      assert [%Block{body: []}] = parse!("{}")
    end

    test "block" do
      assert [%Block{body: [%VarDecl{}, %Print{}]}] = parse!("{ var a = 1; print a; }")
    end

    test "nested blocks" do
      assert [%Block{body: [%Block{body: [%Block{body: []}]}]}] = parse!("{ { {} } }")
    end

    test "if" do
      assert [%If{condition: %Var{name: "x"}, then_branch: %Print{}, else_branch: nil}] =
               parse!("if (x) print 1;")
    end

    test "if with else" do
      assert [%If{then_branch: %Print{}, else_branch: %Block{}}] =
               parse!("if (x) print 1; else {}")
    end

    test "else belongs to the nearest if" do
      assert [%If{then_branch: %If{else_branch: %Print{}}, else_branch: nil}] =
               parse!("if (a) if (b) print 1; else print 2;")
    end

    test "else if" do
      assert [%If{else_branch: %If{else_branch: %Print{}}}] =
               parse!("if (a) print 1; else if (b) print 2; else print 3;")
    end

    test "while" do
      assert [%While{condition: %Binary{op: :lt}, body: %Block{}}] = parse!("while (i < 10) {}")
    end

    test "for with all clauses" do
      assert [
               %For{
                 init: %VarDecl{name: %Ident{name: "i"}, value: %Literal{value: +0.0}},
                 condition: %Binary{op: :lt},
                 update: %Assign{name: "i"},
                 body: %Print{}
               }
             ] = parse!("for (var i = 0; i < 10; i = i + 1) print i;")
    end

    test "for with an expression as init" do
      assert [%For{init: %Assign{name: "i"}}] = parse!("for (i = 0; i < 10;) {}")
    end

    test "for with every clause left out" do
      assert [%For{init: nil, condition: nil, update: nil, body: %Block{}}] =
               parse!("for (;;) {}")
    end

    test "for with a var init and no initializer" do
      assert [%For{init: %VarDecl{value: nil}}] = parse!("for (var i;;) {}")
    end
  end

  describe "declarations" do
    test "var with an initializer" do
      assert [%VarDecl{name: %Ident{name: "a"}, value: %Binary{op: :add}}] =
               parse!("var a = 1 + 2;")
    end

    test "var without an initializer" do
      assert [%VarDecl{name: %Ident{name: "a"}, value: nil}] = parse!("var a;")
    end

    test "function without parameters" do
      assert [%Fun{name: %Ident{name: "f"}, params: [], body: %Block{body: []}}] =
               parse!("fun f() {}")
    end

    test "function with parameters" do
      assert [%Fun{params: params, body: %Block{body: [%Return{}]}}] =
               parse!("fun add(a, b, c) { return a + b + c; }")

      assert Enum.map(params, & &1.name) == ["a", "b", "c"]
    end

    test "declarations are returned in source order" do
      assert [%Fun{name: %Ident{name: "a"}}, %Fun{name: %Ident{name: "b"}}, %Print{}] =
               parse!("fun a() {} fun b() {} print 1;")
    end

    test "declarations inside a function body" do
      assert [%Fun{body: %Block{body: [%VarDecl{}, %Fun{}, %Return{}]}}] =
               parse!("fun outer() { var x = 1; fun inner() {} return inner; }")
    end
  end

  describe "spans" do
    test "statement spans include the semicolon" do
      src = "  print 1;  "
      assert [%Print{span: span}] = parse!(src)
      assert span == span(src, "print 1;")
    end

    test "expression statement span" do
      src = "f(a, b);"
      assert [%ExprStmt{span: stmt, expr: %Call{span: call}}] = parse!(src)
      assert stmt == span(src, "f(a, b);")
      assert call == span(src, "f(a, b)")
    end

    test "grouped expression span includes the parentheses" do
      src = "(a + b) * c;"
      assert [%ExprStmt{expr: %Binary{span: span, left: left}}] = parse!(src)
      assert span == span(src, "(a + b) * c")
      assert left.span == span(src, "(a + b)")
    end

    test "binary span" do
      src = "x = a + b * c;"
      assert [%ExprStmt{expr: %Assign{span: assign, value: %Binary{span: binary}}}] = parse!(src)
      assert assign == span(src, "x = a + b * c")
      assert binary == span(src, "a + b * c")
    end

    test "unary span" do
      src = "-a;"
      assert [%ExprStmt{expr: %Unary{span: span}}] = parse!(src)
      assert span == span(src, "-a")
    end

    test "property access and set spans" do
      src = "a.b.c = 1;"
      assert [%ExprStmt{expr: %Set{span: set, object: %Get{span: get}}}] = parse!(src)
      assert set == span(src, "a.b.c = 1")
      assert get == span(src, "a.b")
    end

    test "var spans" do
      src = "var a = 1;"
      assert [%VarDecl{span: span, name: name}] = parse!(src)
      assert span == span(src, src)
      assert name.span == %Span{source_id: 0, start: 4, end: 5}
    end

    test "function span runs from fun to the closing brace" do
      src = "fun f(a) { print a; }"
      assert [%Fun{span: span, body: body}] = parse!(src)
      assert span == span(src, src)
      assert body.span == span(src, "{ print a; }")
    end

    test "if span ends at the end of the else branch" do
      src = "if (x) print 1; else print 2;"
      assert [%If{span: span}] = parse!(src)
      assert span == span(src, src)
    end

    test "loop spans end at the end of the body" do
      for src <- ["while (x) { }", "for (;;) print 1;"] do
        assert [%{span: span}] = parse!(src)
        assert span == span(src, src)
      end
    end
  end

  describe "errors" do
    test "missing semicolon" do
      assert %Error{kind: {:expected, :semicolon, :eof}, span: %Span{start: 7, end: 7}} =
               error("print 1")
    end

    test "missing expression" do
      assert %Error{kind: {:expected_expression, :semicolon}, span: %Span{start: 6, end: 7}} =
               error("print ;")
    end

    test "missing variable name" do
      assert %Error{kind: {:expected, :ident, :equal}} = error("var = 1;")
    end

    test "unclosed parenthesis" do
      assert %Error{kind: {:expected, :rparen, :semicolon}} = error("(a + b;")
    end

    test "unclosed block" do
      assert %Error{kind: {:expected, :rbrace, :eof}} = error("{ print 1;")
    end

    test "stray closing brace" do
      assert %Error{kind: {:expected_expression, :rbrace}} = error("}")
    end

    test "if without parentheses" do
      assert %Error{kind: {:expected, :lparen, :ident}} = error("if x print 1;")
    end

    test "declaration as an if branch" do
      assert %Error{kind: {:expected_expression, :var}} = error("if (x) var y = 1;")
    end

    test "declaration as a loop body" do
      assert %Error{kind: {:expected_expression, :fun}} = error("while (x) fun f() {}")
    end

    test "for with too few clauses" do
      assert %Error{kind: {:expected_expression, :rparen}} = error("for (;) {}")
    end

    test "trailing comma in arguments" do
      assert %Error{kind: {:expected_expression, :rparen}} = error("f(a,);")
    end

    test "trailing comma in parameters" do
      assert %Error{kind: {:expected, :ident, :rparen}} = error("fun f(a,) {}")
    end

    test "non-identifier parameter" do
      assert %Error{kind: {:expected, :ident, :number}} = error("fun f(1) {}")
    end

    test "function without a body" do
      assert %Error{kind: {:expected, :lbrace, :semicolon}} = error("fun f();")
    end

    test "property access without a name" do
      assert %Error{kind: {:expected, :ident, :semicolon}} = error("a.;")
    end

    test "parsing stops at the first error" do
      assert %Error{kind: {:expected_expression, :semicolon}} = error("print ; print ;")
    end
  end

  describe "error messages" do
    test "expected token" do
      assert Exception.message(error("print 1")) == ~s(expected ";", found end of input at 7..7)
    end

    test "expected identifier" do
      assert Exception.message(error("var 1;")) == "expected identifier, found number at 4..5"
    end

    test "expected expression" do
      assert Exception.message(error("print nil + ;")) ==
               ~s(expected expression, found ";" at 12..13)
    end

    test "keywords are shown as source text" do
      assert Exception.message(error("print var;")) ==
               ~s(expected expression, found "var" at 6..9)
    end

    test "invalid assignment target" do
      assert Exception.message(error("1 = 2;")) == "invalid assignment target at 0..1"
    end
  end
end

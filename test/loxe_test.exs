defmodule LoxeTest do
  use ExUnit.Case, async: true

  alias Loxe.{Interpreter, Lexer, Parser, Resolver}
  alias Loxe.Interpreter.State

  doctest Loxe

  # Runs `src` and returns the result and what it printed.
  defp run(src, state \\ %State{}) do
    {:ok, io} = StringIO.open("")
    result = Loxe.run(src, %{state | out: io})
    {:ok, {"", out}} = StringIO.close(io)
    {result, out}
  end

  test "runs a program" do
    assert {{:ok, %State{}}, "3\n"} = run("var a = 1; print a + 2;")
  end

  test "an empty program" do
    assert {{:ok, %State{globals: globals}}, ""} = run("")
    assert globals == %{}
  end

  test "stops at a lexer error" do
    assert {{:error, %Lexer.Error{kind: :unterminated_string}}, ""} = run(~s|print 1; print "a;|)
  end

  test "stops at a parser error" do
    assert {{:error, %Parser.Error{kind: {:expected_expression, :semicolon}}}, ""} =
             run("print 1; print ;")
  end

  test "stops at a resolver error" do
    assert {{:error, %Resolver.Error{kind: {:already_declared, "a"}}}, ""} =
             run("print 1; { var a; var a; }")

    assert {{:error, %Resolver.Error{kind: {:outside_loop, :break}}}, ""} = run("print 1; break;")
  end

  test "a runtime error keeps what was printed before it" do
    assert {{:error, %Interpreter.Error{kind: {:invalid_operand, :neg}}}, "1\n"} =
             run(~s|print 1; print -"a"; print 2;|)
  end

  test "globals carry over when the returned state is passed back" do
    {{:ok, state}, ""} = run("var a = 1; fun inc() { a = a + 1; }")
    {{:ok, state}, ""} = run("inc(); inc();", state)
    assert {{:ok, _}, "3\n"} = run("print a;", state)
  end

  test "a failed run leaves the earlier state usable" do
    {{:ok, state}, ""} = run("var a = 1;")
    assert {{:error, %Interpreter.Error{}}, ""} = run(~s|a = 2; -"x";|, state)
    assert {{:ok, _}, "1\n"} = run("print a;", state)
  end

  test "spans record the source id" do
    for src <- [~s|"a|, "print ;", "break;", ~s|-"a";|] do
      assert {:error, %{span: %{source_id: 7}}} = Loxe.run(src, %State{}, 7), src
    end
  end

  test "errors from every stage have messages" do
    for src <- [~s|"a|, "print ;", "break;", ~s|-"a";|] do
      {:error, error} = Loxe.run(src)
      assert Exception.message(error) =~ ~r/ at \d+\.\.\d+$/, src
    end
  end
end

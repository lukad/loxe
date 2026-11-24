defmodule Loxe do
  @moduledoc """
  An interpreter for Lox, the language from
  [Crafting Interpreters](https://craftinginterpreters.com).

  `run/3` runs a program from source in four stages, and stops at the
  first one that fails:

    1. `Loxe.Lexer` splits the source into tokens.
    2. `Loxe.Parser` builds a `Loxe.Ast` from the tokens.
    3. `Loxe.Resolver` checks the scoping rules.
    4. `Loxe.Interpreter` runs the program.

  Each stage has its own error struct with a `kind` and a `span`, and
  `Exception.message/1` works on all of them.
  """

  alias Loxe.Interpreter
  alias Loxe.Interpreter.State
  alias Loxe.Lexer
  alias Loxe.Parser
  alias Loxe.Resolver

  @doc """
  Runs the Lox program in `source`.

  Returns `{:ok, state}` with the final state, or `{:error, error}` with
  the error from the first stage that failed. If the lexer, parser or
  resolver rejects the source, the program doesn't run and prints
  nothing. If it fails while running, what it printed before the error
  stays printed.

  Pass a `state` returned by an earlier call to keep its globals, as a
  REPL would. Every span records `source_id`, so a caller running several
  sources can tell which one an error came from.

  ## Examples

      iex> {:ok, state} = Loxe.run("var a = 1 + 2;")
      iex> state.globals["a"]
      3.0

      iex> {:ok, state} = Loxe.run("var a = 1;")
      iex> {:ok, state} = Loxe.run("a = a + 1;", state)
      iex> state.globals["a"]
      2.0

      iex> Loxe.run("{ var a = a; }")
      {:error,
       %Loxe.Resolver.Error{
         kind: {:own_initializer, "a"},
         span: %Loxe.Span{source_id: 0, start: 10, end: 11}
       }}

  """
  @spec run(String.t(), State.t(), non_neg_integer()) ::
          {:ok, State.t()}
          | {:error, Lexer.Error.t()}
          | {:error, Parser.Error.t()}
          | {:error, Resolver.Error.t()}
          | {:error, Interpreter.Error.t()}
  def run(source, state \\ %State{}, source_id \\ 0) do
    with {:ok, tokens} <- Lexer.lex(source, source_id),
         {:ok, decls} <- Parser.parse(tokens),
         :ok <- Resolver.check(decls) do
      Interpreter.run(decls, state)
    end
  end
end

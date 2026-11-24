defmodule Loxe.IEx.Helpers do
  @moduledoc false

  alias Loxe.Interpreter
  alias Loxe.Lexer
  alias Loxe.Parser
  alias Loxe.Resolver

  def run(source, source_id \\ 0) do
    with {:ok, tokens} <- Lexer.lex(source, source_id),
         {:ok, decls} <- Parser.parse(tokens),
         :ok <- Resolver.check(decls) do
      Interpreter.run(decls)
    end
  end
end

defmodule Loxe.Interpreter.Closure do
  @moduledoc """
  A function value: a `Loxe.Ast.Fun` declaration or `Loxe.Ast.Lambda`
  expression, and the scope it was evaluated in.

  `env` is internal.
  """

  alias Loxe.Ast.{Fun, Lambda}
  alias Loxe.Interpreter.Env

  defstruct [:fun, :env]

  @type t() :: %__MODULE__{
          fun: Fun.t() | Lambda.t(),
          env: Env.t()
        }
end

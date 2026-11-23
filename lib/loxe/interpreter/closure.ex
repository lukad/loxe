defmodule Loxe.Interpreter.Closure do
  @moduledoc """
  A function value: a `Loxe.Ast.Fun` declaration and the scope it was
  declared in.

  `env` is internal.
  """

  alias Loxe.Ast.Fun
  alias Loxe.Interpreter.Env

  defstruct [:fun, :env]

  @type t() :: %__MODULE__{
          fun: Fun.t(),
          env: Env.t()
        }
end

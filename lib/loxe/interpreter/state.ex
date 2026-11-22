defmodule Loxe.Interpreter.State do
  @moduledoc """
  The state of a running program, passed to and returned by
  `Loxe.Interpreter.run/2`.

    * `out` - the device `print` writes to. Defaults to `:stdio`.
    * `globals` - the global variables, by name.

  The other fields are internal.
  """

  alias Loxe.Interpreter

  defstruct globals: %{}, heap: %{}, next_ref: 0, out: :stdio

  @type t() :: %__MODULE__{
          globals: %{String.t() => Interpreter.value()},
          heap: %{non_neg_integer() => Interpreter.value()},
          next_ref: non_neg_integer(),
          out: IO.device()
        }

  @doc false
  def alloc(state, value) do
    ref = state.next_ref
    {ref, %{state | heap: Map.put(state.heap, ref, value), next_ref: ref + 1}}
  end

  @doc false
  def fetch(state, ref), do: Map.fetch!(state.heap, ref)

  @doc false
  def store(state, ref, value), do: %{state | heap: Map.put(state.heap, ref, value)}
end

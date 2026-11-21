defmodule Loxe.Interpreter.Env do
  # Maps local variable names to heap refs in `Loxe.Interpreter.State`.
  # `:global` means no local scope; lookups go straight to the globals.
  @moduledoc false

  alias Loxe.Interpreter.{Error, State}

  @type t :: :global | %{String.t() => non_neg_integer()}

  def scope(:global), do: %{}
  def scope(env), do: env

  def declare(name, value, :global, %State{} = state),
    do: {:global, %{state | globals: Map.put(state.globals, name, value)}}

  def declare(name, value, env, %State{} = state) do
    {ref, state} = State.alloc(state, value)
    {Map.put(env, name, ref), state}
  end

  def lookup(name, span, env, %State{} = state) do
    case env do
      %{^name => ref} ->
        State.fetch(state, ref)

      _ ->
        case Map.fetch(state.globals, name) do
          {:ok, value} -> value
          :error -> raise Error, kind: {:undefined_variable, name}, span: span
        end
    end
  end

  def assign(name, value, span, env, %State{} = state) do
    case env do
      %{^name => ref} ->
        State.store(state, ref, value)

      _ ->
        if Map.has_key?(state.globals, name),
          do: %State{state | globals: Map.put(state.globals, name, value)},
          else: raise(Error, kind: {:undefined_variable, name}, span: span)
    end
  end
end

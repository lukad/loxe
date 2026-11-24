defmodule Loxe.Resolver.Error do
  @moduledoc """
  Returned by `Loxe.Resolver.check/1` when a program breaks a scoping
  rule.

  `kind` is one of:

    * `{:already_declared, name}` - a local variable, function or
      parameter `name` was declared twice in the same scope, such as
      `{ var a; var a; }` or `fun f(a, a) {}`. `span` covers the second
      name.
    * `{:own_initializer, name}` - the local variable `name` was read in
      its own initializer, such as `{ var a = a; }`. `span` covers the
      read.
    * `{:outside_loop, keyword}` - a `break` or `continue` statement is
      outside a loop. `keyword` is `:break` or `:continue`, and `span`
      covers the statement.
    * `:outside_function` - a `return` statement is outside a function.
      `span` covers the statement.
  """

  defexception [:kind, :span]

  @type t() :: %__MODULE__{
          kind:
            {:already_declared, String.t()}
            | {:own_initializer, String.t()}
            | {:outside_loop, :break | :continue}
            | :outside_function,
          span: Loxe.Span.t()
        }

  @impl true
  def message(%{kind: kind, span: span}) do
    "#{describe(kind)} at #{span.start}..#{span.end}"
  end

  defp describe({:already_declared, name}), do: "#{name} is already declared in this scope"
  defp describe({:own_initializer, name}), do: "can't read #{name} in its own initializer"
  defp describe({:outside_loop, keyword}), do: "#{keyword} outside a loop"
  defp describe(:outside_function), do: "return outside a function"
end

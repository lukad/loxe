defmodule Loxe.Interpreter.Error do
  @moduledoc """
  Raised by `Loxe.Interpreter.eval/1` when evaluation fails.

  `span` covers the expression that failed. `kind` is one of:

    * `{:invalid_operands, op}` - the operands of the binary operator `op`
      have the wrong types, such as `1 + "a"` or `"a" < "b"`.
    * `{:invalid_operand, op}` - the operand of the unary operator `op` has
      the wrong type, such as `-"a"`.
    * `:division_by_zero` - the right side of `/` is zero.
    * `:overflow` - the result of `+`, `-`, `*` or `/` is too large for a
      float, such as multiplying the largest float by 10.
  """

  defexception [:kind, :span]

  @type t() :: %__MODULE__{
          kind:
            {:invalid_operands, Loxe.Ast.binary_op()}
            | {:invalid_operand, Loxe.Ast.unary_op()}
            | :division_by_zero
            | :overflow,
          span: Loxe.Span.t()
        }

  @impl true
  def message(%{kind: kind, span: span}) do
    "#{describe(kind)} at #{span.start}..#{span.end}"
  end

  defp describe({:invalid_operands, op}), do: "invalid operands for #{binary_symbol(op)}"
  defp describe({:invalid_operand, op}), do: "invalid operand for #{unary_symbol(op)}"
  defp describe(:division_by_zero), do: "division by zero"
  defp describe(:overflow), do: "overflow"

  defp binary_symbol(:or), do: "or"
  defp binary_symbol(:and), do: "and"
  defp binary_symbol(:eq), do: "=="
  defp binary_symbol(:ne), do: "!="
  defp binary_symbol(:lt), do: "<"
  defp binary_symbol(:le), do: "<="
  defp binary_symbol(:gt), do: ">"
  defp binary_symbol(:ge), do: ">="
  defp binary_symbol(:add), do: "+"
  defp binary_symbol(:sub), do: "-"
  defp binary_symbol(:mul), do: "*"
  defp binary_symbol(:div), do: "/"

  defp unary_symbol(:neg), do: "-"
  defp unary_symbol(:not), do: "!"
end

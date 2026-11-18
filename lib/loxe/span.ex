defmodule Loxe.Span do
  @moduledoc """
  Represents a location in a source file.
  """

  defstruct [:source_id, :start, :end]

  @type t() :: %__MODULE__{
          source_id: non_neg_integer(),
          start: non_neg_integer(),
          end: non_neg_integer()
        }

  @spec join(t(), t()) :: t()
  def join(%__MODULE__{source_id: source_id} = a, %__MODULE__{source_id: source_id} = b) do
    %__MODULE__{
      source_id: source_id,
      start: min(a.start, b.start),
      end: max(a.end, b.end)
    }
  end
end

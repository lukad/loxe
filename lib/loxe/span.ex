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
end

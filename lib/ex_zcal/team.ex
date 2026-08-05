defmodule ExZcal.Team do
  @moduledoc "The team a booked event belongs to, when the invite is a team invite."

  defstruct [:id, :name, :raw]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          raw: map()
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{} = raw) do
    %__MODULE__{id: raw["id"], name: raw["name"], raw: raw}
  end
end

defmodule ExZcal.Host do
  @moduledoc """
  A host of a booked event.

  For a **collective** team invite every team member on the event is listed; for
  a **round robin** invite the list holds the single member who was assigned.
  """

  defstruct [:name, :email, :raw]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          email: String.t() | nil,
          raw: map()
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{} = raw) do
    %__MODULE__{name: raw["name"], email: raw["email"], raw: raw}
  end
end

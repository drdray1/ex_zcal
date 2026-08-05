defmodule ExZcal.Invite do
  @moduledoc """
  The invite (booking link) an event was booked through.

  `id` is the identifier that appears in a `/i/<id>` booking URL, which makes it
  the natural key for mapping an incoming booking back to whichever of your
  users owns that link.

  `invite_type` is one of `"one_on_one"`, `"one_on_many"`, `"group"`,
  `"collective"`, or `"round_robin"`. It is kept as a string rather than an atom
  because zcal documents no exhaustive list and the payload is unversioned.
  """

  defstruct [:id, :name, :invite_type, :description, :raw]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          invite_type: String.t() | nil,
          description: String.t() | nil,
          raw: map()
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{} = raw) do
    %__MODULE__{
      id: raw["id"],
      name: raw["name"],
      invite_type: raw["inviteType"],
      description: raw["description"],
      raw: raw
    }
  end
end

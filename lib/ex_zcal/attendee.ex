defmodule ExZcal.Attendee do
  @moduledoc """
  Someone attending a booked event.

  `type` distinguishes the **invitee** — the person who actually booked, and the
  only attendee carrying `custom_question_answers` — from additional **guests**
  they invited. Unrecognized types are passed through as the raw string.
  """

  alias ExZcal.Answer

  defstruct [:name, :email, :timezone, :phone_number, :type, :answers, :raw]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          email: String.t() | nil,
          timezone: String.t() | nil,
          phone_number: String.t() | nil,
          type: :invitee | :guest | String.t() | nil,
          answers: [Answer.t()],
          raw: map()
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{} = raw) do
    %__MODULE__{
      name: raw["name"],
      email: raw["email"],
      timezone: raw["timezone"],
      phone_number: raw["phoneNumber"],
      type: type(raw["type"]),
      answers: answers(raw["customQuestionAnswers"]),
      raw: raw
    }
  end

  defp type("invitee"), do: :invitee
  defp type("guest"), do: :guest
  defp type(other), do: other

  defp answers(list) when is_list(list), do: Enum.map(list, &Answer.new/1)
  defp answers(_), do: []
end

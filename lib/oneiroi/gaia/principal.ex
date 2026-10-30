defmodule Oneiroi.Gaia.Principal do
  @moduledoc """
  Who a request is: an account, reached through a session (the client)
  or a token (a script). The web layer assigns one, the actor on every
  command is built from it, and the contract tests assert exactly which
  routes each kind may call (spec §7).
  """

  @enforce_keys [:account_id, :via]
  defstruct [:account_id, :email, :via]

  @type t :: %__MODULE__{account_id: String.t(), email: String.t() | nil, via: :session | :token}

  @doc "The actor a principal acts as: the witness, by account id."
  @spec actor(t()) :: Oneiroi.Actor.t()
  def actor(%__MODULE__{account_id: id}), do: Oneiroi.Actor.new(:witness, id)
end

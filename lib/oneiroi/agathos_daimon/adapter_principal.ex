defmodule Oneiroi.AgathosDaimon.AdapterPrincipal do
  @moduledoc """
  What an adapter's bearer token resolves to (spec §8): the resident it
  speaks for and the role it holds. The brain role gets the resident's
  own tools and captures; the hands roles get none of them in this phase.
  """
  # `via: :token` so the Origin check treats it as a script's bearer
  # (`OneiroiWeb.Plugs.Origin`), which it is.
  defstruct [:resident_id, :adapter, :role, via: :token]

  @type t :: %__MODULE__{
          resident_id: String.t(),
          adapter: String.t(),
          role: String.t(),
          via: :token
        }
end

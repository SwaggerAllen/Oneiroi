defmodule Oneiroi.Gaia.InviteRouter do
  @moduledoc "The invite aggregate's router (gaia#18): `invite-<id>`, one code and its SKU."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Gaia.Invite",
    prefix: "invite-",
    commands: "Oneiroi.Gaia.Commands",
    dispatching: ~w(IssueInvite RedeemInvite RevokeInvite)
end

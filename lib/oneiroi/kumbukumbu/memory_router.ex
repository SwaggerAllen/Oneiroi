defmodule Oneiroi.Kumbukumbu.MemoryRouter do
  @moduledoc "The memory aggregate's router: `memory-<resident_id>`, strong consistency and the actor middleware from `Oneiroi.Router`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Kumbukumbu.Memory",
    prefix: "memory-",
    commands: "Oneiroi.Kumbukumbu.MemoryCommands",
    dispatching:
      ~w(AddBookmark ExtendBookmark PinBookmark UnpinBookmark ProposeBookmark DeclineBookmarkProposal ProposeTag ApproveTag RejectTag CreateTag RetireTag ApplyTag RemoveTagging Revise AcceptRevision DeclineRevision)
end

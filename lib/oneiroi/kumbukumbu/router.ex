defmodule Oneiroi.Kumbukumbu.Router do
  @moduledoc "The conversation aggregate's router; strong consistency and the actor middleware come with `Oneiroi.Router`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Kumbukumbu.Conversation",
    prefix: "conversation-",
    commands: "Oneiroi.Kumbukumbu.Commands",
    dispatching:
      ~w(OpenSession StartTurn CaptureTurn RecordContext FailCapture ResolveCaptureFailure ShareSession)
end

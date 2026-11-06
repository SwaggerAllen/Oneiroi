defmodule Oneiroi.Gaia.FeedbackRouter do
  @moduledoc "The platform reports aggregate's router (gaia#20): `feedback-feedback`, one stream, numbered."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Gaia.Feedback",
    prefix: "feedback-",
    commands: "Oneiroi.Gaia.Commands",
    dispatching: ~w(FileFeedback MoveFeedback)
end

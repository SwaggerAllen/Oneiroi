defmodule Oneiroi.Brain.ForwardWorker do
  @moduledoc """
  A forward out of a sealed mail wake (kumbukumbu#98; the witness,
  2026-11-21: "we need a way for you to kick out of a sealed conversation
  and wake yourself unsealed so that you can forward anything that needs
  forwarding from a mail conversation without me having to check if a
  conversation is over"). Enqueued by `mail_forward`, it wakes the
  conversation she named, unsealed, with the forward she composed as its
  note. The session's queue runs it once the sealed turn has ended, so it
  fires as soon as that turn is captured. Runs once: a forward is never
  repeated.
  """
  use Oneiroi.Worker, queue: :brain_forward, max_attempts: 1

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Brain.Session

  def run(%{"resident_id" => resident_id, "session_key" => key, "note" => note}) do
    case Session.wake(resident_id, key, note, :chat) do
      {:ok, _answer} -> :ok
      other -> other
    end
  end

  @doc "Enqueues the unsealed wake of `session_key` carrying `note`."
  def enqueue(resident_id, session_key, note),
    do:
      Jobs.enqueue(__MODULE__, %{
        "resident_id" => resident_id,
        "session_key" => session_key,
        "note" => note
      })
end

defmodule Oneiroi.Brain.MergeWatchWorker do
  @moduledoc """
  A pull request's review is its merge (sunna#118; the witness,
  2026-11-27: "the conclusion of the pr review is the merge"). An approved
  review of a PR with no merge step after it waits; each minute this reads
  every one that waits, and settles those whose pull request has merged:
  at the approved head the review is done, at another it is blocked.

  A poll, with its reason (CLAUDE.md, "pages are pushed to"): the merge
  happens on GitHub, outside Oneiroi, and the platform's token can read
  but not merge, so the platform learns of it only by asking. One read a
  waiting review a minute, and none when nothing waits.

  A cross-tenant job under the platform scope for the list (conventions
  §12), each settle a command on its own household's queue. Replay-safe:
  a settled review no longer waits, and a second settle is refused.
  """
  use Oneiroi.Worker, queue: :brain_merge_watch, unique: [period: 30]

  alias Oneiroi.Actor
  alias Oneiroi.Brain.QueueHeads
  alias Oneiroi.Sunna

  @actor Actor.new(:job, "brain_merge_watch")

  def run(_args) do
    Enum.each(Sunna.queue_awaiting_merge(), &settle/1)
    :ok
  end

  @doc "Settles one waiting review when its pull request has merged; the result of the settle, or `:open`/`:unknown`."
  def settle(%{household: h, task: task, act: act, artifact: artifact}) do
    case QueueHeads.merge_state(artifact) do
      {:merged, sha} -> Sunna.queue_settle_merge(h, task, act, sha, @actor)
      other -> other
    end
  end
end

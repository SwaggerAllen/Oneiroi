defmodule Oneiroi.Kumbukumbu.PassageWorker do
  @moduledoc """
  The transcripts by meaning, kept current (kumbukumbu #49): every ten
  minutes, every active resident's newest captured messages are cut and
  embedded, a batch at a time, so a backlog is worked through over
  several runs and a turn is findable by meaning within minutes. A
  cross-tenant job; a resident whose embedding fails is logged and the
  pass goes on, and the messages wait for the next run.
  """
  use Oneiroi.Worker, queue: :kumbukumbu_passages, unique: [period: 300]

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu.Passages

  @actor Actor.new(:job, "kumbukumbu_passages")

  def run(_args) do
    for row <- AgathosDaimon.active_residents() do
      case Passages.refresh(row.id, @actor) do
        {:ok, _figures} ->
          :ok

        {:error, %{kind: kind}} ->
          Logger.warning("kumbukumbu: passages not embedded for a resident (#{kind})")

        {:error, _other} ->
          Logger.warning("kumbukumbu: passages not embedded for a resident")
      end
    end

    :ok
  end
end

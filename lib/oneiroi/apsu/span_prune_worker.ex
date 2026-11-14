defmodule Oneiroi.Apsu.SpanPruneWorker do
  @moduledoc """
  The span rows' retention (apsu#26): nightly, rows older than
  `APSU_SPAN_RETENTION_DAYS` go. Measurements, not records: nothing in the
  resident's life is in them, and the event store keeps what happened.
  """
  use Oneiroi.Worker, queue: :apsu_spans

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  def run(_args) do
    before = DateTime.add(Clock.now(), -Config.fetch!(:apsu, :span_retention_days) * 86_400)
    Scope.platform(fn -> Repo.delete_all(from(s in "apsu_span", where: s.at < ^before)) end)
    :ok
  end
end

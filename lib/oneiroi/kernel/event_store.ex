defmodule Oneiroi.EventStore do
  @moduledoc """
  The event log's own store: a dedicated Postgres schema (`eventstore`,
  created by the infrastructure migration), reached only through this
  module and Commanded's API. Nothing reads `eventstore.*` directly
  (conventions §12); the export (`Oneiroi.SimaQian`) reads streams through
  `read_stream_forward/4`.

  Connection settings are assembled at init from the platform's declared
  settings, never re-declared here, so `DATABASE_URL` has exactly two
  readers in the tree: `Oneiroi.Repo.init/2` and this.
  """
  use EventStore, otp_app: :oneiroi

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  def init(config) do
    Oneiroi.Boot.load!()

    {:ok,
     config
     |> Keyword.merge(Secret.unwrap(Config.fetch!(:apsu, :database_url)))
     |> Keyword.put(:schema, "eventstore")
     |> Keyword.put(:column_data_type, "jsonb")
     |> Keyword.put(:pool_size, Config.fetch!(:apsu, :event_store_pool_size))
     |> Keyword.put(:serializer, Commanded.Serialization.JsonSerializer)}
  end
end

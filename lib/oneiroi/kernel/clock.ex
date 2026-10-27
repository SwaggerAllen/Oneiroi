defmodule Oneiroi.Apsu.Clock do
  @moduledoc """
  The injected clock's two implementations, chosen by the platform's
  `APSU_CLOCK` setting (conventions §9): `system` in every real build,
  `fake` in test. Domain code calls `Oneiroi.Apsu.Clock.now/0` and
  never `DateTime.utc_now/0`; the audit's `wall_clock` check holds it.
  """

  @doc "The current instant, through the configured clock."
  @spec now() :: DateTime.t()
  def now, do: Oneiroi.Config.fetch!(:apsu, :clock).utc_now()

  defmodule Fake do
    @moduledoc """
    A clock a test sets: `Fake.put(~U[...])` for the current process,
    otherwise a fixed epoch, so two runs of one test see one instant.
    """
    @behaviour Oneiroi.Clock

    # Microsecond precision, because every `at` lands in a
    # `:utc_datetime_usec` column and Ecto refuses a coarser instant.
    @epoch ~U[2026-10-26 12:00:00.000000Z]
    @key :oneiroi_fake_now

    @impl Oneiroi.Clock
    def utc_now, do: Process.get(@key, @epoch)

    @doc "Sets the instant this process's clock answers with."
    @spec put(DateTime.t()) :: :ok
    def put(%DateTime{} = at) do
      Process.put(@key, at)
      :ok
    end

    @doc "Moves this process's clock forward by `seconds`."
    @spec advance(integer()) :: DateTime.t()
    def advance(seconds) do
      at = DateTime.add(utc_now(), seconds, :second)
      put(at)
      at
    end
  end
end

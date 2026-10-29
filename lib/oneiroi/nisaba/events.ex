defmodule Oneiroi.Nisaba.Events do
  @moduledoc """
  The ledger stream's events, version 1 (spec §3.1). Money is an integer
  count of nano-dollars (`Oneiroi.Nisaba.Money`): OpenRouter's cost figure
  carries more places than a cent and a float in an event is a number
  that replays differently on another machine. Purposes and periods are
  strings on the wire.
  """

  defmodule BudgetSet do
    # `cap_nanos` nil means no limit; the line still names its period so
    # the screen can say "no limit a month" rather than nothing.
    use Oneiroi.Event, version: 1, fields: [:id, :purpose, :cap_nanos, :period]
  end

  defmodule ModelCallRecorded do
    # `estimated` marks a cost the provider did not report (spec §6.11:
    # "or the list-price estimate, marked"); `ref` is the call's own id,
    # minted at the command edge, so a record is one row and never two.
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :ref,
        :purpose,
        :model,
        :prompt_tokens,
        :completion_tokens,
        :cost_nanos,
        :estimated
      ]
  end

  defmodule BudgetExceeded do
    # The stop the resident is told about honestly (spec §6.11): written
    # once per purpose per period, by the aggregate, on the call that
    # crossed the cap.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :purpose, :cap_nanos, :spent_nanos, :period, :period_key]
  end
end

defmodule Oneiroi.Nisaba do
  @moduledoc """
  The ledger (spec §6.11): the one provider port every model call goes
  through, metered by purpose against the resident's budget lines, with
  the steward's OpenRouter key spent and every call recorded with its
  model, tokens, cost and actor.

  A model call outside this port is an architecture violation
  (`non-asks.md`, conventions §11); the audit's `model_port` check holds
  it at AST grade, and the `prompts` check holds that a system prompt is
  a file under `priv/prompts/` and never a string in the tree.

  The ledger's own stream is `ledger-<resident_id>` (systems/nisaba.md
  #9): its events are the resident's, written at the volume of its turns,
  and Commanded holds one aggregate per stream.
  """
  use Oneiroi.System, slug: :nisaba

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Gaia,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Decimal,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason,
      Req,
      Req.Response
    ],
    exports: [
      Error,
      Ledgers,
      Router,
      Money,
      Period,
      Prompt,
      Purpose,
      Provider,
      Provider.Request,
      Provider.Result,
      Provider.Usage,
      Provider.Fake,
      Provider.OpenRouter,
      Provider.OpenRouter.SSE,
      Commands.SetBudget,
      Commands.RecordModelCall,
      Events.BudgetSet,
      Events.ModelCallRecorded,
      Events.BudgetExceeded,
      Store,
      Store.Budget,
      Store.Usage,
      Policies.ModelPort,
      Policies.Prompts
    ]

  alias Oneiroi.Nisaba.Ledgers
  alias Oneiroi.Nisaba.Purpose

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:provider, "NISABA_PROVIDER",
       cast: &__MODULE__.cast_provider/1,
       default: "openrouter",
       usage:
         "which provider port implementation answers: openrouter in every real build, fake in test (conventions §9)"},
      # The one place the host is spelled outside the port: the setting
      # the port reads it from.
      # oneiroi:allow model_port
      {:openrouter_url, "NISABA_OPENROUTER_URL",
       default: "https://openrouter.ai/api/v1",
       usage:
         "the OpenRouter API base the port posts chat completions to (Oneiroi.Nisaba.Provider.OpenRouter)"},
      {:request_timeout_ms, "NISABA_REQUEST_TIMEOUT_MS",
       cast: :integer,
       default: "120000",
       tag: :bound,
       usage:
         "how long the port waits for a completion before calling the call a transport failure; a bound until a slow model is measured"}
    ]
  end

  @impl Oneiroi.Component
  def feature_flags, do: [:nisaba_openrouter_off]

  @impl Oneiroi.Component
  def externals do
    [
      {:openrouter,
       adapter: Oneiroi.Nisaba.Provider.OpenRouter,
       fake: Oneiroi.Nisaba.Provider.Fake,
       kill_switch: :nisaba_openrouter_off,
       classification: :customer_content}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Nisaba.Events.BudgetSet, 1},
      {Oneiroi.Nisaba.Events.ModelCallRecorded, 1},
      {Oneiroi.Nisaba.Events.BudgetExceeded, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:nisaba_unknown_purpose, "the purpose is not one the ledger bills under",
       remedy: "use one of chat, free_time, judge, hands, embeddings, drafting, regression"},
      {:nisaba_no_steward, "the resident has no steward to spend from",
       remedy: "a resident in community custody runs on the insurance floor, which is P2"},
      {:nisaba_budget_exceeded, "the budget line for this purpose is spent for its period",
       remedy: "raise the line on the Ledger screen, or wait for the period to turn"},
      {:nisaba_provider_failed, "the provider did not answer",
       remedy: "a transport failure; retry, and if it persists check the provider's status"},
      {:nisaba_request_refused, "the provider refused the request as malformed or unauthorised",
       remedy:
         "the request shape or the key is wrong; a refusal by the model is not this, it is an ordinary reply"},
      {:nisaba_not_recorded, "the call was made and its record was not written",
       remedy:
         "the spend happened; the record is retried by the next sweep of the log, and this is reported loudly on purpose"}
    ]
  end

  @impl Oneiroi.Component
  def policies do
    [
      {Oneiroi.Nisaba.Policies.ModelPort, "lib/**/*.ex",
       policy: "conventions §11: every model call goes through the one provider port"},
      {Oneiroi.Nisaba.Policies.Prompts, "lib/**/*.ex",
       policy: "conventions §11: prompts are files under priv/prompts, never strings in the tree"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Nisaba.Projectors.Ledger]

  @doc "The purposes a call is billed under, in the order the screen lists them (`Oneiroi.Nisaba.Purpose`)."
  @spec purposes() :: [Purpose.t()]
  def purposes, do: Purpose.all()

  @doc "Casts the provider setting to the module that implements the port."
  @spec cast_provider(String.t()) :: {:ok, module()} | {:error, String.t()}
  def cast_provider("openrouter"), do: {:ok, Oneiroi.Nisaba.Provider.OpenRouter}
  def cast_provider("fake"), do: {:ok, Oneiroi.Nisaba.Provider.Fake}

  def cast_provider(other),
    do: {:error, "is #{inspect(other)}, expected \"openrouter\" or \"fake\""}

  @doc "Sets a budget line: a cap in nano-dollars (nil for no limit) per period."
  @spec set_budget(String.t(), atom(), non_neg_integer() | nil, atom(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_budget(resident_id, purpose, cap_nanos, period, actor),
    do: Ledgers.set_budget(resident_id, purpose, cap_nanos, period, actor)
  )

  @doc "The resident's budget lines with their spend this period, every purpose listed; the resident's view omits the steward-only purposes."
  @spec budgets(String.t(), :steward | :resident) :: [map()]
  defexport(budgets(resident_id, view), do: Ledgers.budgets(resident_id, view))

  @doc "Spend grouped by purpose, model or actor since an instant; the resident's view omits the steward-only purposes."
  @spec spend(String.t(), :steward | :resident, :purpose | :model | :actor, DateTime.t()) ::
          [map()]
  defexport(spend(resident_id, view, by, since), do: Ledgers.spend(resident_id, view, by, since))

  @doc "One metered model call: the budget line is checked, the steward's key spent, the call recorded."
  @spec call(String.t(), atom(), Oneiroi.Nisaba.Provider.Request.t(), Oneiroi.Actor.t()) ::
          {:ok, Oneiroi.Nisaba.Provider.Result.t()} | {:error, term()}
  defexport(call(resident_id, purpose, request, actor),
    do: Ledgers.call(resident_id, purpose, request, actor)
  )

  @doc "The same call, streaming each delta of the reply to `sink` before the recorded result returns."
  @spec stream(
          String.t(),
          atom(),
          Oneiroi.Nisaba.Provider.Request.t(),
          Oneiroi.Actor.t(),
          (String.t() -> any())
        ) :: {:ok, Oneiroi.Nisaba.Provider.Result.t()} | {:error, term()}
  defexport(stream(resident_id, purpose, request, actor, sink),
    do: Ledgers.stream(resident_id, purpose, request, actor, sink)
  )
end

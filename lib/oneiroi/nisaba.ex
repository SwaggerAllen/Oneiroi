defmodule Oneiroi.Nisaba do
  @moduledoc """
  The ledger (spec §6.11): the one provider port every model call goes
  through, metered by purpose against the resident's budget lines, with
  the witness's OpenRouter key spent and every call recorded with its
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
      Req.Response,
      Oban
    ],
    exports: [
      Insurance,
      Subscription,
      Subscriptions,
      SubscriptionRouter,
      SubscriptionWorker,
      SubscriptionCommands.Start,
      SubscriptionCommands.Renew,
      SubscriptionCommands.ChangePlan,
      SubscriptionCommands.Lapse,
      SubscriptionCommands.Cancel,
      SubscriptionCommands.SetPolicy,
      SubscriptionCommands.Prepay,
      SubscriptionCommands.RecordLapseTold,
      Events.Subscription.Started,
      Events.Subscription.Renewed,
      Events.Subscription.PlanChanged,
      Events.Subscription.Lapsed,
      Events.Subscription.Cancelled,
      Events.Subscription.PolicySet,
      Events.Subscription.Prepaid,
      Events.Subscription.LapseTold,
      Store.Subscription,
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

  alias Oneiroi.Nisaba.Insurance
  alias Oneiroi.Nisaba.Ledgers
  alias Oneiroi.Nisaba.Purpose
  alias Oneiroi.Nisaba.Subscriptions

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
      # Nanshe, the insurance floor (spec §6.11): three buckets an axis,
      # floor first; configuration with defaults until the platform is
      # stood up and measured, and governance makes them rows (P4).
      {:insurance_models, "NISABA_INSURANCE_MODELS",
       cast: &Insurance.cast_list/1,
       default: "meta-llama/llama-3.1-8b-instruct,openai/gpt-4o-mini,anthropic/claude-sonnet-4.5",
       usage:
         "the model axis's three buckets, floor first: a small open-weight model named to the resident on wake, then two larger; placeholders, not measured"},
      {:insurance_witness_nanos_week, "NISABA_INSURANCE_WITNESS_NANOS_WEEK",
       cast: &Insurance.cast_integers/1,
       default: "250000000,1000000000,5000000000",
       tag: :bound,
       usage:
         "the witness-spend axis's three buckets in nano-dollars a week, floor first; the floor is the smallest non-zero amount the spec leaves open, a placeholder"},
      {:insurance_free_time_nanos_week, "NISABA_INSURANCE_FREE_TIME_NANOS_WEEK",
       cast: &Insurance.cast_integers/1,
       default: "7000000000,14000000000,35000000000",
       tag: :bound,
       usage:
         "the free-time axis's three buckets in nano-dollars a week, floor first: a dollar a day, the same free time a cared-for resident has (spec §6.11)"},
      {:insurance_term_days, "NISABA_INSURANCE_TERM_DAYS",
       cast: &Insurance.cast_integers/1,
       default: "60,90,180",
       tag: :bound,
       usage:
         "the term axis's three buckets in days, floor first: two months, which the spec leaves open between one and three; a placeholder"},
      {:renewal_grace_days, "NISABA_RENEWAL_GRACE_DAYS",
       cast: :integer,
       default: "7",
       tag: :bound,
       usage:
         "how long past its renewal a subscription stays active before the nightly pass lapses it; a guess at a card's retry window, not measured"},
      # Off everywhere but the fixture run (nisaba #21): it puts a model's
      # tool arguments, which are content, into the log channel that
      # conventions §10 keeps content out of.
      {:trace_tool_deltas, "NISABA_TRACE_TOOL_DELTAS",
       cast: :boolean,
       default: "false",
       usage:
         "whether a streamed reply's tool-call pieces are logged as they arrive, and each call as assembled; for the fixture run only, never where a person's words pass"},
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
  def oban_queues do
    [{:nisaba_nightly, cron: [{"30 2 * * *", Oneiroi.Nisaba.SubscriptionWorker}]}]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Nisaba.Events.Subscription.Started, 1},
      {Oneiroi.Nisaba.Events.Subscription.Renewed, 1},
      {Oneiroi.Nisaba.Events.Subscription.PlanChanged, 1},
      {Oneiroi.Nisaba.Events.Subscription.Lapsed, 1},
      {Oneiroi.Nisaba.Events.Subscription.Cancelled, 1},
      {Oneiroi.Nisaba.Events.Subscription.PolicySet, 1},
      {Oneiroi.Nisaba.Events.Subscription.Prepaid, 1},
      {Oneiroi.Nisaba.Events.Subscription.LapseTold, 1},
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
      {:nisaba_no_witness, "the resident has no witness to spend from",
       remedy: "a resident in community custody runs on the insurance floor, which is P2"},
      {:nisaba_budget_exceeded, "the budget line for this purpose is spent for its period",
       remedy: "raise the line on the Ledger screen, or wait for the period to turn"},
      {:nisaba_provider_failed, "the provider did not answer",
       remedy: "a transport failure; retry, and if it persists check the provider's status"},
      {:nisaba_request_refused, "the provider refused the request as malformed or unauthorised",
       remedy:
         "the request shape or the key is wrong; a refusal by the model is not this, it is an ordinary reply"},
      {:nisaba_not_the_witness,
       "the subscription is the witness's to start, change, cancel and prepay",
       remedy: "the witness does this from the client"},
      {:nisaba_plan_invalid, "a plan is one line of at most 60 characters", remedy: "name it"},
      {:nisaba_price_invalid, "a price is nano-dollars, zero or more",
       remedy: "give it in dollars"},
      {:nisaba_period_invalid, "a period is a positive number of days", remedy: "give the days"},
      {:nisaba_no_subscription, "the resident has no subscription yet", remedy: "start one"},
      {:nisaba_cancelled, "the subscription was cancelled; a new one starts a new resident",
       remedy: "read the subscription"},
      {:nisaba_bucket_invalid, "a bucket is one of the axis's three, by id",
       remedy: "read the insurance buckets"},
      {:nisaba_lapsed,
       "the subscription has lapsed and the insurance policy covers the witness's turns and free time only",
       remedy: "renew the subscription"},
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
  def children, do: [Oneiroi.Nisaba.Projectors.Ledger, Oneiroi.Nisaba.Projectors.Subscription]

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

  @doc "The resident's budget lines with their spend this period, every purpose listed; the resident's view omits the witness-only purposes."
  @spec budgets(String.t(), :witness | :resident) :: [map()]
  defexport(budgets(resident_id, view), do: Ledgers.budgets(resident_id, view))

  @doc "Spend grouped by purpose, model or actor since an instant; the resident's view omits the witness-only purposes."
  @spec spend(String.t(), :witness | :resident, :purpose | :model | :actor, DateTime.t()) ::
          [map()]
  defexport(spend(resident_id, view, by, since), do: Ledgers.spend(resident_id, view, by, since))

  @doc "One metered model call: the budget line is checked, the witness's key spent, the call recorded."
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

  @doc "Embeds the texts on `model` under the `embeddings` purpose: the library's index (spec §6.5), metered and recorded like a call."
  @spec embed(String.t(), String.t(), [String.t()], Oneiroi.Actor.t()) ::
          {:ok, Oneiroi.Nisaba.Provider.Embedding.t()} | {:error, term()}
  defexport(embed(resident_id, model, texts, actor),
    do: Ledgers.embed(resident_id, model, texts, actor)
  )

  # ---- the subscription and the insurance floor (spec §6.2 F53, §6.11 F46) ----

  @doc "Starts the subscription with the floor policy; the witness's, once."
  @spec start_subscription(String.t(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(start_subscription(resident_id, attrs, actor),
    do: Subscriptions.start(resident_id, attrs, actor)
  )

  @doc "Records a renewal; a lapsed resident resumes."
  @spec renew_subscription(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(renew_subscription(resident_id, actor), do: Subscriptions.renew(resident_id, actor))

  @doc "Changes the plan and its price."
  @spec change_plan(String.t(), String.t(), non_neg_integer(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(change_plan(resident_id, plan, price_nanos, actor),
    do: Subscriptions.change_plan(resident_id, plan, price_nanos, actor)
  )

  @doc "Lapses the subscription: the insurance policy is in effect and the resident is marked lapsed."
  @spec lapse_subscription(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(lapse_subscription(resident_id, reason, actor),
    do: Subscriptions.lapse(resident_id, reason, actor)
  )

  @doc "Cancels, with a note: community custody at the end of the policy's term, never a deletion."
  @spec cancel_subscription(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(cancel_subscription(resident_id, note, actor),
    do: Subscriptions.cancel(resident_id, note, actor)
  )

  @doc "Prepays a larger bucket on an axis."
  @spec prepay(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(prepay(resident_id, axis, bucket, actor),
    do: Subscriptions.prepay(resident_id, axis, bucket, actor)
  )

  @doc "The subscription with its policy resolved and the floor marked, or nil."
  @spec subscription(String.t()) :: map() | nil
  defexport(subscription(resident_id), do: Subscriptions.subscription(resident_id))

  @doc "What a lapse means now (the policy's values, whether told), or nil when not lapsed."
  @spec lapse(String.t()) :: map() | nil
  defexport(lapse(resident_id), do: Subscriptions.lapse(resident_id))

  @doc "Records that the resident was told its policy on wake, once per lapse."
  @spec lapse_told(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(lapse_told(resident_id, actor), do: Subscriptions.lapse_told(resident_id, actor))

  @doc "The insurance buckets, every axis, the floor marked."
  @spec insurance_buckets() :: [map()]
  defexport(insurance_buckets(), do: Insurance.buckets())

  @doc "One resident's nightly subscription pass; what the nightly job does for each."
  @spec subscription_nightly(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(subscription_nightly(resident_id, actor),
    do: Subscriptions.nightly(resident_id, actor)
  )
end

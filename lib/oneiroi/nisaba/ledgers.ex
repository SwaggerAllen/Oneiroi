defmodule Oneiroi.Nisaba.Ledgers do
  @moduledoc """
  The ledger's service functions: the command edge, where instants and
  the call's own id are made, and the metered call itself.

  A metered call is five steps in order, and the order is the design:
  the purpose is checked, the witness found, the key fetched, the budget
  line checked, and only then the provider called; the record is written
  after, and a record that fails to write is reported as a failure of
  the call, loudly, because a model call the ledger cannot explain is
  the one thing `non-asks.md` forbids.
  """
  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Nisaba.Commands
  alias Oneiroi.Nisaba.Error
  alias Oneiroi.Nisaba.Insurance
  alias Oneiroi.Nisaba.Period
  alias Oneiroi.Nisaba.Provider.{Embedding, Request, Result, Usage}
  alias Oneiroi.Nisaba.Purpose
  alias Oneiroi.Nisaba.Router
  alias Oneiroi.Nisaba.Store
  alias Oneiroi.Scope

  def set_budget(resident_id, purpose, cap_nanos, period, %Actor{} = actor) do
    cond do
      purpose not in Purpose.all() ->
        {:error, Error.new(:nisaba_unknown_purpose, purpose: purpose)}

      period not in Period.all() ->
        {:error, :period_invalid}

      not (is_nil(cap_nanos) or (is_integer(cap_nanos) and cap_nanos >= 0)) ->
        {:error, :cap_invalid}

      true ->
        command = %Commands.SetBudget{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          purpose: purpose,
          cap_nanos: cap_nanos,
          period: period
        }

        with {:ok, _} <- Router.dispatch(command), do: :ok
    end
  end

  def budgets(resident_id, view) when view in [:witness, :resident] do
    now = Clock.now()

    Scope.resident(resident_id, fn ->
      lines = Map.new(Store.budgets(), &{&1.purpose, &1})

      for purpose <- visible(view) do
        line = Map.get(lines, Atom.to_string(purpose))
        period = (line && Period.parse(line.period)) || :month
        key = Period.key(period, now)
        {from, to} = Period.range(period, now)

        %{
          purpose: purpose,
          cap_nanos: line && line.cap_nanos,
          period: period,
          period_key: key,
          spent_nanos: Store.spent(Atom.to_string(purpose), from, to),
          exceeded: line != nil and line.exceeded_period_key == key,
          set_at: line && line.set_at
        }
      end
    end)
  end

  def spend(resident_id, view, by, %DateTime{} = since)
      when view in [:witness, :resident] and by in [:purpose, :model, :actor] do
    purposes = Enum.map(visible(view), &Atom.to_string/1)
    Scope.resident(resident_id, fn -> Store.spend_by(by, since, purposes) end)
  end

  def call(resident_id, purpose, %Request{} = request, %Actor{} = actor) do
    request = tag(request, resident_id)
    metered(resident_id, purpose, actor, fn provider, key -> provider.complete(request, key) end)
  end

  def stream(resident_id, purpose, %Request{} = request, %Actor{} = actor, sink)
      when is_function(sink, 1) do
    request = tag(request, resident_id)

    metered(resident_id, purpose, actor, fn provider, key ->
      provider.stream(request, key, sink)
    end)
  end

  @doc "Embeds the texts under the `embeddings` purpose on the platform-pinned model; metered and recorded like a call."
  def embed(resident_id, model, texts, %Actor{} = actor)
      when is_binary(model) and is_list(texts) do
    metered(resident_id, :embeddings, actor, fn provider, key ->
      provider.embed(model, texts, key)
    end)
  end

  # The resident rides on the request's metadata so a provider can tell
  # whose call it is: the fake finds a per-resident script by it, and the
  # OpenRouter adapter does not send metadata at all.
  defp tag(%Request{metadata: metadata} = request, resident_id),
    do: %{request | metadata: Map.put(metadata || %{}, :resident_id, resident_id)}

  defp metered(resident_id, purpose, actor, run) do
    with :ok <- purpose_ok(purpose),
         {:ok, witness} <- witness_of(resident_id),
         {:ok, secret} <- Oneiroi.Gaia.key_for(witness),
         :ok <- within_budget(resident_id, purpose),
         {:ok, %{usage: %Usage{}} = result} <- taxonomy(run.(provider(), Secret.unwrap(secret))),
         :ok <- record(resident_id, purpose, result, actor) do
      {:ok, result}
    end
  end

  defp purpose_ok(purpose) do
    if purpose in Purpose.all(),
      do: :ok,
      else: {:error, Error.new(:nisaba_unknown_purpose, purpose: purpose)}
  end

  defp witness_of(resident_id) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, %{account_id: id}} when is_binary(id) -> {:ok, id}
      _other -> {:error, Error.new(:nisaba_no_witness)}
    end
  end

  # No line for the purpose means no limit: the creation flow's "their
  # means" gift sets the lines, and a resident whose witness set none is
  # spending the witness's own key with the witness's own silence.
  defp within_budget(resident_id, purpose) do
    now = Clock.now()
    name = Atom.to_string(purpose)

    Scope.resident(resident_id, fn ->
      case {Store.subscription(), Store.budget(name)} do
        {%{state: "lapsed"} = sub, _line} ->
          under_policy(name, sub, now)

        {_sub, %{cap_nanos: cap, period: period}} when is_integer(cap) ->
          under_cap(name, cap, period, now)

        _no_cap ->
          :ok
      end
    end)
  end

  # Under a lapse the insurance policy is the budget (spec §6.11): the
  # witness's turns and free time each a week's bucket, nothing else
  # covered. The lines the witness set no longer apply; the floor does.
  defp under_policy(name, sub, now) do
    policy =
      Insurance.resolve(%{
        model: sub.policy_model,
        witness: sub.policy_witness,
        free_time: sub.policy_free_time,
        term: sub.policy_term
      })

    case name do
      "chat" -> under_cap(name, policy.witness_nanos_week || 0, "week", now)
      "free_time" -> under_cap(name, policy.free_time_nanos_week || 0, "week", now)
      _other -> {:error, Error.new(:nisaba_lapsed, purpose: name)}
    end
  end

  defp under_cap(name, cap, period, now) do
    {from, to} = Period.range(Period.parse(period) || :month, now)

    if Store.spent(name, from, to) >= cap,
      do: {:error, Error.new(:nisaba_budget_exceeded, purpose: name, period: period)},
      else: :ok
  end

  defp provider, do: Config.fetch!(:nisaba, :provider)

  defp taxonomy({:ok, %Result{}} = ok), do: ok
  defp taxonomy({:ok, %Embedding{}} = ok), do: ok

  defp taxonomy({:error, {:transport, reason}}),
    do: {:error, Error.new(:nisaba_provider_failed, reason: reason)}

  defp taxonomy({:error, {:schema_invalid, reason}}),
    do: {:error, Error.new(:nisaba_request_refused, reason: reason)}

  # A completion or an embedding: both carry a model and a usage, and the
  # ledger records them the same way (an embedding has no completion).
  defp record(resident_id, purpose, %{usage: %Usage{}} = result, actor) do
    command = %Commands.RecordModelCall{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      ref: Ecto.UUID.generate(),
      purpose: purpose,
      model: result.model,
      prompt_tokens: result.usage.prompt_tokens,
      completion_tokens: result.usage.completion_tokens,
      cost_nanos: result.usage.cost_nanos,
      estimated: result.usage.estimated
    }

    case Router.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, reason} ->
        # Nothing content-bearing: the purpose and the failure, never the request.
        Logger.error(
          "nisaba: a model call for #{purpose} was made and not recorded (#{inspect(reason)})",
          component: "nisaba"
        )

        {:error, Error.new(:nisaba_not_recorded)}
    end
  end

  defp visible(view), do: Purpose.visible(view)
end

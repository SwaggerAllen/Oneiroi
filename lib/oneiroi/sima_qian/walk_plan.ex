defmodule Oneiroi.SimaQian.WalkPlan do
  @moduledoc """
  The walk's plan (sima-qian#48; Lily's generator brief, design/generator-brief.md
  §B and §M, signed off by the witness 2026-11-06): which model walks each
  conversation, where the eras fall, and what the walk is likely to cost,
  computed before anything runs and shown at the approval wall.

  - **The mirror.** Each conversation is walked by the model that lived it,
    where the catalogue offers it: the export's slug (`gpt-4o`) through a
    small reviewed table to a callable model (`openai/gpt-4o`). A slug that
    names nothing callable (`auto`, a tool-suffixed variant, a retired
    model) is substituted with the walk's fallback and said so, never
    guessed; an unmapped slug lands in the plan's gaps. The importing user
    may instead pick one model for the whole walk.
  - **The eras.** Mechanical, not semantic: whole conversations, oldest
    first, packed until their estimated text reaches half the walking
    model's context (the other half is the walker's room to think); a new
    era where the model changes; a conversation larger than the half walks
    alone, named. Text is estimated at four bytes a token, the house's rule,
    so the half is by estimate and the estimate is shown as one.
  - **The estimate.** Each era's tool rounds re-send its context, so an era
    costs roughly its rounds times its text and carried state, plus what
    the walker writes. The figures are an estimate, never a quote: the
    assumptions are in the plan beside the numbers.
  """

  alias Oneiroi.Config

  # The reviewed table (the brief's build facts): an export's model slug
  # to the catalogue model that is its API twin, or `:substitute` when the
  # slug names nothing anyone can call. A slug missing from here is a gap,
  # never a guess; adding one is a reviewed commit.
  @mirror %{
    "gpt-4o" => "openai/gpt-4o",
    "gpt-4o-mini" => "openai/gpt-4o-mini",
    "gpt-4" => "openai/gpt-4",
    "gpt-4-turbo" => "openai/gpt-4-turbo",
    "gpt-4-1106-preview" => "openai/gpt-4-turbo",
    "gpt-4.1" => "openai/gpt-4.1",
    "gpt-4.1-mini" => "openai/gpt-4.1-mini",
    "gpt-4.5" => "openai/gpt-4.5-preview",
    "gpt-5" => "openai/gpt-5",
    "gpt-3.5-turbo" => "openai/gpt-3.5-turbo",
    "o1" => "openai/o1",
    "o1-mini" => "openai/o1-mini",
    "o1-preview" => "openai/o1-preview",
    "o3" => "openai/o3",
    "o3-mini" => "openai/o3-mini",
    "o4-mini" => "openai/o4-mini",
    "auto" => :substitute,
    "text-davinci-002-render-sha" => :substitute,
    "text-davinci-002-render-paid" => :substitute,
    "gpt-4o-canmore" => :substitute,
    "gpt-4-gizmo" => :substitute,
    "gpt-4-browsing" => :substitute,
    "gpt-4-plugins" => :substitute
  }

  @bytes_a_token 4

  @type era :: %{
          number: pos_integer(),
          model: String.t(),
          conversations: [String.t()],
          from: DateTime.t() | nil,
          to: DateTime.t() | nil,
          tokens: non_neg_integer(),
          capacity: pos_integer(),
          oversized: boolean()
        }

  @doc "The reviewed table: export slug to catalogue model or `:substitute`."
  @spec mirror_table() :: %{String.t() => String.t() | :substitute}
  def mirror_table, do: @mirror

  @doc """
  The model that walks a conversation of `slug`: `{:mirror, id}` when the
  table names a twin the catalogue offers, `{:substitute, fallback, why}`
  otherwise, the why in words for the birth certificate.
  """
  @spec mirror(String.t() | nil, [String.t()], String.t()) ::
          {:mirror, String.t()} | {:substitute, String.t(), String.t()}
  def mirror(slug, offered, fallback) do
    case Map.get(@mirror, slug) do
      id when is_binary(id) ->
        if id in offered,
          do: {:mirror, id},
          else: {:substitute, fallback, "#{slug}'s twin #{id} is not in the catalogue"}

      :substitute ->
        {:substitute, fallback, "#{slug} names no model anyone can call"}

      nil when is_nil(slug) ->
        {:substitute, fallback, "the conversation names no model"}

      nil ->
        {:substitute, fallback, "#{slug} is not in the reviewed table"}
    end
  end

  @doc """
  The plan for `conversations` (as `Oneiroi.SimaQian.ChatGPT.read/1` gives
  them, oldest first): the eras, the substitutions and the gaps. `pick` is
  `:mirror` (each conversation by the model that lived it) or
  `{:one, model}` (one model for the whole walk).
  """
  @spec plan([map()], :mirror | {:one, String.t()}, [map()]) :: %{
          eras: [era()],
          substitutions: [map()],
          gaps: [map()]
        }
  def plan(conversations, pick, catalog) do
    offered = Enum.map(catalog, & &1.id)
    contexts = Map.new(catalog, &{&1.id, &1.context_length})
    fallback = Config.fetch!(:sima_qian, :walk_fallback_model)

    walked =
      Enum.map(conversations, fn c ->
        slug = lived_model(c)

        {model, substitution} =
          case pick do
            {:one, model} -> {model, nil}
            :mirror -> mirrored(slug, offered, fallback, c)
          end

        %{conversation: c, model: model, substitution: substitution, tokens: tokens(c)}
      end)

    eras = pack(walked, contexts)
    substitutions = walked |> Enum.map(& &1.substitution) |> Enum.reject(&is_nil/1)

    gaps =
      for s <- substitutions,
          s.unmapped,
          do: %{kind: :unmapped_model, where: s.conversation, detail: s.why}

    %{eras: eras, substitutions: substitutions, gaps: gaps}
  end

  defp mirrored(slug, offered, fallback, c) do
    case mirror(slug, offered, fallback) do
      {:mirror, id} ->
        {id, nil}

      {:substitute, fallback, why} ->
        {fallback,
         %{
           conversation: c.title,
           lived: slug,
           walked: fallback,
           why: why,
           unmapped: not is_nil(slug) and not Map.has_key?(@mirror, slug)
         }}
    end
  end

  # The model that lived a conversation: the slug most of its assistant
  # messages carry.
  defp lived_model(%{messages: messages}) do
    messages
    |> Enum.filter(&(&1.role == :assistant and is_binary(&1.model)))
    |> Enum.frequencies_by(& &1.model)
    |> Enum.max_by(fn {_slug, n} -> n end, fn -> {nil, 0} end)
    |> elem(0)
  end

  @doc "A conversation's text in tokens, estimated at four bytes a token."
  @spec tokens(map()) :: non_neg_integer()
  def tokens(%{messages: messages}),
    do: div(Enum.sum(Enum.map(messages, &byte_size(&1.text || ""))), @bytes_a_token)

  # Whole conversations, oldest first, until the half is reached; a new
  # era where the model changes; an oversized conversation alone.
  defp pack(walked, contexts) do
    walked
    |> Enum.reduce([], fn w, eras ->
      capacity = div(Map.get(contexts, w.model, 32_000), 2)

      case eras do
        [%{model: model, tokens: t} = era | rest]
        when model == w.model and t + w.tokens <= capacity and not era.oversized ->
          [add(era, w) | rest]

        _new ->
          [new_era(length(eras) + 1, w, capacity) | eras]
      end
    end)
    |> Enum.reverse()
  end

  defp new_era(number, w, capacity),
    do: %{
      number: number,
      model: w.model,
      conversations: [w.conversation.id],
      from: w.conversation.created_at,
      to: w.conversation.created_at,
      tokens: w.tokens,
      capacity: capacity,
      oversized: w.tokens > capacity
    }

  defp add(era, w),
    do: %{
      era
      | conversations: era.conversations ++ [w.conversation.id],
        to: w.conversation.created_at || era.to,
        tokens: era.tokens + w.tokens
    }

  @doc """
  The walk's estimated cost: per era, its tool rounds re-sending its text
  and the state it carries, plus what the walker writes, at the model's
  catalogue prices. An estimate, with its assumptions beside it.
  """
  @spec estimate([era()], [map()]) :: %{
          eras: non_neg_integer(),
          nanos: non_neg_integer(),
          per_era: [map()],
          assumptions: String.t()
        }
  def estimate(eras, catalog) do
    prices = Map.new(catalog, &{&1.id, &1})
    rounds = Config.fetch!(:sima_qian, :walk_rounds_estimate)
    carried = Config.fetch!(:sima_qian, :walk_carried_tokens)
    written = Config.fetch!(:sima_qian, :walk_written_tokens)

    per_era =
      Enum.map(eras, fn era ->
        price = Map.get(prices, era.model, %{prompt_nanos: 0.0, completion_nanos: 0.0})
        input = rounds * (era.tokens + carried)
        output = rounds * written

        %{
          number: era.number,
          model: era.model,
          nanos: round(input * price.prompt_nanos + output * price.completion_nanos)
        }
      end)

    %{
      eras: length(eras),
      nanos: per_era |> Enum.map(& &1.nanos) |> Enum.sum(),
      per_era: per_era,
      assumptions:
        "an estimate, never a quote: text at four bytes a token; each era taken as #{rounds} tool rounds, each re-sending the era's text and about #{carried} tokens of carried state, and writing about #{written} tokens; prices from the catalogue as read today"
    }
  end
end

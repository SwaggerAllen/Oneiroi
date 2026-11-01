defmodule Oneiroi.Nisaba.Provider.Fake do
  @moduledoc """
  The in-memory provider (conventions §9): what every test calls, and
  what `NISABA_PROVIDER=fake` selects. It answers deterministically from
  the request unless scripted, and it prices every token the same, so a
  test can assert a cost it can compute by hand.

  Two places a script lives. The calling process, for a test that calls
  the port in its own process; and a table keyed by resident, for a test
  whose call runs on another process (the brain's session process), set
  with `for: resident_id` and found through the resident the ledger puts
  on the request's metadata. The process script wins where both exist.
  """
  @behaviour Oneiroi.Nisaba.Provider

  alias Oneiroi.Nisaba.Error
  alias Oneiroi.Nisaba.Provider.{Embedding, Request, Result, Usage}

  @key :nisaba_fake_script
  @embed_key :nisaba_fake_embed
  # The width spec §6.5 names for the pinned model (1,536); the library's
  # column is declared at the same width and the suite proves they agree.
  @width 1536
  @table :nisaba_fake_scripts
  # A flat fake price: one micro-dollar a token, so a 30-token call costs
  # 30,000 nano-dollars and the arithmetic in a test is legible.
  @nanos_per_token 1_000

  @type answer ::
          {:ok, String.t()}
          | {:refusal, String.t()}
          | {:calls, [map()]}
          | {:error, Oneiroi.Nisaba.Provider.failure()}

  @doc "Scripts the answers: a function of the request, for this process or, with `for:`, for a resident from any process."
  @spec script((Request.t() -> answer()), keyword()) :: :ok
  def script(fun, opts \\ []) when is_function(fun, 1) do
    case Keyword.get(opts, :for) do
      nil ->
        Process.put(@key, fun)

      resident_id ->
        :ets.insert(table(), {resident_id, fun})
    end

    :ok
  end

  @doc "Scripts a fixed reply."
  @spec reply(String.t(), keyword()) :: :ok
  def reply(text, opts \\ []) when is_binary(text),
    do: script(fn _request -> {:ok, text} end, opts)

  @doc "Scripts a refusal, in the model's words."
  @spec refuse(String.t(), keyword()) :: :ok
  def refuse(text, opts \\ []) when is_binary(text),
    do: script(fn _request -> {:refusal, text} end, opts)

  @doc """
  Scripts tool calls on the first round and a reply once the tool results
  are back: `calls` are maps with `name` and `arguments` (a map, encoded
  here as the JSON string a model writes). A request that offers no tools
  gets the reply, as a model offered none cannot call one.
  """
  @spec calls([map()], String.t(), keyword()) :: :ok
  def calls(calls, reply, opts \\ []) when is_list(calls) and is_binary(reply) do
    script(
      fn %Request{messages: messages, tools: tools} ->
        if tools == [] or Enum.any?(messages, &(&1[:role] == :tool)),
          do: {:ok, reply},
          else: {:calls, calls}
      end,
      opts
    )
  end

  @doc "Scripts a failure of the given kind (`:transport` or `:schema_invalid`)."
  @spec fail(:transport | :schema_invalid, keyword()) :: :ok
  def fail(kind, opts \\ []) when kind in [:transport, :schema_invalid],
    do: script(fn _request -> {:error, scripted(kind)} end, opts)

  @doc "Scripts the next embeddings calls from this process to fail."
  @spec embed_fail(:transport | :schema_invalid) :: :ok
  def embed_fail(kind) when kind in [:transport, :schema_invalid] do
    Process.put(@embed_key, {:error, scripted(kind)})
    :ok
  end

  # The two port failures, as the adapter answers them.
  defp scripted(:transport),
    do: Error.new(:nisaba_provider_failed, :nisaba_fake_scripted_transport, reason: :scripted)

  defp scripted(:schema_invalid),
    do: Error.new(:nisaba_request_refused, :nisaba_fake_scripted_refused, reason: :scripted)

  @doc "Scripts the next embeddings calls from this process to answer vectors of another width, as a model swapped under the index would."
  @spec embed_width(pos_integer()) :: :ok
  def embed_width(width) when is_integer(width) and width > 0 do
    Process.put(@embed_key, {:width, width})
    :ok
  end

  @doc "Forgets this process's script and, with `for:`, a resident's."
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    Process.delete(@key)
    Process.delete(@embed_key)
    if resident_id = Keyword.get(opts, :for), do: :ets.delete(table(), resident_id)
    :ok
  end

  @doc "The fake's flat price per token, in nano-dollars."
  @spec nanos_per_token() :: pos_integer()
  def nanos_per_token, do: @nanos_per_token

  @impl Oneiroi.Nisaba.Provider
  def complete(%Request{} = request, key) when is_binary(key) do
    case refusal(request) || answer(request) do
      {:ok, text} -> {:ok, result(request, text, false)}
      {:refusal, text} -> {:ok, result(request, text, true)}
      {:calls, calls} -> {:ok, calls_result(request, calls)}
      {:error, failure} -> {:error, failure}
    end
  end

  @impl Oneiroi.Nisaba.Provider
  def stream(%Request{} = request, key, sink) when is_binary(key) and is_function(sink, 1) do
    with {:ok, result} <- complete(request, key) do
      result.content |> String.split(~r/(?<=\s)/) |> Enum.each(sink)
      {:ok, result}
    end
  end

  # A deterministic vector per text: a bag of words hashed into the
  # width and normalised to unit length, so two texts sharing words sit
  # close under cosine distance and a search test can know its answer.
  # Not an embedding model's geometry; enough for the library's ranking
  # to be asserted rather than trusted.
  @impl Oneiroi.Nisaba.Provider
  def embed(model, texts, key) when is_binary(model) and is_list(texts) and is_binary(key) do
    case Process.get(@embed_key) do
      {:error, failure} ->
        {:error, failure}

      scripted ->
        prompt = texts |> Enum.map(&tokens/1) |> Enum.sum()

        {:ok,
         %Embedding{
           model: model,
           vectors: vectors_for(scripted, texts),
           usage: %Usage{
             prompt_tokens: prompt,
             completion_tokens: 0,
             cost_nanos: prompt * @nanos_per_token,
             estimated: false
           }
         }}
    end
  end

  @doc "The width of the fake's vectors."
  @spec width() :: pos_integer()
  def width, do: @width

  defp vectors_for({:width, w}, texts), do: Enum.map(texts, fn _ -> List.duplicate(0.0, w) end)
  defp vectors_for(_unscripted, texts), do: Enum.map(texts, &vector/1)

  defp vector(text) do
    counts =
      text
      |> String.downcase()
      |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
      |> Enum.frequencies()
      |> Enum.reduce(%{}, fn {word, n}, acc ->
        Map.update(acc, :erlang.phash2(word, @width), n, &(&1 + n))
      end)

    norm = counts |> Map.values() |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
    norm = if norm == 0, do: 1.0, else: norm
    for i <- 0..(@width - 1), do: Map.get(counts, i, 0) / norm
  end

  # The chat format's rules on tool messages, refused as OpenRouter
  # refuses them, with the 400 the adapter answers as `nisaba_request_refused`. A
  # `tool` message answers a call by its id, and the calls of one
  # assistant message are all answered by the `tool` messages that
  # follow it; a request carrying either names its tools, which is
  # Anthropic's documented rule rather than one measured here. Without
  # this the fake answered any shape, and a transcript replaying bare
  # `tool` rows passed the suite while every provider refused it: the
  # fixture's turns 3 to 12 after a turn that used tools.
  defp refusal(%Request{messages: messages, tools: tools}) do
    case wire_error(messages, MapSet.new(), tools != []) do
      nil ->
        nil

      message ->
        {:error,
         Error.new(:nisaba_request_refused, :nisaba_fake_wire_refused,
           reason: {:status, 400, message}
         )}
    end
  end

  defp wire_error([], open, _tools?), do: unanswered(open)

  defp wire_error([%{role: :tool} = m | rest], open, tools?) do
    id = m[:tool_call_id]

    if MapSet.member?(open, id),
      do: wire_error(rest, MapSet.delete(open, id), tools?),
      else: "tool message #{inspect(id)} answers no preceding call"
  end

  defp wire_error([m | rest], open, tools?) do
    calls = m[:tool_calls] || []

    cond do
      MapSet.size(open) > 0 ->
        unanswered(open)

      calls != [] and m[:role] != :assistant ->
        "tool calls on a #{m[:role]} message"

      calls != [] and not tools? ->
        "a tool call in a request that names no tools"

      bad = Enum.find(calls, &(not object?(&1))) ->
        "Extra data: call #{inspect(bad.id)}'s arguments are not one JSON object"

      true ->
        wire_error(rest, MapSet.new(calls, & &1.id), tools?)
    end
  end

  # A call's arguments are one JSON object: fixture run 41248366617's
  # provider refused a request carrying one object twice over with
  # "400 Extra data: line 1 column 86 (char 85)".
  defp object?(%{function: %{arguments: arguments}}) when is_binary(arguments),
    do: match?({:ok, %{}}, Jason.decode(arguments))

  defp object?(_call), do: false

  defp unanswered(open) do
    if MapSet.size(open) > 0,
      do: "tool calls #{inspect(MapSet.to_list(open))} have no tool message answering them"
  end

  defp answer(request) do
    case Process.get(@key) || resident_script(request) do
      nil -> {:ok, default(request)}
      fun -> fun.(request)
    end
  end

  defp resident_script(%Request{metadata: %{resident_id: resident_id}}) do
    case :ets.lookup(table(), resident_id) do
      [{_id, fun}] -> fun
      [] -> nil
    end
  end

  defp resident_script(_request), do: nil

  # Created on first use by whichever process gets there; a second
  # creator finds it made and uses it.
  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          # The race above, lost: the table is there. Any other refusal
          # is not this one and goes on up.
          e in ArgumentError ->
            if :ets.whereis(@table) == :undefined, do: reraise(e, __STACKTRACE__), else: @table
        end

      _ref ->
        @table
    end
  end

  defp default(%Request{messages: messages}) do
    last =
      messages
      |> Enum.reverse()
      |> Enum.find_value("nothing", fn
        %{role: :user, content: content} when is_binary(content) -> content
        _other -> nil
      end)

    "The fake provider heard: " <> last
  end

  defp result(request, text, refusal?) do
    prompt = request.messages |> Enum.map(&tokens(&1[:content])) |> Enum.sum()
    completion = tokens(text)

    %Result{
      content: text,
      model: request.model,
      finish_reason: if(refusal?, do: "content_filter", else: "stop"),
      refusal?: refusal?,
      usage: %Usage{
        prompt_tokens: prompt,
        completion_tokens: completion,
        cost_nanos: (prompt + completion) * @nanos_per_token,
        estimated: false
      }
    }
  end

  defp calls_result(request, calls) do
    tool_calls =
      calls
      |> Enum.with_index()
      |> Enum.map(fn {call, i} ->
        arguments = Map.get(call, :arguments) || %{}

        %{
          id: Map.get(call, :id) || "call_#{i}",
          name: Map.fetch!(call, :name),
          arguments: if(is_binary(arguments), do: arguments, else: Jason.encode!(arguments))
        }
      end)

    %{result(request, "", false) | finish_reason: "tool_calls", tool_calls: tool_calls}
  end

  defp tokens(nil), do: 0
  defp tokens(text) when is_binary(text), do: text |> String.split() |> length()
end

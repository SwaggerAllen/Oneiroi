defmodule Oneiroi.Nisaba.Provider.OpenRouter do
  @moduledoc """
  The real provider: OpenRouter's chat completions over Req (spec §2.1),
  on the witness's own key. The only module in the tree that talks to a
  model provider, which the `model_port` check holds.

  OpenRouter reports the call's cost when asked (`usage: {include: true}`)
  and the cost is what the ledger records; when it is absent the record
  is marked estimated and carries zero rather than a guess (spec §6.11
  allows a list-price estimate, and a price list is a measurement this
  codebase has not taken).

  Status classification follows conventions §8: 408, 409, 425, 429 and
  every 5xx are transport failures (retryable); any other non-2xx is a
  request the provider refused (cancelled). A model's refusal arrives as
  a 200 and is an ordinary result.
  """
  @behaviour Oneiroi.Nisaba.Provider

  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Money
  alias Oneiroi.Nisaba.Provider.{Embedding, Request, Result, Usage}

  require Logger

  @transport_statuses [408, 409, 425, 429]

  @impl Oneiroi.Nisaba.Provider
  def complete(%Request{} = request, key) when is_binary(key) do
    case Req.post(url(),
           json: body(request, false),
           headers: headers(key),
           receive_timeout: timeout()
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> parse(body)
      {:ok, %Req.Response{status: status, body: body}} -> classify(status, body)
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  @impl Oneiroi.Nisaba.Provider
  def stream(%Request{} = request, key, sink) when is_binary(key) and is_function(sink, 1) do
    trace? = Config.fetch!(:nisaba, :trace_tool_deltas)

    case Req.post(url(),
           json: body(request, true),
           headers: headers(key),
           receive_timeout: timeout(),
           into: collector(sink, trace?)
         ) do
      {:ok, %Req.Response{status: 200, private: %{sse_state: state}}} ->
        trace_assembled(state, trace?)
        __MODULE__.SSE.outcome(state)

      {:ok, %Req.Response{status: 200}} ->
        {:error, {:schema_invalid, :empty_stream}}

      {:ok, %Req.Response{status: status, private: private}} ->
        classify(status, Map.get(private, :raw, ""))

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  # The stream's collector: each chunk's events fed through the SSE
  # parser into the state the response carries, the raw text beside it.
  defp collector(sink, trace?) do
    fn {:data, data}, {req, resp} ->
      {events, rest} = __MODULE__.SSE.feed((resp.private[:sse_buffer] || "") <> data)
      trace_events(events, trace?)

      state =
        Enum.reduce(events, resp.private[:sse_state] || __MODULE__.SSE.initial(), fn event, acc ->
          __MODULE__.SSE.absorb(acc, event, sink)
        end)

      resp =
        resp
        |> Req.Response.put_private(:sse_buffer, rest)
        |> Req.Response.put_private(:sse_state, state)
        |> Req.Response.put_private(:raw, (resp.private[:raw] || "") <> data)

      {:cont, {req, resp}}
    end
  end

  defp trace_events(_events, false), do: :ok

  defp trace_events(events, true),
    do: events |> Enum.flat_map(&trace_lines/1) |> Enum.each(&trace/1)

  defp trace_assembled(_state, false), do: :ok
  defp trace_assembled(state, true), do: state |> assembled_lines() |> Enum.each(&trace/1)

  # Where a call's arguments arrive twice over (fixture runs 41240586421,
  # 41248366617 and PR 26's, six in the last): from the provider, or from
  # this adapter joining a piece twice, is not measured. Each streamed
  # tool-call piece is logged as it came, with the upstream provider the
  # chunk names, and each call as assembled, so one fixture run with the
  # trace on answers it (nisaba #21). Content, so off but in that run.
  @doc false
  @spec trace_lines(term()) :: [String.t()]
  def trace_lines(%{} = chunk) do
    provider = Map.get(chunk, "provider")

    for %{"delta" => %{"tool_calls" => [_ | _] = calls}} = choice <-
          List.wrap(Map.get(chunk, "choices")),
        call <- calls do
      function = Map.get(call, "function") || %{}

      "tool-call piece provider=#{provider} index=#{call["index"]} id=#{call["id"]} " <>
        "name=#{function["name"]} finish=#{choice["finish_reason"]} " <>
        "arguments=#{inspect(function["arguments"])}"
    end
  end

  def trace_lines(_other), do: []

  @doc false
  @spec assembled_lines(map()) :: [String.t()]
  def assembled_lines(%{tool_calls: calls}) do
    for {index, call} <- Enum.sort_by(calls, &elem(&1, 0)) do
      "tool call assembled index=#{index} id=#{call.id} name=#{call.name} " <>
        "arguments=#{inspect(call.arguments)}"
    end
  end

  defp trace(line), do: Logger.info("nisaba: " <> line, component: "nisaba")

  # The embeddings endpoint is OpenAI-shaped (`POST /embeddings` with
  # `model` and `input`, answered by `data[].embedding` in input order and
  # a `usage`), read from OpenRouter's documentation and not yet measured
  # against a live reply on this build: a claim until the first index run
  # on a witness's key (conventions §9). A cost is not expected in the
  # reply, so the record is marked estimated with zero, as `usage/1` does.
  @impl Oneiroi.Nisaba.Provider
  def embed(model, texts, key) when is_binary(model) and is_list(texts) and is_binary(key) do
    case Req.post(Config.fetch!(:nisaba, :openrouter_url) <> "/embeddings",
           json: %{model: model, input: texts, encoding_format: "float"},
           headers: headers(key),
           receive_timeout: timeout()
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> parse_embedding(body, model)
      {:ok, %Req.Response{status: status, body: body}} -> classify(status, body)
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  @doc "An embeddings reply into the port's shape; public so the shape is testable without a network."
  @spec parse_embedding(term(), String.t()) ::
          {:ok, Embedding.t()} | {:error, Oneiroi.Nisaba.Provider.failure()}
  def parse_embedding(%{"data" => data} = body, model) when is_list(data) do
    vectors =
      data
      |> Enum.sort_by(&Map.get(&1, "index", 0))
      |> Enum.map(&Map.get(&1, "embedding"))

    if vectors != [] and
         Enum.all?(vectors, &(is_list(&1) and Enum.all?(&1, fn x -> is_number(x) end))),
       do:
         {:ok,
          %Embedding{
            model: Map.get(body, "model") || model,
            vectors: vectors,
            usage: usage(Map.get(body, "usage"))
          }},
       else: {:error, {:schema_invalid, :embedding_shape}}
  end

  def parse_embedding(other, _model),
    do: {:error, {:schema_invalid, {:unexpected_body, summarize(other)}}}

  @doc "The request body OpenRouter receives; public so the shape is testable without a network."
  @spec body(Request.t(), boolean()) :: map()
  def body(%Request{} = request, stream?) do
    %{
      model: request.model,
      messages: Enum.map(request.messages, &message/1),
      usage: %{include: true},
      stream: stream?
    }
    |> put_unless_nil(:max_tokens, request.max_tokens)
    |> put_unless_nil(:temperature, request.temperature)
    |> put_unless_empty(:tools, request.tools)
  end

  @doc "A result from a non-streaming response body; public for the same reason as `body/2`."
  @spec parse(term()) :: {:ok, Result.t()} | {:error, {:schema_invalid, term()}}
  def parse(%{"choices" => [choice | _]} = body) do
    message = Map.get(choice, "message", %{})
    refusal = Map.get(message, "refusal")
    finish = Map.get(choice, "finish_reason")

    {:ok,
     %Result{
       content: Map.get(message, "content") || refusal || "",
       model: Map.get(body, "model"),
       finish_reason: finish,
       refusal?: is_binary(refusal) or finish == "content_filter",
       tool_calls: tool_calls(Map.get(message, "tool_calls")),
       usage: usage(Map.get(body, "usage"))
     }}
  end

  def parse(other), do: {:error, {:schema_invalid, {:unexpected_body, summarize(other)}}}

  @doc "Usage from OpenRouter's usage object; absent cost is estimated zero, marked."
  @spec usage(term()) :: Usage.t()
  def usage(%{} = u) do
    cost = Map.get(u, "cost")

    %Usage{
      prompt_tokens: Map.get(u, "prompt_tokens") || 0,
      completion_tokens: Map.get(u, "completion_tokens") || 0,
      cost_nanos: if(is_number(cost), do: Money.from_usd(cost), else: 0),
      estimated: not is_number(cost)
    }
  end

  def usage(_absent), do: %Usage{estimated: true}

  @doc "Tool calls in the port's shape: id, name and the arguments as the JSON string the model wrote."
  @spec tool_calls(term()) :: [map()]
  def tool_calls(calls) when is_list(calls) do
    for %{"id" => id, "function" => %{"name" => name} = f} <- calls do
      %{id: id, name: name, arguments: Map.get(f, "arguments") || "{}"}
    end
  end

  def tool_calls(_other), do: []

  defp classify(status, body) when status in @transport_statuses or status >= 500,
    do: {:error, {:transport, {:status, status, summarize(body)}}}

  defp classify(status, body), do: {:error, {:schema_invalid, {:status, status, summarize(body)}}}

  # The provider's error message, never the request: a body echoing a
  # prompt back would put resident text in an error tuple.
  @doc """
  An error body's message, and nothing else of it. A streamed refusal
  arrives as raw text, which is decoded first: sliced as it came, its
  first 200 bytes would carry the error's `metadata`, where OpenRouter
  documents putting a moderation hit's flagged input, and the summary
  rides a capture failure's reason (brain #39).
  """
  @spec summarize(term()) :: String.t() | :unparseable
  def summarize(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  def summarize(%{"error" => error}) when is_binary(error), do: error

  def summarize(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, %{} = body} -> summarize(body)
      _not_json -> String.slice(text, 0, 200)
    end
  end

  def summarize(_other), do: :unparseable

  defp message(%{role: role, content: content} = m) do
    %{role: Atom.to_string(role), content: content}
    |> put_unless_nil(:name, m[:name])
    |> put_unless_nil(:tool_call_id, m[:tool_call_id])
    |> put_unless_nil(:tool_calls, m[:tool_calls])
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
  defp put_unless_empty(map, _key, []), do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  defp url, do: Config.fetch!(:nisaba, :openrouter_url) <> "/chat/completions"
  defp timeout, do: Config.fetch!(:nisaba, :request_timeout_ms)

  defp headers(key) do
    [{"authorization", "Bearer " <> key}, {"x-title", "Oneiroi"}]
  end

  defmodule SSE do
    @moduledoc """
    The streaming half, pure: server-sent events split from the wire and
    absorbed into a result. Public and network-free so its parsing is
    testable; the fixture it is tested against is the OpenAI-compatible
    stream format OpenRouter documents, written by hand rather than
    recorded, and says so where it is used (conventions §9).
    """

    alias Oneiroi.Nisaba.Provider.OpenRouter
    alias Oneiroi.Nisaba.Provider.{Result, Usage}

    @type state :: %{
            content: iodata(),
            model: String.t() | nil,
            finish_reason: String.t() | nil,
            refusal: iodata(),
            usage: Usage.t() | nil,
            tool_calls: %{non_neg_integer() => map()},
            error: {term(), String.t() | :unparseable} | nil
          }

    @doc "An empty accumulator."
    @spec initial() :: state()
    def initial,
      do: %{
        content: [],
        model: nil,
        finish_reason: nil,
        refusal: [],
        usage: nil,
        tool_calls: %{},
        error: nil
      }

    @doc "Complete events in `buffer`, decoded, and the unterminated rest."
    @spec feed(String.t()) :: {[term()], String.t()}
    def feed(buffer) do
      {complete, rest} =
        case String.split(buffer, ~r/\r?\n\r?\n/) do
          [only] -> {[], only}
          parts -> {Enum.drop(parts, -1), List.last(parts)}
        end

      {Enum.flat_map(complete, &decode/1), rest}
    end

    defp decode(block) do
      block
      |> String.split(~r/\r?\n/)
      |> Enum.flat_map(fn
        "data: [DONE]" -> [:done]
        "data: " <> json -> decode_json(json)
        _comment_or_other -> []
      end)
    end

    defp decode_json(json) do
      case Jason.decode(json) do
        {:ok, %{} = chunk} -> [chunk]
        _other -> []
      end
    end

    @doc "Folds one decoded event into the state, calling `sink` with any content delta."
    @spec absorb(state(), term(), (String.t() -> any())) :: state()
    def absorb(state, :done, _sink), do: state

    def absorb(state, %{} = chunk, sink) do
      state =
        if u = Map.get(chunk, "usage"),
          do: %{state | usage: OpenRouter.usage(u)},
          else: state

      state =
        case Map.get(chunk, "error") do
          %{} = e -> %{state | error: {Map.get(e, "code", "error"), OpenRouter.summarize(chunk)}}
          _none -> state
        end

      state = %{state | model: state.model || Map.get(chunk, "model")}

      case Map.get(chunk, "choices") do
        [choice | _] -> choice(state, choice, sink)
        _none -> state
      end
    end

    defp choice(state, choice, sink) do
      delta = Map.get(choice, "delta", %{})
      content = Map.get(delta, "content")
      if is_binary(content) and content != "", do: sink.(content)

      %{
        state
        | content: if(is_binary(content), do: [state.content, content], else: state.content),
          refusal:
            if(is_binary(delta["refusal"]),
              do: [state.refusal, delta["refusal"]],
              else: state.refusal
            ),
          finish_reason: Map.get(choice, "finish_reason") || state.finish_reason,
          tool_calls: tool_deltas(state.tool_calls, Map.get(delta, "tool_calls"))
      }
    end

    defp tool_deltas(calls, nil), do: calls

    defp tool_deltas(calls, deltas) when is_list(deltas) do
      Enum.reduce(deltas, calls, fn d, acc ->
        index = Map.get(d, "index", 0)
        f = Map.get(d, "function", %{})
        current = Map.get(acc, index, %{id: nil, name: nil, arguments: ""})

        Map.put(acc, index, %{
          id: current.id || Map.get(d, "id"),
          name: current.name || Map.get(f, "name"),
          arguments: current.arguments <> (Map.get(f, "arguments") || "")
        })
      end)
    end

    @doc """
    What the absorbed stream amounts to: the result, or the failure it
    carried. OpenRouter documents an error after streaming has begun as
    an event in the stream under a 200, with `finish_reason` `error`.
    Read as a result, as it was, such a stream is a reply with no words
    and no usage: fixture run 41240586421 ended eight of its twelve turns
    so, each recorded `ok` at zero cost. Whether those eight carried an
    error event or nothing at all was not recorded; both now fail the
    call, the provider's words kept when it gave them, and a stream
    with no words, no call, no refusal and no usage is read as nothing
    having answered.
    """
    @spec outcome(state()) :: {:ok, Result.t()} | {:error, {:transport, term()}}
    def outcome(%{error: {code, message}}), do: {:error, {:transport, {:status, code, message}}}

    def outcome(%{finish_reason: "error"}),
      do: {:error, {:transport, {:status, "error", "the stream ended in an error"}}}

    def outcome(%{usage: nil, tool_calls: calls} = state) when map_size(calls) == 0 do
      if IO.iodata_length(state.content) == 0 and IO.iodata_length(state.refusal) == 0,
        do: {:error, {:transport, {:status, 200, "the stream carried nothing"}}},
        else: {:ok, result(state)}
    end

    def outcome(state), do: {:ok, result(state)}

    @doc "The result the absorbed stream amounts to."
    @spec result(state()) :: Result.t()
    def result(state) do
      refusal = IO.iodata_to_binary(state.refusal)
      content = IO.iodata_to_binary(state.content)

      %Result{
        content: if(content == "" and refusal != "", do: refusal, else: content),
        model: state.model,
        finish_reason: state.finish_reason,
        refusal?: refusal != "" or state.finish_reason == "content_filter",
        tool_calls: state.tool_calls |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)),
        usage: state.usage || %Usage{estimated: true}
      }
    end
  end
end

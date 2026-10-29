defmodule Oneiroi.Nisaba.Provider.OpenRouter do
  @moduledoc """
  The real provider: OpenRouter's chat completions over Req (spec §2.1),
  on the steward's own key. The only module in the tree that talks to a
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
  alias Oneiroi.Nisaba.Provider.{Request, Result, Usage}

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
    into = fn {:data, data}, {req, resp} ->
      {events, rest} = __MODULE__.SSE.feed((resp.private[:sse_buffer] || "") <> data)

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

    case Req.post(url(),
           json: body(request, true),
           headers: headers(key),
           receive_timeout: timeout(),
           into: into
         ) do
      {:ok, %Req.Response{status: 200, private: %{sse_state: state}}} ->
        {:ok, __MODULE__.SSE.result(state)}

      {:ok, %Req.Response{status: 200}} ->
        {:error, {:schema_invalid, :empty_stream}}

      {:ok, %Req.Response{status: status, private: private}} ->
        classify(status, Map.get(private, :raw, ""))

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

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
  defp summarize(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp summarize(%{"error" => error}) when is_binary(error), do: error
  defp summarize(text) when is_binary(text), do: String.slice(text, 0, 200)
  defp summarize(_other), do: :unparseable

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
            tool_calls: %{non_neg_integer() => map()}
          }

    @doc "An empty accumulator."
    @spec initial() :: state()
    def initial,
      do: %{content: [], model: nil, finish_reason: nil, refusal: [], usage: nil, tool_calls: %{}}

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

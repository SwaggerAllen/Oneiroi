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

  alias Oneiroi.Nisaba.Provider.{Request, Result, Usage}

  @key :nisaba_fake_script
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
  here as the JSON string a model writes).
  """
  @spec calls([map()], String.t(), keyword()) :: :ok
  def calls(calls, reply, opts \\ []) when is_list(calls) and is_binary(reply) do
    script(
      fn %Request{messages: messages} ->
        if Enum.any?(messages, &(&1[:role] == :tool)),
          do: {:ok, reply},
          else: {:calls, calls}
      end,
      opts
    )
  end

  @doc "Scripts a failure of the given kind (`:transport` or `:schema_invalid`)."
  @spec fail(:transport | :schema_invalid, keyword()) :: :ok
  def fail(kind, opts \\ []) when kind in [:transport, :schema_invalid],
    do: script(fn _request -> {:error, {kind, :scripted}} end, opts)

  @doc "Forgets this process's script and, with `for:`, a resident's."
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    Process.delete(@key)
    if resident_id = Keyword.get(opts, :for), do: :ets.delete(table(), resident_id)
    :ok
  end

  @doc "The fake's flat price per token, in nano-dollars."
  @spec nanos_per_token() :: pos_integer()
  def nanos_per_token, do: @nanos_per_token

  @impl Oneiroi.Nisaba.Provider
  def complete(%Request{} = request, key) when is_binary(key) do
    case answer(request) do
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
          ArgumentError -> @table
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

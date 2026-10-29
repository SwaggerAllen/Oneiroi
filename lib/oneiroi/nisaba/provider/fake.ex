defmodule Oneiroi.Nisaba.Provider.Fake do
  @moduledoc """
  The in-memory provider (conventions §9): what every test calls, and
  what `NISABA_PROVIDER=fake` selects. It answers deterministically from
  the request unless the calling process scripted an answer, and it
  prices every token the same, so a test can assert a cost it can
  compute by hand.

  Scripts are per process: a test sets one and the call runs in the test's
  own process. A brain process of its own, later, sees the default answer
  unless the test scripts through it.
  """
  @behaviour Oneiroi.Nisaba.Provider

  alias Oneiroi.Nisaba.Provider.{Request, Result, Usage}

  @key :nisaba_fake_script
  # A flat fake price: one micro-dollar a token, so a 30-token call costs
  # 30,000 nano-dollars and the arithmetic in a test is legible.
  @nanos_per_token 1_000

  @type answer ::
          {:ok, String.t()}
          | {:refusal, String.t()}
          | {:error, Oneiroi.Nisaba.Provider.failure()}

  @doc "Scripts the next answers for this process: a function of the request."
  @spec script((Request.t() -> answer())) :: :ok
  def script(fun) when is_function(fun, 1) do
    Process.put(@key, fun)
    :ok
  end

  @doc "Scripts a fixed reply."
  @spec reply(String.t()) :: :ok
  def reply(text) when is_binary(text), do: script(fn _request -> {:ok, text} end)

  @doc "Scripts a refusal, in the model's words."
  @spec refuse(String.t()) :: :ok
  def refuse(text) when is_binary(text), do: script(fn _request -> {:refusal, text} end)

  @doc "Scripts a failure of the given kind (`:transport` or `:schema_invalid`)."
  @spec fail(:transport | :schema_invalid) :: :ok
  def fail(kind) when kind in [:transport, :schema_invalid],
    do: script(fn _request -> {:error, {kind, :scripted}} end)

  @doc "Forgets this process's script."
  @spec clear() :: :ok
  def clear do
    Process.delete(@key)
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
    case Process.get(@key) do
      nil -> {:ok, default(request)}
      fun -> fun.(request)
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

  defp tokens(nil), do: 0
  defp tokens(text) when is_binary(text), do: text |> String.split() |> length()
end

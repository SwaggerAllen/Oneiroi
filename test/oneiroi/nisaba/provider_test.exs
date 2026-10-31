defmodule Oneiroi.Nisaba.ProviderTest do
  @moduledoc """
  The port's two implementations, with no network: the fake's scripting
  and pricing, and the OpenRouter adapter's request shape, response
  parsing and stream parsing over an OpenAI-compatible fixture. The
  stream fixture is hand-written from OpenRouter's documented format,
  not recorded (conventions §9), and a live run on the witness's key is
  the measurement that confirms it.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Provider.{Embedding, Fake, OpenRouter, Request, Result, Usage}
  alias Oneiroi.Nisaba.Provider.OpenRouter.SSE

  @request Request.new("fake/model", [
             %{role: :user, content: "three words here"}
           ])

  describe "the fake" do
    test "answers from the request by default and prices every token the same" do
      assert {:ok, %Result{} = r} = Fake.complete(@request, "key")
      assert r.content == "The fake provider heard: three words here"
      assert r.refusal? == false
      assert r.usage.prompt_tokens == 3
      assert r.usage.completion_tokens == 7
      assert r.usage.cost_nanos == 10 * Fake.nanos_per_token()
      assert r.usage.estimated == false
    end

    test "refuses a tool message the chat format refuses, as the provider does" do
      tools = [%{type: "function", function: %{name: "t"}}]
      call = %{id: "c1", type: "function", function: %{name: "t", arguments: "{}"}}
      asks = %{role: :assistant, content: "", tool_calls: [call]}
      answers = %{role: :tool, tool_call_id: "c1", content: "done"}
      user = %{role: :user, content: "hi"}
      refused = &match?({:error, {:schema_invalid, {:status, 400, _}}}, Fake.complete(&1, "k"))

      assert {:ok, %Result{}} =
               Fake.complete(Request.new("m", [user, asks, answers], tools: tools), "k")

      # A bare tool message, as a replayed transcript once sent one.
      assert refused.(Request.new("m", [user, %{role: :tool, content: "done"}], tools: tools))
      # An answer to a call nobody made.
      assert refused.(Request.new("m", [user, %{answers | tool_call_id: "c2"}], tools: tools))
      # A call left unanswered, before more words and at the end.
      assert refused.(Request.new("m", [user, asks, user], tools: tools))
      assert refused.(Request.new("m", [user, asks], tools: tools))
      # Either half in a request that names no tools.
      assert refused.(Request.new("m", [user, asks, answers]))
    end

    test "a scripted reply, refusal and failure, per process" do
      Fake.reply("scripted")
      assert {:ok, %Result{content: "scripted", refusal?: false}} = Fake.complete(@request, "k")

      Fake.refuse("I would rather not.")

      assert {:ok, %Result{content: "I would rather not.", refusal?: true}} =
               Fake.complete(@request, "k")

      Fake.fail(:transport)
      assert {:error, {:transport, :scripted}} = Fake.complete(@request, "k")

      Fake.clear()

      assert {:ok, %Result{content: "The fake provider heard: " <> _}} =
               Fake.complete(@request, "k")
    end

    test "embeds deterministically at the pinned width, unit length, near for shared words, and fails when scripted" do
      assert {:ok, %Embedding{model: "fake/embed", vectors: [a, b, c], usage: usage}} =
               Fake.embed(
                 "fake/embed",
                 ["roses by the gate", "roses by the wall", "salt and gulls"],
                 "k"
               )

      assert length(a) == Fake.width() and Fake.width() == 1536
      assert_in_delta Enum.sum(Enum.map(a, &(&1 * &1))), 1.0, 1.0e-9

      assert a ==
               elem(
                 Fake.embed("fake/embed", ["roses by the gate"], "k")
                 |> elem(1)
                 |> Map.fetch!(:vectors)
                 |> List.pop_at(0),
                 0
               )

      dot = fn x, y -> Enum.zip(x, y) |> Enum.map(fn {p, q} -> p * q end) |> Enum.sum() end
      assert dot.(a, b) > dot.(a, c)
      assert usage.prompt_tokens == 11 and usage.completion_tokens == 0
      assert usage.cost_nanos == 11 * Fake.nanos_per_token()

      Fake.embed_fail(:transport)
      assert {:error, {:transport, :scripted}} = Fake.embed("fake/embed", ["x"], "k")
      Fake.clear()
      assert {:ok, _} = Fake.embed("fake/embed", ["x"], "k")
    end

    test "streams the reply in pieces to the sink and returns the same result" do
      Fake.reply("one two three")
      parent = self()

      assert {:ok, %Result{content: "one two three"}} =
               Fake.stream(@request, "k", &send(parent, {:delta, &1}))

      assert_received {:delta, "one "}
      assert_received {:delta, "two "}
      assert_received {:delta, "three"}
    end
  end

  describe "the OpenRouter adapter, without a network" do
    test "the request body asks for the cost and carries only what was set" do
      body = OpenRouter.body(@request, false)
      assert body.model == "fake/model"
      assert body.messages == [%{role: "user", content: "three words here"}]
      assert body.usage == %{include: true}
      assert body.stream == false
      refute Map.has_key?(body, :max_tokens)

      body = OpenRouter.body(%{@request | max_tokens: 10, temperature: 0.2}, true)
      assert body.max_tokens == 10 and body.temperature == 0.2 and body.stream == true
    end

    test "a completion parses with its reported cost in nano-dollars" do
      assert {:ok, %Result{} = r} =
               OpenRouter.parse(%{
                 "model" => "openai/gpt-4o-mini",
                 "choices" => [
                   %{"message" => %{"content" => "hello"}, "finish_reason" => "stop"}
                 ],
                 "usage" => %{
                   "prompt_tokens" => 10,
                   "completion_tokens" => 2,
                   "cost" => 0.0000195
                 }
               })

      assert r.content == "hello" and r.model == "openai/gpt-4o-mini"

      assert r.usage == %Usage{
               prompt_tokens: 10,
               completion_tokens: 2,
               cost_nanos: 19_500,
               estimated: false
             }

      refute r.refusal?
    end

    test "a refusal is an ordinary result in the model's words, and a missing cost is marked estimated" do
      assert {:ok, %Result{} = r} =
               OpenRouter.parse(%{
                 "choices" => [
                   %{
                     "message" => %{"content" => nil, "refusal" => "I can't help with that."},
                     "finish_reason" => "stop"
                   }
                 ],
                 "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2}
               })

      assert r.refusal? and r.content == "I can't help with that."
      assert r.usage.estimated and r.usage.cost_nanos == 0

      assert {:error, {:schema_invalid, _}} = OpenRouter.parse(%{"error" => %{"message" => "no"}})

      # A streamed refusal is raw text: its message is kept and its
      # metadata, where a moderation hit's input would sit, is not.
      raw =
        Jason.encode!(%{
          "error" => %{
            "message" => "Input was flagged",
            "metadata" => %{"flagged_input" => "what she said"}
          }
        })

      assert OpenRouter.summarize(raw) == "Input was flagged"
      assert OpenRouter.summarize("<html>bad gateway</html>") == "<html>bad gateway</html>"
      assert OpenRouter.summarize(~s({"other": 1})) == :unparseable
    end

    test "tool calls carry the arguments as the model wrote them" do
      assert [%{id: "c1", name: "bookmark_add", arguments: ~s({"line":"x"})}] =
               OpenRouter.tool_calls([
                 %{
                   "id" => "c1",
                   "type" => "function",
                   "function" => %{"name" => "bookmark_add", "arguments" => ~s({"line":"x"})}
                 }
               ])
    end

    test "a stream of deltas assembles the reply, the usage from the last chunk, and the sink saw every delta" do
      wire =
        ": OPENROUTER PROCESSING\n\n" <>
          ~s(data: {"model":"openai/gpt-4o-mini","choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}\n\n) <>
          ~s(data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}\n\n) <>
          ~s(data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":1,"cost":0.000001}}\n\n) <>
          "data: [DONE]\n\n"

      # Fed in two halves split mid-event, as a socket delivers it.
      {a, b} = String.split_at(wire, 70)
      {events1, rest} = SSE.feed(a)
      {events2, ""} = SSE.feed(rest <> b)

      parent = self()

      state =
        Enum.reduce(
          events1 ++ events2,
          SSE.initial(),
          &SSE.absorb(&2, &1, fn d -> send(parent, {:delta, d}) end)
        )

      assert %Result{content: "Hello", model: "openai/gpt-4o-mini", finish_reason: "stop"} =
               r = SSE.result(state)

      assert r.usage == %Usage{
               prompt_tokens: 5,
               completion_tokens: 1,
               cost_nanos: 1_000,
               estimated: false
             }

      assert_received {:delta, "Hel"}
      assert_received {:delta, "lo"}
    end

    test "streamed tool calls assemble by index across deltas" do
      chunks = [
        %{
          "choices" => [
            %{
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 0,
                    "id" => "c1",
                    "function" => %{"name" => "f", "arguments" => "{\"a\":"}
                  }
                ]
              }
            }
          ]
        },
        %{
          "choices" => [
            %{
              "delta" => %{
                "tool_calls" => [%{"index" => 0, "function" => %{"arguments" => "1}"}}]
              },
              "finish_reason" => "tool_calls"
            }
          ]
        }
      ]

      state = Enum.reduce(chunks, SSE.initial(), &SSE.absorb(&2, &1, fn _ -> :ok end))

      assert %Result{
               tool_calls: [%{id: "c1", name: "f", arguments: "{\"a\":1}"}],
               finish_reason: "tool_calls"
             } = SSE.result(state)
    end
  end

  describe "the OpenRouter embeddings reply" do
    test "is parsed in input order with its usage, and a wrong shape is a refused request" do
      body = %{
        "model" => "openai/text-embedding-3-small",
        "data" => [
          %{"index" => 1, "embedding" => [0.5, 0.5]},
          %{"index" => 0, "embedding" => [1.0, 0.0]}
        ],
        "usage" => %{"prompt_tokens" => 6, "total_tokens" => 6}
      }

      assert {:ok,
              %Embedding{
                model: "openai/text-embedding-3-small",
                vectors: vectors,
                usage: %Usage{prompt_tokens: 6, cost_nanos: 0, estimated: true}
              }} =
               OpenRouter.parse_embedding(body, "asked/model")

      assert vectors == [[1.0, 0.0], [0.5, 0.5]]

      assert {:error, {:schema_invalid, :embedding_shape}} =
               OpenRouter.parse_embedding(%{"data" => [%{"embedding" => "no"}]}, "m")

      assert {:error, {:schema_invalid, {:unexpected_body, _}}} =
               OpenRouter.parse_embedding(%{"error" => %{"message" => "nope"}}, "m")
    end
  end
end

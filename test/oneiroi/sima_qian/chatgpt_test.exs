defmodule Oneiroi.SimaQian.ChatGPTTest do
  @moduledoc """
  sima-qian#47: a ChatGPT export read defensively (research #14): the
  canonical path rebuilt from parents, current_node missing or dangling,
  memories and instructions from the tree, lone surrogates repaired,
  media parts and unreadable shards logged as gaps, shards in order.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.SimaQian.ChatGPT

  defp node(id, parent, role, text, t, extra \\ %{}) do
    {id,
     %{
       "id" => id,
       "parent" => parent,
       "message" =>
         Map.merge(
           %{
             "author" => %{"role" => role},
             "create_time" => t,
             "content" => %{"content_type" => "text", "parts" => [text]},
             "metadata" => %{"model_slug" => if(role == "assistant", do: "gpt-4o")}
           },
           extra
         )
     }}
  end

  defp export(dir, name, conversations),
    do: File.write!(Path.join(dir, name), Jason.encode!(conversations))

  setup do
    dir = Path.join(System.tmp_dir!(), "chatgpt-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "the canonical path from current_node, a regeneration left aside, memories from the tree",
       ctx do
    mapping =
      Map.new([
        {"root", %{"id" => "root", "parent" => nil, "message" => nil}},
        node("u1", "root", "user", "hello", 1_700_000_000.5),
        node("a1", "u1", "assistant", "first try", 1_700_000_001.0),
        node("a2", "u1", "assistant", "second try", 1_700_000_002.0),
        node("m", "a2", "system", "", 1_700_000_003.0, %{
          "content" => %{
            "content_type" => "model_editable_context",
            "model_set_context" => "1. [2026-10-01]. Likes herons."
          }
        }),
        node("u2", "m", "user", "and then?", 1_700_000_004.0)
      ])

    export(ctx.dir, "conversations.json", [
      %{
        "id" => "c1",
        "title" => "Herons",
        "create_time" => 1_700_000_000.0,
        "current_node" => "u2",
        "mapping" => mapping
      }
    ])

    assert {:ok, %{conversations: [c], context: [mem], gaps: []}} = ChatGPT.read(ctx.dir)
    assert Enum.map(c.messages, & &1.text) == ["hello", "second try", "and then?"]
    assert [%{role: :user}, %{role: :assistant, model: "gpt-4o"}, %{role: :user}] = c.messages
    assert %{kind: :memories, text: "1. [2026-10-01]. Likes herons.", conversation: "c1"} = mem
    assert hd(c.messages).at == ~U[2023-11-14 22:13:20.500000Z]
  end

  test "no current_node: the most recent leaf; a dangling one is said; media and lone surrogates are gaps",
       ctx do
    mapping =
      Map.new([
        node("u1", nil, "user", "look", 1_700_000_000.0, %{
          "content" => %{
            "content_type" => "multimodal_text",
            "parts" => [%{"asset_pointer" => "file-1"}, "at this"]
          }
        }),
        node("a1", "u1", "assistant", "older", 1_700_000_001.0),
        node("a2", "u1", "assistant", "newer", 1_700_000_009.0)
      ])

    json =
      Jason.encode!([
        %{
          "id" => "c2",
          "title" => "Look",
          "create_time" => 1_700_000_000.0,
          "mapping" => mapping
        },
        %{
          "id" => "c3",
          "title" => "Gone",
          "current_node" => "nowhere",
          "mapping" => Map.new([node("x", nil, "user", "lone", 1_600_000_000.0)])
        }
      ])
      |> String.replace("lone", "lone \\ud83d")

    File.write!(Path.join(ctx.dir, "conversations-1.json"), json)
    File.write!(Path.join(ctx.dir, "conversations-2.json"), "{not json")

    assert {:ok, %{conversations: [gone, look], gaps: gaps}} = ChatGPT.read(ctx.dir)
    assert Enum.map(look.messages, & &1.text) == ["at this", "newer"]
    assert gone.messages |> hd() |> Map.get(:text) == "lone �"

    kinds = Enum.map(gaps, & &1.kind)
    assert :surrogates_repaired in kinds
    assert :shard_unreadable in kinds
    assert :no_current_node in kinds
    assert :dangling_current_node in kinds
    assert :media_part in kinds
  end

  # Lily's ask (#178): a children array that contradicts the canonical
  # path is followed nowhere and said in the gap log.
  test "a children array contradicting the parents is not followed, and the disagreement is a gap",
       ctx do
    {"u1", u1} = node("u1", nil, "user", "which way?", 1_700_000_000.0)
    {"a1", a1} = node("a1", "u1", "assistant", "this way", 1_700_000_001.0)
    {"ghost", ghost} = node("ghost", "u1", "assistant", "the other way", 1_700_000_002.0)
    # u1's array names a1 only, but ghost is also u1's child, and a1's names ghost as its child.
    mapping = %{
      "u1" => Map.put(u1, "children", ["a1"]),
      "a1" => Map.put(a1, "children", ["ghost"]),
      "ghost" => ghost
    }

    export(ctx.dir, "conversations.json", [
      %{
        "id" => "c9",
        "title" => "Forks",
        "create_time" => 1_700_000_000.0,
        "current_node" => "a1",
        "mapping" => mapping
      }
    ])

    assert {:ok, %{conversations: [c], gaps: gaps}} = ChatGPT.read(ctx.dir)
    assert Enum.map(c.messages, & &1.text) == ["which way?", "this way"]

    assert [%{kind: :children_disagree, detail: detail}] =
             Enum.filter(gaps, &(&1.kind == :children_disagree))

    assert detail =~ "a1 names ghost"
  end

  test "no conversations file at all", ctx do
    assert :none = ChatGPT.read(ctx.dir)
  end
end

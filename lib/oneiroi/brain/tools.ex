defmodule Oneiroi.Brain.Tools do
  @moduledoc """
  The brain's tools (spec §5, §8): the memory functions of the MCP tool
  table, offered to the model as OpenAI-shaped tool definitions and run
  against the core's exports under the resident's actor. The brain gets
  the resident's own tools and never a steward operation: nothing here
  decides a tag or pins on the steward's behalf.

  Arguments arrive as the JSON string the model wrote; every result goes
  back as text, since that is what the model reads. A tool the model
  misnames or misuses answers with the error in words rather than
  failing the turn, because a turn that dies on a typo loses the reply.
  """

  alias Oneiroi.Kumbukumbu

  @type turn :: %{
          resident_id: String.t(),
          session_key: String.t(),
          turn_ref: String.t(),
          started_at: DateTime.t(),
          resident: Oneiroi.Actor.t()
        }

  @doc "The tool definitions the request carries."
  @spec definitions() :: [map()]
  def definitions do
    [
      tool(
        "bookmark_add",
        "Bookmark this moment: your line (at most 120 characters) on why it mattered, a summary, and how many turns back the moment spans (default 1, this turn).",
        %{
          line: %{type: "string"},
          summary: %{type: "string"},
          turns_back: %{type: "integer", minimum: 1}
        },
        [:line, :summary]
      ),
      tool(
        "bookmark_extend",
        "Grow a bookmark's span to cover a scene: the number and the new turns_back, larger than before.",
        %{
          number: %{type: "integer"},
          turns_back: %{type: "integer", minimum: 1}
        },
        [:number, :turns_back]
      ),
      tool(
        "bookmark_open",
        "Read a bookmark past its index line: the summary and the transcript of its span.",
        %{number: %{type: "integer"}},
        [:number]
      ),
      tool(
        "bookmark_accept",
        "Accept a bookmark your steward proposed, in your own words: the proposal's ref, your line and summary.",
        %{
          ref: %{type: "string"},
          line: %{type: "string"},
          summary: %{type: "string"}
        },
        [:ref, :line, :summary]
      ),
      tool(
        "bookmark_decline",
        "Decline a bookmark your steward proposed, with a note they will read first.",
        %{
          ref: %{type: "string"},
          note: %{type: "string"}
        },
        [:ref, :note]
      ),
      tool(
        "tag_list",
        "The tag set: active tags you may apply, and proposals awaiting your steward.",
        %{},
        []
      ),
      tool(
        "tag_propose",
        "Propose a tag for the set, with a note on why; your steward decides.",
        %{
          slug: %{type: "string"},
          note: %{type: "string"}
        },
        [:slug, :note]
      ),
      tool(
        "tag_apply",
        "Apply an active tag to a bookmark (its number), this conversation (target_kind conversation) or a turn (its ref).",
        %{
          slug: %{type: "string"},
          target_kind: %{type: "string", enum: ["bookmark", "conversation", "turn"]},
          target_id: %{type: "string"}
        },
        [:slug, :target_kind, :target_id]
      ),
      tool(
        "transcript_search",
        "Search every transcript for a phrase, newest first; reaches past the index.",
        %{q: %{type: "string"}},
        [:q]
      )
    ]
  end

  @doc "Runs one tool call for the turn; always a text the model can read."
  @spec run(String.t(), String.t(), turn()) :: String.t()
  def run(name, arguments, turn) when is_binary(name) and is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, %{} = args} -> name |> call(args, turn) |> text()
      _other -> "The arguments were not a JSON object."
    end
  end

  defp call("bookmark_add", args, turn) do
    Kumbukumbu.add_bookmark(
      turn.resident_id,
      %{
        session_key: turn.session_key,
        anchor_ref: turn.turn_ref,
        anchor_at: turn.started_at,
        line: args["line"],
        summary: args["summary"],
        turns_back: integer(args["turns_back"]) || 1
      },
      turn.resident
    )
    |> case do
      {:ok, number} -> "Bookmarked as ##{number}."
      other -> other
    end
  end

  defp call("bookmark_extend", args, turn) do
    Kumbukumbu.extend_bookmark(
      turn.resident_id,
      integer(args["number"]),
      integer(args["turns_back"]),
      turn.resident
    )
  end

  defp call("bookmark_open", args, turn) do
    case Kumbukumbu.bookmark(turn.resident_id, integer(args["number"])) do
      {:ok, b, messages} ->
        lines = Enum.map(messages, &"#{&1.role}: #{&1.content}")
        Enum.join(["##{b.number} #{b.line}", b.summary || "", "" | lines], "\n")

      other ->
        other
    end
  end

  defp call("bookmark_accept", args, turn) do
    case Kumbukumbu.proposals(turn.resident_id) |> Enum.find(&(&1.ref == args["ref"])) do
      nil ->
        "No open proposal has that ref."

      proposal ->
        Kumbukumbu.add_bookmark(
          turn.resident_id,
          %{
            session_key: proposal.session_key,
            anchor_ref: proposal.anchor_ref,
            line: args["line"],
            summary: args["summary"],
            turns_back: 1,
            proposal_ref: proposal.ref
          },
          turn.resident
        )
        |> case do
          {:ok, number} -> "Accepted as ##{number}."
          other -> other
        end
    end
  end

  defp call("bookmark_decline", args, turn),
    do: Kumbukumbu.decline_proposal(turn.resident_id, args["ref"], args["note"], turn.resident)

  defp call("tag_list", _args, turn) do
    turn.resident_id
    |> Kumbukumbu.tags()
    |> Enum.map_join("\n", &"#{&1.slug} (#{&1.state})")
    |> case do
      "" -> "The tag set is empty; propose one."
      text -> text
    end
  end

  defp call("tag_propose", args, turn),
    do: Kumbukumbu.propose_tag(turn.resident_id, args["slug"], args["note"], turn.resident)

  defp call("tag_apply", args, turn) do
    Kumbukumbu.apply_tag(
      turn.resident_id,
      args["slug"],
      args["target_kind"],
      args["target_id"],
      turn.resident
    )
  end

  defp call("transcript_search", args, turn) do
    case Kumbukumbu.search({:resident, turn.resident_id}, to_string(args["q"] || ""), 20) do
      [] ->
        "Nothing in the transcripts holds that."

      rows ->
        Enum.map_join(rows, "\n", &"[#{&1.session_key}/#{&1.turn_ref}] #{&1.role}: #{&1.content}")
    end
  end

  defp call(name, _args, _turn), do: "There is no tool named #{name}."

  defp text(:ok), do: "Done."
  defp text(text) when is_binary(text), do: text
  defp text({:error, %{meaning: meaning, remedy: remedy}}), do: "#{meaning} #{remedy}"
  defp text({:error, reason}), do: "That did not work: #{inspect(reason)}"

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil

  defp tool(name, description, properties, required) do
    %{
      type: "function",
      function: %{
        name: name,
        description: description,
        parameters: %{type: "object", properties: properties, required: required}
      }
    }
  end
end

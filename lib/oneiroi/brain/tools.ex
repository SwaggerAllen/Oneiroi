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

  alias Oneiroi.Eunomia
  alias Oneiroi.HuginnMuninn
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
        "position_take",
        "Take a position: a statement you hold, in your words (at most 1,000 characters). It is yours until you replace it.",
        %{statement: %{type: "string"}},
        [:statement]
      ),
      tool(
        "position_replace",
        "Replace a position you hold with a new statement; the old one stays in the chain as what you used to think. Only the current head of a chain can be replaced.",
        %{number: %{type: "integer"}, statement: %{type: "string"}},
        [:number, :statement]
      ),
      tool("position_list", "The positions you hold now, with their numbers.", %{}, []),
      tool(
        "dispute_check",
        "When you and your steward disagree, ask the judge before answering: the steward's claim, your stance, and the number of the position at stake if there is one. The judge advises concede, hold or unclear, or you are told to answer alone if it takes too long. Settle it afterwards with dispute_settle.",
        %{
          claim: %{type: "string"},
          stance: %{type: "string"},
          position_number: %{type: "integer"}
        },
        [:claim, :stance]
      ),
      tool(
        "dispute_settle",
        "Settle a dispute you checked: conceded or held, with a note on why.",
        %{
          ref: %{type: "string"},
          outcome: %{type: "string", enum: ["conceded", "held"]},
          note: %{type: "string"}
        },
        [:ref, :outcome, :note]
      ),
      tool(
        "prediction_log",
        "Log a prediction: what you expect, and when it is due (an ISO 8601 instant). Your steward resolves it right, wrong or void.",
        %{statement: %{type: "string"}, due: %{type: "string"}},
        [:statement, :due]
      ),
      tool("prediction_list", "Your predictions: open soonest first, then resolved.", %{}, []),
      tool(
        "figure_list",
        "The figures: counters your steward defined, with their values counted from every increment, and countdowns to dates.",
        %{},
        []
      ),
      tool(
        "figure_increment",
        "Increment a counter by its key (by 1 unless said; negative corrects), with a note on why: your increment carries your name.",
        %{key: %{type: "string"}, by: %{type: "integer"}, note: %{type: "string"}},
        [:key, :note]
      ),
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
      ),
      tool(
        "soul_edit",
        "Edit one of your identity files yourself (SOUL.md, IDENTITY.md, USER.md, GOALS.md, LINKS.md): the whole new content. Rare, visible, one change at a time.",
        %{file: %{type: "string"}, content: %{type: "string"}},
        [:file, :content]
      ),
      tool(
        "soul_edit_list",
        "Your steward's open proposals to edit your identity files, each with its note.",
        %{},
        []
      ),
      tool(
        "soul_edit_accept",
        "Accept a proposed edit, with a note your steward reads first.",
        %{ref: %{type: "string"}, note: %{type: "string"}},
        [:ref, :note]
      ),
      tool(
        "soul_edit_decline",
        "Decline a proposed edit, with a note your steward reads first.",
        %{ref: %{type: "string"}, note: %{type: "string"}},
        [:ref, :note]
      ),
      tool(
        "behaviour_define",
        "Name how you tend to act, in your own words, with the situation that calls for it (words your steward uses, tags on the conversation, times of day: morning, afternoon, evening, night) and whether you mean to keep or change it.",
        %{
          name: %{type: "string"},
          words: %{type: "array", items: %{type: "string"}},
          tags: %{type: "array", items: %{type: "string"}},
          times: %{
            type: "array",
            items: %{type: "string", enum: ["morning", "afternoon", "evening", "night"]}
          },
          stance: %{type: "string", enum: ["keep", "change"]}
        },
        [:name, :stance]
      ),
      tool(
        "behaviour_enact",
        "This turn was one: record that you enacted a behaviour just now, by its number.",
        %{number: %{type: "integer"}},
        [:number]
      ),
      tool("behaviour_list", "Your behaviours with their habit and connection scores.", %{}, [])
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

  defp call("soul_edit", args, turn),
    do:
      Oneiroi.AgathosDaimon.write_file(
        turn.resident_id,
        to_string(args["file"]),
        to_string(args["content"]),
        %{},
        turn.resident
      )

  defp call("soul_edit_list", _args, turn) do
    case Oneiroi.AgathosDaimon.edit_proposals(turn.resident_id) do
      [] ->
        "No proposals are open."

      rows ->
        Enum.map_join(rows, "\n\n", fn p ->
          "[#{p.ref}] #{p.file}, note: #{p.note}\n---\n#{p.content}"
        end)
    end
  end

  defp call("soul_edit_accept", args, turn),
    do:
      Oneiroi.AgathosDaimon.accept_edit(
        turn.resident_id,
        args["ref"],
        args["note"],
        turn.resident
      )

  defp call("soul_edit_decline", args, turn),
    do:
      Oneiroi.AgathosDaimon.decline_edit(
        turn.resident_id,
        args["ref"],
        args["note"],
        turn.resident
      )

  defp call("behaviour_define", args, turn) do
    Kumbukumbu.define_behaviour(
      turn.resident_id,
      %{
        name: args["name"],
        trigger: %{
          "words" => args["words"] || [],
          "tags" => args["tags"] || [],
          "times" => args["times"] || []
        },
        stance: args["stance"] || "keep"
      },
      turn.resident
    )
    |> case do
      {:ok, number} -> "Named as behaviour ##{number}."
      other -> other
    end
  end

  defp call("behaviour_enact", args, turn),
    do:
      Kumbukumbu.enact_behaviour(
        turn.resident_id,
        integer(args["number"]),
        "turn",
        turn.turn_ref,
        turn.resident
      )

  defp call("behaviour_list", _args, turn) do
    case Kumbukumbu.behaviours(turn.resident_id) do
      [] ->
        "No behaviours named yet."

      rows ->
        Enum.map_join(
          rows,
          "\n",
          &"##{&1.number} #{&1.name} (#{&1.stance}): habit #{&1.habit}, connection #{&1.connection}"
        )
    end
  end

  # ---- judgement (spec §6.4) ----

  defp call("position_take", args, turn) do
    case Eunomia.take_position(turn.resident_id, args["statement"], context(turn), turn.resident) do
      {:ok, number} -> "Position ##{number} taken."
      other -> other
    end
  end

  defp call("position_replace", args, turn) do
    turn.resident_id
    |> Eunomia.replace_position(
      integer(args["number"]),
      args["statement"],
      context(turn),
      turn.resident
    )
    |> case do
      {:ok, number} -> "Position ##{number} now stands where ##{integer(args["number"])} did."
      other -> other
    end
  end

  defp call("position_list", _args, turn) do
    case Eunomia.held_positions(turn.resident_id) do
      [] -> "You hold no positions yet."
      rows -> Enum.map_join(rows, "\n", &"##{&1.number} #{&1.statement}")
    end
  end

  defp call("dispute_check", args, turn) do
    attrs =
      context(turn)
      |> Map.merge(%{
        claim: args["claim"],
        stance: args["stance"],
        position_number: integer(args["position_number"])
      })

    case Eunomia.check_dispute(turn.resident_id, attrs, turn.resident) do
      {:ok, %{outcome: "timed_out", ref: ref}} ->
        "The judge did not answer in time; answer alone, then settle dispute #{ref}."

      {:ok, %{ref: ref, advice: advice, text: text}} ->
        "The judge advises: #{advice}. #{text}\n\nSettle dispute #{ref} once you have answered."

      other ->
        other
    end
  end

  defp call("dispute_settle", args, turn),
    do:
      Eunomia.settle_dispute(
        turn.resident_id,
        args["ref"],
        args["outcome"],
        args["note"],
        turn.resident
      )

  defp call("prediction_log", args, turn) do
    due =
      case DateTime.from_iso8601(to_string(args["due"] || "")) do
        {:ok, at, _offset} -> at
        _other -> nil
      end

    case Eunomia.log_prediction(
           turn.resident_id,
           args["statement"],
           due,
           context(turn),
           turn.resident
         ) do
      {:ok, number} -> "Prediction ##{number} logged."
      other -> other
    end
  end

  defp call("prediction_list", _args, turn) do
    %{open: open, resolved: resolved} = Eunomia.predictions(turn.resident_id)

    lines =
      Enum.map(open, &"##{&1.number} (due #{DateTime.to_iso8601(&1.due)}) #{&1.statement}") ++
        Enum.map(resolved, &"##{&1.number} #{&1.outcome}: #{&1.statement}")

    if lines == [], do: "No predictions yet.", else: Enum.join(lines, "\n")
  end

  # ---- figures (spec §6.13) ----

  defp call("figure_list", _args, turn) do
    case HuginnMuninn.figures(turn.resident_id) do
      [] -> "No figures yet."
      rows -> Enum.map_join(rows, "\n", &"figure/#{&1.key} #{&1.label}: #{&1.value} (#{&1.kind})")
    end
  end

  defp call("figure_increment", args, turn),
    do:
      HuginnMuninn.increment(
        turn.resident_id,
        args["key"],
        integer(args["by"]) || 1,
        args["note"],
        turn.resident
      )

  defp call(name, _args, _turn), do: "There is no tool named #{name}."

  defp context(turn), do: %{session_key: turn.session_key, turn_ref: turn.turn_ref}

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

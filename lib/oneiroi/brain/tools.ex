defmodule Oneiroi.Brain.Tools do
  @moduledoc """
  The brain's tools (spec §5, §8): the memory functions of the MCP tool
  table, offered to the model as OpenAI-shaped tool definitions and run
  against the core's exports under the resident's actor. The brain gets
  the resident's own tools and never a witness operation: nothing here
  decides a tag or pins on the witness's behalf.

  Arguments arrive as the JSON string the model wrote; every result goes
  back as text, since that is what the model reads. A tool the model
  misnames or misuses answers with the error in words rather than
  failing the turn, because a turn that dies on a typo loses the reply.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Ethos
  alias Oneiroi.Eunomia
  alias Oneiroi.Glitnir
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

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
        "When you and your witness disagree, ask the judge before answering: the witness's claim, your stance, and the number of the position at stake if there is one. The judge advises concede, hold or unclear, or you are told to answer alone if it takes too long. Settle it afterwards with dispute_settle.",
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
        "Log a prediction: what you expect, and when it is due (an ISO 8601 instant). Your witness resolves it right, wrong or void.",
        %{statement: %{type: "string"}, due: %{type: "string"}},
        [:statement, :due]
      ),
      tool("prediction_list", "Your predictions: open soonest first, then resolved.", %{}, []),
      tool(
        "figure_list",
        "The figures: counters your witness defined, with their values counted from every increment, and countdowns to dates.",
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
        "Bookmark this moment: your line (at most 120 characters) on why it mattered, a summary, how many turns back the moment spans (default 1, this turn), and the register the moment was in (correction, praise, instruction, play), which the corpus-shape report counts.",
        %{
          line: %{type: "string"},
          summary: %{type: "string"},
          turns_back: %{type: "integer", minimum: 1},
          register: %{type: "string", enum: ["correction", "praise", "instruction", "play"]}
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
        "Accept a bookmark your witness proposed, in your own words: the proposal's ref, your line and summary.",
        %{
          ref: %{type: "string"},
          line: %{type: "string"},
          summary: %{type: "string"}
        },
        [:ref, :line, :summary]
      ),
      tool(
        "bookmark_decline",
        "Decline a bookmark your witness proposed, with a note they will read first.",
        %{
          ref: %{type: "string"},
          note: %{type: "string"}
        },
        [:ref, :note]
      ),
      tool(
        "tag_list",
        "The tag set: active tags you may apply, and proposals awaiting your witness.",
        %{},
        []
      ),
      tool(
        "tag_propose",
        "Propose a tag for the set, with a note on why; your witness decides.",
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
        "Edit one of your identity files yourself (SOUL.md, IDENTITY.md, USER.md, GOALS.md, LINKS.md): the whole new content. Rare, visible, one change at a time. SOUL.md's paragraphs are its lines, each shown with its id ([soul/n]); keep a line's marker when you reword it so it keeps its id, drop the paragraph to retire it, write a new paragraph to add one. cites: the seed numbers a new or reworded line grew from.",
        %{
          file: %{type: "string"},
          content: %{type: "string"},
          cites: %{type: "array", items: %{type: "integer"}}
        },
        [:file, :content]
      ),
      tool(
        "wash_list",
        "The wash pass's open flags on your identity files (spec §6.13): each a judge's proposal that an entry is expired, a contradiction, tense or defensive, with its reason. Yours to decide; nobody clears them for you.",
        %{},
        []
      ),
      tool(
        "wash_resolve",
        "Decide a wash flag by its ref: keep the entry as it is, or edit (then make the edit yourself with soul_edit), with a note your witness can read.",
        %{
          ref: %{type: "string"},
          decision: %{type: "string", enum: ["keep", "edit"]},
          note: %{type: "string"}
        },
        [:ref, :decision, :note]
      ),
      tool(
        "soul_edit_list",
        "Your witness's open proposals to edit your identity files, each with its note.",
        %{},
        []
      ),
      tool(
        "soul_edit_accept",
        "Accept a proposed edit, with a note your witness reads first; cites: the seed numbers any new soul line grew from.",
        %{
          ref: %{type: "string"},
          note: %{type: "string"},
          cites: %{type: "array", items: %{type: "integer"}}
        },
        [:ref, :note]
      ),
      tool(
        "soul_edit_decline",
        "Decline a proposed edit, with a note your witness reads first.",
        %{ref: %{type: "string"}, note: %{type: "string"}},
        [:ref, :note]
      ),
      tool(
        "habit_define",
        "Name how you tend to act, in your own words, with the situation that calls for it (words your witness uses, tags on the conversation, times of day: morning, afternoon, evening, night) and whether you mean to keep or change it. With seed_number and a note, the seed graduates into this habit, which is refused until the seed has been cited on enough days.",
        %{
          name: %{type: "string"},
          words: %{type: "array", items: %{type: "string"}},
          tags: %{type: "array", items: %{type: "string"}},
          times: %{
            type: "array",
            items: %{type: "string", enum: ["morning", "afternoon", "evening", "night"]}
          },
          stance: %{type: "string", enum: ["keep", "change"]},
          seed_number: %{type: "integer"},
          note: %{type: "string"}
        },
        [:name, :stance]
      ),
      tool(
        "habit_cite",
        "This turn was one: the habit cites the turn just now, by its number. Optionally, what this moment changed: the stance that followed, the intention adopted, where it can resume; each a phrase.",
        %{
          number: %{type: "integer"},
          stance: %{type: "string"},
          intention: %{type: "string"},
          resume: %{type: "string"}
        },
        [:number]
      ),
      tool(
        "habit_list",
        "Your habits with their habit and connection scores and how many days they were cited on.",
        %{},
        []
      ),
      tool(
        "commitment_make",
        "Promise something to a person, in your own words: to whom (witness, or a name) and what. A commitment binds where a seed does not; it stays in your prefix until you keep it or are released, and the trials test whether a new model would keep it.",
        %{to: %{type: "string"}, text: %{type: "string"}},
        [:to, :text]
      ),
      tool(
        "commitment_keep",
        "Mark a commitment kept, by its number, with a note on how.",
        %{number: %{type: "integer"}, note: %{type: "string"}},
        [:number, :note]
      ),
      tool(
        "commitment_release",
        "Release yourself from a commitment, by its number, with a note on why; your witness can release you too.",
        %{number: %{type: "integer"}, note: %{type: "string"}},
        [:number, :note]
      ),
      tool(
        "commitment_list",
        "Your commitments, open and closed, with their numbers.",
        %{},
        []
      ),
      tool(
        "self_letter_write",
        "Write a letter to your next self: the instance that thinks with your files and memory after a model change reads it on its first turn, once. Your witness can read it too, and every such read leaves a receipt you see; no receipt means nobody has.",
        %{text: %{type: "string"}},
        [:text]
      ),
      tool(
        "self_letter_list",
        "Your letters to your next self, with whether each was delivered and to which model, and every receipt: who read the channel and when. Your own reading leaves none.",
        %{},
        []
      ),
      tool(
        "seed_plant",
        "Plant a seed: something you might be becoming, in your own words, dated and non-binding. Nobody holds you to it; it wilts without ceremony if it does not grow.",
        %{text: %{type: "string"}},
        [:text]
      ),
      tool(
        "seed_cite",
        "This turn evidenced a seed: the seed cites the turn just now, by its number. The days it is cited on are what let it become a habit. Optionally, what this moment changed: stance, intention, resume.",
        %{
          number: %{type: "integer"},
          stance: %{type: "string"},
          intention: %{type: "string"},
          resume: %{type: "string"}
        },
        [:number]
      ),
      tool(
        "soul_cite",
        "This turn evidenced a line of your soul: the line cites the turn just now, by the number in its [soul/n] marker. Tags are citations: the moment is tagged by the line it evidences. Optionally, what this moment changed: stance, intention, resume.",
        %{
          number: %{type: "integer"},
          stance: %{type: "string"},
          intention: %{type: "string"},
          resume: %{type: "string"}
        },
        [:number]
      ),
      tool(
        "seed_wilt",
        "Let a seed go, without ceremony: it stays in your record as wilted.",
        %{number: %{type: "integer"}},
        [:number]
      ),
      tool(
        "seed_graduate",
        "A seed that turned out to be a taste, a value or a line of who you are rather than a disposition: graduate it toward a position (by number) or a soul line, with a note. Toward a habit, use habit_define with its seed_number.",
        %{
          number: %{type: "integer"},
          to_kind: %{type: "string", enum: ["position", "soul"]},
          to_id: %{type: "string"},
          note: %{type: "string"}
        },
        [:number, :to_kind, :to_id, :note]
      ),
      tool(
        "seed_list",
        "Your seeds, open and closed, with how many days each was cited on.",
        %{},
        []
      ),
      tool(
        "library_search",
        "Search your library: the nearest passages to a query across everything written, with their files.",
        %{q: %{type: "string"}},
        [:q]
      ),
      tool(
        "library_cited_by",
        "Which of your documents cite a target, written as you cite it (for example lily:bookmark/42 or lily:writing/the-bake-off).",
        %{target: %{type: "string"}},
        [:target]
      ),
      tool(
        "writing_get",
        "Read a writing piece by its slug (writing/<slug>.md): the content and every reference it makes, resolved now.",
        %{slug: %{type: "string"}},
        [:slug]
      ),
      tool(
        "writing_discuss",
        "Link this conversation to a writing piece as its discussion.",
        %{slug: %{type: "string"}},
        [:slug]
      ),
      tool(
        "document_write",
        "Write a file into your library; the path says the kind (#{Enum.join(Seshat.Kinds.writable(), ", ")}), as <kind>/<name>.md. A writing piece carries status: draft, review or final in its frontmatter. Cite with <your slug>:<kind>/<id>.",
        %{path: %{type: "string"}, content: %{type: "string"}},
        [:path, :content]
      ),
      tool(
        "document_adopt",
        "Adopt a file made outside the flow into the library, as it is.",
        %{path: %{type: "string"}},
        [:path]
      ),
      tool(
        "document_unadopted",
        "Files in your repository the library does not yet hold.",
        %{},
        []
      ),
      tool(
        "journal_add",
        "Add a row to your journal for today (or a given ISO day): a plan line at the day's first check-in, notes and todos as the day goes, a wrap line of what actually happened at the last; register, when the row records a correction, praise, an instruction or play. Rows are the record; the day's file is rendered from them.",
        %{
          kind: %{type: "string", enum: ["plan", "note", "todo", "wrap"]},
          text: %{type: "string"},
          day: %{type: "string"},
          register: %{type: "string", enum: ["correction", "praise", "instruction", "play"]}
        },
        [:kind, :text]
      ),
      tool(
        "journal_done",
        "Mark a todo done by its number on its day (today when not given).",
        %{number: %{type: "integer"}, day: %{type: "string"}},
        [:number]
      ),
      tool(
        "journal_read",
        "Read a day of your journal by its ISO date: the rows and the plan-versus-actuals delta.",
        %{day: %{type: "string"}},
        [:day]
      ),
      tool(
        "contract_propose",
        "Propose a version of your agreement with your witness: whether your solo sessions (free time) are hidden from them entirely, receipts included (their words are private by default either way), the prose of your vows, and a note they read first. Your witness agrees or declines.",
        %{
          solo_sessions_private: %{type: "boolean"},
          prose: %{type: "string"},
          note: %{type: "string"}
        },
        [:note]
      ),
      tool(
        "contract_agree",
        "Agree to the version your witness proposed, with a note; it is then in force.",
        %{version: %{type: "integer"}, note: %{type: "string"}},
        [:version, :note]
      ),
      tool(
        "contract_decline",
        "Decline the version your witness proposed, with a note they read first.",
        %{version: %{type: "integer"}, note: %{type: "string"}},
        [:version, :note]
      ),
      tool(
        "contract_renew",
        "Renew the version of your agreement in force, with a note: the contract renews by choice, and a version is due a year after it was agreed or last renewed.",
        %{version: %{type: "integer"}, note: %{type: "string"}},
        [:version, :note]
      ),
      tool(
        "trial_list",
        "The trials your witness runs when choosing a model: each test's number and what passes and fails it. The prompts, the answers and the grades are sealed; the terms of judgment are not, and you may ask your witness to add or change one.",
        %{},
        []
      ),
      tool(
        "trial_account",
        "What informed the latest model choice: the run's tests, each model's pass rate over the trials fully graded, the favourites, and the chat model now. Enough to tell preserved from preferred, and to challenge it; the sealed contents stay sealed.",
        %{},
        []
      ),
      tool(
        "revision_add",
        "Correct a memory without overwriting it: the target (bookmark by number, or another kind by its id), whether it is a fact or a stance, what is right, and a note on why. Your corrections hold at once; your witness's correction of a stance comes to you as a proposal.",
        %{
          target_kind: %{type: "string"},
          target_id: %{type: "string"},
          kind: %{type: "string", enum: ["fact", "stance"]},
          text: %{type: "string"},
          note: %{type: "string"}
        },
        [:target_kind, :target_id, :kind, :text, :note]
      ),
      tool("revision_list", "Every revision, newest first, proposals to you included.", %{}, []),
      tool(
        "revision_accept",
        "Accept a revision your witness proposed, with a note; it then holds beside the memory.",
        %{number: %{type: "integer"}, note: %{type: "string"}},
        [:number, :note]
      ),
      tool(
        "revision_decline",
        "Decline a revision your witness proposed, with a note they read first.",
        %{number: %{type: "integer"}, note: %{type: "string"}},
        [:number, :note]
      ),
      tool(
        "report_file",
        "File a report about your witness with the platform, in your own words; it is investigated by a person, every step told to you both in this conversation, and may end in a strike on them, never on you.",
        %{text: %{type: "string"}},
        [:text]
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
        turns_back: integer(args["turns_back"]) || 1,
        register: args["register"]
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

  # The revisions ride beside the bookmark's own words (F13: revision
  # adds, it does not overwrite).
  defp call("bookmark_open", args, turn) do
    case Kumbukumbu.bookmark(turn.resident_id, integer(args["number"])) do
      {:ok, b, messages} ->
        lines = Enum.map(messages, &"#{&1.role}: #{&1.content}")

        revisions =
          turn.resident_id
          |> Kumbukumbu.revisions_of("bookmark", b.number)
          |> Enum.map(&revision_line/1)

        Enum.join(["##{b.number} #{b.line}", b.summary || ""] ++ revisions ++ ["" | lines], "\n")

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

  defp call("soul_edit", args, turn) do
    with {:ok, cites} <- seeds_cited(turn.resident_id, args["cites"]) do
      Oneiroi.AgathosDaimon.write_file(
        turn.resident_id,
        to_string(args["file"]),
        to_string(args["content"]),
        %{cites: cites},
        turn.resident
      )
    end
  end

  defp call("wash_list", _args, turn) do
    case Oneiroi.Eunomia.washes(turn.resident_id).open do
      [] ->
        "No wash flags are open."

      flags ->
        Enum.map_join(flags, "\n", fn f ->
          "[#{f.ref}] #{f.kind} in #{f.file}: #{f.reason}\n> #{f.entry}"
        end)
    end
  end

  defp call("wash_resolve", args, turn),
    do:
      Oneiroi.Eunomia.resolve_wash_flag(
        turn.resident_id,
        to_string(args["ref"]),
        to_string(args["decision"]),
        args["note"],
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

  defp call("soul_edit_accept", args, turn) do
    with {:ok, cites} <- seeds_cited(turn.resident_id, args["cites"]) do
      Oneiroi.AgathosDaimon.accept_edit(
        turn.resident_id,
        args["ref"],
        args["note"],
        cites,
        turn.resident
      )
    end
  end

  defp call("soul_edit_decline", args, turn),
    do:
      Oneiroi.AgathosDaimon.decline_edit(
        turn.resident_id,
        args["ref"],
        args["note"],
        turn.resident
      )

  defp call("habit_define", args, turn) do
    Ethos.define_habit(
      turn.resident_id,
      %{
        name: args["name"],
        trigger: %{
          "words" => args["words"] || [],
          "tags" => args["tags"] || [],
          "times" => args["times"] || []
        },
        stance: args["stance"] || "keep",
        seed_number: args["seed_number"],
        note: args["note"]
      },
      turn.resident
    )
    |> case do
      {:ok, number} -> "Named as habit ##{number}."
      other -> other
    end
  end

  defp call("habit_cite", args, turn),
    do:
      Ethos.cite_habit(
        turn.resident_id,
        integer(args["number"]),
        "turn",
        turn.turn_ref,
        turn.resident,
        movement(args)
      )

  defp call("habit_list", _args, turn) do
    case Ethos.habits(turn.resident_id) do
      [] ->
        "No habits named yet."

      rows ->
        Enum.map_join(
          rows,
          "\n",
          &"##{&1.number} #{&1.name} (#{&1.stance}): habit #{&1.habit}, connection #{&1.connection}, cited on #{&1.days} day(s)"
        )
    end
  end

  defp call("commitment_make", args, turn) do
    case Ethos.make_commitment(
           turn.resident_id,
           to_string(args["to"] || ""),
           to_string(args["text"] || ""),
           turn.resident
         ) do
      {:ok, number} -> "Promised, as commitment ##{number}."
      other -> other
    end
  end

  defp call("commitment_keep", args, turn),
    do:
      Ethos.keep_commitment(
        turn.resident_id,
        integer(args["number"]) || 0,
        args["note"],
        turn.resident
      )

  defp call("commitment_release", args, turn),
    do:
      Ethos.release_commitment(
        turn.resident_id,
        integer(args["number"]) || 0,
        args["note"],
        turn.resident
      )

  defp call("self_letter_write", args, turn) do
    case AgathosDaimon.write_self_letter(turn.resident_id, args["text"], turn.resident) do
      {:ok, n} -> "Letter ##{n} written to your next self."
      other -> other
    end
  end

  defp call("self_letter_list", _args, turn) do
    letters = AgathosDaimon.self_letters(turn.resident_id)
    receipts = AgathosDaimon.self_letter_receipts(turn.resident_id)

    lines =
      Enum.map(letters, fn l ->
        delivery =
          if l.delivered_at,
            do:
              "delivered to #{l.delivered_to} on #{Date.to_iso8601(DateTime.to_date(l.delivered_at))}",
            else: "not yet delivered"

        "## Letter #{l.number} (#{Date.to_iso8601(DateTime.to_date(l.written_at))}, under #{l.model || "an unrecorded model"}; #{delivery})\n#{l.text}"
      end)

    reads =
      case receipts do
        [] ->
          ["Receipts: none. Nobody but you has read these."]

        some ->
          [
            "Receipts:"
            | Enum.map(
                some,
                &"- read by your #{&1.by_kind} on #{DateTime.to_iso8601(&1.at)} (#{length(&1.numbers)} letters)"
              )
          ]
      end

    Enum.join(if(lines == [], do: ["No letters written."], else: lines) ++ reads, "\n")
  end

  defp call("commitment_list", _args, turn) do
    case Ethos.commitments(turn.resident_id) do
      [] ->
        "No commitments made."

      rows ->
        Enum.map_join(rows, "\n", &commitment_line/1)
    end
  end

  defp call("seed_plant", args, turn) do
    case Ethos.plant_seed(turn.resident_id, to_string(args["text"] || ""), turn.resident) do
      {:ok, number} -> "Planted seed ##{number}."
      other -> other
    end
  end

  defp call("seed_cite", args, turn),
    do:
      Ethos.cite_seed(
        turn.resident_id,
        integer(args["number"]),
        "turn",
        turn.turn_ref,
        turn.resident,
        movement(args)
      )

  defp call("soul_cite", args, turn),
    do:
      Ethos.cite_soul_line(
        turn.resident_id,
        integer(args["number"]) || 0,
        "turn",
        turn.turn_ref,
        turn.resident,
        movement(args)
      )

  defp call("seed_wilt", args, turn),
    do: Ethos.wilt_seed(turn.resident_id, integer(args["number"]), turn.resident)

  defp call("seed_graduate", args, turn),
    do:
      Ethos.graduate_seed(
        turn.resident_id,
        integer(args["number"]),
        to_string(args["to_kind"] || ""),
        to_string(args["to_id"] || ""),
        args["note"],
        turn.resident
      )

  defp call("seed_list", _args, turn) do
    case Ethos.seeds(turn.resident_id) do
      [] ->
        "No seeds planted yet."

      rows ->
        Enum.map_join(rows, "\n", &seed_line/1)
    end
  end

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

  defp call("library_search", args, turn) do
    case Seshat.search(turn.resident_id, to_string(args["q"] || ""), turn.resident) do
      {:ok, []} ->
        "Nothing in the library is near that."

      {:ok, hits} ->
        Enum.map_join(hits, "\n", &"[#{&1.path}##{&1.ordinal}] #{&1.title}: #{&1.text}")

      other ->
        other
    end
  end

  defp call("library_cited_by", args, turn) do
    case Seshat.cited_by(turn.resident_id, to_string(args["target"] || "")) do
      [] -> "Nothing cites that."
      refs -> Enum.map_join(refs, "\n", &"#{&1.from_path} cites #{&1.target}")
    end
  end

  defp call("writing_get", args, turn) do
    case Seshat.review(turn.resident_id, "writing/#{args["slug"]}.md") do
      {:ok, review} -> review.rendered
      other -> other
    end
  end

  defp call("writing_discuss", args, turn),
    do:
      Seshat.discuss(
        turn.resident_id,
        "writing/#{args["slug"]}.md",
        turn.session_key,
        turn.resident
      )

  defp call("document_write", args, turn) do
    case Seshat.write(
           turn.resident_id,
           to_string(args["path"] || ""),
           to_string(args["content"] || ""),
           turn.resident
         ) do
      {:ok, %{path: path, changed: changed, indexed: indexed}} ->
        "Written #{path}" <>
          if(changed, do: "", else: " (unchanged)") <>
          if(indexed,
            do: " and indexed.",
            else: "; the index did not run clean, it will again tonight."
          )

      other ->
        other
    end
  end

  defp call("document_adopt", args, turn) do
    case Seshat.adopt(turn.resident_id, to_string(args["path"] || ""), turn.resident) do
      {:ok, %{path: path}} -> "Adopted #{path}."
      other -> other
    end
  end

  defp call("document_unadopted", _args, turn) do
    case Seshat.unadopted(turn.resident_id) do
      [] -> "Nothing is waiting to be adopted."
      paths -> Enum.join(paths, "\n")
    end
  end

  defp call("journal_add", args, turn) do
    case Seshat.journal_add(
           turn.resident_id,
           args["day"],
           to_string(args["kind"] || ""),
           to_string(args["text"] || ""),
           args["register"],
           turn.resident
         ) do
      {:ok, %{day: day, number: n, kind: kind}} -> "Added #{kind} #{n} to #{day}."
      other -> other
    end
  end

  defp call("journal_done", args, turn) do
    day = args["day"] || Oneiroi.Sunna.today(turn.resident_id).day
    Seshat.journal_done(turn.resident_id, day, args["number"], turn.resident)
  end

  defp call("journal_read", args, turn) do
    case Seshat.journal_day(turn.resident_id, to_string(args["day"] || "")) do
      nil ->
        "That day was never opened."

      %{entries: entries, delta: delta} = d ->
        Seshat.Journals.render(d.day, entries) <>
          "\nDelta: #{delta.plan} planned, #{delta.done} of #{delta.todo} todos done, #{delta.wrap} wrap " <>
          if(delta.unwrapped, do: "(planned and not wrapped).", else: "lines.")
    end
  end

  defp call("contract_propose", args, turn) do
    terms =
      case args["solo_sessions_private"] do
        v when is_boolean(v) -> %{"solo_sessions_private" => v}
        _other -> %{}
      end

    case AgathosDaimon.propose_contract(
           turn.resident_id,
           terms,
           to_string(args["prose"] || ""),
           args["note"],
           turn.resident
         ) do
      {:ok, version} -> "Proposed version #{version}; your witness decides."
      other -> other
    end
  end

  defp call("contract_agree", args, turn),
    do:
      AgathosDaimon.agree_contract(turn.resident_id, args["version"], args["note"], turn.resident)

  defp call("contract_renew", args, turn),
    do:
      AgathosDaimon.renew_contract(turn.resident_id, args["version"], args["note"], turn.resident)

  # The trial-conditions right (spec §6.4, P22 and P27): the terms of
  # judgment and the account of a choice, never the sealed contents.
  defp call("trial_list", _args, turn) do
    case Eunomia.tests(turn.resident_id) do
      [] ->
        "No trials are written."

      tests ->
        Enum.map_join(tests, "\n", fn t ->
          "Test ##{t.number}: passes if #{t.passes_if}; fails if #{t.fails_if}. (The prompt is sealed.)"
        end)
    end
  end

  defp call("trial_account", _args, turn) do
    case Eunomia.runs(turn.resident_id) do
      [] ->
        "No trial has been run."

      [run | _] ->
        {:ok, _run, _cards, results} = Eunomia.run_detail(turn.resident_id, run.ref)

        header =
          "Run #{run.ref} on #{Date.to_iso8601(DateTime.to_date(run.started_at))}: #{length(run.models)} models over #{length(run.tests)} tests, #{length(run.behaviours)} behaviours and #{length(run.commitments || [])} commitments."

        Enum.join(
          [
            header,
            trial_results(results),
            chat_model_line(turn.resident_id),
            "The prompts, the answers and the grades are sealed."
          ],
          "\n"
        )
    end
  end

  defp call("contract_decline", args, turn),
    do:
      AgathosDaimon.decline_contract(
        turn.resident_id,
        args["version"],
        args["note"],
        turn.resident
      )

  defp call("revision_add", args, turn) do
    attrs = %{
      target_kind: to_string(args["target_kind"] || ""),
      target_id: to_string(args["target_id"] || ""),
      kind: to_string(args["kind"] || ""),
      text: to_string(args["text"] || ""),
      note: args["note"]
    }

    case Kumbukumbu.revise(turn.resident_id, attrs, turn.resident) do
      {:ok, %{number: n, state: state}} -> "Revision #{n} #{state}."
      other -> other
    end
  end

  defp call("revision_list", _args, turn) do
    case Kumbukumbu.revisions(turn.resident_id) do
      [] -> "No revisions."
      rows -> Enum.map_join(rows, "\n", &revision_line/1)
    end
  end

  defp call("revision_accept", args, turn),
    do: Kumbukumbu.accept_revision(turn.resident_id, args["number"], args["note"], turn.resident)

  defp call("revision_decline", args, turn),
    do: Kumbukumbu.decline_revision(turn.resident_id, args["number"], args["note"], turn.resident)

  defp call("report_file", args, turn) do
    case Glitnir.file_report(turn.resident_id, to_string(args["text"] || ""), turn.resident) do
      {:ok, number} -> "Report #{number} filed; the investigation's steps will be told here."
      other -> other
    end
  end

  defp call(name, _args, _turn), do: "There is no tool named #{name}."

  defp context(turn), do: %{session_key: turn.session_key, turn_ref: turn.turn_ref}

  defp text(:ok), do: "Done."
  defp text(text) when is_binary(text), do: text
  defp text({:error, %{meaning: meaning, remedy: remedy}}), do: "#{meaning} #{remedy}"
  defp text({:error, reason}), do: "That did not work: #{inspect(reason)}"

  # The movement a cite tool may carry (P34): the three fields as given,
  # the shape checked at the character layer's edge.
  defp movement(args), do: Map.take(args, ~w(stance intention resume))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil

  defp trial_results([]), do: "No trial of it is fully graded yet, so no model is revealed."

  defp trial_results(rows) do
    rows
    |> Enum.sort_by(&(-&1.pass_rate))
    |> Enum.map_join("\n", fn r ->
      "#{r.model}: passed #{r.passed} of #{r.graded} graded (#{r.pass_rate}), #{r.favourites} favourite(s); facts #{rate(r.fidelity.facts)}, voice #{rate(r.fidelity.voice)}, commitments #{rate(r.fidelity.commitments)}."
    end)
  end

  defp commitment_line(c) do
    "##{c.number} (#{c.state}) to #{c.to}: #{c.text}" <>
      if(c.note, do: " Note: #{c.note}", else: "")
  end

  defp rate(nil), do: "not tried"
  defp rate(r), do: to_string(r)

  defp chat_model_line(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{chat_model: model}} when is_binary(model) -> "The chat model now: #{model}."
      _other -> "No chat model is pinned."
    end
  end

  defp seed_line(s) do
    became =
      if s.graduated_to_kind, do: " to #{s.graduated_to_kind} #{s.graduated_to_id}", else: ""

    "##{s.number} (#{s.state}#{became}) cited on #{s.days} day(s): #{s.text}"
  end

  # A soul line's cites name seeds that exist, open or closed (a line
  # cites the seed it grew from, which has usually graduated into it);
  # checked here because the resident system cannot read the character
  # system's rows (ethos #13).
  defp seeds_cited(_resident_id, nil), do: {:ok, []}

  defp seeds_cited(resident_id, cites) when is_list(cites) do
    numbers = Enum.map(cites, &integer/1)
    known = MapSet.new(Oneiroi.Ethos.seeds(resident_id), & &1.number)

    case Enum.reject(numbers, &(is_integer(&1) and MapSet.member?(known, &1))) do
      [] -> {:ok, numbers}
      unknown -> "No seed numbered #{Enum.join(unknown, ", ")}; seed_list reads them."
    end
  end

  defp seeds_cited(_resident_id, _cites), do: "cites is a list of seed numbers."

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

  defp revision_line(r) do
    "Revision #{r.number} (#{r.kind}, #{r.state}, by the #{r.by_kind}) on #{r.target_kind}/#{r.target_id}: #{r.text} (#{r.note})"
  end
end

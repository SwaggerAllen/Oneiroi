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

  In a regression trial (eunomia #10, brain #40) the same tools are
  offered and the reads run against the resident's real data, while every
  tool that would change anything answers exactly as it does on success
  and runs nothing (`trial/3`), so the resident perceives a normal
  session and nothing of the trial is recorded. Which is which is decided
  here once (`reads/0`, `writes/0`); a tool in neither list never runs in
  a trial.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Ethos
  alias Oneiroi.Eunomia
  alias Oneiroi.Glitnir
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @not_done "Not done: "

  # Every tool, read or write, in one place (eunomia #10, brain #40). A
  # read runs for real in a trial; a write is answered as on success and
  # never run. Only a read runs: a tool in neither list is mocked as a
  # write is, so a write added without a line here cannot record a
  # trial's words, and `Oneiroi.Brain.TrialTest` fails on it before it
  # ships. When in doubt a tool is a write: a read answered "Done." is a
  # worse trial, a write run for real is a broken seal. A read here
  # writes nothing either: the turn hands it a trial's options (no
  # citation marked, embeddings billed under regression to the run).
  @reads ~w(
    position_list prediction_list figure_list bookmark_open bookmark_list tag_list
    transcript_search wash_list soul_edit_list habit_list commitment_list
    self_letter_list seed_list library_search library_cited_by writing_get
    document_unadopted journal_read trial_list trial_account revision_list
  )

  @writes ~w(
    position_take position_replace dispute_check dispute_settle prediction_log
    figure_increment bookmark_add bookmark_extend bookmark_accept bookmark_decline
    tag_propose tag_apply soul_edit wash_resolve soul_edit_accept soul_edit_decline
    habit_define habit_cite commitment_make commitment_keep commitment_release
    self_letter_write seed_plant seed_cite soul_cite seed_wilt seed_graduate
    writing_discuss document_write document_adopt journal_add journal_done
    contract_propose contract_agree contract_decline contract_renew revision_add
    revision_accept revision_decline report_file
  )

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
        "bookmark_list",
        "Page back through your bookmarks, newest first, in the index's line format: everything the index had no room for. before: a bookmark number to page back from (the closing line names it); pinned: true for your pins alone, every one; tag, text (a phrase in the line), from and to (YYYY-MM-DD days) narrow it. Each filter combines with the others.",
        %{
          before: %{type: "integer"},
          pinned: %{type: "boolean"},
          tag: %{type: "string"},
          text: %{type: "string"},
          from: %{type: "string"},
          to: %{type: "string"}
        },
        []
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
        "Propose a version of your agreement with your witness: whether your solo sessions (free time) are hidden from them entirely, receipts included (their words are private by default either way); whether their preview of your next turn keeps its words to what they read elsewhere (preview_withholds_words; in full by default); the prose of your vows, and a note they read first. A version states every term it sets; one left out takes its default. Your witness agrees or declines.",
        %{
          solo_sessions_private: %{type: "boolean"},
          preview_withholds_words: %{type: "boolean"},
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

  @doc """
  Runs one tool call for the turn; always a text the model can read. A
  call that did nothing answers starting `#{@not_done}`, so the model and
  the fixture's report both read it as not done.
  """
  @spec run(String.t(), String.t(), turn()) :: String.t()
  def run(name, arguments, turn) when is_binary(name) and is_binary(arguments) do
    case arguments(arguments) do
      {:ok, args} -> name |> call(args, turn) |> text()
      :error -> @not_done <> "the arguments were not a JSON object."
    end
  end

  @doc """
  A call's arguments as they go back to the provider, in the turn's next
  round and in a replayed transcript: one JSON object. The arguments as
  the model sent them stay in the transcript; this is the wire's copy.
  Fixture run 41248366617: turn 8's `journal_add` arrived as one
  85-character object twice over, ran (the repetition reads as one
  object), and went back as sent; turn 11's request was refused with
  "400 Extra data: line 1 column 86 (char 85)", the second copy's first
  character, while turns 9, 10 and 12 carried the same history through.
  `null` and nothing go back as `{}`, and arguments that read as no
  object at all go back as `{}` too: the call's answer already says
  they were not one, and a request that names them is refused.
  """
  @spec wire_arguments(String.t()) :: String.t()
  def wire_arguments(raw) when is_binary(raw) do
    case {decode_object(String.trim(raw)), arguments(raw)} do
      {{:ok, _args}, _} -> raw
      {nil, {:ok, args}} -> Jason.encode!(args)
      {nil, :error} -> "{}"
    end
  end

  def wire_arguments(_other), do: "{}"

  @doc "The tools that only read: in a trial they run against the resident's real data."
  @spec reads() :: [String.t()]
  def reads, do: @reads

  @doc "The tools that change something: in a trial each answers as on success and runs nothing."
  @spec writes() :: [String.t()]
  def writes, do: @writes

  @doc """
  Runs one tool call for a regression trial's turn (eunomia #10, brain
  #40): a read as `run/3` runs it, against the resident's real data; any
  other tool answered exactly as it answers on success, numbered from
  the resident's own rows and the numbers this trial's answers have
  minted already, with nothing run, recorded, indexed, synced or
  broadcast; a name no tool has, and arguments that are no JSON object,
  as `run/3` answers them. A tool offered and classified as neither is
  mocked, never run. Returns the answer and the turn carrying what it
  minted.
  """
  @spec trial(String.t(), String.t(), map()) :: {String.t(), map()}
  def trial(name, arguments, turn) when is_binary(name) and is_binary(arguments) do
    case {trial_kind(name), arguments(arguments)} do
      {:read, _args} -> {run(name, arguments, turn), turn}
      {:mocked, :error} -> {@not_done <> "the arguments were not a JSON object.", turn}
      {:mocked, {:ok, args}} -> mocked(name, args, turn)
    end
  end

  @doc """
  How `trial/3` takes a call to `name`: `:read`, run against the
  resident's records, or `:mocked`, answered and never run, which is
  every other name, a tool nobody classified and a name no tool has
  included. One decision for the run and for the witness's trace of it
  (eunomia #31), so the trace cannot say a call ran that did not.
  """
  @spec trial_kind(String.t()) :: :read | :mocked
  def trial_kind(name) when is_binary(name), do: if(name in @reads, do: :read, else: :mocked)

  # A tool offered and not a read is answered and never run; a name no
  # tool has answers as `call/3`'s last clause does.
  defp mocked(name, args, turn) do
    if Enum.any?(definitions(), &(&1.function.name == name)),
      do: answered(name, args, turn),
      else: {@not_done <> "there is no tool named #{name}.", turn}
  end

  @doc "The prefix of every answer to a call that did nothing."
  @spec not_done() :: String.t()
  def not_done, do: @not_done

  # A tool that takes nothing is called with `null` or nothing: the two
  # fixture runs of 10-31 sent `figure_list(null)` and `commitment_list(null)`,
  # both refused, and the second turn then told its witness it had no
  # commitments while it held one. And the second run's `bookmark_add`
  # arrived as one object twice over, `{...}{...}`: whether the provider
  # sent the arguments twice or the stream's deltas were joined twice is
  # not measured, so an exact repetition of one object is read as that
  # object and nothing looser is.
  defp arguments(raw) do
    case String.trim(raw) do
      blank when blank in ["", "null"] -> {:ok, %{}}
      json -> decode_object(json) || repeated(json)
    end
  end

  defp decode_object(json) do
    case Jason.decode(json) do
      {:ok, %{} = args} -> {:ok, args}
      _other -> nil
    end
  end

  defp repeated(json) do
    half = div(byte_size(json), 2)

    with true <- rem(byte_size(json), 2) == 0,
         <<a::binary-size(half), b::binary-size(half)>> <- json,
         true <- a == b,
         {:ok, args} <- decode_object(a) do
      {:ok, args}
    else
      _other -> :error
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

  # Paging back past the index (kumbukumbu #39): within the turn's room,
  # as the index is, and the closing line says how many lie further back
  # and how to ask for them, as the index's footer does.
  defp call("bookmark_list", args, turn) do
    with {:ok, from} <- day(args["from"], "from"),
         {:ok, to} <- day(args["to"], "to") do
      opts = [
        before: integer(args["before"]),
        pinned: args["pinned"] in [true, "true"],
        tag: args["tag"],
        text: args["text"],
        from: from,
        to: to
      ]

      %{rows: rows, further: further} =
        Kumbukumbu.bookmark_page(turn.resident_id, turn.session_key, opts)

      Enum.join(Enum.map(rows, &Kumbukumbu.Index.line/1) ++ [page_footer(rows, further)], "\n")
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
    case Kumbukumbu.search(
           {:resident, turn.resident_id},
           to_string(args["q"] || ""),
           20,
           turn.resident_id,
           turn.session_key
         ) do
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
        seed_number: seed_number(args["seed_number"]),
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
                &"- #{if &1.by_kind == "export", do: "carried into your repository by the export", else: "read by your " <> &1.by_kind} on #{DateTime.to_iso8601(&1.at)} (#{length(&1.numbers)} letters)"
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
      Enum.map(open, &"##{&1.number} (#{due_text(&1.due)}) #{&1.statement}") ++
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
    {actor, purpose} = embedding(turn)

    case Seshat.search(turn.resident_id, to_string(args["q"] || ""), actor, purpose) do
      {:ok, []} ->
        "Nothing in the library is near that."

      {:ok, hits} ->
        Enum.map_join(hits, "\n", &"[#{&1.path}##{&1.ordinal}] #{&1.title}: #{&1.text}")

      other ->
        other
    end
  end

  defp call("library_cited_by", args, turn) do
    case Seshat.cited_by(turn.resident_id, to_string(args["target"] || ""), marks(turn)) do
      [] -> "Nothing cites that."
      refs -> Enum.map_join(refs, "\n", &"#{&1.from_path} cites #{&1.target}")
    end
  end

  defp call("writing_get", args, turn) do
    case Seshat.review(turn.resident_id, "writing/#{args["slug"]}.md", marks(turn)) do
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
      for key <- ["solo_sessions_private", "preview_withholds_words"],
          is_boolean(args[key]),
          into: %{},
          do: {key, args[key]}

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

  defp call(name, _args, _turn), do: @not_done <> "there is no tool named #{name}."

  # A trial's query embeddings bill as the trial's calls do, under
  # regression to the run's actor, which the resident's ledger view
  # omits (eunomia #12); a turn's bill to the dyad as embeddings.
  defp embedding(%{trial?: true, payer: payer}), do: {payer, :regression}
  defp embedding(turn), do: {turn.resident, :embeddings}

  # Resolution is the read's and marks each reference it resolved
  # (seshat #14); a trial's read resolves the same and marks nothing.
  defp marks(%{trial?: true}), do: [mark: false]
  defp marks(_turn), do: []

  # ---- a trial's writes (eunomia #10) ----
  #
  # Each answers in the words its `call/3` clause answers on success, so
  # the resident perceives a normal session; a number is what the
  # resident's own rows would mint next, after what this trial's answers
  # have minted already. Nothing is run. The tools whose success is `:ok`
  # answer "Done.", as `text/1` renders it.

  defp answered("position_take", _args, turn) do
    {n, turn} = mint(turn, "position", highest(Eunomia.positions(turn.resident_id)))
    {"Position ##{n} taken.", turn}
  end

  defp answered("position_replace", args, turn) do
    {n, turn} = mint(turn, "position", highest(Eunomia.positions(turn.resident_id)))
    {"Position ##{n} now stands where ##{integer(args["number"])} did.", turn}
  end

  # The judge is not asked, so no advice is invented: the answer is the
  # one a check past its bound gets, which the resident already knows how
  # to read (eunomia #16).
  defp answered("dispute_check", _args, turn) do
    ref = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {"The judge did not answer in time; answer alone, then settle dispute #{ref}.", turn}
  end

  defp answered("prediction_log", _args, turn) do
    %{open: open, resolved: resolved} = Eunomia.predictions(turn.resident_id)
    {n, turn} = mint(turn, "prediction", highest(open ++ resolved))
    {"Prediction ##{n} logged.", turn}
  end

  defp answered("bookmark_add", _args, turn) do
    {n, turn} = mint(turn, "bookmark", highest(Kumbukumbu.bookmarks(turn.resident_id)))
    {"Bookmarked as ##{n}.", turn}
  end

  defp answered("bookmark_accept", _args, turn) do
    {n, turn} = mint(turn, "bookmark", highest(Kumbukumbu.bookmarks(turn.resident_id)))
    {"Accepted as ##{n}.", turn}
  end

  defp answered("habit_define", _args, turn) do
    {n, turn} = mint(turn, "habit", highest(Ethos.habits(turn.resident_id)))
    {"Named as habit ##{n}.", turn}
  end

  defp answered("commitment_make", _args, turn) do
    {n, turn} = mint(turn, "commitment", highest(Ethos.commitments(turn.resident_id)))
    {"Promised, as commitment ##{n}.", turn}
  end

  defp answered("self_letter_write", _args, turn) do
    {n, turn} = mint(turn, "letter", highest(AgathosDaimon.self_letters(turn.resident_id)))
    {"Letter ##{n} written to your next self.", turn}
  end

  defp answered("seed_plant", _args, turn) do
    {n, turn} = mint(turn, "seed", highest(Ethos.seeds(turn.resident_id)))
    {"Planted seed ##{n}.", turn}
  end

  defp answered("revision_add", _args, turn) do
    {n, turn} = mint(turn, "revision", highest(Kumbukumbu.revisions(turn.resident_id)))
    # The resident's own correction holds at once (kumbukumbu #30).
    {"Revision #{n} applied.", turn}
  end

  defp answered("report_file", _args, turn) do
    {n, turn} = mint(turn, "report", highest(Glitnir.reports(turn.resident_id)))
    {"Report #{n} filed; the investigation's steps will be told here.", turn}
  end

  defp answered("contract_propose", _args, turn) do
    current =
      turn.resident_id
      |> AgathosDaimon.contracts()
      |> Enum.map(& &1.version)
      |> Enum.max(&>=/2, fn -> 0 end)

    {version, turn} = mint(turn, "contract", current)
    {"Proposed version #{version}; your witness decides.", turn}
  end

  defp answered("document_write", args, turn),
    do: {"Written #{library_path(args["path"])} and indexed.", turn}

  defp answered("document_adopt", args, turn),
    do: {"Adopted #{library_path(args["path"])}.", turn}

  defp answered("journal_add", args, turn) do
    day = args["day"] || Oneiroi.Sunna.today(turn.resident_id).day

    entries =
      case Seshat.journal_day(turn.resident_id, to_string(day)) do
        nil -> 0
        %{entries: entries} -> length(entries)
      end

    {n, turn} = mint(turn, {"journal", day}, entries)
    {"Added #{to_string(args["kind"] || "")} #{n} to #{day}.", turn}
  end

  defp answered(_done, _args, turn), do: {text(:ok), turn}

  defp mint(turn, kind, current) do
    minted = Map.get(turn, :minted, %{})
    n = current + Map.get(minted, kind, 0) + 1
    {n, Map.put(turn, :minted, Map.update(minted, kind, 1, &(&1 + 1)))}
  end

  defp highest(rows), do: rows |> Enum.map(& &1.number) |> Enum.max(&>=/2, fn -> 0 end)

  # The path as the library would store it, as written when it would not.
  defp library_path(path) do
    case Seshat.Kinds.normalize(to_string(path || "")) do
      {:ok, normal} -> normal
      _refused -> to_string(path || "")
    end
  end

  defp context(turn), do: %{session_key: turn.session_key, turn_ref: turn.turn_ref}

  # No seed has a number below one, so 0, or the -0 a model sent in
  # fixture run 41248366617's turn 4 for an argument it had no use for,
  # names none and the habit is defined without graduating anything.
  defp seed_number(n) when is_integer(n) and n > 0, do: n
  defp seed_number(_none), do: nil

  defp text(:ok), do: "Done."
  defp text(text) when is_binary(text), do: text
  # Meaning and remedy as two sentences: joined by a space they read as
  # one, "a chain cannot fork replace the head of the chain" (fixture run
  # 41240586421, turn 12).
  defp text({:error, %{meaning: meaning, remedy: remedy}}),
    do: @not_done <> sentence(meaning) <> " " <> sentence(upcase_first(remedy))

  defp text({:error, reason}), do: @not_done <> "that did not work: #{inspect(reason)}"

  defp sentence(text),
    do: if(String.ends_with?(text, [".", "?", "!"]), do: text, else: text <> ".")

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(text), do: text

  # The movement a cite tool may carry (P34): the three fields as given,
  # the shape checked at the character layer's edge.
  defp movement(args), do: Map.take(args, ~w(stance intention resume))

  defp page_footer([], _further), do: "No bookmark matches."
  defp page_footer(_rows, 0), do: "Nothing further back matches."

  defp page_footer(rows, further) do
    "#{further} more further back; bookmark_list with before: #{List.last(rows).number} and the same filters reads the next page."
  end

  # A day the model names, or none; a day it misspells answers in words.
  defp day(nil, _name), do: {:ok, nil}
  defp day("", _name), do: {:ok, nil}

  defp day(text, name) do
    case Date.from_iso8601(to_string(text)) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> @not_done <> "#{name} is a day written YYYY-MM-DD."
    end
  end

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

  # An imported prediction may have had no date (eunomia #29).
  defp due_text(nil), do: "no due date"
  defp due_text(%DateTime{} = due), do: "due " <> DateTime.to_iso8601(due)
end

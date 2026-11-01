defmodule Oneiroi.Ethos do
  @moduledoc """
  The character layer (spec §6.17): seeds, habits, and later the trait
  baseline and the measurement layer. Who the resident is becoming and
  how it tends to act, kept apart from what happened: every record here
  cites the moments in memory that evidence it and never lives among
  them, because a kind that cites cannot vote, which is what ends the
  receipt loop where one encounter acquired the weight of several
  independent signals.

  The ladder is explicit (the author's call): moments, then seeds, then
  habits or the evaluative kinds, then soul lines, each rung citing
  downward and every graduation a receipted move that leaves the seed's
  row in place. Habits are retrieved in a lane of their own by trigger
  and never pooled with memory's scoring; the counts are shown to the
  brain as figures beside the words.

  Named for Aristotle's word: character is what repeated action leaves
  behind (`systems/ethos.md`).
  """
  use Oneiroi.System, slug: :ethos

  @behaviour Oneiroi.Kumbukumbu.Tree

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      # The habit and seed numbers are minted by the resident aggregate so
      # `<slug>:habit/<n>` survives a rebuild; first contact decides who
      # may define.
      Oneiroi.AgathosDaimon,
      # The moments a habit or a seed cites: turns and bookmarks are
      # memory's rows, read here and never written.
      Oneiroi.Kumbukumbu,
      # The trigger lane's vectors come from the provider port, metered
      # under the embeddings purpose like the library's (spec §6.17).
      Oneiroi.Nisaba,
      Commanded,
      Pgvector,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason
    ],
    exports: [
      Error,
      Character,
      Edge,
      Habits,
      Seeds,
      Router,
      Commands.PlantSeed,
      Commands.WiltSeed,
      Commands.GraduateSeed,
      Commands.CiteSeed,
      Commands.DefineHabit,
      Commands.ChangeHabit,
      Commands.AffirmHabit,
      Commands.CiteHabit,
      Events.SeedPlanted,
      Events.SeedWilted,
      Events.SeedGraduated,
      Events.SeedCited,
      Events.HabitDefined,
      Events.HabitChanged,
      Events.HabitAffirmed,
      Events.HabitCited,
      Events.SoulLineCited,
      Events.BaselineTaken,
      Events.CommitmentMade,
      Events.CommitmentKept,
      Events.CommitmentReleased,
      Commands.CiteSoulLine,
      Commands.TakeBaseline,
      Commands.MakeCommitment,
      Commands.KeepCommitment,
      Commands.ReleaseCommitment,
      Commitments,
      Evidence,
      Lane,
      Measure,
      Store,
      Store.Baseline,
      Store.Commitment,
      Store.Vector,
      Store.Seed,
      Store.Habit,
      Store.Citation,
      Store.Affirmation
    ]

  alias Oneiroi.Ethos.Commitments
  alias Oneiroi.Ethos.Evidence
  alias Oneiroi.Ethos.Habits
  alias Oneiroi.Ethos.Lane
  alias Oneiroi.Ethos.Measure
  alias Oneiroi.Ethos.Seeds

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Ethos.Events.SeedPlanted, 1},
      {Oneiroi.Ethos.Events.SeedWilted, 1},
      {Oneiroi.Ethos.Events.SeedGraduated, 1},
      {Oneiroi.Ethos.Events.SeedCited, 2},
      {Oneiroi.Ethos.Events.HabitDefined, 1},
      {Oneiroi.Ethos.Events.HabitChanged, 1},
      {Oneiroi.Ethos.Events.HabitAffirmed, 1},
      {Oneiroi.Ethos.Events.HabitCited, 2},
      {Oneiroi.Ethos.Events.SoulLineCited, 2},
      {Oneiroi.Ethos.Events.BaselineTaken, 1},
      {Oneiroi.Ethos.Events.CommitmentMade, 1},
      {Oneiroi.Ethos.Events.CommitmentKept, 1},
      {Oneiroi.Ethos.Events.CommitmentReleased, 1}
    ]
  end

  @impl Oneiroi.Component
  def config do
    [
      {:half_life_days, "ETHOS_HALF_LIFE_DAYS",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "the half-life of a citation or an affirmation in a habit's scores (spec §6.3, F11's 30 days); the plan's guess"},
      {:exemplars, "ETHOS_EXEMPLARS",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "how many cited turns a matched habit is shown with in the brain's context (spec §6.3: one or two); a bound on prompt size"},
      {:promotion_confirmations, "ETHOS_PROMOTION_CONFIRMATIONS",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how many distinct days a seed must have been cited on before it may graduate to a habit (spec §6.17's fork): a recorded if-then contingency is a hypothesis, moderately reliable in the literature (design/research-self-and-character.md §3), and the number is a guess at what counts as repeated"},
      {:measure_window_days, "ETHOS_MEASURE_WINDOW_DAYS",
       cast: :integer,
       default: "7",
       tag: :bound,
       usage:
         "the window the measurement layer's markers compare, this one against the one before (spec §6.17, P43); a week is a guess at the cadence a pattern shows on"},
      {:baseline_interval_days, "ETHOS_BASELINE_INTERVAL_DAYS",
       cast: :integer,
       default: "7",
       tag: :bound,
       usage:
         "how often a trait baseline is taken and the interval the drift reading carries (P42; research §5 asks that the band name its interval); a week, a guess, far shorter than any human benchmark's"},
      {:collapse_percent, "ETHOS_COLLAPSE_PERCENT",
       cast: :integer,
       default: "50",
       tag: :bound,
       usage:
         "the fall, as a percentage of the prior reading, that reads as variance collapse, signature flattening or shrinking temporal depth (research §5, §6); a guess, never measured on a resident"},
      {:approach_min, "ETHOS_APPROACH_MIN",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "the habit strength at and above which no payoff reads as approach without payoff (Berridge's wanting without liking, research §6); a guess"},
      {:embedding_model, "ETHOS_EMBEDDING_MODEL",
       default: "openai/text-embedding-3-small",
       usage:
         "the embedding model the trigger lane's vectors come from (spec §6.17's load question), pinned platform-wide with the library's and one model with it in every build so far; a change re-embeds every row on the next refresh"},
      {:embedding_width, "ETHOS_EMBEDDING_WIDTH",
       cast: :integer,
       default: "1536",
       tag: :bound,
       usage:
         "the width of the lane's vectors, the library's 1,536; the column is declared at this width, so a model answering another width fails the refresh rather than the table"},
      {:lane_distance_percent, "ETHOS_LANE_DISTANCE_PERCENT",
       cast: :integer,
       default: "80",
       tag: :bound,
       usage:
         "the cosine distance, as a percentage, within which a habit or a seed counts as near the situation's words; a guess, never measured on an embedding model, and the suite's fake geometry is bags of words"},
      {:lane_seeds, "ETHOS_LANE_SEEDS",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "how many open seeds the lane names near a situation, so the prefix does not grow with the person (spec §6.17); a guess"},
      {:commitments_shown, "ETHOS_COMMITMENTS_SHOWN",
       cast: :integer,
       default: "10",
       tag: :bound,
       usage:
         "how many open commitments the prefix names each turn (spec §3.1, P19), the rest counted; a guess at what a person holds at once"}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:ethos_not_the_resident,
       "seeds and habits are the resident's: planted, cited, revised and graduated from its own turn; a witness defines a habit only before first contact",
       remedy: "the resident does this; affirm a habit instead"},
      {:ethos_not_the_witness, "affirming a habit is the witness's",
       remedy: "the witness does this"},
      {:ethos_no_such_seed, "no seed has that number", remedy: "read the seeds"},
      {:ethos_seed_closed, "that seed has wilted or graduated; it is history now",
       remedy: "plant a new one"},
      {:ethos_seed_text_invalid, "a seed is one text of at most 2,000 characters, not blank",
       remedy: "say what you might be becoming, briefly"},
      {:ethos_unconfirmed,
       "a seed becomes a habit only once it has been cited on enough distinct days",
       remedy:
         "cite the moments that evidence it as they happen, or graduate it toward a position or a soul line instead"},
      {:ethos_graduation_invalid, "a seed graduates toward a habit, a position or a soul line",
       remedy: "name one of the three"},
      {:ethos_no_such_habit, "no habit has that number", remedy: "read the list"},
      {:ethos_name_invalid, "a habit's name is one line of at most 120 characters",
       remedy: "say it shorter"},
      {:ethos_stance_invalid, "a habit's stance is keep or change", remedy: "say which"},
      {:ethos_trigger_invalid,
       "a trigger names words, tags or times (morning, afternoon, evening, night), at least one",
       remedy: "give the situation that calls for it in one of those three"},
      {:ethos_target_invalid,
       "a citation targets a turn by ref or a bookmark by number that exists",
       remedy: "cite the turn in flight, or a bookmark's number"},
      {:ethos_not_a_party,
       "a soul line's evidence is cited by the resident or its witness, as a tagging is",
       remedy: "one of the two parties cites it"},
      {:ethos_movement_invalid,
       "a citation's movement says what stance followed, what intention was adopted and where it can resume, each a phrase",
       remedy: "give any of the three as a short phrase, or none"},
      {:ethos_baseline_fresh, "a baseline stands for its interval before another is taken",
       remedy: "the nightly pass takes the next one when the interval has passed"},
      {:ethos_no_such_commitment, "no commitment has that number",
       remedy: "read the commitments"},
      {:ethos_commitment_closed, "that commitment was kept or released already",
       remedy: "a closed commitment stays as what it became; make a new one"},
      {:ethos_commitment_invalid, "a commitment names a person and says what is promised",
       remedy: "give both, in your own words"},
      {:ethos_embedding_mismatched,
       "the provider answered vectors that do not fit the trigger lane: another count than the texts sent, or another width than ETHOS_EMBEDDING_WIDTH",
       remedy:
         "set ETHOS_EMBEDDING_WIDTH to the model's width, or pin a model that answers it; the refresh retries on the next turn"},
      {:ethos_dispatch_failed,
       "the command did not reach the character aggregate: the command middleware or the event store refused it",
       remedy:
         "retry; if it repeats, an operator reads the log line carrying this error's site and cause"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Ethos.Projectors.Character]

  # ---- seeds (P37) ----

  @doc "Plants a seed, a non-binding becoming in the resident's words; returns its number."
  @spec plant_seed(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(plant_seed(resident_id, text, actor), do: Seeds.plant(resident_id, text, actor))

  @doc "Plants seeds an import carried from another platform's seedbed, each on the day it was planted there (sima-qian #19); returns how many."
  @spec import_seeds(String.t(), [map()], Oneiroi.Actor.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defexport(import_seeds(resident_id, seeds, actor),
    do: Seeds.import_seeds(resident_id, seeds, actor)
  )

  @doc "Wilts an open seed, without ceremony."
  @spec wilt_seed(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(wilt_seed(resident_id, number, actor), do: Seeds.wilt(resident_id, number, actor))

  @doc "Graduates a seed toward a position or a soul line with a note (toward a habit, define the habit with its seed_number)."
  @spec graduate_seed(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | pos_integer(),
          String.t(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(graduate_seed(resident_id, number, to_kind, to_id, note, actor),
    do: Seeds.graduate(resident_id, number, to_kind, to_id, note, actor)
  )

  @doc "The seed cites a moment that evidenced it: a turn by ref, or a bookmark by number."
  @spec cite_seed(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(cite_seed(resident_id, number, kind, target_id, actor),
    do: Seeds.cite(resident_id, number, kind, target_id, actor)
  )

  @doc "The same, with the movement the moment made (P34): stance, intention, resume, any subset, or nil."
  @spec cite_seed(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t(),
          map() | nil
        ) ::
          :ok | {:error, term()}
  defexport(cite_seed(resident_id, number, kind, target_id, actor, movement),
    do: Seeds.cite(resident_id, number, kind, target_id, actor, movement)
  )

  @doc "Every seed with its citations and the days it was cited."
  @spec seeds(String.t()) :: [Oneiroi.Ethos.Store.Seed.t()]
  defexport(seeds(resident_id), do: Seeds.seeds(resident_id))

  # ---- habits (P38) ----

  @doc "Defines a habit (the resident's, or the witness's before first contact); returns its number. Attrs: name, trigger, stance, and seed_number with a note to graduate a seed into it."
  @spec define_habit(String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(define_habit(resident_id, attrs, actor), do: Habits.define(resident_id, attrs, actor))

  @doc "The resident revises a habit."
  @spec change_habit(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(change_habit(resident_id, number, attrs, actor),
    do: Habits.change(resident_id, number, attrs, actor)
  )

  @doc "The witness affirms a habit, with a note."
  @spec affirm_habit(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(affirm_habit(resident_id, number, note, actor),
    do: Habits.affirm(resident_id, number, note, actor)
  )

  @doc "The habit cites a moment that was one: a turn by ref, or a bookmark by number."
  @spec cite_habit(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(cite_habit(resident_id, number, kind, target_id, actor),
    do: Habits.cite(resident_id, number, kind, target_id, actor)
  )

  @doc "The same, with the movement the moment made (P34): stance, intention, resume, any subset, or nil."
  @spec cite_habit(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t(),
          map() | nil
        ) ::
          :ok | {:error, term()}
  defexport(cite_habit(resident_id, number, kind, target_id, actor, movement),
    do: Habits.cite(resident_id, number, kind, target_id, actor, movement)
  )

  @doc "The habits with their two scores, ranked."
  @spec habits(String.t()) :: [Oneiroi.Ethos.Store.Habit.t()]
  defexport(habits(resident_id), do: Habits.habits(resident_id))

  @doc "The citations of one habit, newest first."
  @spec habit_citations(String.t(), pos_integer()) :: [Oneiroi.Ethos.Store.Citation.t()]
  defexport(habit_citations(resident_id, number), do: Habits.citations(resident_id, number))

  # ---- tags as citations (spec §6.17, P39) ----

  @doc "A soul line cites a moment that evidenced it, by either party: a turn by ref or a bookmark by number."
  @spec cite_soul_line(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(cite_soul_line(resident_id, number, kind, target_id, actor, movement),
    do: Evidence.cite_soul_line(resident_id, number, kind, target_id, actor, movement)
  )

  defexport(cite_soul_line(resident_id, number, kind, target_id, actor),
    do: Evidence.cite_soul_line(resident_id, number, kind, target_id, actor)
  )

  @doc "Pins a bookmark as evidence of a soul line: the pin carries the line and the line cites the bookmark."
  @spec pin_as_evidence(String.t(), pos_integer(), pos_integer(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(pin_as_evidence(resident_id, bookmark, soul_line, actor),
    do: Evidence.pin_as_evidence(resident_id, bookmark, soul_line, actor)
  )

  @doc "The citations of one soul line, newest first."
  @spec soul_line_citations(String.t(), pos_integer()) :: [Oneiroi.Ethos.Store.Citation.t()]
  defexport(soul_line_citations(resident_id, number),
    do: Evidence.soul_line_citations(resident_id, number)
  )

  @doc "Every soul line's citations, newest first."
  @spec soul_evidence(String.t()) :: [Oneiroi.Ethos.Store.Citation.t()]
  defexport(soul_evidence(resident_id), do: Evidence.soul_evidence(resident_id))

  @doc "Memory's tree port: the tree's tags (`soul/3`, `habit/2`, `seed/1`) on the moments named."
  @spec tags_of(String.t(), String.t(), [String.t()]) :: %{String.t() => [String.t()]}
  @impl Oneiroi.Kumbukumbu.Tree
  defexport(tags_of(resident_id, target_kind, target_ids),
    do: Evidence.tags_of(resident_id, target_kind, target_ids)
  )

  # ---- the measurement layer (spec §6.17, P42, P43) ----

  @doc "One measurement check now, by key (`Oneiroi.Ethos.Measure.keys/0`): a flag or silence with what it read and did not."
  @spec measure(String.t(), String.t(), Oneiroi.Actor.t()) :: Oneiroi.Ethos.Measure.result()
  defexport(measure(resident_id, key, actor), do: Measure.measure(resident_id, key, actor))

  @doc "Re-embeds the trigger lane's changed rows and drops the gone ones (spec §6.17); the brain's turn does this before each read."
  @spec refresh_lane(String.t(), Oneiroi.Actor.t()) ::
          {:ok, %{embedded: non_neg_integer(), removed: non_neg_integer()}} | {:error, term()}
  defexport(refresh_lane(resident_id, actor), do: Lane.refresh(resident_id, actor))

  @doc "The trait baselines taken, newest first."
  @spec baselines(String.t()) :: [Oneiroi.Ethos.Store.Baseline.t()]
  defexport(baselines(resident_id), do: Measure.baselines(resident_id))

  # ---- commitments (spec §3.1, P19) ----

  @doc "The resident commits, in its own words, to a person; returns the number."
  @spec make_commitment(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(make_commitment(resident_id, to, text, actor),
    do: Commitments.make(resident_id, to, text, actor)
  )

  @doc "The resident keeps a commitment, with a note."
  @spec keep_commitment(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(keep_commitment(resident_id, number, note, actor),
    do: Commitments.keep(resident_id, number, note, actor)
  )

  @doc "A commitment is released, by the resident or the witness, with a note."
  @spec release_commitment(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(release_commitment(resident_id, number, note, actor),
    do: Commitments.release(resident_id, number, note, actor)
  )

  @doc "Every commitment, by number."
  @spec commitments(String.t()) :: [Oneiroi.Ethos.Store.Commitment.t()]
  defexport(commitments(resident_id), do: Commitments.all(resident_id))

  @doc "The prefix's section: the open commitments, bounded, with their numbers."
  @spec promised(String.t()) :: %{text: String.t(), numbers: [pos_integer()]}
  defexport(promised(resident_id), do: Commitments.promised(resident_id))

  @doc "The 'how I act' section for a situation, the trigger lane: text, the numbers it names, the count, the open seeds."
  @spec how_i_act(String.t(), map()) :: %{
          text: String.t(),
          numbers: [pos_integer()],
          count: non_neg_integer(),
          seeds: non_neg_integer()
        }
  defexport(how_i_act(resident_id, situation), do: Habits.how_i_act(resident_id, situation))
end

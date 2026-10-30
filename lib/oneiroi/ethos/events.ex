defmodule Oneiroi.Ethos.Events do
  @moduledoc """
  The character stream's events, version 1 (spec §6.17): seeds and
  habits, each citing the moments in memory that evidence it, and never
  living among them. Nothing person-shaped is stored as a memory event;
  a kind that cites cannot vote.
  """

  defmodule SeedPlanted do
    # A seed is a dated, first-person, non-binding becoming ("I might be
    # becoming this"), the resident's alone to write (P37). `number` is
    # the resident's own sequence, so `<slug>:seed/<n>` survives a rebuild.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :text]
  end

  defmodule SeedWilted do
    # A seed may wilt without ceremony, by the resident's hand: no note is
    # asked for, because a premature line kept out of the soul file is the
    # mechanism working, not a decision to justify.
    use Oneiroi.Event, version: 1, fields: [:id, :number]
  end

  defmodule SeedGraduated do
    # The receipted move up the ladder (the author's call: the hierarchy
    # is explicit): toward a habit (a disposition, once its citations
    # confirm it across days) or toward an evaluative kind (a position, a
    # soul line) that needs no behavioural evidence. The seed's row stays,
    # with its state and the citation to what it became.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number, :to_kind, :to_id]
  end

  defmodule SeedCited do
    # A seed cites a moment (a turn or a bookmark) that evidenced it; the
    # distinct days of its citations are the confirmations the fork
    # counts (research §3: a recorded contingency is a hypothesis).
    use Oneiroi.Event, version: 1, fields: [:id, :number, :target_kind, :target_id]
  end

  defmodule HabitDefined do
    # A habit is a first-person tendency the resident owns (spec §6.3's
    # behaviour, moved here by P38): a name in its own words, the trigger
    # it answers (a map of `words`, `tags` and `times`, any of which
    # matching is a match), a stance (`keep` or `change`), and the seed
    # it graduated from, if any.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :name, :trigger, :stance, :seed_number]
  end

  defmodule HabitChanged do
    # Revision adds, it does not overwrite: the new words, trigger and
    # stance, with the old ones still in the log.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :name, :trigger, :stance]
  end

  defmodule HabitAffirmed do
    # "I like when you do that": the witness's, with a note, part of the
    # connection score and never of the habit score.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule HabitCited do
    # The habit cites the moment that was one, on a turn or a bookmark, by
    # the resident's actor at turn time; the direction is the habit's to
    # the moment, never a tag on the moment (P38, P39). Nothing enters a
    # habit's record without the resident's actor on it.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :target_kind, :target_id]
  end

  defmodule SoulLineCited do
    # A soul line cites the moment that evidenced it (spec §6.17, P39:
    # tags are citations): the moment's tag is the line it evidences,
    # and a pin naming a line writes this beside the pin. By either
    # party, as a tagging is (spec §6.3); the line itself stays the
    # resident's words (agathos-daimon #27). The line's existence is the
    # edge's to check, since the lines are the resident system's rows.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :target_kind, :target_id]
  end

  defmodule BaselineTaken do
    # The trait baseline (spec §6.17, P42): the dispositional profile as
    # measured, the habits with their two scores and their enactments in
    # the window, the spread of the strengths and the breadth of the
    # signature, machine-held and never loaded as identity. Taken on an
    # interval, compared with the one before (research §5).
    use Oneiroi.Event, version: 1, fields: [:id, :habits, :spread, :breadth]
  end
end

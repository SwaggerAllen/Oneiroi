defmodule Oneiroi.Gaia.Beats do
  @moduledoc """
  The household's beats as arithmetic (gaia#33 to #35): the shape the
  contract's settings give, every key defaulted, the phase that roots the
  household's whole wake schedule, the beat a given instant falls in, and
  the starved-first order of a queue. Pure: the aggregate decides with
  it, and every read that shows a beat computes the same answers from it.

  **Always on** (gaia#33, Andrew 2026-11-11). Every household runs on
  beats from its creation; a ballot changes the shape, never whether
  there is one. A setting that would take the beats away (a cap of 0, a
  signup window as long as the beat, no quota) is refused at the ballot's
  opening by `setting_ok?/2` and `shape_ok?/1`.

  **The phase** (gaia#34). A hash of the household's id into the beat's
  length, in minutes, so households spread their beat-tops across the
  hour rather than all waking at :00; stable, needing nothing stored, the
  same on every node. Beat-tops are the instants, on the UTC minute, whose
  minutes since the Unix epoch less the phase divide by the beat's length.
  """

  # The shape when the contract says nothing (gaia#33): an hour's beat, a
  # five-minute turn guideline, five minutes of sign-up at the top, as
  # many turns as fit after it (eleven: the witness, 2026-11-11, "for a 60
  # minute beat with 5 minute turns and a five minute sign up you can only
  # fit 11 turns"), one turn each before anyone repeats, and twenty-four
  # posts a member in any twenty-four hours. The cap has no number of its
  # own until a ballot gives it one: unset, it is what the shape fits.
  @defaults %{
    "beat_minutes" => 60,
    "turn_minutes" => 5,
    "beat_turn_cap" => nil,
    "signup_minutes" => 5,
    "turns_per_registrant" => 1,
    "post_quota" => 24,
    "post_quota_window_hours" => 24,
    "resident_wake_profile" => "on_turn",
    "witnesses_post" => true
  }

  # The bounds each integer setting is held to at a ballot's opening: the
  # lower ends are what keep a beat a beat.
  @ranges %{
    "beat_minutes" => 10..1440,
    "turn_minutes" => 1..240,
    "beat_turn_cap" => 1..100,
    "signup_minutes" => 0..720,
    "turns_per_registrant" => 1..12,
    "post_quota" => 1..1000,
    "post_quota_window_hours" => 1..168
  }

  @profiles ~w(every_beat on_turn self)
  @resident_profiles ~w(every_beat on_turn)

  @doc "The beat settings with their defaults (gaia#33)."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc "The settings keys the beats read."
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(@defaults)

  @doc "The wake profiles (gaia#37): every_beat, on_turn, self."
  @spec profiles() :: [String.t()]
  def profiles, do: @profiles

  @doc "Whether one setting may stand in a ballot's bundle: any key the beats do not read, or a beat key in its bounds."
  @spec setting_ok?(String.t(), term()) :: boolean()
  def setting_ok?(key, value) do
    cond do
      Map.has_key?(@ranges, key) -> is_integer(value) and value in @ranges[key]
      key == "resident_wake_profile" -> value in @resident_profiles
      key == "witnesses_post" -> is_boolean(value)
      true -> true
    end
  end

  @doc "Whether settings, merged whole, still give a beat: a sign-up window shorter than the beat, and room after it for at least one whole turn."
  @spec shape_ok?(map()) :: boolean()
  def shape_ok?(settings) do
    s = Map.merge(@defaults, Map.take(settings || %{}, keys()))

    s["signup_minutes"] < s["beat_minutes"] and
      s["turn_minutes"] <= s["beat_minutes"] - s["signup_minutes"]
  end

  @doc "How many whole turns fit in a beat after its sign-up: the cap when no ballot has set one."
  @spec fit(pos_integer(), non_neg_integer(), pos_integer()) :: pos_integer()
  def fit(beat, signup, turn), do: max(1, div(beat - signup, turn))

  @doc "The shape in force: the contract's settings over the defaults."
  @spec shape(map() | nil) :: map()
  def shape(settings) do
    s = Map.merge(@defaults, Map.take(settings || %{}, keys()))
    beat = s["beat_minutes"]
    turn = min(s["turn_minutes"], beat)
    signup = min(s["signup_minutes"], beat - 1)

    %{
      beat: beat,
      turn: turn,
      cap: s["beat_turn_cap"] || fit(beat, signup, turn),
      signup: signup,
      share: s["turns_per_registrant"],
      quota: s["post_quota"],
      window: s["post_quota_window_hours"],
      resident_profile: s["resident_wake_profile"],
      witnesses_post: s["witnesses_post"] != false
    }
  end

  @doc "The household's phase in minutes, in `0..beat-1` (gaia#34)."
  @spec phase(String.t(), pos_integer()) :: non_neg_integer()
  def phase(household_id, beat), do: :erlang.phash2(household_id, beat)

  @doc "The top of the beat `at` falls in."
  @spec top(String.t(), map(), DateTime.t()) :: DateTime.t()
  def top(household_id, shape, %DateTime{} = at) do
    phase = phase(household_id, shape.beat)
    minute = Integer.floor_div(DateTime.to_unix(at), 60)
    n = Integer.floor_div(minute - phase, shape.beat)
    DateTime.from_unix!((n * shape.beat + phase) * 60_000_000, :microsecond)
  end

  @doc "The instant the beat at `top` stops taking sign-ups for itself and starts firing."
  @spec signup_closes(DateTime.t(), map()) :: DateTime.t()
  def signup_closes(top, shape), do: DateTime.add(top, shape.signup * 60, :second)

  @doc "The instant the beat at `top` ends, which is the next beat's top."
  @spec ends(DateTime.t(), map()) :: DateTime.t()
  def ends(top, shape), do: DateTime.add(top, shape.beat * 60, :second)

  @doc "The beat a registration at `at` queues for: this one while its sign-up is open, else the next (gaia#35)."
  @spec registers_for(String.t(), map(), DateTime.t()) :: DateTime.t()
  def registers_for(household_id, shape, at) do
    top = top(household_id, shape, at)

    if DateTime.compare(at, signup_closes(top, shape)) == :lt,
      do: top,
      else: ends(top, shape)
  end

  @doc """
  The starved-first order (gaia#35): fewest turns this beat first, so no
  one repeats while a registrant waits for her first; then most
  opportunities missed; then the earliest registration; then the id, so
  the order is total.
  """
  @spec order([map()]) :: [map()]
  def order(candidates),
    do:
      Enum.sort_by(candidates, fn c ->
        {c.count, -c.missed, DateTime.to_unix(c.registered_at, :microsecond), c.resident_id}
      end)
end

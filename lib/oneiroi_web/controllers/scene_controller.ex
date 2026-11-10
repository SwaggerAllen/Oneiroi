defmodule OneiroiWeb.SceneController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["library"])

  plug(:witnessed)
  # Her words, as the journal's are: behind the contract's switch
  # (agathos-daimon#34), after the party check.
  plug(OneiroiWeb.Plugs.Switch, [key: "witness_reads"] when action in [:index])

  operation(:index,
    summary:
      "The day's scenes as rows (seshat#52): every day with scenes from `from` to `to` (ISO dates, both included, either left open), oldest first, each `{day, complete, closed_at, scenes}`; `complete` is false until the bedtime pass closed the day, so a pass that ended short reads as not finished. Each row has its number, kind (`scene`, or `correction` of scene `corrects`'s lines), title, turns, times, summary, mood (with `mood_was` and `mood_corrected_at` when corrected past its day), register, rounds_ran_out, when and by whom written and when its facts were last corrected",
    parameters: [
      id: [in: :path, type: :string],
      from: [in: :query, type: :string],
      to: [in: :query, type: :string]
    ],
    responses: [
      ok: {"days", "application/json", %Schema{type: :object}},
      unprocessable_entity:
        {"a bound that is no date", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, %{"id" => id} = params) do
    with {:ok, from} <- day(params["from"], :from),
         {:ok, to} <- day(params["to"], :to) do
      days =
        for d <- Seshat.scenes(id, from, to),
            do: %{d | scenes: Enum.map(d.scenes, &scene/1)}

      json(conn, %{days: days})
    else
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp day(nil, _side), do: {:ok, nil}
  defp day("", _side), do: {:ok, nil}

  defp day(text, side) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, _date} ->
        {:ok, text}

      _other ->
        {:error,
         Seshat.Error.new(:seshat_day_invalid, :seshat_scene_controller_day_invalid,
           day: text,
           side: side
         )}
    end
  end

  defp day(other, side), do: day(inspect(other), side)

  defp scene(s),
    do: %{
      number: s.number,
      kind: s.kind,
      corrects: s.corrects,
      title: s.title,
      from_turn: s.from_turn,
      to_turn: s.to_turn,
      from_time: s.from_time,
      to_time: s.to_time,
      summary: s.summary,
      mood: s.mood,
      mood_was: s.mood_was,
      mood_corrected_at: s.mood_corrected_at,
      register: s.register,
      rounds_ran_out: s.rounds_ran_out,
      at: s.at,
      by: s.actor_kind,
      corrected_at: s.corrected_at
    }

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_scene_not_witnessed
          )
        )
        |> halt()
  end
end

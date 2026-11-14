defmodule Oneiroi.Apsu.Queue do
  @moduledoc """
  The operator's queue (apsu#31; the witness, 2026-11-13: "stuff falling
  off my radar is pretty common, maybe we make a queue for the operator
  ui"). What waits on the person running the platform, apart from what
  waits on him as a witness: env vars to set, a setting to decide, a PR to
  review, a check after a deploy. Each item says what is needed and why,
  who raised it (the agent that helps run the platform with its ops token,
  the operator, or the platform itself) and links; he closes it done or
  dropped, with a note. An item with a `key` is raised once while it is
  open, so a recurring condition does not pile up. Never content.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Error
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @what 300
  @why 4_000
  @links 10

  @fields [
    :number,
    :what,
    :why,
    :raised_by,
    :links,
    :key,
    :status,
    :note,
    :raised_at,
    :closed_at,
    :closed_by
  ]

  @doc "Raises an item; `{:ok, number}`, or the open item's number when one with the same `key` is open."
  @spec add(map(), String.t()) :: {:ok, pos_integer()} | {:error, Oneiroi.Error.t()}
  def add(attrs, raised_by) do
    item = %{
      what: text(field(attrs, :what)),
      why: text(field(attrs, :why)),
      links: field(attrs, :links) || [],
      key: text(field(attrs, :key))
    }

    cond do
      not valid?(item) -> {:error, Error.new(:apsu_queue_item_invalid, :apsu_queue_raise_invalid)}
      item.key && open_number(item.key) -> {:ok, open_number(item.key)}
      true -> insert(item, raised_by)
    end
  end

  defp field(attrs, key), do: Map.get(attrs, Atom.to_string(key)) || Map.get(attrs, key)

  defp valid?(%{what: what, why: why, links: links}) do
    is_binary(what) and what != "" and String.length(what) <= @what and
      (is_nil(why) or String.length(why) <= @why) and is_list(links) and length(links) <= @links and
      Enum.all?(links, &is_binary/1)
  end

  defp insert(item, raised_by) do
    Scope.platform(fn ->
      {1, [%{number: n}]} =
        Repo.insert_all(
          "apsu_operator_item",
          [Map.merge(item, %{raised_by: raised_by, status: "open", raised_at: Clock.now()})],
          returning: [:number]
        )

      {:ok, n}
    end)
  end

  @doc "Closes an open item done or dropped, with a note."
  @spec close(pos_integer(), String.t(), String.t(), String.t()) ::
          :ok | {:error, Oneiroi.Error.t()}
  def close(number, status, note, closed_by) when status in ["done", "dropped"] do
    if is_binary(note) and String.trim(note) != "" do
      {n, _} =
        Scope.platform(fn ->
          Repo.update_all(
            from(i in "apsu_operator_item", where: i.number == ^number and i.status == "open"),
            set: [
              status: status,
              note: String.trim(note),
              closed_at: Clock.now(),
              closed_by: closed_by
            ]
          )
        end)

      if n == 1,
        do: :ok,
        else: {:error, Error.new(:apsu_queue_no_such_item, :apsu_queue_close_absent)}
    else
      {:error, Error.new(:apsu_queue_item_invalid, :apsu_queue_close_note_required)}
    end
  end

  def close(_number, _status, _note, _by),
    do: {:error, Error.new(:apsu_queue_item_invalid, :apsu_queue_close_status_invalid)}

  @doc "Closes the open item with `key`, if any: the platform's own items clear themselves."
  @spec clear(String.t(), String.t()) :: :ok
  def clear(key, note) do
    case open_number(key) do
      nil -> :ok
      n -> close(n, "done", note, "platform")
    end
  end

  @doc "The open items, oldest first, and the last twenty closed, newest first."
  @spec list() :: %{open: [map()], closed: [map()]}
  def list do
    Scope.platform(fn ->
      %{
        open:
          Repo.all(
            from(i in "apsu_operator_item",
              where: i.status == "open",
              order_by: [asc: i.raised_at, asc: i.number],
              select: map(i, ^@fields)
            )
          ),
        closed:
          Repo.all(
            from(i in "apsu_operator_item",
              where: i.status != "open",
              order_by: [desc: i.closed_at],
              limit: 20,
              select: map(i, ^@fields)
            )
          )
      }
    end)
  end

  defp open_number(key) do
    Scope.platform(fn ->
      Repo.one(
        from(i in "apsu_operator_item",
          where: i.key == ^key and i.status == "open",
          select: i.number
        )
      )
    end)
  end

  defp text(nil), do: nil
  defp text(t) when is_binary(t), do: String.trim(t)
  defp text(_other), do: nil
end

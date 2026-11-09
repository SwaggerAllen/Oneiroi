defmodule Oneiroi.Brain.Pulls do
  @moduledoc """
  The platform's pull requests, read (brain#71; the witness, 2026-11-08,
  through Lily's letter #365): two reads, never a write. `meta/1` is
  everything about a pull request but its diffs, with the list of the
  files it changes; `diffs/3` is the diffs of the files named, exactly
  those. "That way you can make a conscious decision about how much of
  the PR is in context at once": the file list is the menu, and no read
  loads the whole diff.

  The repository is `BRAIN_PULLS_REPO`, the platform's own; GitHub is
  reached through the port (`BRAIN_PULLS_CLIENT`), so no test crosses
  the network (conventions §9). Nothing posts, comments, approves or
  merges.
  """

  alias Oneiroi.Brain.Error
  alias Oneiroi.Config

  # `token` is the witness's GitHub read token (gaia#24), else the
  # platform's `BRAIN_GITHUB_TOKEN`, else nil for an anonymous read.
  @callback pull(repo :: String.t(), number :: pos_integer(), token :: term()) ::
              {:ok, map()} | {:error, term()}
  @callback files(repo :: String.t(), number :: pos_integer(), token :: term()) ::
              {:ok, [map()]} | {:error, term()}
  @callback checks(repo :: String.t(), sha :: String.t(), token :: term()) ::
              {:ok, [map()]} | {:error, term()}

  @doc "A pull request's title, description, author, state, its checks, and the files it changes, one line each, no diff."
  @spec meta(term(), term()) :: {:ok, String.t()} | {:error, Error.t()}
  def meta(number, token \\ nil) do
    with {:ok, n} <- number(number),
         {:ok, pr} <- call(:pull, [repo(), n, token(token)]),
         {:ok, files} <- call(:files, [repo(), n, token(token)]) do
      checks =
        case call(:checks, [repo(), pr["head"]["sha"] || "", token(token)]) do
          {:ok, runs} -> runs
          {:error, _} -> :unknown
        end

      {:ok, meta_text(n, pr, files, checks)}
    end
  end

  @doc "The diffs of the files named in a pull request, exactly those, each cut at `BRAIN_PULLS_DIFF_CHARS` from `from` with the way on said."
  @spec diffs(term(), term(), term(), term()) :: {:ok, String.t()} | {:error, Error.t()}
  def diffs(number, names, from \\ 0, token \\ nil) do
    with {:ok, n} <- number(number),
         {:ok, names} <- names(names),
         {:ok, files} <- call(:files, [repo(), n, token(token)]) do
      by_name = Map.new(files, &{&1["filename"], &1})
      from = if is_integer(from) and from > 0, do: from, else: 0
      {:ok, Enum.map_join(names, "\n\n", &diff_text(n, &1, by_name[&1], from))}
    end
  end

  defp meta_text(n, pr, files, checks) do
    state =
      cond do
        pr["merged_at"] -> "merged #{pr["merged_at"]}"
        pr["draft"] -> "#{pr["state"]}, draft"
        true -> to_string(pr["state"])
      end

    body = String.trim(pr["body"] || "")

    lines =
      Enum.map_join(files, "\n", fn f ->
        "- #{f["filename"]} (#{f["status"]}, +#{f["additions"]} −#{f["deletions"]})"
      end)

    """
    Pull request ##{n}: #{pr["title"]}
    By #{get_in(pr, ["user", "login"])}, #{state}; #{get_in(pr, ["head", "ref"])} into #{get_in(pr, ["base", "ref"])}, opened #{pr["created_at"]}, updated #{pr["updated_at"]}.
    Checks: #{checks_text(checks)}

    #{if body == "", do: "(No description.)", else: body}

    #{length(files)} files changed (pr_diffs reads the ones you name):
    #{lines}
    """
    |> String.trim_trailing()
  end

  defp checks_text(:unknown), do: "could not be read."
  defp checks_text([]), do: "none reported."

  defp checks_text(runs) do
    Enum.map_join(runs, "; ", fn r ->
      "#{r["name"]} #{r["conclusion"] || r["status"]}"
    end)
  end

  defp diff_text(n, name, nil, _from),
    do:
      "## #{name}\n\nPull request ##{n} does not change #{name}; pr_meta lists the files it does."

  defp diff_text(_n, name, %{"patch" => patch} = f, from) when is_binary(patch) do
    bound = Config.fetch!(:brain, :pulls_diff_chars)
    total = String.length(patch)
    page = String.slice(patch, from, bound)
    upto = from + String.length(page)

    more =
      if upto < total,
        do:
          "\n\n(#{total - upto} more characters of this file's diff; pr_diffs with this file alone and from: #{upto} reads on.)",
        else: ""

    "## #{name} (#{f["status"]}, +#{f["additions"]} −#{f["deletions"]})\n\n```diff\n#{page}\n```" <>
      more
  end

  defp diff_text(_n, name, f, _from),
    do:
      "## #{name} (#{f["status"]})\n\nGitHub gives no diff for this file: binary, or too large to show."

  defp number(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp number(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, ""} when i > 0 -> {:ok, i}
      _ -> number(nil)
    end
  end

  defp number(_other),
    do: {:error, Error.new(:brain_pulls_invalid, :brain_pulls_number_invalid)}

  defp names(names) when is_list(names) and names != [] do
    if Enum.all?(names, &(is_binary(&1) and &1 != "")),
      do: {:ok, Enum.uniq(names)},
      else: names(nil)
  end

  defp names(_other), do: {:error, Error.new(:brain_pulls_invalid, :brain_pulls_files_invalid)}

  defp repo, do: Config.fetch!(:brain, :pulls_repo)

  # The witness's token first (gaia#24), the platform's after, else none.
  defp token(nil), do: Config.fetch!(:brain, :github_token)
  defp token(witness_token), do: witness_token

  defp call(fun, args) do
    case apply(Config.fetch!(:brain, :pulls_client), fun, args) do
      {:ok, _} = ok ->
        ok

      {:error, %Error{}} = sited ->
        sited

      {:error, reason} ->
        {:error, Error.caught(:brain_pulls_failed, :brain_pulls_github_failed, reason)}
    end
  end
end

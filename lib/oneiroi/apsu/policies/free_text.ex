defmodule Oneiroi.Apsu.Policies.FreeText do
  @moduledoc """
  Free text is text (conventions §12, 2026-11-03): a migration's
  `add(:name, :string)` or `modify(:name, :string)` is Ecto's
  varchar(255), a limit nobody chose. On 2026-11-03 a provider's refusal
  of some 330 characters overflowed one, the projector stopped, and the
  app went down with it.

  `:string` stays for the names that are identifiers: ids, refs, keys,
  slugs, kinds, roles, states, hashes, tags and labels (bounded on their
  commands, `Oneiroi.Command`'s `bounds:`). Anything else a model, a
  person or a third party writes is `:text`. A deliberate exception says
  so with `# oneiroi:allow free_text` and its reason.

  Read from `20261103000010_free_text_unbounded` on: migrations are
  immutable, and the earlier ones' free-text strings are the ones that
  migration made text.
  """

  @behaviour Oneiroi.Audit.Check

  alias Oneiroi.Audit.Source

  @from "20261103000010"

  # Names that are identifiers, whole or by their suffix.
  @names ~w(id key slug kind role state status platform hash label tag model scope
            purpose tone op type mode currency sha adapter register how domain
            account external_id sender thread identity to)
  @suffixes ~w(_id _key _ref _kind _slug _hash _state _by _type)

  @impl Oneiroi.Audit.Check
  def run(scope) do
    scope
    |> Path.wildcard()
    |> Enum.filter(&(Path.basename(&1) >= @from))
    |> Enum.flat_map(fn path ->
      Source.scan(path, "free_text", fn source ->
        Source.collect(source.ast, &violation/1)
      end)
    end)
  end

  defp violation({form, meta, [name, :string | _rest]})
       when form in [:add, :modify] and is_atom(name) do
    if identifier?(Atom.to_string(name)) do
      []
    else
      [
        {Keyword.get(meta, :line, 0),
         "free_text: #{inspect(name)} is :string in #{form}/2, which is varchar(255); free text is :text (a name that is an identifier is #{Enum.join(@suffixes, "/")}-suffixed or one of #{Enum.join(@names, ", ")})"}
      ]
    end
  end

  defp violation(_node), do: []

  defp identifier?(name), do: name in @names or Enum.any?(@suffixes, &String.ends_with?(name, &1))
end

# The Repo's Postgrex type set: Ecto's own extensions and pgvector's
# `vector`, so the library's embedding column (spec §6.5) encodes and
# decodes through the one Repo. Declared where the Repo is, in the
# kernel, because a type set is a connection fact and not a system's.
Postgrex.Types.define(
  Oneiroi.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)

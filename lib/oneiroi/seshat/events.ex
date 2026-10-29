defmodule Oneiroi.Seshat.Events do
  @moduledoc """
  The library stream's events, version 1 (spec §3.1, §6.5):
  `library-<resident_id>`, one per resident. The file is the record and
  lives in the repository; the event is its provenance: that it was
  written through the flow or adopted from outside it, its hash and its
  size, by whom, never its content.
  """

  defmodule DocumentWritten do
    use Oneiroi.Event, version: 1, fields: [:id, :path, :kind, :hash, :bytes]
  end

  defmodule DocumentAdopted do
    # A file made outside the flow (F27), registered as it was found.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :kind, :hash, :bytes]
  end

  defmodule PiecePublished do
    use Oneiroi.Event, version: 1, fields: [:id, :path, :url]
  end

  defmodule DiscussionOpened do
    # A session linked to a piece (`writing_discuss`, spec §8).
    use Oneiroi.Event, version: 1, fields: [:id, :path, :session_key]
  end
end

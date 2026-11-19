defmodule Oneiroi.EpubFixture do
  @moduledoc "A small, real EPUB built in memory for the book tests (seshat#98): a package, a cover with no words, and chapters."

  @doc """
  The bytes of an EPUB. `chapters` is a list of `{title, paragraphs}`;
  `opts` sets `:title`, `:author`, `:identifier` and `:dir` (the
  package's folder, "OEBPS" by default).
  """
  def build(chapters, opts \\ []) do
    title = Keyword.get(opts, :title, "The Long Field")
    author = Keyword.get(opts, :author, "Ada Wren")
    identifier = Keyword.get(opts, :identifier, "urn:uuid:4e1f-field")
    # The package's folder; nil puts it at the archive's root.
    prefix =
      case Keyword.get(opts, :dir, "OEBPS") do
        nil -> ""
        dir -> dir <> "/"
      end

    pages =
      chapters
      |> Enum.with_index(1)
      |> Enum.map(fn {{heading, paragraphs}, i} ->
        body = Enum.map_join(paragraphs, "\n", &"<p>#{&1}</p>")
        {"text/ch#{i}.xhtml", xhtml("<h1>#{heading}</h1>\n#{body}")}
      end)

    cover = {"text/cover.xhtml", xhtml(~s(<div><img src="../img/cover.jpg" alt=""/></div>))}

    items =
      Enum.map_join([cover | pages], "\n", fn {href, _} ->
        id = href |> Path.basename(".xhtml")
        ~s(<item id="#{id}" href="#{href}" media-type="application/xhtml+xml"/>)
      end)

    spine =
      Enum.map_join([cover | pages], "\n", fn {href, _} ->
        ~s(<itemref idref="#{Path.basename(href, ".xhtml")}"/>)
      end)

    opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="bookid">#{identifier}</dc:identifier>
        <dc:title>#{title}</dc:title>
        <dc:creator>#{author}</dc:creator>
        <dc:publisher>Small Press</dc:publisher>
        <dc:date>1921</dc:date>
        <dc:language>en</dc:language>
      </metadata>
      <manifest>
        <item id="css" href="style.css" media-type="text/css"/>
    #{items}
      </manifest>
      <spine>
    #{spine}
      </spine>
    </package>
    """

    container = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="#{prefix}content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """

    files =
      [
        {"mimetype", "application/epub+zip"},
        {"META-INF/container.xml", container},
        {"#{prefix}content.opf", opf},
        {"#{prefix}style.css", "p { margin: 0 }"}
      ] ++ Enum.map([cover | pages], fn {href, page} -> {"#{prefix}#{href}", page} end)

    {:ok, {_name, bytes}} =
      :zip.create(~c"book.epub", Enum.map(files, fn {n, b} -> {to_charlist(n), b} end), [:memory])

    bytes
  end

  defp xhtml(body),
    do: """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title><style>p{}</style></head>
    <body>#{body}</body></html>
    """
end

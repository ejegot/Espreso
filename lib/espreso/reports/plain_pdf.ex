defmodule Espreso.Reports.PlainPdf do
  @moduledoc """
  Minimal PDF 1.4 text document for owner day-close printouts.

  Helvetica / WinAnsi only — callers should pass ASCII (use PHP not ₱).
  """

  @page_width 612
  @page_height 792
  @left 50
  @top 742
  @line_height 13
  @lines_per_page 52
  @wrap 92

  @doc """
  Returns a PDF binary for `title` plus body `lines`.
  """
  def render(title, lines) when is_binary(title) and is_list(lines) do
    wrapped =
      [ascii(title), "" | Enum.flat_map(lines, fn line -> wrap_line(ascii(to_string(line))) end)]

    pages =
      case Enum.chunk_every(wrapped, @lines_per_page) do
        [] -> [[]]
        chunks -> chunks
      end

    page_count = length(pages)
    font_id = 3 + page_count * 2

    page_objs =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {page_lines, index} ->
        page_id = 3 + index
        content_id = 3 + page_count + index
        stream = page_stream(page_lines)

        [
          {page_id,
           dict(%{
             "Type" => "/Page",
             "Parent" => "2 0 R",
             "MediaBox" => "[0 0 #{@page_width} #{@page_height}]",
             "Contents" => "#{content_id} 0 R",
             "Resources" => "<< /Font << /F1 #{font_id} 0 R >> >>"
           })},
          {content_id, stream_obj(stream)}
        ]
      end)

    kids =
      pages
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {_page, index} -> "#{3 + index} 0 R" end)

    objects =
      [
        {1, dict(%{"Type" => "/Catalog", "Pages" => "2 0 R"})},
        {2, dict(%{"Type" => "/Pages", "Kids" => "[#{kids}]", "Count" => "#{page_count}"})}
      ] ++
        page_objs ++
        [
          {font_id,
           dict(%{
             "Type" => "/Font",
             "Subtype" => "/Type1",
             "BaseFont" => "/Helvetica"
           })}
        ]

    assemble(objects)
  end

  defp page_stream(lines) do
    moves =
      lines
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {line, index} ->
        y = @top - index * @line_height
        size = if index == 0, do: 14, else: 10
        "BT /F1 #{size} Tf #{@left} #{y} Td (#{escape(line)}) Tj ET"
      end)

    moves <> "\n"
  end

  defp wrap_line(""), do: [""]

  defp wrap_line(line) when byte_size(line) <= @wrap, do: [line]

  defp wrap_line(line) do
    words = String.split(line, " ")

    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {acc, cur} ->
        joined = if cur == "", do: word, else: cur <> " " <> word

        if String.length(joined) <= @wrap do
          {acc, joined}
        else
          {acc ++ [cur], word}
        end
      end)

    Enum.reject(lines ++ [current], &(&1 == ""))
  end

  defp ascii(text) do
    text
    |> String.replace("₱", "PHP ")
    |> String.replace("·", "-")
    |> String.replace("—", "-")
    |> String.replace("–", "-")
    |> String.normalize(:nfkd)
    |> String.replace(~r/[^\x09\x0A\x0D\x20-\x7E]/, "")
  end

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end

  defp dict(map) do
    inner =
      Enum.map_join(map, " ", fn {key, value} -> "/#{key} #{value}" end)

    "<< #{inner} >>"
  end

  defp stream_obj(content) do
    "<< /Length #{byte_size(content)} >>\nstream\n" <> content <> "endstream"
  end

  defp assemble(objects) do
    header = "%PDF-1.4\n"
    sorted = Enum.sort_by(objects, &elem(&1, 0))

    {body, offsets} =
      Enum.reduce(sorted, {header, %{}}, fn {id, payload}, {acc, offs} ->
        chunk = "#{id} 0 obj\n#{payload}\nendobj\n"
        {acc <> chunk, Map.put(offs, id, byte_size(acc))}
      end)

    max_id = sorted |> Enum.map(&elem(&1, 0)) |> Enum.max()
    xref_pos = byte_size(body)

    xref_rows =
      Enum.map_join(1..max_id, fn id ->
        offset = Map.get(offsets, id, 0)
        :io_lib.format("~10.10.0B 00000 n \n", [offset]) |> IO.iodata_to_binary()
      end)

    xref = "xref\n0 #{max_id + 1}\n0000000000 65535 f \n" <> xref_rows
    trailer = "trailer\n<< /Size #{max_id + 1} /Root 1 0 R >>\nstartxref\n#{xref_pos}\n%%EOF\n"
    body <> xref <> trailer
  end
end

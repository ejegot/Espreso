defmodule Espreso.Reports.PlainPdfTest do
  use ExUnit.Case, async: true

  alias Espreso.Reports.PlainPdf

  test "renders a PDF 1.4 document" do
    binary = PlainPdf.render("Elilai Kafe day close", ["Shop date 2026-09-10", "Paid PHP 100"])

    assert String.starts_with?(binary, "%PDF-1.4")
    assert binary =~ "%%EOF"
    assert binary =~ "Elilai Kafe day close"
    assert binary =~ "Paid PHP 100"
  end
end

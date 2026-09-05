defmodule Espreso.Printer.EscPos do
  @moduledoc false

  # HS-802UL 80mm ≈ 48 chars in Font A
  @width 48

  def width, do: @width

  def init, do: <<0x1B, 0x40>>
  def cut, do: <<0x1D, 0x56, 0x00>>
  def drawer_kick_pin2, do: <<0x1B, 0x70, 0x00, 0x19, 0xFA>>
  def drawer_kick_pin5, do: <<0x1B, 0x70, 0x01, 0x19, 0xFA>>

  def align_left, do: <<0x1B, 0x61, 0x00>>
  def align_center, do: <<0x1B, 0x61, 0x01>>
  def bold_on, do: <<0x1B, 0x45, 0x01>>
  def bold_off, do: <<0x1B, 0x45, 0x00>>

  # GS ! n — character size (nibble: height | width << 4)
  def size_normal, do: <<0x1D, 0x21, 0x00>>
  def size_double_height, do: <<0x1D, 0x21, 0x01>>
  def size_double, do: <<0x1D, 0x21, 0x11>>

  def feed(lines) when is_integer(lines) and lines > 0 do
    String.duplicate("\n", lines)
  end

  def separator do
    String.duplicate("-", @width) <> "\n"
  end

  def text_line(line, opts \\ []) when is_binary(line) do
    width = Keyword.get(opts, :width, @width)
    ascii(line) |> String.slice(0, width) |> Kernel.<>("\n")
  end

  def center_line(line) when is_binary(line) do
    text = ascii(line) |> String.slice(0, @width)
    pad = max(div(@width - String.length(text), 2), 0)
    String.duplicate(" ", pad) <> text <> "\n"
  end

  @doc """
  Left label + right value on one 48-char row (Loyverse-style price column).
  """
  def columns(left, right) when is_binary(left) and is_binary(right) do
    left_s = ascii(left)
    right_s = ascii(right)
    max_left = max(@width - String.length(right_s) - 1, 8)
    left_s = String.slice(left_s, 0, max_left)
    gap = max(@width - String.length(left_s) - String.length(right_s), 1)
    left_s <> String.duplicate(" ", gap) <> right_s <> "\n"
  end

  def join(parts) when is_list(parts), do: IO.iodata_to_binary(parts)

  def ascii(text) when is_binary(text) do
    text
    |> String.replace("₱", "P")
    |> String.replace("·", "-")
    |> String.replace("—", "-")
    |> String.replace("–", "-")
    |> String.replace("…", "...")
    |> String.replace(~r/[^\x20-\x7E]/u, "")
    |> String.trim()
  end
end

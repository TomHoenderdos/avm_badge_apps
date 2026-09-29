defmodule Badge.App.Snake.Watermark.Paint do
  @moduledoc false

  @cell_w 8
  @cell_h 16
  @gap 1
  @pad 3
  @label "GOATMIRE"
  @glyph_w byte_size(@label) * @cell_w + (byte_size(@label) + 1) * @gap
  @glyph_h @cell_h
  @img_w @glyph_w + @pad * 2
  @img_h @glyph_h + @pad * 2

  def glyph_w, do: @glyph_w
  def glyph_h, do: @glyph_h
  def pad, do: @pad
  def img_w, do: @img_w
  def img_h, do: @img_h

  @shades 8
  @frames 24
  @reach 3
  @ink @reach + 1
  # Resting purple glow up to white. Nothing in here is black.
  @palette [
    0x1A102C,
    0x2A1844,
    0x7A56B0,
    0x9670C6,
    0xB48CDA,
    0xD0AEEC,
    0xE6D4F8,
    0xFFFFFF
  ]
  # Halo around the letters, dim to bright. Stays under the resting ink.
  @halo [
    0x1A102C,
    0x2A1844,
    0x3E2866,
    0x563A8C
  ]

  def shades, do: @shades
  def frame_count, do: @frames

  def mask, do: build()

  def paint(mask, phase) do
    for y <- 0..(@img_h - 1), x <- 0..(@img_w - 1), into: <<>> do
      case :binary.at(mask, y * @img_w + x) do
        0 -> <<0, 0, 0, 0>>
        role -> shade(role, x, y, phase)
      end
    end
  end

  # Ink is role @ink. Around it three rings of halo, role @reach down to 1
  # by rounded distance from the nearest ink pixel.
  defp build do
    grid =
      Enum.reduce(ink(), %{}, fn {x, y}, grid ->
        Enum.reduce(halo_offsets(), grid, fn {dx, dy, role}, grid ->
          put_px(grid, x + dx, y + dy, role)
        end)
      end)

    for y <- 0..(@img_h - 1), x <- 0..(@img_w - 1), into: <<>> do
      case grid[{x, y}] do
        nil -> <<0>>
        prio -> <<prio>>
      end
    end
  end

  defp shade(role, x, y, phase) do
    <<r, g, b>> = <<color(role, abs(y - hot_row(phase, x)))::24>>
    <<r, g, b, 0xFF>>
  end

  defp color(@ink, dist), do: Enum.at(@palette, max(@shades - 1 - dist, 2))
  defp color(ring, dist), do: Enum.at(@halo, ring - 1 + boost(dist))

  # The halo brightens one step where the wave passes.
  defp boost(dist) when dist <= 4, do: 1
  defp boost(_dist), do: 0

  # One sine wave spans the word, its crest on the top row of the letters
  # and its trough on the bottom row. Every frame slides the wave one
  # frame's worth to the right, so the light rolls through GOATMIRE.
  defp hot_row(phase, x) do
    top = @pad
    bottom = @pad + @glyph_h - 1
    mid = (top + bottom) / 2
    amplitude = (bottom - top) / 2
    t = (x - @pad) / @glyph_w - phase / @frames
    round(mid - amplitude * :math.sin(2 * :math.pi() * t))
  end

  defp halo_offsets do
    for dx <- -@reach..@reach,
        dy <- -@reach..@reach,
        d = round(:math.sqrt(dx * dx + dy * dy)),
        d <= @reach do
      {dx, dy, @ink - d}
    end
  end

  defp put_px(grid, x, y, prio) do
    ix = x + @pad
    iy = y + @pad

    if ix < 0 or iy < 0 or ix >= @img_w or iy >= @img_h do
      grid
    else
      case Map.get(grid, {ix, iy}) do
        old when is_integer(old) and old >= prio -> grid
        _ -> Map.put(grid, {ix, iy}, prio)
      end
    end
  end

  defp ink do
    ~c"GOATMIRE"
    |> indexed(0, [])
    |> Enum.flat_map(fn {ch, index} ->
      ch
      |> glyph()
      |> indexed(0, [])
      |> Enum.flat_map(fn {row, y} ->
        origin = @gap + index * (@cell_w + @gap)

        for x <- 0..(@cell_w - 1), :binary.at(row, x) == ?#, do: {origin + x, y}
      end)
    end)
  end

  defp indexed([], _i, acc), do: :lists.reverse(acc)
  defp indexed([item | rest], i, acc), do: indexed(rest, i + 1, [{item, i} | acc])

  defp glyph(ch) do
    rows = rows(ch)

    unless length(rows) == @cell_h and Enum.all?(rows, &(byte_size(&1) == @cell_w)) do
      raise "glyph must be 8 by 16"
    end

    rows
  end

  defp rows(?G) do
    [
      " ###### ",
      "#      #",
      "#      #",
      "#       ",
      "#       ",
      "#       ",
      "#   ####",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      " ###### ",
      "        "
    ]
  end

  defp rows(?O) do
    [
      " ###### ",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      " ###### ",
      "        "
    ]
  end

  defp rows(?A) do
    [
      " ###### ",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "####### ",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "#      #",
      "        "
    ]
  end

  defp rows(?T) do
    [
      "####### ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "        "
    ]
  end

  defp rows(?M) do
    [
      "#     # ",
      "##   ## ",
      "# # # # ",
      "#  #  # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "        "
    ]
  end

  defp rows(?I) do
    [
      "####### ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "   #    ",
      "####### ",
      "        "
    ]
  end

  defp rows(?R) do
    [
      "######  ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "######  ",
      "#    #  ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "#     # ",
      "        "
    ]
  end

  defp rows(?E) do
    [
      "####### ",
      "#       ",
      "#       ",
      "#       ",
      "#       ",
      "#       ",
      "######  ",
      "#       ",
      "#       ",
      "#       ",
      "#       ",
      "#       ",
      "#       ",
      "#       ",
      "####### ",
      "        "
    ]
  end
end

defmodule Badge.App.Snake.Watermark do
  @moduledoc false

  alias Badge.App.Snake.Watermark.Paint

  @step 120
  # A store pack is at most 64 KB. This mask is one byte per pixel, and
  # `sprite/1` paints the current frame from it.
  @mask Paint.mask()

  def glyph_w, do: Paint.glyph_w()
  def glyph_h, do: Paint.glyph_h()
  def pad, do: Paint.pad()
  def img_w, do: Paint.img_w()
  def img_h, do: Paint.img_h()

  # Monotonic time can be negative. `rem` keeps that sign, so the frame
  # number is folded back into 0..n-1 before the mask is painted.
  def sprite(phase \\ 0), do: Paint.paint(@mask, index(phase))

  def frame_count, do: Paint.frame_count()
  def phase(now), do: index(div(now, @step))

  defp index(n) do
    frames = Paint.frame_count()
    rem(rem(n, frames) + frames, frames)
  end

  def glow_at(now), do: div(now, @step) * @step + @step
end

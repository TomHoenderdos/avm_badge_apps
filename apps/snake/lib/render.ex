defmodule Badge.App.Snake.Render do
  @moduledoc """
  Turns a game into AtomGL items for the board.

  The router paints the title bar and the background, so this list has
  neither. The tail comes first and the word last, so the snake sits on
  top of GOATMIRE.
  """

  alias Badge.App.Snake.Watermark

  @snake 0x3DDC97
  @head 0xE8FFF4
  # The body darkens by a fixed step per segment, from @snake down to
  # @tail after @fade segments, and @tail stays well above the board colour.
  @tail 0x1C6E4C
  @fade 32
  @food_white 0xFFFFFF
  @food_red 0xFF0000
  @blink 200

  def scene(game, layout, now \\ 0) do
    cells(game.snake, layout, 0, []) ++
      [cell(game.food, layout, food_color(now))] ++
      watermark(layout, now)
  end

  def blink_at(now), do: div(now, @blink) * @blink + @blink
  def glow_at(now), do: Watermark.glow_at(now)

  defp food_color(now) do
    if rem(div(now, @blink), 2) == 0, do: @food_white, else: @food_red
  end

  defp watermark(layout, now) do
    scale = scale(layout)
    glyph_w = Watermark.glyph_w()
    glyph_h = Watermark.glyph_h()
    pad = Watermark.pad()
    img_w = Watermark.img_w()
    img_h = Watermark.img_h()
    board_w = layout.cols * layout.cell
    board_h = layout.rows * layout.cell
    x = layout.x0 + div(board_w - glyph_w * scale, 2) - pad * scale
    y = layout.y0 + div(board_h - glyph_h * scale, 2) - pad * scale

    [
      {:scaled_cropped_image, x, y, img_w * scale, img_h * scale, :transparent, 0, 0, scale, scale, [],
       {:rgba8888, img_w, img_h, Watermark.sprite(Watermark.phase(now))}}
    ]
  end

  defp scale(layout) do
    max(min(div(layout.cols * layout.cell, Watermark.glyph_w()), div(layout.rows * layout.cell, Watermark.glyph_h())), 1)
  end

  defp cells([], _layout, _index, acc), do: acc

  defp cells([cell | rest], layout, index, acc) do
    cells(rest, layout, index + 1, [cell(cell, layout, segment_color(index)) | acc])
  end

  def segment_color(0), do: @head

  def segment_color(index) do
    t = min(index, @fade)
    <<r1, g1, b1>> = <<@snake::24>>
    <<r2, g2, b2>> = <<@tail::24>>

    <<color::24>> =
      <<r1 + div((r2 - r1) * t, @fade), g1 + div((g2 - g1) * t, @fade), b1 + div((b2 - b1) * t, @fade)>>

    color
  end

  defp cell({col, row}, layout, color) do
    inset = if layout.cell >= 8, do: 1, else: 0

    {:rect, layout.x0 + col * layout.cell + inset, layout.y0 + row * layout.cell + inset, layout.cell - inset * 2, layout.cell - inset * 2,
     color}
  end
end

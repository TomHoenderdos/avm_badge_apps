defmodule Badge.App.Snake.RenderTest do
  use ExUnit.Case, async: true

  alias Badge.App.Snake.Render
  alias Badge.App.Snake.Watermark

  test "the body fades from green to dark green one step per segment" do
    assert Render.segment_color(0) == 0xE8FFF4
    assert Render.segment_color(1) != Render.segment_color(2)

    colors = Enum.map(1..40, &Render.segment_color/1)
    greens = Enum.map(colors, &green/1)

    assert greens
           |> Enum.take(32)
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.all?(fn [a, b] -> b < a end)

    assert Enum.at(colors, 31) == 0x1C6E4C
    assert Enum.at(colors, 39) == 0x1C6E4C
    assert Enum.at(colors, 0) == 0x3CD995
    assert green(Render.segment_color(1)) > 200
  end

  test "a wave of white light rolls along GOATMIRE" do
    step = Watermark.glow_at(0)
    cycle = step * Watermark.frame_count()
    frames = 0..(cycle - step)//step
    stems = [4, 13, 22, 34, 40, 52, 58, 67]

    assert word_pixel(0) == <<0x7A, 0x56, 0xB0, 0xFF>>
    assert word_pixel(0, 23, 3) == <<0xFF, 0xFF, 0xFF, 0xFF>>
    assert bright?(word_pixel(0, 67, 17))
    assert word_pixel(0, 12, 4) == <<0x56, 0x3A, 0x8C, 0xFF>>
    assert word_pixel(0, 4, 17) == <<0x3E, 0x28, 0x66, 0xFF>>

    rows = Enum.map(stems, &brightest_row(sprite_at(0), &1))
    assert rows == [10, 5, 4, 7, 11, 17, 17, 16]

    trail = for now <- frames, do: brightest_row(sprite_at(now), 34)
    assert Enum.min(trail) == 3
    assert Enum.max(trail) == 17
    assert Enum.count(trail, &(&1 == 3)) == 3

    assert trail
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.all?(fn [a, b] -> abs(a - b) <= 3 end)

    arrivals =
      for x <- [34, 40, 52, 58, 67] do
        Enum.find(frames, fn now -> word_pixel(now, x, 3) == <<0xFF, 0xFF, 0xFF, 0xFF>> end)
      end

    assert arrivals == Enum.sort(arrivals)
    assert Enum.uniq(arrivals) == arrivals
    assert sprite_at(step) != sprite_at(0)
    assert sprite_at(0) == sprite_at(cycle)
  end

  defp green(color), do: color |> Bitwise.bsr(8) |> Bitwise.band(0xFF)

  defp word_pixel(now, x \\ 5, y \\ 3), do: pixel(sprite_at(now), x, y)

  defp brightest_row(sprite, x) do
    Enum.max_by(0..21, fn y ->
      case pixel(sprite, x, y) do
        <<_, _, _, 0>> -> -1
        <<r, g, b, _>> -> r + g + b
      end
    end)
  end

  defp sprite_at(now), do: Watermark.sprite(Watermark.phase(now))

  defp bright?(<<r, g, b, _>>), do: r > 0xE0 and g > 0xC0 and b > 0xE0

  defp pixel(sprite, x, y), do: binary_part(sprite, (y * 79 + x) * 4, 4)
end

defmodule Badge.App.Race.RoadTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Road

  describe "projection tables" do
    test "the car's own depth lands near the bottom" do
      assert Road.depth(0) == 10
      assert Road.y(10) == 225
      assert Road.half(10) == 130
    end

    test "near depths clamp to the bottom row and far ones sit just under the horizon" do
      assert Road.y(3) == 240
      assert Road.y(170) == 107
    end

    test "depth covers everything drawn" do
      assert Road.depth(1_999) == 169
    end
  end

  describe "bands/2" do
    test "at most 20 bands, the nearest reaching the bottom row" do
      bands = Road.bands(0, 0)
      assert length(bands) <= 20
      assert length(bands) >= 15
      {y, h, _c, _half, _s} = hd(bands)
      assert y + h == 240
    end

    test "rows rise strictly from near to far and bands touch" do
      for z <- [0, 37, 4_010, 59_999] do
        bands = Road.bands(z, 0)
        pairs = Enum.zip(bands, tl(bands))

        for {{y1, _, _, _, _}, {y2, h2, _, _, _}} <- pairs do
          assert y2 < y1
          assert y2 + h2 == y1
        end
      end
    end

    test "the road meets the bottom row at the same width wherever the camera is" do
      for z <- 0..99 do
        {y, h, _centre, half, _s} = hd(Road.bands(z, 0))
        assert y + h == 240
        assert half == 145
      end
    end

    test "on a straight the edges run straight: width grows evenly with the row" do
      for z <- [0, 3, 50, 99], {y, h, _centre, half, _s} <- Road.bands(z, 0) do
        assert half == div((y + h - 100) * 1300, 1250)
      end
    end

    test "a straight at the start is centred" do
      assert Enum.all?(Road.bands(0, 0), fn {_, _, centre, _, _} -> centre == 160 end)
    end

    test "a car on the right edge sees the road to its left" do
      [{_, _, centre, half, _} | _] = Road.bands(0, 1024)
      assert centre == 160 - half
    end

    test "a right bend ahead moves the far road right" do
      bands = Road.bands(4_000, 0)
      {_, _, near, _, _} = hd(bands)
      {_, _, far, _, _} = List.last(bands)
      assert near == 160
      assert far > 160
    end

    test "a left bend ahead moves the far road left" do
      {_, _, far, _, _} = List.last(Road.bands(11_000, 0))
      assert far < 160
    end

    test "segment indexes wrap at the lap" do
      segments = for {_, _, _, _, s} <- Road.bands(59_950, 0), do: s
      assert hd(segments) == 599
      assert 0 in segments
    end

    test "every value is an integer" do
      for band <- Road.bands(22_345, -700), value <- Tuple.to_list(band), do: assert(is_integer(value))
    end
  end
end

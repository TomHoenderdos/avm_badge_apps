defmodule Badge.App.Race.SceneTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Race
  alias Badge.App.Race.Scene

  @gas %{steer: 0, throttle: true, brake: false}
  @idle %{steer: 0, throttle: false, brake: false}
  @blue 0x3278E6

  defp racing, do: Race.new({0, 0}) |> Race.start(7_000) |> Race.step(10_000, @idle)

  defp items(race), do: Scene.items(race, Scene.hills())

  defp texts(race), do: for({:text, _x, _y, _f, _c, _b, body} <- items(race), do: body)

  defp with_rival(race, distance), do: %{race | rivals: [%{id: 1, distance: distance, lane: 0, speed: 0}]}

  defp drawn?(race), do: Enum.any?(items(race), &match?({:rect, _, _, _, _, @blue}, &1))

  test "the hills are a 320x24 image" do
    assert {:rgba8888, 320, 24, pixels} = Scene.hills()
    assert byte_size(pixels) == 320 * 24 * 4
  end

  test "a race frame stays under 100 items, text first and sky last" do
    frame = items(racing())
    assert length(frame) <= 100
    assert elem(hd(frame), 0) == :text
    assert List.last(frame) == {:rect, 0, 26, 320, 58, 0x3070C0}
  end

  test "every number in every item is an integer" do
    race = racing() |> Map.put(:car, %{x: -700, speed: 1_200, distance: 22_345})

    for item <- items(race), value <- Tuple.to_list(item), is_number(value) do
      assert is_integer(value)
    end
  end

  test "the speed bar never has zero width" do
    assert Enum.any?(items(racing()), &match?({:rect, 4, 46, 1, 4, _}, &1))
  end

  describe "rivals" do
    test "one just ahead is drawn in its colour" do
      assert drawn?(with_rival(racing(), 500))
    end

    test "one a lap ahead is drawn on the same stretch" do
      assert drawn?(with_rival(racing(), 60_500))
    end

    test "one behind, level or out of sight is not drawn" do
      race = %{racing() | car: %{x: 0, speed: 0, distance: 1_000}}
      refute drawn?(with_rival(race, 500))
      refute drawn?(with_rival(race, 1_000))
      refute drawn?(with_rival(race, 3_000))
    end
  end

  describe "screens" do
    test "the intro names the track and asks for Space" do
      texts = texts(Race.new({0, 0}))
      assert "Goatmire Ring" in texts
      assert "No best lap yet" in texts
      assert "Space to start" in texts
      assert "Best lap 0:40.1" in texts(Race.new({40_100, 0}))
    end

    test "the countdown shows its number" do
      assert "3" in texts(Race.start(Race.new({0, 0}), 0))
    end

    test "the first second of racing says GO!" do
      assert "GO!" in texts(racing())
      refute "GO!" in texts(Race.step(racing(), 11_000, @idle))
    end

    test "the HUD shows lap, time and place" do
      texts = texts(Race.step(racing(), 10_100, @gas))
      assert "LAP 1/3" in texts
      assert "0:00.1" in texts
      assert "P8/8" in texts
    end

    test "the result shows place, time, best lap and a record" do
      race = racing()
      last = %{race | car: %{x: 0, speed: 1_500, distance: 179_990}, lap: 3, lap_times: [41_000, 40_000], lap_start: 5_000}
      texts = texts(Race.step(last, 10_100, @gas))
      assert "Time 0:00.1" in texts
      assert "Best lap 0:05.1" in texts
      assert "New record!" in texts
      assert "Space to race again" in texts
    end
  end

  test "clock formats minutes, seconds and tenths" do
    assert Scene.clock(0) == "0:00.0"
    assert Scene.clock(5_000) == "0:05.0"
    assert Scene.clock(83_400) == "1:23.4"
  end
end

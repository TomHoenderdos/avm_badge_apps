defmodule Badge.App.Race.RivalsTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Rivals
  alias Badge.App.Race.Track

  defp rival(fields), do: Map.merge(%{id: 1, distance: 0, lane: 512, speed: 0}, fields)

  test "seven cars on a two-wide grid ahead of the start" do
    rivals = Rivals.new()
    assert for(r <- rivals, do: r.id) == Enum.to_list(1..7)
    assert Enum.all?(rivals, &(&1.distance > 0 and &1.speed == 0))

    [first, second | _] = rivals
    assert first.distance == second.distance
    assert first.lane == -second.lane
  end

  test "gains 500 a second from a standstill on a straight" do
    [moved] = Rivals.step([rival(%{})], 1_000)
    assert moved.speed == 500
    assert moved.distance == 500
  end

  test "slows for a sharp bend" do
    assert Track.curve_at(22_000) == 4
    [moved] = Rivals.step([rival(%{distance: 22_000, speed: 1_470})], 1_000)
    assert moved.speed == 1_070
  end

  test "never beyond its own target speed" do
    Enum.reduce(1..40, [rival(%{})], fn _, rivals ->
      rivals = Rivals.step(rivals, 1_000)
      assert hd(rivals).speed <= 1_470
      rivals
    end)
  end

  test "distance keeps counting past the lap" do
    [moved] = Rivals.step([rival(%{distance: 59_900, speed: 1_470})], 1_000)
    assert moved.distance > Track.lap_length()
  end

  test "positions stay within 200 of the lane" do
    rivals = Enum.reduce(1..30, Rivals.new(), fn _, r -> Rivals.step(r, 200) end)

    for {{id, distance, x}, r} <- Enum.zip(Rivals.positions(rivals), rivals) do
      assert id == r.id
      assert distance == r.distance
      assert abs(x - r.lane) <= 200
    end
  end
end

defmodule Badge.App.Race.RaceTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Race

  @gas %{steer: 0, throttle: true, brake: false}
  @idle %{steer: 0, throttle: false, brake: false}

  # Racing since t = 10_000.
  defp racing, do: Race.new({0, 0}) |> Race.start(7_000) |> Race.step(10_000, @idle)

  defp car(race, fields), do: %{race | car: Map.merge(race.car, fields)}

  defp last_lap(best) do
    race = racing()
    %{car(race, %{distance: 179_990, speed: 1_500}) | best: best, lap: 3, lap_times: [41_000, 40_000], lap_start: 5_000}
  end

  describe "phases" do
    test "a new race waits on the intro and ignores the pedals" do
      race = Race.new({0, 0})
      assert race.phase == :intro
      assert Race.step(race, 5_000, @gas) == race
    end

    test "start counts down 3, 2, 1 and then races" do
      race = Race.start(Race.new({0, 0}), 1_000)
      assert race.phase == :countdown
      assert Race.count(race) == 3
      assert Race.count(Race.step(race, 2_000, @gas)) == 2

      almost = Race.step(race, 3_999, @gas)
      assert almost.phase == :countdown
      assert Race.count(almost) == 1
      assert almost.car.distance == 0

      go = Race.step(race, 4_000, @gas)
      assert go.phase == :racing
      assert go.since == 4_000
    end
  end

  describe "racing" do
    test "the throttle moves the car" do
      race = Race.step(racing(), 10_100, @gas)
      assert race.car.speed == 60
      assert race.car.distance == 6
      assert Race.elapsed(race) == 100
    end

    test "a long stall counts as 200 ms" do
      assert Race.step(racing(), 15_000, @gas).car.speed == 120
    end

    test "crossing the line starts the next lap" do
      race = racing() |> car(%{distance: 59_990, speed: 1_500}) |> Race.step(10_100, @gas)
      assert race.lap == 2
      assert race.lap_times == [100]
      assert race.lap_start == 10_100
    end

    test "a bend turns the heading" do
      race = racing() |> car(%{distance: 5_000, speed: 1_500}) |> Race.step(10_200, @gas)
      assert race.heading == 6
    end

    test "the grid starts ahead, so the player starts last" do
      assert Race.place(racing()) == 8
      assert Race.place(car(racing(), %{distance: 10_000})) == 1
      assert Race.cars() == 8
    end
  end

  describe "finishing" do
    test "the third lap finishes the race and freezes the clock" do
      race = Race.step(last_lap({0, 0}), 10_100, @gas)
      assert race.phase == :finished
      assert race.lap == 3
      assert race.lap_times == [41_000, 40_000, 5_100]
      assert race.total == 100
      assert Race.elapsed(race) == 100
      assert Race.elapsed(Race.step(race, 20_000, @gas)) == 100
    end

    test "a first finish is a record on both counts" do
      race = Race.step(last_lap({0, 0}), 10_100, @gas)
      assert Race.best_lap(race) == 5_100
      assert Race.new_best(race) == {5_100, 100}
      assert Race.record?(race)
    end

    test "a slower race keeps the old best and is no record" do
      race = Race.step(last_lap({1_000, 50}), 10_100, @gas)
      assert Race.new_best(race) == {1_000, 50}
      refute Race.record?(race)
    end

    test "only a finished race can be a record" do
      refute Race.record?(racing())
    end

    test "the next race compares against the record just set" do
      race = last_lap({0, 0}) |> Race.step(10_100, @gas) |> Race.start(30_000)
      assert race.phase == :countdown
      assert race.best == {5_100, 100}
      assert race.car.distance == 0
      assert race.lap == 1
    end
  end
end

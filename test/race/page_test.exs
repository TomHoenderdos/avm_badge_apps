defmodule Badge.App.Race.PageTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Page
  alias Badge.App.Race.Race
  alias Badge.App.Race.Scene

  defp loaded(race), do: %{Page.init() | race: race, seen: race, hills: Scene.hills()}

  defp racing, do: Race.new({0, 0}) |> Race.start(7_000) |> Race.step(10_000, %{steer: 0, throttle: false, brake: false})

  test "init is pure and draws nothing" do
    assert Page.init().race == nil
    assert Page.render(Page.init()) == []
    assert Page.title() == "Racer"
  end

  test "repaints and stays awake only while counting down or racing" do
    assert Page.refresh(Page.init()) == 100
    assert Page.refresh(loaded(Race.new({0, 0}))) == 100
    assert Page.refresh(loaded(Race.start(Race.new({0, 0}), 0))) == 50
    assert Page.refresh(loaded(racing())) == 50
    refute Page.awake?(Page.init())
    refute Page.awake?(loaded(Race.new({0, 0})))
    assert Page.awake?(loaded(racing()))
  end

  describe "steer/3" do
    test "arrow keys give full lock" do
      assert Page.steer([], 0, 0) == 0
      assert Page.steer([~c"Right"], 0, 0) == 1024
      assert Page.steer([~c"Left"], 0, 0) == -1024
    end

    test "turning right raises the lean: 423 mg from zero is full lock, less is proportional" do
      assert Page.steer([], 423, 0) == 1024
      assert Page.steer([], -423, 0) == -1024
      assert Page.steer([], 200, 0) == 484
      assert Page.steer([], 300, 300) == 0
    end

    test "tilt and keys add up and clamp" do
      assert Page.steer([~c"Right"], 1_000, 0) == 1024
      assert Page.steer([~c"Left"], 200, 0) == -540
    end

    test "a full g either way from a tilted zero is still full lock" do
      assert Page.steer([], 1_000, -1_000) == 1024
      assert Page.steer([], -1_000, 1_000) == -1024
    end
  end

  test "Space or Up is the throttle, Down the brake" do
    input = fn held -> Page.input(%{loaded(racing()) | held: held}) end
    assert %{throttle: true, brake: false} = input.([~c"Space"])
    assert %{throttle: true, brake: false} = input.([~c"Up"])
    assert %{throttle: false, brake: true} = input.([~c"Down"])
    assert %{throttle: false, brake: false, steer: 0} = input.([])
  end

  describe "handle_key/2" do
    test "Space on the intro starts the countdown and zeroes the tilt" do
      state = %{loaded(Race.new({0, 0})) | lean: 120}
      assert {:ok, started} = Page.handle_key({:char, ?\s}, state)
      assert started.race.phase == :countdown
      assert started.zero == 120
    end

    test "Space still held from the race does not skip the result" do
      race = racing()
      finished = %{race | phase: :finished, total: 100_000, lap_times: [30_000, 30_000, 40_000]}
      assert Page.handle_key({:char, ?\s}, %{loaded(finished) | held: [~c"Space"]}) == :ignore
    end

    test "a fresh Space press on the result starts the next race" do
      race = racing()
      finished = %{race | phase: :finished, total: 100_000, lap_times: [30_000, 30_000, 40_000]}
      assert {:ok, %{race: %{phase: :countdown}}} = Page.handle_key({:char, ?\s}, loaded(finished))
    end

    test "Space during a race is the throttle, not a restart" do
      assert Page.handle_key({:char, ?\s}, loaded(racing())) == :ignore
    end

    test "other keys are ignored" do
      assert Page.handle_key({:char, ?x}, loaded(Race.new({0, 0}))) == :ignore
      assert Page.handle_key({:move, :up}, loaded(racing())) == :ignore
    end
  end

  test "held keys and tilt arrive as messages" do
    state = loaded(racing())
    assert {:ok, %{held: [~c"Up"]}} = Page.handle_info({:held, [~c"Up"]}, state)
    assert {:ok, %{lean: -70}} = Page.handle_info({:tilt, -70}, state)
    assert Page.handle_info(:whatever, state) == :ignore
  end

  describe "best times in NVS" do
    test "round trip" do
      assert Page.decode(Page.encode({40_100, 125_000})) == {40_100, 125_000}
    end

    test "missing or malformed reads as no best" do
      assert Page.decode(nil) == {0, 0}
      assert Page.decode(<<5>>) == {0, 0}
      assert Page.decode(<<1::32, 2::32, 3>>) == {0, 0}
    end
  end

  test "a loaded page renders the scene" do
    assert length(Page.render(loaded(racing()))) > 50
  end
end

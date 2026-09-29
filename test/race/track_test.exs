defmodule Badge.App.Race.TrackTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Track

  test "a lap is 600 segments of 100 units" do
    assert Track.segments() == 600
    assert Track.segment_length() == 100
    assert Track.lap_length() == 60_000
  end

  test "starts on a straight" do
    assert Track.curve(0) == 0
    assert Track.curve_at(0) == 0
  end

  test "the first bend is a gentle right at segment 50" do
    assert Track.curve(49) == 0
    assert Track.curve(50) == 2
  end

  test "curve_at wraps every lap" do
    assert Track.curve_at(5_000) == 2
    assert Track.curve_at(5_000 + Track.lap_length()) == 2
    assert Track.curve_at(5_000 + 2 * Track.lap_length()) == 2
  end

  test "every curve is within -4..4" do
    for i <- 0..599, do: assert(Track.curve(i) in -4..4)
  end

  test "has an ASCII name" do
    assert Track.name() =~ ~r/^[ -~]+$/
  end
end

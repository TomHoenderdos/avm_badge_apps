defmodule Badge.App.Race.CarTest do
  use ExUnit.Case, async: true

  alias Badge.App.Race.Car

  @gas %{steer: 0, throttle: true, brake: false}
  @brake %{steer: 0, throttle: false, brake: true}
  @coast %{steer: 0, throttle: false, brake: false}

  defp car(fields), do: Map.merge(Car.new(), fields)

  test "starts still in the middle of the road" do
    assert Car.new() == %{x: 0, speed: 0, distance: 0}
  end

  describe "speed" do
    test "throttle gains 600 a second" do
      assert Car.step(Car.new(), 1_000, @gas, 0).speed == 600
    end

    test "brake loses 1500 a second" do
      assert Car.step(car(%{speed: 1_000}), 100, @brake, 0).speed == 850
    end

    test "coasting loses 200 a second" do
      assert Car.step(car(%{speed: 1_000}), 1_000, @coast, 0).speed == 800
    end

    test "never beyond top speed or below zero" do
      assert Car.step(car(%{speed: 1_490}), 1_000, @gas, 0).speed == Car.top_speed()
      assert Car.step(car(%{speed: 100}), 1_000, @brake, 0).speed == 0
    end

    test "grass pulls the car down to 500, even on the throttle" do
      grassy = Enum.reduce(1..10, car(%{x: 1_200, speed: 1_500}), fn _, c -> Car.step(c, 200, @gas, 0) end)
      assert grassy.speed == 500
      assert grassy.x == 1_200
    end

    test "grass does not slow a car already below 500" do
      assert Car.step(car(%{x: -1_200, speed: 300}), 100, @coast, 0).speed == 280
    end
  end

  describe "position" do
    test "distance grows by speed times time" do
      assert Car.step(car(%{speed: 1_500}), 200, @gas, 0).distance == 300
    end

    test "full right lock at top speed moves 1800 a second" do
      assert Car.step(car(%{speed: 1_500}), 100, %{@gas | steer: 1024}, 0).x == 180
    end

    test "no steering at a standstill" do
      assert Car.step(Car.new(), 100, %{@coast | steer: 1024}, 0).x == 0
    end

    test "a bend pushes the car outward" do
      assert Car.step(car(%{speed: 1_500}), 100, @gas, 4).x == -135
      assert Car.step(car(%{speed: 1_500}), 100, @gas, -4).x == 135
    end

    test "never leaves the drawn scene" do
      assert Car.step(car(%{x: 1_590, speed: 1_500}), 200, %{@gas | steer: 1024}, 0).x == 1_600
      assert Car.step(car(%{x: -1_590, speed: 1_500}), 200, %{@gas | steer: -1024}, 0).x == -1_600
    end
  end
end

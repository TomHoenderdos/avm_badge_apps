defmodule Badge.App.Snake.GameTest do
  use ExUnit.Case, async: true

  alias Badge.App.Snake.Game

  test "starts heading right and moves one cell per tick" do
    game = Game.new(12, 10, 1)
    [{hx, hy} | _] = game.snake
    next = Game.tick(game)

    assert hd(next.snake) == {hx + 1, hy}
    assert length(next.snake) == 3
  end

  test "will not reverse into itself" do
    game = Game.new(12, 10, 1)
    turned = game |> Game.turn(:left) |> Game.tick()

    assert turned.dir == :right
    assert hd(turned.snake) == {3, 5}
  end

  test "a perpendicular turn is taken on the next tick" do
    game = Game.new(12, 10, 1)
    next = game |> Game.turn(:up) |> Game.tick()

    assert hd(next.snake) == {2, 4}
    assert next.dir == :up
  end

  test "grows when the head lands on food" do
    game = Game.new(12, 10, 1)
    food = {3, 5}
    next = Game.tick(%{game | food: food})

    assert hd(next.snake) == food
    assert length(next.snake) == 4
    assert next.score == 1
    assert next.food != food
  end

  test "dies on the wall and on its own body, but not on the cell the tail leaves" do
    game = Game.new(12, 10, 1)
    walled = game |> Map.put(:snake, [{11, 5}, {10, 5}, {9, 5}]) |> Game.tick()
    assert walled.alive == false

    sliding = %{game | snake: [{1, 5}, {1, 6}, {0, 6}, {0, 5}], dir: :left, queued: :left}
    assert Game.tick(sliding).alive

    biting = %{sliding | food: {0, 5}}
    assert Game.tick(biting).alive == false
  end
end

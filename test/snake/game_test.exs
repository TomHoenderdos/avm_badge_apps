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

  test "screensaver steers toward the food and around walls and body" do
    game = Game.new(12, 10, 1) |> Game.screensaver()
    assert game.screensaver

    ahead = %{game | snake: [{5, 5}, {4, 5}, {3, 5}], dir: :right, queued: :right, food: {9, 5}}
    assert hd(Game.tick(ahead).snake) == {6, 5}

    above = %{ahead | food: {5, 1}}
    assert hd(Game.tick(above).snake) == {5, 4}

    edged = %{ahead | snake: [{11, 5}, {10, 5}, {9, 5}], food: {11, 9}}
    edged = Game.tick(edged)
    assert edged.alive
    assert hd(edged.snake) == {11, 6}

    cornered = %{ahead | snake: [{11, 5}, {10, 5}, {9, 5}], food: {0, 5}}
    assert Game.tick(cornered).alive

    coiled = %{
      ahead
      | snake: [{5, 5}, {5, 6}, {6, 6}, {6, 5}, {6, 4}, {5, 4}, {4, 4}],
        dir: :up,
        queued: :up,
        food: {7, 5}
    }

    around = Game.tick(coiled)
    assert around.alive
    assert hd(around.snake) == {4, 5}
  end

  test "screensaver avoids pockets it cannot leave" do
    game = Game.new(12, 10, 1) |> Game.screensaver()

    snake = [
      {2, 7},
      {2, 8},
      {1, 8},
      {0, 8},
      {0, 9},
      {1, 9},
      {2, 9},
      {3, 9},
      {4, 9},
      {4, 8},
      {4, 7},
      {4, 6},
      {3, 6},
      {3, 5},
      {3, 4},
      {3, 3},
      {3, 2},
      {3, 1},
      {3, 0}
    ]

    game = %{game | snake: snake, dir: :right, queued: :right, food: {10, 2}}
    next = Game.tick(game)
    assert next.alive
    assert hd(next.snake) == {2, 6}

    hemmed = [
      {2, 7},
      {2, 6},
      {1, 6},
      {1, 7},
      {0, 7},
      {0, 8},
      {1, 8},
      {2, 8} | Enum.drop(snake, 4)
    ]

    boxed = %{game | snake: hemmed, food: {3, 8}}
    assert hd(Game.tick(boxed).snake) == {3, 7}
  end

  test "screensaver starts over after a crash and keeps the mode" do
    game = Game.new(12, 10, 1) |> Game.screensaver()

    boxed = %{
      game
      | snake: [{11, 5}, {11, 4}, {10, 4}, {10, 5}, {10, 6}, {11, 6}, {11, 7}],
        dir: :right,
        queued: :right
    }

    dead = Game.tick(boxed)
    assert dead.alive == false
    assert dead.screensaver

    paused = Enum.reduce(1..7, dead, fn _, g -> Game.tick(g) end)
    assert paused.alive == false

    fresh = Game.tick(paused)
    assert fresh.alive
    assert fresh.screensaver
    assert fresh.score == 0

    assert Game.screensaver(%{game | alive: false, screensaver: false}).alive
  end
end

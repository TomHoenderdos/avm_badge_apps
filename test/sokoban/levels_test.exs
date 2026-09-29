defmodule Badge.App.Sokoban.LevelsTest do
  use ExUnit.Case, async: true

  alias Badge.App.Sokoban.Board
  alias Badge.App.Sokoban.Levels

  test "there are twenty levels" do
    assert Levels.count() == 20
  end

  test "the first level is Microban 1" do
    assert Levels.get(1) == "####\n# .#\n#  ###\n#*@  #\n#  $ #\n#  ###\n####"
  end

  test "every level has a player, as many goals as boxes, and fits with 8 px tiles" do
    for n <- 1..Levels.count() do
      board = Board.parse(Levels.get(n))

      assert board.player != nil, "level #{n} has no player"
      assert length(board.boxes) == length(board.goals), "level #{n} boxes != goals"
      assert board.w * 8 <= 320 and board.h * 8 <= 188, "level #{n} is too big"
    end
  end
end

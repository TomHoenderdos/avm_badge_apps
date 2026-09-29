defmodule Badge.App.Sokoban.BoardTest do
  use ExUnit.Case, async: true

  alias Badge.App.Sokoban.Board

  # A one-row corridor: player, box, floor, goal.
  @row "######\n#@$ .#\n######"

  test "parse finds every piece and the size" do
    board = Board.parse(@row)

    assert board.w == 6
    assert board.h == 3
    assert board.player == {1, 1}
    assert board.boxes == [{2, 1}]
    assert board.goals == [{4, 1}]
    assert length(board.walls) == 14
  end

  test "parse reads boxes and the player standing on goals" do
    board = Board.parse("#####\n#*+ #\n#####\n")

    assert board.h == 3
    assert board.player == {2, 1}
    assert board.boxes == [{1, 1}]
    assert Enum.sort(board.goals) == [{1, 1}, {2, 1}]
  end

  test "moving onto floor moves the player" do
    {result, board} = Board.move(Board.parse("#####\n#@  #\n#####"), :right)

    assert result == :moved
    assert board.player == {2, 1}
  end

  test "moving into a wall is blocked" do
    board = Board.parse(@row)

    assert Board.move(board, :up) == {:blocked, board}
  end

  test "pushing moves the box one step" do
    {result, board} = Board.move(Board.parse(@row), :right)

    assert result == :pushed
    assert board.player == {2, 1}
    assert board.boxes == [{3, 1}]
  end

  test "a box against a wall is blocked" do
    board = Board.parse("#####\n#@$#\n#####")

    assert Board.move(board, :right) == {:blocked, board}
  end

  test "a box against another box is blocked" do
    board = Board.parse("######\n#@$$ #\n######")

    assert Board.move(board, :right) == {:blocked, board}
  end

  test "solved once every box is on a goal" do
    board = Board.parse(@row)
    refute Board.solved?(board)

    {:pushed, board} = Board.move(board, :right)
    {:pushed, board} = Board.move(board, :right)

    assert Board.solved?(board)
  end

  test "runs merge adjacent walls on a row" do
    runs = Board.runs(Board.parse("###\n# #\n###"))

    assert runs == [{0, 0, 3}, {0, 1, 1}, {2, 1, 1}, {0, 2, 3}]
  end
end

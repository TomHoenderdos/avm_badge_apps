defmodule Badge.App.Sokoban.RecordTest do
  use ExUnit.Case, async: true

  alias Badge.App.Sokoban.Board
  alias Badge.App.Sokoban.Record

  @board Board.parse("#####\n#@$.#\n#####")

  test "a record round-trips its moves and heat" do
    heat = %{{1, 1} => 2, {2, 1} => 1}

    assert Record.decode(Record.encode(7, heat, @board), @board) == {7, heat}
  end

  test "one byte per tile after the move count" do
    assert byte_size(Record.encode(7, %{}, @board)) == 2 + 5 * 3
  end

  test "counts cap at 255" do
    {_moves, heat} = Record.decode(Record.encode(300, %{{1, 1} => 999}, @board), @board)

    assert heat == %{{1, 1} => 255}
  end

  test "nothing stored, garbage, or another level's size reads as no record" do
    other = Board.parse("###\n#@#\n###")

    assert Record.decode(nil, @board) == nil
    assert Record.decode("junk", @board) == nil
    assert Record.decode(Record.encode(3, %{}, other), @board) == nil
  end

  test "only fewer moves beat a stored record" do
    assert Record.better?(9, nil)
    assert Record.better?(8, {9, %{}})
    refute Record.better?(9, {9, %{}})
    refute Record.better?(10, {9, %{}})
  end
end

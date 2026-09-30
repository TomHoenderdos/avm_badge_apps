defmodule Badge.App.Sokoban.Record do
  @moduledoc """
  A solved level's best run: its move count and how often each tile was visited.

  Stored as `<<moves::16, count, ...>>`, one count byte per tile, row by row
  across the level's `w * h` grid. Counts cap at 255, moves at 65535. `decode/2`
  answers nil for anything that does not fit the board, so a bad value reads as
  an unsolved level.
  """

  @doc "The binary for `moves` and the `heat` map on `board`."
  @spec encode(non_neg_integer, map, map) :: binary
  def encode(moves, heat, board) do
    counts = for y <- :lists.seq(0, board.h - 1), x <- :lists.seq(0, board.w - 1), do: min(Map.get(heat, {x, y}, 0), 255)

    :erlang.list_to_binary([<<min(moves, 65_535)::16>> | counts])
  end

  @doc "`{moves, heat}` from a stored binary, or nil when it does not fit `board`."
  @spec decode(binary | nil, map) :: {non_neg_integer, map} | nil
  def decode(<<moves::16, counts::binary>>, %{w: w, h: h}) when byte_size(counts) == w * h do
    {moves, heat(counts, 0, w, %{})}
  end

  def decode(_value, _board), do: nil

  @doc "Whether a run of `moves` beats the stored record."
  @spec better?(non_neg_integer, {non_neg_integer, map} | nil) :: boolean
  def better?(_moves, nil), do: true
  def better?(moves, {best, _heat}), do: moves < best

  defp heat(<<>>, _i, _w, acc), do: acc
  defp heat(<<0, rest::binary>>, i, w, acc), do: heat(rest, i + 1, w, acc)
  defp heat(<<n, rest::binary>>, i, w, acc), do: heat(rest, i + 1, w, Map.put(acc, {rem(i, w), div(i, w)}, n))
end

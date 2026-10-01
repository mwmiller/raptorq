defmodule RaptorqDecodeConsistencyTest do
  @moduledoc """
  Regression tests for silent data corruption during decode.

  Prior to 0.3.0, `Raptorq.decode/3` could return `{:ok, wrong_data}`
  when the selected subset produced a singular system that the solver
  did not detect.  These tests assert that decoding either produces the
  original data or reports an error — never plausible-looking garbage.
  """
  use ExUnit.Case, async: false

  @trials 15

  test "shuffled subsets decode to the original data or an error, never wrong data" do
    for k <- [10, 20] do
      data = :crypto.strong_rand_bytes(k * 8)
      {:ok, encoded} = Raptorq.encode(data, k, 8)
      needed = encoded.params.l - encoded.params.s - encoded.params.h

      symbols =
        for isi <- 0..(needed + 4) do
          {isi, Raptorq.repair(encoded.c, encoded.params, isi)}
        end

      for trial <- 1..@trials do
        shuffled = Enum.shuffle(symbols)

        case Raptorq.decode(shuffled, k, byte_size(data)) do
          {:ok, ^data} ->
            :ok

          {:ok, wrong} ->
            flunk(
              "k=#{k} trial=#{trial}: decode returned WRONG DATA " <>
                "(expected #{byte_size(data)} bytes, got #{byte_size(wrong)})"
            )

          {:error, reason} ->
            assert reason in [:singular, :insufficient_symbols, :inconsistent_symbol_size]
        end
      end
    end
  end

  test "exact-K' subsets decode to the original data or an error, never wrong data" do
    data = :crypto.strong_rand_bytes(80)
    k = 10
    {:ok, encoded} = Raptorq.encode(data, k, 8)
    needed = encoded.params.l - encoded.params.s - encoded.params.h

    symbols =
      for isi <- 0..(needed - 1) do
        {isi, Raptorq.repair(encoded.c, encoded.params, isi)}
      end

    for trial <- 1..@trials do
      subset = Enum.shuffle(symbols)

      case Raptorq.decode(subset, k, byte_size(data)) do
        {:ok, ^data} ->
          :ok

        {:ok, _wrong} ->
          flunk("trial=#{trial}: exact-K' decode returned wrong data")

        {:error, reason} ->
          assert reason in [:singular, :insufficient_symbols, :inconsistent_symbol_size]
      end
    end
  end

  test "extra symbols are used to recover from a bad leading subset" do
    data = :crypto.strong_rand_bytes(80)
    k = 10
    {:ok, encoded} = Raptorq.encode(data, k, 8)
    needed = encoded.params.l - encoded.params.s - encoded.params.h

    symbols =
      for isi <- 0..(needed + 9) do
        {isi, Raptorq.repair(encoded.c, encoded.params, isi)}
      end

    # Several shuffles to exercise different window selections
    for _ <- 1..10 do
      assert {:ok, ^data} = Raptorq.decode(Enum.shuffle(symbols), k, byte_size(data))
    end
  end

  test "streaming decoder never yields wrong data" do
    data = :crypto.strong_rand_bytes(80)
    k = 10
    {:ok, encoded} = Raptorq.encode(data, k, 8)
    needed = encoded.params.l - encoded.params.s - encoded.params.h

    symbols =
      for isi <- 0..(needed + 9) do
        {isi, Raptorq.repair(encoded.c, encoded.params, isi)}
      end

    for _ <- 1..5 do
      state = Raptorq.StreamingDecoder.new(k, byte_size(data))

      result =
        Enum.reduce_while(Enum.shuffle(symbols), state, fn {isi, sym}, acc ->
          case Raptorq.StreamingDecoder.add_symbol(acc, isi, sym) do
            {:ok, {:decoded, decoded}, _new_state} ->
              assert decoded == data, "streaming decode produced wrong data"
              {:halt, {:ok, decoded}}

            {:ok, :incomplete, new_state} ->
              {:cont, new_state}

            {:error, reason, _} ->
              flunk("unexpected streaming error: #{inspect(reason)}")
          end
        end)

      assert result == {:ok, data}
    end
  end
end

defmodule Exa.Json.JsonWriter do
  @moduledoc "Utilities to write JSON format."

  use Exa.Json.Constants

  alias Exa.Text, as: T

  import Exa.Indent, except: [reduce: 3]
  alias Exa.Indent, as: I

  import Exa.Types

  import Exa.Json.Types
  alias Exa.Json.Types, as: J

  # document ----------

  @doc "Write JSON data to file."
  @spec to_file(J.value(), String.t()) :: T.textdata()
  def to_file(value, filename) when is_nonempty_string(filename) do
    value |> encode() |> Exa.File.to_file_text(filename)
  end

  @doc """
  Create a new JSON document.

  The argument is a root object or array.
  Keywords and maps are objects, lists are arrays.
  Empty list `[]` is intepreted as empty array. 
  Use empty map `%{}` for empty object.

  The result is text data for the whole JSON document.
  """
  @spec encode(J.value()) :: T.textdata()
  def encode(value), do: indent() |> root(value) |> to_text()

  # root ----------

  @spec root(I.indent(), J.value()) :: I.indent()

  defp root(io, []), do: io |> txtl("[]")
  defp root(io, m) when is_empty_map(m), do: io |> txtl("{}")
  defp root(io, map) when is_map(map), do: root(io, Map.to_list(map))

  # object
  defp root(io, [{k, v} | kw]) do
    io
    |> chr(?{)
    |> pushl()
    |> kv(k, v)
    |> reduce(kw, fn {k, v}, io -> io |> chr(?,) |> endl() |> newl() |> kv(k, v) end)
    |> popl()
    |> chr(?})
  end

  # array
  defp root(io, [v | vals]) when is_list(vals) do
    io
    |> chr(?[)
    |> pushl()
    |> val(v)
    |> reduce(vals, fn v, io -> io |> chr(?,) |> endl() |> newl() |> val(v) end)
    |> popl()
    |> chr(?])
  end

  # -----------------
  # private functions
  # -----------------

  @spec reduce(I.indent(), Enumerable.t(), (any(), I.indent() -> I.indent())) :: I.indent()
  defp reduce(io, xs, fun), do: Enum.reduce(xs, io, fun)

  @spec kv(I.indent(), J.key(), any()) :: I.indent()
  defp kv(io, k, v) when is_key(k) do
    io |> txt([?", to_string(k), "\": "]) |> val(v)
  end

  @spec val(I.indent(), J.value()) :: I.indent()
  defp val(io, nil), do: txt(io, "null")
  defp val(io, true), do: txt(io, "true")
  defp val(io, false), do: txt(io, "false")
  defp val(io, i) when is_integer(i), do: str(io, i)
  defp val(io, x) when is_float(x), do: str(io, x)
  defp val(io, a) when is_atom(a), do: txt(io, [?", escape(to_string(a)), ?"])
  defp val(io, s) when is_string(s), do: txt(io, [?", escape(s), ?"])
  defp val(io, arr_kw) when is_list(arr_kw), do: root(io, arr_kw)
  defp val(io, map) when is_map(map), do: root(io, map)

  defp escape(s) when is_string(s) or is_atom(s) do
    s |> to_string() |> String.to_charlist() |> esc() |> to_string()
  end

  defp esc(chars, out \\ [])
  defp esc([?\\, ?" | rest], out), do: esc(rest, [?" | out])
  defp esc([?\\, ?n | rest], out), do: esc(rest, [?\n | out])
  defp esc([?\\, ?r | rest], out), do: esc(rest, [?\r | out])
  defp esc([?\\, ?t | rest], out), do: esc(rest, [?\t | out])
  defp esc([?\\, ?f | rest], out), do: esc(rest, [?\f | out])
  defp esc([?\\, ?b | rest], out), do: esc(rest, [?\b | out])
  defp esc([?\\, ?\\ | rest], out), do: esc(rest, [?\\ | out])
  defp esc([?\\, ?u, a, b, c, d | rest], out), do: esc(rest, [hex([a, b, c, d]) | out])
  defp esc([c | rest], out), do: esc(rest, [c | out])
  defp esc([], out), do: Enum.reverse(out)

  defp hex(hex), do: hex |> IO.chardata_to_string() |> Integer.parse(16)
end

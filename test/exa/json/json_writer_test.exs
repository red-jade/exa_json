defmodule Exa.Json.JsonWriterTest do
  use ExUnit.Case

  use Exa.Json.Constants

  import Exa.Json.JsonWriter

  @out_dir ["test", "output", "json"]

  defp file(name), do: Exa.File.join(@out_dir, name, @filetype_json)

  @simple_json ~s|[
  {
    "a": 1,
    "label": "one",
    "size": 3.14
  },
  {
    "close": false,
    "open": true,
    "a": null
  },
  [
    "foo",
    [
      2,
      "\"three\"",
      null
    ]
  ],
  {
    "bar": {
      "x": 1.2e10,
      "y": -2.3
    },
    "baz": {
      "y": 2,
      "x": 1
    }
  }
]|

  # JSON output ---------

  test "simple" do
    json =
      to_file(
        [
          # keyword object
          [a: 1, label: "one", size: 3.14],
          # map object
          %{:a => nil, :open => true, :close => false},
          # nested arrays
          ["foo", [2, "\"thr\u0065e\"", nil]],
          # keyword object, nested array, nested map object
          [bar: [x: 1.2e10, y: -2.3], baz: %{x: 1, y: 2}]
        ],
        file("simple")
      )

    assert @simple_json == to_string(json)
  end
end

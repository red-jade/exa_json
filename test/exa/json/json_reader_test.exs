defmodule Exa.Json.JsonReaderTest do
  use ExUnit.Case

  use Exa.Json.Constants

  import Exa.Json.JsonReader

  @in_dir ["test", "input", "json"]

  @bench_dir Path.join(["test", "bench"])

  @pkg_json_dir ["deps", "pkg_json", "testdata"]

  @gz_files ["example", "sample", "code", "twitter", "canada", "citm_catalog"]

  defp file(name), do: Exa.File.join(@in_dir, name, @filetype_json)

  defp pkg_file(name), do: Exa.File.join(@pkg_json_dir, name, [@filetype_json, @filetype_gz])

  @simple_kw [
    [a: 1.0, label: "one", size: 3.14],
    [close: false, open: true, a: nil],
    ["foo", [2.0, "\"three\"", nil]],
    [bar: [x: 1.2e10, y: -2.3], baz: [y: 2, x: 1]]
  ]

  @simple_map [
    %{label: "one", size: 3.14, a: 1},
    %{close: false, open: true, a: nil},
    ["foo", [2.0, "\"three\"", nil]],
    %{baz: %{x: 1, y: 2}, bar: %{y: -2.3, x: 1.2e10}}
  ]

  @simple_pt [
    [a: 1, label: "one", size: 3.14],
    [close: false, open: true, a: nil],
    ["foo", [2, "\"three\"", nil]],
    [bar: {:p2d, 12_000_000_000.0, -2.3}, baz: {:p2d, 1, 2}]
  ]

  defmodule Pointer do
    # factory to test custom object creation
    def new(kvs) do
      if Keyword.has_key?(kvs, :x) and Keyword.has_key?(kvs, :y) do
        {
          :p2d,
          Keyword.fetch!(kvs, :x),
          Keyword.fetch!(kvs, :y)
        }
      else
        Keyword.new(kvs)
      end
    end
  end

  # JSON input ---------

  test "decode object to keyword" do
    2 = decode("2")
    3.14 = decode("3.14")
    "string" = decode(~S|"string"|)

    [] = decode("[  ]")
    [1, 2, 3] = decode("[1,2,3]")
    [1, [2, 3, 4], [foo: 9]] = decode(~S|[1,[2,3,4],{"foo": 9}]|)

    [] = decode("{  }")
    [foo: 3, bar: "val"] = decode(~S|{"foo": 3, "bar": "val"}|)
    [baz: [-3, -2]] = decode(~S|{"baz": [-3,-2]}|)
  end

  test "basic errors" do
    assert_raise ArgumentError, fn -> decode(":") end
    assert_raise ArgumentError, fn -> decode(",") end
    assert_raise ArgumentError, fn -> decode("}") end
    assert_raise ArgumentError, fn -> decode("]") end

    assert_raise ArgumentError, fn -> decode(~S|["foo": 9]|) end
    assert_raise ArgumentError, fn -> decode(~S|[[]|) end
    assert_raise ArgumentError, fn -> decode(~S|[]]|) end

    assert_raise ArgumentError, fn -> decode(~S|{"foo", 9}|) end
    assert_raise ArgumentError, fn -> decode(~S|{"foo"  9}|) end
    assert_raise ArgumentError, fn -> decode(~S|{"foo": 9}}|) end
    assert_raise ArgumentError, fn -> decode(~S|{"foo": }|) end
    assert_raise ArgumentError, fn -> decode(~S|{9: "foo"}|) end
    assert_raise ArgumentError, fn -> decode(~S|{ } }|) end
    assert_raise ArgumentError, fn -> decode(~S|{ { }|) end
  end

  test "commas" do
    # badly formed, but accepted, because commas are whitespace
    [1, 9] = decode("[1 9]")
    [1, 9] = decode("[1,9,]")
    [1, 9] = decode("[1,,9]")
    [1, 9] = decode("[1,9],")
    [1, 9] = decode(",[1,9]")

    # catch errors

    assert 1 = decode("1", comma: true)
    assert_raise ArgumentError, fn -> decode("[null 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[true 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[false 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[1 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[-1 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[3.1 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[[1] 9]", comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/[{"a":1} 9]/, comma: true) end

    assert_raise ArgumentError, fn -> decode("[1,9,]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[1,,9]", comma: true) end
    assert_raise ArgumentError, fn -> decode("[1,9],", comma: true) end
    assert_raise ArgumentError, fn -> decode(",[1,9]", comma: true) end
    # assert_raise ArgumentError, fn -> decode("[,1,9]", comma: true) end

    assert_raise ArgumentError, fn -> decode(~s/{"a": 1,}/, comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/{"a": 1,,"b":2}/, comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/{,"a": 1}/, comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/{"a":, 1}/, comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/{"a",: 1}/, comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/,{"a": 1}/, comma: true) end
    assert_raise ArgumentError, fn -> decode(~s/{"a": 1},/, comma: true) end
  end

  test "simple file" do
    cms = ["//", "#"]
    jsonkw = from_json(file("simple"), comments: cms)
    assert @simple_kw == jsonkw

    jsonmap = from_json(file("simple"), object: Map, comments: cms)
    assert @simple_map == jsonmap

    jsonpt = from_json(file("simple"), object: Pointer, comments: cms)
    assert @simple_pt == jsonpt

    # fails if comments are not removed
    assert_raise ArgumentError, fn -> from_json(file("simple")) end
  end

  test "geojson file" do
    json = from_json(file("geo"), object: Map)
    assert is_map(json)
    feats = Map.get(json, :features)
    assert is_list(feats)
    assert is_map(hd(feats))
  end

  # compressed input files with/without benchmarking ----------

  test "compressed" do
    run(benchmarks())
  end

  @tag benchmark: true
  @tag timeout: 200_000
  test "compressed benchmarks" do
    Benchee.run(
      benchmarks(),
      time: 20,
      save: [path: @bench_dir <> "/json_reader.benchee"],
      load: @bench_dir <> "/json_reader.latest.benchee"
    )
  end

  defp benchmarks() do
    for gzfile <- @gz_files, into: %{} do
      {gzfile, fn -> from_json(pkg_file(gzfile)) end}
    end
  end

  defp run(funmap), do: funmap |> Map.values() |> Enum.each(& &1.())
end

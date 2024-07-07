defmodule Exa.Json.JsonReader do
  @moduledoc "Utilities to parse JSON format."

  require Logger
  use Exa.Json.Constants

  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Factory, as: F

  import Exa.Json.Types
  alias Exa.Json.Types, as: J

  alias Exa.Option

  @doc """
  Read a JSON file.

  The file is assumed to be encoded in UTF-8 (UTF16/UTF32 LE/BE not supported).
  If the file has a UTF-8 BOM, it will be ignored.

  See `decode` for descritption of the `:options`.
  """
  @spec from_json(String.t(), E.options()) :: J.value()
  def from_json(filename, opts \\ []) when is_nonempty_string(filename) do
    # don't handle comments in the file reader
    # because lexer now handles inline comments and needs the newlines
    filename |> Exa.File.from_file_text() |> Exa.File.bom!() |> decode(opts)
  end

  @doc """
  Decode JSON text.

  Multi-line C-style comments `/* ... */` are always ignored.

  The option `:comma` determines how commas are parsed:
  - `false` (default): Commas are ignored. 
     Commas are treated as whitespace.
     There are no errors reported for repeated or trailing commas.
  - `true`: Commas are processed and must only occur between array values.
     Errors are reported for repeated, trailing or out-of-place commas.

  The option `:comments` contains a list of line prefixes that will be ignored.
  For example, `comments: ["#", //"]` ignores both Elixir-style comments
  and C-style single-line comments (must be the full line, not inline after content).
  If there are no comment prefixes, the file will be loaded as a bulk binary string.

  The option `:object` determines how JSON objects are returned to Elixir.
  The option value should be a factory function, 
  or the (atom) name of a module that has a `new` method 
  to be used as a factory.

  The factory method (or `new`) takes a list of `{key,value}` 
  pairs to create a new object. 
  For example, `Keyword` (default) or `Map` both have the required `new` function.
  The `Exa.Factory` can generate a factory function from a list of structs.
  A custom module could create application-specific objects
  based on the set of keys in the list.

  Duplicate keys are handled in accordance with the underlying object implementation:
  `Keyword` list will preserve duplicates; 
  `Map` will remove duplicates, with last instance prevailing;
  the struct `Factory` behaves like `Map`.
  """
  @spec decode(String.t(), E.options()) :: J.value()
  def decode(json, opts \\ []) when is_string(json) do
    ca = Option.get_bool(opts, :comma, false)
    cms = Option.get_list_nonempty_string(opts, :comments, [])

    fac = Keyword.get(opts, :object, Keyword)

    facfun =
      cond do
        is_function(fac, 1) ->
          fac

        is_module(fac) and function_exported?(fac, :new, 1) ->
          &fac.new/1

        true ->
          msg = "Illegal ':object' option '#{fac}'"
          Logger.error(msg)
          raise ArgumentError, message: msg
      end

    json |> lex(cms, ca, []) |> parse([], ca, facfun)
  end

  # ------
  # parser 
  # ------

  @typep delim() :: :open_brace | :close_brace | :open_square | :close_square | :colon | :comma
  @typep tok() :: J.prim() | delim()

  @typep arr() :: {:arr, J.array()}
  @typep obj() :: {:obj, Keyword.t()}
  @typep stack() :: [J.value() | arr() | obj()]

  @spec parse([tok()], stack(), bool(), F.factory_fun()) :: J.value()

  # array

  defp parse([:open_square, delim | _], _, _ca, _facfun) when delim in [:colon, :comma] do
    msg = "Unexpected comma ',' or colon ':' after '[', expecting value"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:open_square | _toks], [{:obj, _} | _], _ca, _facfun) do
    msg = "Unexpected nested open object '[', expecting key"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:open_square | toks], stack, ca, facfun) do
    parse(toks, [{:arr, []} | stack], ca, facfun)
  end

  defp parse([:close_square | toks], [{:arr, arr} | stack], ca, facfun) do
    parse(toks, push(Enum.reverse(arr), stack), ca, facfun)
  end

  defp parse([:close_square | _], _stack, _ca, _facfun) do
    msg = "Unexpected close array ']'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # object

  defp parse([:open_brace | [tok | _] = toks], stack, ca, facfun)
       when is_string(tok) or tok == :close_brace do
    parse(toks, [{:obj, []} | stack], ca, facfun)
  end

  defp parse([:open_brace, delim | _toks], _stack, _ca, _facfun) when delim in [:colon, :comma] do
    msg = "Unexpected comma ',' or colon ':' after '{', expecting key or '}'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:open_brace | _toks], [{:obj, _} | _], _ca, _facfun) do
    msg = "Unexpected nested open object '{', expecting key"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:open_brace | [tok | _]], _stack, _ca, _facfun) do
    msg = "Unexpected object token, expecting key, found '#{tok}'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:close_brace | toks], [{:obj, kw} | stack], ca, facfun) do
    new_obj = facfun.(Enum.reverse(kw))
    new_stack = push(new_obj, stack)
    parse(toks, new_stack, ca, facfun)
  end

  defp parse([:close_brace | _], [k | _], _ca, _facfun) when is_key(k) do
    msg = "Unexpected close object '}', expecting value"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:close_brace | _], _stack, _ca, _facfun) do
    msg = "Unexpected close object '}'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # colon

  defp parse([key, :colon | toks], [{:obj, _} | _] = stack, ca, facfun) when is_string(key) do
    parse(toks, [String.to_atom(key) | stack], ca, facfun)
  end

  defp parse([:colon | _], [{:arr, _} | _], _ca, _facfun) do
    msg = "Found colon ':' in array, expecting comma ',' or value"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:colon | _], [{:obj, _} | _], _ca, _facfun) do
    msg = "Unexpected colon ':' in object, expecting key or colon ':' or value"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:colon | _], [k, {:obj, _} | _], _ca, _facfun) when is_atom(k) do
    msg = "Repeated colon ':' in object, expecting value"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:colon | _], _stack, _ca, _facfun) do
    msg = "Unexpected colon ':'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # comma

  defp parse([:comma | [tok | _] = toks], [{:arr, _} | _] = stack, true, facfun)
       when is_value(tok) or tok in [:open_square, :open_brace] do
    parse(toks, stack, true, facfun)
  end

  defp parse([:comma | [tok | _] = toks], [{:obj, _} | _] = stack, true, facfun)
       when is_string(tok) or tok in [:open_square, :open_brace] do
    parse(toks, stack, true, facfun)
  end

  defp parse([:comma, :comma | _], _, true, _facfun) do
    msg = "Repeated comma ',,'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:comma, :close_square | _], _, true, _facfun) do
    msg = "Trailing comma after final array value ',]'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:comma, :close_brace | _], _, true, _facfun) do
    msg = "Trailing comma after final object value ',}'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([:comma | _], _stack, true, _facfun) do
    msg = "Unexpected comma ','"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # value 

  defp parse([val], [], ca, facfun) when is_prim(val) do
    parse([], [val], ca, facfun)
  end

  defp parse([val | _], [{:arr, _} | _], true, _facfun) when is_prim(val) do
    msg = "Unexpected value '#{val}', expecting comma ','"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([val | toks], [{:arr, _} | _] = stack, false, facfun) when is_prim(val) do
    parse(toks, push(val, stack), false, facfun)
  end

  defp parse([val | toks], [k, {:obj, _} | _] = stack, ca, facfun)
       when is_prim(val) and is_atom(k) do
    parse(toks, push(val, stack), ca, facfun)
  end

  defp parse([val | _], [{:obj, _} | _], _ca, _facfun) when is_prim(val) do
    msg = "Unexpected value '#{val}', expecting '\"key\":'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # end of json

  defp parse([], [{:arr, _}], _, _) do
    msg = "Incomplete array, expecting ']'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([], [{:obj, _}], _, _) do
    msg = "Incomplete object, expecting '}'"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([], [k, {:obj, _}], _, _) when is_atom(k) do
    msg = "Incomplete object with key '#{k}', expecting value"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp parse([], [root], _, _), do: root

  defp parse([], [], _, _) do
    msg = "Empty document"
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # update the stack with a value
  # depending if an array or an object is currently open
  # if the stack is empty it is the end of the document
  @spec push(J.value(), stack()) :: stack()
  defp push(root, []), do: [root]

  defp push(v, [k, {:obj, kw} | stack]) when is_atom(k), do: [{:obj, [{k, v} | kw]} | stack]
  defp push(v, [{:arr, arr} | stack]), do: [{:arr, [v | arr]} | stack]

  defp push(v, _stack) when is_string(v) do
    msg = ~s/Found value '#{v}' in Object, expecting ':'/
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  defp push(v, _stack) do
    msg = ~s/Found value '#{v}' in Object, expecting string '"key":'/
    Logger.error(msg)
    raise ArgumentError, message: msg
  end

  # -----
  # lexer 
  # -----

  # Tokenize the string
  #
  # note that ascii-is-ascii in utf8
  # so ascii can be handled as raw byte (default) in binary format
  # only when the character can be non-ascii is the utf8 modifier needed
  #
  # use the comma flag to indicate if commas should be ignored or tokenized
  #
  # always remove multi-line comments  /* ... */

  @spec lex(String.t(), [String.t()], bool(), [tok()]) :: [tok()]

  defp lex(<<c, s::binary>>, cms, ca, toks) when is_ws(c), do: lex(s, cms, ca, toks)
  defp lex(<<?,, s::binary>>, cms, false, toks), do: lex(s, cms, false, toks)
  defp lex(<<?,, s::binary>>, cms, true, toks), do: lex(s, cms, true, [:comma | toks])
  defp lex(<<?:, s::binary>>, cms, ca, toks), do: lex(s, cms, ca, [:colon | toks])
  defp lex(<<?[, s::binary>>, cms, ca, toks), do: lex(s, cms, ca, [:open_square | toks])
  defp lex(<<?], s::binary>>, cms, ca, toks), do: lex(s, cms, ca, [:close_square | toks])
  defp lex(<<?{, s::binary>>, cms, ca, toks), do: lex(s, cms, ca, [:open_brace | toks])
  defp lex(<<?}, s::binary>>, cms, ca, toks), do: lex(s, cms, ca, [:close_brace | toks])
  defp lex("null" <> s, cms, ca, toks), do: lex(s, cms, ca, [nil | toks])
  defp lex("true" <> s, cms, ca, toks), do: lex(s, cms, ca, [true | toks])
  defp lex("false" <> s, cms, ca, toks), do: lex(s, cms, ca, [false | toks])

  defp lex(<<?", s::binary>>, cms, ca, toks) do
    {str, rest} = quoted(s, "")
    lex(rest, cms, ca, [str | toks])
  end

  defp lex(<<c, s::binary>>, cms, ca, toks) when is_numstart(c) do
    {val, rest} = num(s, <<c>>, false)
    lex(rest, cms, ca, [val | toks])
  end

  defp lex("/*" <> s, cms, ca, toks), do: lex(comment(s), cms, ca, toks)

  defp lex("", _cms, _ca, toks), do: Enum.reverse(toks)

  defp lex(str, cms, ca, toks) do
    if not String.starts_with?(str, cms) do
      msg = "Unrecognized JSON data:  '#{Exa.String.summary(str)}'"
      Logger.error(msg)
      raise ArgumentError, message: msg
    end

    lex(endline(str), cms, ca, toks)
  end

  # consume multiline comments
  @spec comment(String.t()) :: String.t()
  defp comment("*/" <> s), do: s
  defp comment(<<_::utf8, s::binary>>), do: comment(s)

  # consume to the end of the line
  @spec endline(String.t()) :: String.t()
  defp endline(<<?\n, s::binary>>), do: s
  defp endline(<<_::utf8, s::binary>>), do: endline(s)
  defp endline(<<>>), do: ""

  # read a quoted string up to the close quotes
  @spec quoted(String.t(), String.t()) :: {String.t(), String.t()}

  defp quoted(<<?", s::binary>>, name), do: {name, s}
  defp quoted(<<?\\, ?", s::binary>>, name), do: quoted(s, <<name::binary, ?">>)
  defp quoted(<<?\\, ?\n, s::binary>>, name), do: quoted(s, <<name::binary, ?\n>>)
  defp quoted(<<?\\, ?\r, s::binary>>, name), do: quoted(s, <<name::binary, ?\r>>)
  defp quoted(<<?\\, ?\t, s::binary>>, name), do: quoted(s, <<name::binary, ?\t>>)
  defp quoted(<<?\\, ?\b, s::binary>>, name), do: quoted(s, <<name::binary, ?\b>>)
  defp quoted(<<?\\, ?\f, s::binary>>, name), do: quoted(s, <<name::binary, ?\f>>)
  defp quoted(<<?\\, ?/, s::binary>>, name), do: quoted(s, <<name::binary, ?/>>)
  defp quoted(<<?\\, ?\\, s::binary>>, name), do: quoted(s, <<name::binary, ?\\>>)

  defp quoted(<<?\\, ?u, a, b, c, d, s::binary>>, name) do
    quoted(s, <<name::binary, from_hex([a, b, c, d])::utf8>>)
  end

  defp quoted(<<c::utf8, s::binary>>, name) when is_char(c),
    do: quoted(s, <<name::binary, c::utf8>>)

  defp quoted(<<c::utf8, s::binary>>, name) do
    IO.puts("Warning: unrecognized character U+#{to_hex(c)}")
    # substitute the Unicode replacement character
    quoted(s, <<name::binary, 0xFFFD::utf8>>)
  end

  # read a number and parse as int or float, if it contains '.' or 'E' or 'e'
  @spec num(String.t(), String.t(), bool()) :: {number(), String.t()}
  defp num(<<?., s::binary>>, num, _isf), do: num(s, <<num::binary, ?.>>, true)
  defp num(<<?E, s::binary>>, num, _isf), do: num(s, <<num::binary, ?E>>, true)
  defp num(<<?e, s::binary>>, num, _isf), do: num(s, <<num::binary, ?e>>, true)
  defp num(<<c, s::binary>>, num, isf) when is_numchar(c), do: num(s, <<num::binary, c>>, isf)
  defp num(s, num, true), do: {num |> Float.parse() |> elem(0), s}
  defp num(s, num, false), do: {num |> Integer.parse() |> elem(0), s}

  @spec from_hex(charlist()) :: non_neg_integer()
  def from_hex(hex), do: hex |> to_string() |> Integer.parse(16) |> elem(0)

  @spec to_hex(non_neg_integer(), E.count()) :: String.t()
  def to_hex(c, pad \\ 4), do: c |> Integer.to_string(16) |> String.pad_leading(pad, "0")
end

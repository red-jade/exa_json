defmodule Exa.Json.Types do
  @moduledoc "Types for JSON format."

  import Exa.Types

  @type object() :: Keyword.t() | %{key() => value()}
  defguard is_object(o) when is_keyword(o) or is_map(o) or is_struct(o)

  @type array() :: [value()]
  defguard is_array(a) when is_list(a)

  @type prim() :: nil | true | false | number() | String.t()
  defguard is_prim(v) when is_number(v) or is_string(v) or v in [true, false, nil]

  @type value() :: prim() | array() | object()
  defguard is_value(v) when is_prim(v) or is_array(v) or is_object(v)

  @type key() :: atom()
  defguard is_key(k) when is_atom(k)

  # options for JsonReader
  @type opt_obj_key() :: :object | :comma | :comments
  @type fac_fun() :: module() | Exa.Factory.factory_fun()
end

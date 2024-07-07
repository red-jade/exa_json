defmodule Exa.Json.Constants do
  @moduledoc "Constants for JSON format."

  defmacro __using__(_) do
    quote do
      @filetype_json :json
      # TODO - move to Exa core
      @filetype_gz :gz
    end
  end
end

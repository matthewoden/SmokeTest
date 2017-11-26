defmodule SmokeTest.Adapters.JSONEncoder do
    @type encoded :: binary

    @moduledoc """
    A basic adapter for a JSON encoder. Returns JSON, or raises an error.
    """

    @doc """
    Encodes data into a `binary`.
    """
    @callback encode!(term, Keyword.t) :: encoded | no_return
end

if Code.ensure_loaded?(Poison) do
    defmodule SmokeTest.Adapters.JSONEncoder.Poison do

        @moduledoc """
        A Posion-baed JSON encoder for SmokeTest. 

        To use, add Poison to your mix.exs dependencies:

            def deps do
                [{:poison, "~> 3.0"}]
            end

        Then, update your dependencies:

            $ mix deps.get

        The adapter will automatically be picked up and used by SmokeTest,
        unless explicitly configured for another adapter. If you want 
        to manually add this parser to the configuration, simply
        include the following:

            config :your_app, SmokeTest
                json_encoder: SmokeTest.Adapters.JSONEncoder.Poison
        """
        @behaviour SmokeTest.Adapters.JSONEncoder

        @impl true
        @doc """
        encodes a value into JSON.
        """
        def encode!(data, options \\ []) do
            Poison.encode!(data, options)
        end
    end
end
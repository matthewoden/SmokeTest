defmodule SmokeTest.Test do
  defstruct [:id, :task, :timeout, :result]
end


defmodule SmokeTest do
  @moduledoc """
  A configurable Plug middleware to quickly find errors that might prevent a 
  deployment. It can also be used as an application health-check.

  ## Usage
  
  SmokeTest can be easily configured for Plug or Phoenix servers. The only 
  options you need to provide is the OTP application that contains your 
  smoketest configuration.

  ### Plug

  For pure Plug applications, simply use `Plug.Router.forward/2` on the 
  path you'd like to use for smoke-testing. 
  
  ```
  defmodule ExamplePlugWeb.Router do
    use Plug.Router

    forward "/ping", to: SmokeTest, init_opts: [otp_app: :example])
  end
  ```

  ### Phoenix

  For Phoenix applications, adding SmokeTest to your router is also a one-liner. 
  You can pass Smoketest into [`Phoenix.Router.forward/4`](https://hexdocs.pm/phoenix/Phoenix.Router.html#forward/4), choosing
  whatever route you prefer for smoke testing.

  ```
  defmodule ExamplePhoenixWeb.Router do
    use ExampleWeb, :router
    
    forward "/ping", SmokeTest, [otp_app: :example]

  end
  ```

  ### Registering Tests

  Tests are added as part of your mix configuration. Configuration expects an a map with the following properties:
  - `id` the id of the test.
  - `test` either a three item tuple of `{ Module, :fun, [args]}` or an anonymous function.
  - `timeout` (optional) the amount of time (in ms) the test has to complete. Defaults to 1000.

  Each test should return a two-item tuple of `{:ok, term}` or `{:error, reason}`. Items that
  don't fulfill this spec are marked as a failure.

  ```
  config :example, SmokeTest,
    tests: [
      # Test "db" calls a Module.function(args), with a timeout of 5000 ms
      %{ id: "db", test: {Module, :function, [args]}, timeout: 5000} ,
      
      # Test "cluster" calls an anonymous function, with a timeout of 1500ms
      %{ id: "cluster", test: fn -> :net_adm.names() end, timeout: 1500 },

      # Test "other" calls another  module, and uses the default timeout of 1000
      %{ id: "other", test: {Other.Module, :function, [args]} },
    ]   
  ```

  ### Additional Configuration
  
  #### Response Status
  The status to return on success and failure is also configurable. Success 
  defaults to 200, and failure defaults to 503

  ```
  config :example, Smoketest,
    success_status: 201,
    failure_status: 500
  ```


  #### Json Encoder
  A json encoder is required to diplay output. A `Poison` adapter is provided by
  default, and need not be configured if present in your deps. See `SmokeTest.Adapters.JSONEncoder.Poison`
  for more information.

  To explicitly configure your own adapter, add the following to your `SmokeTest`
  configuration:

  ```
  config :example, SmokeTest,
    json_encoder: SmokeTest.Adapters.JSONEncoder.Poison # Again, used by default.
  ```

  ## Example JSON Output
  
  Here's a quick example output of a failed smoketest.
  
  ```
  {
    "app":"example",
    "status":"failures",
    "version":"0.0.1",
    "timeouts":[
      {
        "id": "cluster"
        "result": "No response",
        "timeout": 15000
      }
    ],
    "failures":[
        {
          "id":"DB"
          "timeout":5000,
          "result":"Argument Error"
        }
    ],
  }
  ```

  And a successful one

  ```
  {
    "app":"example",
    "status":"ok",
    "version":"0.0.1",
  }
  ```

  ## Encoders
  The `Poison` JSON encoder is included with this module. If present, the 
  module will automatically include the adapter for you. See `SmokeTest.Adapters.JSONEncoder`
  and `SmokeTest.Adapters.JSONEncoder.Poison` for more details.
  """

  import Plug.Conn
  alias SmokeTest.Adapters.JSONEncoder
  @behaviour Plug

  @default_encoder if Code.ensure_loaded?(Poison), do: JSONEncoder.Poison, else: nil
  
  def init(opts), do: opts

  def call(_conn, []), do: raise otp_app_error()

  def call(conn, [otp_app: otp_app]) do 
    config = Application.get_env(otp_app, __MODULE__, [])
    encoder = Keyword.get(config, :json_encoder, @default_encoder) || raise decoder_error()
    tests = Keyword.get(config, :tests, [])
    success_status = Keyword.get(config, :success_status, 200)
    failure_status = Keyword.get(config, :failure_status, 503)

    project = Mix.Project.config()    

    results = 
      tests
      |> Enum.map(&run_test/1)
      |> Enum.map(&await_tests/1)
      |> Enum.group_by(
        fn 
          %SmokeTest.Test{result: {:ok, _ }}      -> :ok
          %SmokeTest.Test{result: {:timeout, _}}  -> :timeouts
          %SmokeTest.Test{result: {:error, _}}    -> :failures
          _                                       -> :failures
        end,
        fn 
          %{result: {_, result}} = test -> 
            %{ id: test.id, result: result, timeout: test.timeout } 
          test ->
            %{ id: test.id, result: inspect(test.result), timeout: test.timeout }
        end
      )
      |> Map.delete(:ok)

    {status_code, status_text} = format_status(results, success_status, failure_status)
    
    body = Map.merge(results, %{ 
      status: status_text, 
      app: project[:app], 
      version: project[:version]
    })

    send_resp(conn, status_code, encoder.encode!(body))
  end

  defp format_status(%{failures: _}, _, status), do: { status, "failures" }
  defp format_status(%{timeouts: _}, _, status), do: { status, "failures" } 
  defp format_status(_, status, _), do: { status, "ok"}

  
  defp run_test(%{id: id, test: fun, timeout: timeout}) when is_function(fun) do
    %SmokeTest.Test{ id: id, task: Task.async(fun), timeout: timeout }
  end
  
  defp run_test(%{id: id, test: {mod, fun, args}, timeout: timeout}) do
    %SmokeTest.Test{ id: id, task: Task.async(mod,fun,args), timeout: timeout }
  end

  defp run_test(%{id: id, test: fun}) do
     run_test(%{id: id, test: fun, timeout: 1000})
  end
  

  defp await_tests(test) do
    result =
      case Task.yield(test.task, test.timeout) || Task.shutdown(test.task) do
        {:ok, result }   -> result
        {:exit, reason} -> {:error, reason}
        nil             -> {:timeout, "No response"}
      end

    Map.put(test, :result, result)
  end

  # Error messages

  defp decoder_error do
    """
    No JSON encoder specified in configuration, and default JSON encoder is 
    unavailable. Please include a JSON encoder adapter. See hexdocs for details.
    """    
  end

  defp otp_app_error do
    "No OTP app specified in options. Please specify an application holding the SmokeTest configuration."
  end

end

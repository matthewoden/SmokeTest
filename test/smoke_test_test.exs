defmodule SmokeTestTest do
  use ExUnit.Case, async: true
  use Plug.Test

  doctest SmokeTest

  def pass, do: {:ok, "Woo!"}

  def fail, do: {:error, "Oh no"}

  def decode(string), do: Poison.decode!(string)

  def add_config(config) do
    conn = conn(:get, "/ping")
    config = Keyword.merge([{:json_encoder, Poison}], config)
    SmokeTest.call(conn, config)
  end

  describe("init") do
    test "throws when no otp_app is provided" do
      try do
        SmokeTest.init([])
      rescue
        e in RuntimeError ->
          assert e.message =~ "No OTP app specified in application config or plug options"
      end
    end

    test "merges application and parameterized config" do
      Application.put_env(:smoke_test, SmokeTest, json_encoder: Poison)
      opts = SmokeTest.init(otp_app: :smoke_test, json_encoder: Jason)

      assert opts == [
               json_encoder: Jason,
               version: "0.1.2",
               otp_app: :smoke_test
             ]
    end

    test "defaults to poison if available" do
      opts = SmokeTest.init(otp_app: :smoke_test)

      assert opts == [
               json_encoder: SmokeTest.Adapters.JSONEncoder.Poison,
               version: "0.1.2",
               otp_app: :smoke_test
             ]
    end
  end

  describe("conn") do
    test "can run an anonymous function test" do
      conn = add_config(tests: [%{id: "pass anon", test: fn -> {:ok, true} end, timeout: 2000}])

      assert conn.status == 200

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "ok"
    end

    test "can run a mfa test" do
      conn =
        add_config(tests: [%{id: "pass mfa", test: {SmokeTestTest, :pass, []}, timeout: 2000}])

      assert conn.status == 200

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "ok"
    end

    test "does not return a failure property if nothing failed." do
      conn =
        add_config(tests: [%{id: "pass mfa", test: {SmokeTestTest, :pass, []}, timeout: 2000}])

      decoded = decode(conn.resp_body)
      assert decoded["failures"] == nil
    end

    test "does not return a timeouts property if nothing timed out." do
      conn =
        add_config(tests: [%{id: "pass mfa", test: {SmokeTestTest, :pass, []}, timeout: 2000}])

      decoded = decode(conn.resp_body)
      assert decoded["timeouts"] == nil
    end

    test "returns errors on a failed mfa test" do
      conn =
        add_config(
          tests: [%{id: "fail mfa test", test: {SmokeTestTest, :fail, []}, timeout: 2000}]
        )

      assert conn.status == 503

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"

      assert decoded["failures"] == [
               %{"id" => "fail mfa test", "result" => "Oh no", "timeout" => 2000}
             ]
    end

    test "returns errors on a failed anonymous function test" do
      conn = add_config(tests: [%{id: "fail anon test", test: fn -> fail() end, timeout: 2000}])

      assert conn.status == 503

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"

      assert decoded["failures"] == [
               %{"id" => "fail anon test", "result" => "Oh no", "timeout" => 2000}
             ]
    end

    test "returns a timeout failure when an mfa times out" do
      conn =
        add_config(
          tests: [%{id: "timeout mfa test", test: {Process, :sleep, [200]}, timeout: 100}]
        )

      assert conn.status == 503

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"

      assert decoded["timeouts"] == [
               %{"id" => "timeout mfa test", "result" => "No response", "timeout" => 100}
             ]
    end

    test "returns a timeout failure when an anon function times out" do
      conn =
        add_config(
          tests: [%{id: "timeout mfa test", test: fn -> Process.sleep(200) end, timeout: 100}]
        )

      assert conn.status == 503

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"

      assert decoded["timeouts"] == [
               %{"id" => "timeout mfa test", "result" => "No response", "timeout" => 100}
             ]
    end

    test "returns a failure when unknown/invalid parameters are returned." do
      conn =
        add_config(tests: [%{id: "unknown mfa test", test: {String, :capitalize, ["smoke"]}}])

      assert conn.status == 503

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"

      assert decoded["failures"] == [
               %{"id" => "unknown mfa test", "result" => "\"Smoke\"", "timeout" => 1000}
             ]
    end

    test "defaults a timeout at 1000 seconds." do
      conn =
        add_config(tests: [%{id: "timeout default test", test: fn -> Process.sleep(1010) end}])

      assert conn.status == 503

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"

      assert decoded["timeouts"] == [
               %{"id" => "timeout default test", "result" => "No response", "timeout" => 1000}
             ]
    end

    test "can set the success status" do
      conn = add_config(success_status: 201)

      assert conn.status == 201

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "ok"
    end

    test "can set the failure status" do
      conn =
        add_config(
          tests: [%{id: "fail anon test", test: fn -> fail() end, timeout: 2000}],
          failure_status: 403
        )

      assert conn.status == 403

      decoded = decode(conn.resp_body)
      assert decoded["status"] == "failures"
    end

    test "returns a content-type of application/json" do
      conn = add_config(tests: [%{id: "success!", test: {SmokeTestTest, :pass, []}}])

      assert conn.status == 200

      assert Plug.Conn.get_resp_header(conn, "content-type") == [
               "application/json; charset=utf-8"
             ]
    end
  end
end

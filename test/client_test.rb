require "test_helper"

class ClientTest < Minitest::Test
  def test_create_entry_request_shape
    transport = FakeTransport.new(response(201, ENTRY))
    result = client_with(transport).create_entry(body: "hi", actor: "codex", url: "https://x.y/z", project: "p")

    call = transport.last
    assert_equal "POST", call.request.method
    assert_equal "https://shiplogg.test/api/v1/entries", call.uri.to_s
    assert_equal "Bearer slg_test", call.header("Authorization")
    assert_equal "application/json; charset=utf-8", call.header("Content-Type")
    assert_equal "application/json", call.header("Accept")
    assert_equal "shiplogg-cli/#{Shiplogg::VERSION}", call.header("User-Agent")
    assert_equal({ "source" => "cli", "body" => "hi", "actor" => "codex", "external_url" => "https://x.y/z", "project" => "p" }, call.json)
    assert_equal "shipped it", result["entry"]["body"]
  end

  def test_create_entry_omits_nil_fields
    transport = FakeTransport.new(response(201, ENTRY))
    client_with(transport).create_entry(body: "hi")
    assert_equal %w[source body actor], transport.last.json.keys
  end

  def test_me_request_shape
    transport = FakeTransport.new(response(200, ME))
    result = client_with(transport).me
    assert_equal "GET", transport.last.request.method
    assert_equal "/api/v1/me", transport.last.uri.path
    assert_nil transport.last.request.body
    assert_equal "wen", result["handle"]
  end

  def test_trailing_slash_in_base_url
    transport = FakeTransport.new(response(200, ME))
    Shiplogg::Client.new(base_url: "https://shiplogg.test/", token: "t", transport: transport).me
    assert_equal "https://shiplogg.test/api/v1/me", transport.last.uri.to_s
  end

  def test_missing_token_raises_before_any_request
    transport = FakeTransport.new
    err = assert_raises(Shiplogg::Error) { client_with(transport, token: nil).me }
    assert_includes err.message, "no token"
    assert_empty transport.calls
  end

  def test_error_body_becomes_message
    transport = FakeTransport.new(response(429, { "error" => "Rate limit exceeded" }))
    err = assert_raises(Shiplogg::Error) { client_with(transport).me }
    assert_equal "Rate limit exceeded", err.message
  end

  def test_non_json_error_falls_back_to_status
    transport = FakeTransport.new(response(502, "<html>bad gateway</html>"))
    err = assert_raises(Shiplogg::Error) { client_with(transport).me }
    assert_equal "HTTP 502", err.message
  end

  def test_network_failure_is_wrapped
    transport = ->(_uri, _req) { raise Errno::ECONNREFUSED }
    err = assert_raises(Shiplogg::Error) { client_with(transport).me }
    assert_includes err.message, "could not reach https://shiplogg.test"
  end
end

require "minitest/autorun"
require "stringio"
require "tmpdir"
require "json"
require "shiplogg"

module ShiplogHelpers
  # A transport that records requests and answers with canned responses.
  class FakeTransport
    Call = Struct.new(:uri, :request) do
      def json = JSON.parse(request.body)
      def header(name) = request[name]
    end

    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def call(uri, request)
      @calls << Call.new(uri, request)
      @responses.size > 1 ? @responses.shift : @responses.first
    end

    def last = @calls.last
  end

  def response(code, body)
    klass = code.to_i.between?(200, 299) ? Net::HTTPSuccess : Net::HTTPClientError
    res = klass.new("1.1", code.to_s, "")
    res.instance_variable_set(:@body, body.is_a?(String) ? body : JSON.generate(body))
    res.instance_variable_set(:@read, true)
    res
  end

  ME = {
    "handle" => "wen", "log_url" => "https://shiplogg.com/@wen",
    "projects" => [{ "name" => "Shiplogg", "slug" => "shiplogg" }, { "name" => "Side", "slug" => "side" }],
    "stats" => {
      "total_entries" => 312, "current_streak" => 4, "longest_streak" => 12,
      "split" => { "counts" => { "claude_code" => 190, "human" => 122 }, "human_share" => 0.391 },
      "verified_split" => nil
    }
  }.freeze

  ENTRY = { "entry" => { "id" => 1, "body" => "shipped it", "actor" => "human", "source" => "cli" },
            "log_url" => "https://shiplogg.com/@wen" }.freeze

  def client_with(transport, token: "slg_test")
    Shiplogg::Client.new(base_url: "https://shiplogg.test", token: token, transport: transport)
  end

  # Runs the CLI in a throwaway git repo and returns [exit_code, stdout, stderr].
  def run_cli(argv, client: nil, env: {}, input: "", root: nil)
    out, err = StringIO.new, StringIO.new
    code = Shiplogg::CLI.new(out: out, err: err, input: StringIO.new(input), env: env, root: root, client: client).run(argv)
    [code, out.string, err.string]
  end

  def with_git_repo
    Dir.mktmpdir("shiplogg") do |dir|
      dir = File.realpath(dir)
      system("git", "init", "-q", dir, exception: true)
      yield dir
    end
  end
end

Minitest::Test.include ShiplogHelpers

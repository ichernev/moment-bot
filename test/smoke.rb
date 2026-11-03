# Replays a pull_request webhook against the app with a fake GitHub API and checks the statuses it posts.
#   ruby test/smoke.rb     (after `bundle install --standalone`, see script/build.sh)
require_relative "../vendor/bundle/bundler/setup"
require "json"
require "socket"
require "uri"

calls = Queue.new
fake = TCPServer.new("127.0.0.1", 0)
Thread.new do
  loop do
    sock = fake.accept
    request_line = sock.gets
    headers = {}
    while (line = sock.gets) && line != "\r\n"
      k, v = line.split(":", 2)
      headers[k.downcase] = v.strip
    end
    body = sock.read(headers.fetch("content-length", "0").to_i)
    verb, path, = request_line.split
    calls << [verb, path, body]
    status, resp =
      if verb == "GET" && path.include?("/files")
        page = URI.decode_www_form(URI(path).query.to_s).to_h["page"]
        ["200 OK", page == "1" ? [{ filename: "src/lib/moment.js" }, { filename: "locale/fi.js" }] : []]
      else
        ["201 Created", {}]
      end
    data = JSON.dump(resp)
    sock.write "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{data.bytesize}\r\nConnection: close\r\n\r\n#{data}"
    sock.close
  end
end

ENV["OCTOKIT_API_ENDPOINT"] = "http://127.0.0.1:#{fake.addr[1]}"
ENV["MY_PERSONAL_GITHUB_TOKEN"] = "test-token"
ENV["RACK_ENV"] = "production"
require "rack/mock_request"
require_relative "../server"

app = CITutorial.new
abort "GET / failed" unless app.call(Rack::MockRequest.env_for("/", "HTTP_HOST" => "moment-bot.iskren.info"))[0] == 200

payload = {
  pull_request: {
    number: 1234, title: "Fix the frobnicator",
    head: { sha: "abc123" },
    base: { ref: "master", repo: { full_name: "moment/moment" } },
  },
}
res = Rack::MockRequest.new(app).post(
  "/event_handler",
  "HTTP_HOST" => "moment-bot.iskren.info",
  "HTTP_X_GITHUB_EVENT" => "pull_request",
  params: { payload: JSON.dump(payload) },
)
abort "event_handler returned #{res.status}: #{res.body}" unless res.status == 200

statuses = []
statuses << calls.pop until calls.empty?
final = statuses.select { |v, p, _| v == "POST" && p.end_with?("/statuses/abc123") }
                .map { |_, _, b| JSON.parse(b) }
                .reject { |s| s["state"] == "pending" }
                .to_h { |s| [s["context"], s["state"]] }
expected = { "Title" => "error", "Base branch" => "error", "Generated files" => "error" }
abort "unexpected statuses: #{final.inspect}" unless final == expected
puts "ok: #{final.inspect}"

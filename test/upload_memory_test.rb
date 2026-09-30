# frozen_string_literal: true

require "test_helper"
require "pathname"
require "socket"
require "tmpdir"

# A 100 MB upload, Pennylane's largest, through the whole client and the
# real NetHttpTransport, must not load the file into memory.
#
# WebMock reads a request's body stream into one String to match it, so it
# is switched off for this test and a local socket stands in for Pennylane.
# Nothing leaves 127.0.0.1.
class UploadMemoryTest < Minitest::Test
  MB = 1024 * 1024
  SIZE = 100 * MB
  # Loading the file would cost at least SIZE. Streaming costs a few chunks;
  # the rest of this budget is headroom for GC and the test process.
  BUDGET = 40 * MB

  def setup = WebMock.disable!

  def teardown
    WebMock.enable!
    super
  end

  def rss = Integer(`ps -o rss= -p #{Process.pid}`.strip) * 1024

  def test_uploads_100_mb_without_loading_the_file_into_memory
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("large.pdf")
      File.open(path, "wb") { _1.truncate(SIZE) } # sparse: costs no disk
      GC.start
      baseline = rss
      received, peak = upload_to_local_server(path)

      assert_operator received, :>, SIZE
      assert_operator peak - baseline, :<, BUDGET, "memory grew #{(peak - baseline) / MB} MB during the upload"
    end
  end

  private

  # The bytes the server received, and the peak memory it saw meanwhile.
  def upload_to_local_server(path)
    server = TCPServer.new("127.0.0.1", 0)
    pennylane = Thread.new { receive(server.accept) }
    result = upload(path, server.addr[1])
    [result[:received], pennylane.value]
  ensure
    server&.close
  end

  def upload(path, port)
    transport = PennylaneClient::NetHttpTransport.new
    client = PennylaneClient.new(token: "tok", base_url: "http://127.0.0.1:#{port}", transport:,
                                 limiters: PennylaneClient::LimiterRegistry.new)
    client.call(:postFileAttachments, file: path)
  ensure
    transport.close
  end

  # Reads the request, sampling this process's memory every 10 MB, and
  # answers with the byte count. Returns the peak sample.
  def receive(socket)
    length = read_headers(socket)
    received, peak = read_body(socket, length)
    answer(socket, received)
    [peak, rss].max
  ensure
    socket.close
  end

  def read_body(socket, length)
    received = 0
    samples = [rss]
    buffer = String.new(capacity: MB)
    while received < length
      received += socket.readpartial(MB, buffer).bytesize
      samples << rss if (received % (10 * MB)) < buffer.bytesize
    end
    [received, samples.max]
  end

  def read_headers(socket)
    length = 0
    while (line = socket.gets) != "\r\n"
      name, value = line.split(":", 2)
      length = Integer(value.strip) if name.casecmp?("content-length")
    end
    length
  end

  def answer(socket, received)
    body = %({"received":#{received}})
    socket.write("HTTP/1.1 201 Created\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  end
end

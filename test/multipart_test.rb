# frozen_string_literal: true

require "test_helper"
require "pathname"
require "stringio"
require "tmpdir"

class MultipartTest < Minitest::Test
  def form(fields) = PennylaneClient::Multipart.new(fields)

  def boundary(form) = form.content_type[/boundary=(\S+)/, 1]

  def test_sends_a_file_part_and_text_parts_in_multipart_form_data
    form = form(file: StringIO.new("%PDF-1.7"), filename: "Invoice42.pdf")

    assert_match(%r{\Amultipart/form-data; boundary=\S+\z}, form.content_type)
    assert_equal expected_body(boundary(form)), form.read
  end

  def expected_body(boundary)
    <<~BODY.gsub("\n", "\r\n")
      --#{boundary}
      Content-Disposition: form-data; name="file"; filename="upload"
      Content-Type: application/octet-stream

      %PDF-1.7
      --#{boundary}
      Content-Disposition: form-data; name="filename"

      Invoice42.pdf
      --#{boundary}--
    BODY
  end

  def test_size_is_the_exact_byte_count
    form = form(file: StringIO.new("é" * 10), note: "ü")

    assert_equal form.read.bytesize, form.size
    assert_equal Encoding::BINARY, form.tap(&:rewind).read.encoding
  end

  def test_names_a_file_after_its_path_and_types_it_by_extension
    Dir.mktmpdir do |dir|
      path = File.join(dir, "receipt.pdf")
      File.write(path, "%PDF")

      File.open(path, "rb") { assert_includes form(file: _1).read, 'filename="receipt.pdf"' }
      assert_includes form(file: Pathname(path)).read, "Content-Type: application/pdf"
    end
  end

  def test_an_upload_sets_its_own_filename_and_content_type
    upload = PennylaneClient::Upload.new(StringIO.new("<Invoice/>"), filename: "ubl.xml", content_type: "text/xml")
    body = form(file: upload).read

    assert_includes body, 'filename="ubl.xml"'
    assert_includes body, "Content-Type: text/xml"
  end

  # The e-invoice imports declare their object and array fields as
  # application/json parts.
  def test_sends_hashes_and_arrays_as_json_parts
    body = form(file: StringIO.new("x"), invoice_options: { customer_id: 12 }, send_to_pa: true).read

    assert_includes body, %(name="invoice_options"\r\nContent-Type: application/json\r\n\r\n{"customer_id":12}\r\n)
    assert_includes body, %(name="send_to_pa"\r\n\r\ntrue\r\n)
  end

  def test_leaves_out_nil_fields
    refute_includes form(file: StringIO.new("x"), filename: nil).read, 'name="filename"'
  end

  def test_inspect_names_the_fields_not_the_content
    inspected = form(file: StringIO.new("secret-bytes"), filename: "a.pdf").inspect

    assert_includes inspected, ":file"
    refute_includes inspected, "secret-bytes"
  end
end

# Multipart as an IO: how Net::HTTP and Retry read it.
class MultipartStreamTest < Minitest::Test
  # An IO that records every length it is asked to read.
  class ReadSpy < StringIO
    attr_reader :lengths

    def initialize(...)
      super
      @lengths = []
    end

    def read(length = nil, *)
      @lengths << length
      super
    end
  end

  def form(fields) = PennylaneClient::Multipart.new(fields)

  def test_streams_the_file_in_the_chunks_the_reader_asks_for
    spy = ReadSpy.new("a" * 100_000)
    form = form(file: spy)
    read = +""
    while (chunk = form.read(16_384))
      read << chunk
    end

    assert_equal form.size, read.bytesize
    assert(spy.lengths.all? { _1&.<=(16_384) }, "read the file whole: #{spy.lengths.inspect}")
  end

  def test_reads_like_an_io
    form = form(file: StringIO.new("abc"))
    buffer = +"old"

    assert_same buffer, form.read(4, buffer)
    assert_equal 4, buffer.bytesize
    form.read
    assert_nil form.read(1)
    assert_equal "", form.read
  end

  def test_rewinds_to_send_again
    io = StringIO.new("head-body")
    io.read(5)
    form = form(file: io)
    first = form.read
    form.rewind

    assert_equal first, form.read
    assert_includes first, "\r\n\r\nbody\r\n"
  end

  def test_closes_only_the_files_it_opened
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.png")
      File.write(path, "png")
      File.open(path, "rb") do |given|
        form = form(file: given, other: Pathname(path))
        form.read
        form.close

        refute_predicate given, :closed?
      end
    end
  end

  def test_escapes_quotes_and_line_breaks_in_names
    upload = PennylaneClient::Upload.new(StringIO.new("x"), filename: %(a"b\r\nc.pdf))

    assert_includes form(file: upload).read, 'filename="a%22b%0D%0Ac.pdf"'
  end

  # Content-Length is fixed when the form is built. Sending more would leave
  # bytes on the keep-alive socket; sending fewer would hang the server.
  def test_sends_no_more_than_the_size_it_announced
    io = StringIO.new(+"abc")
    form = form(file: io)
    io.string << "grown"

    assert_equal form.size, form.read.bytesize
  end

  def test_raises_when_a_file_shrinks_before_it_is_sent
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("a.pdf").tap { _1.write("%PDF-1.7") }
      form = form(file: path)
      path.write("%")

      error = assert_raises(PennylaneClient::Error) { form.read }
      assert_match(/a\.pdf/, error.message)
    end
  end

  def test_refuses_a_path_it_cannot_read_before_sending
    Dir.mktmpdir do |dir|
      assert_raises(ArgumentError) { form(file: Pathname(dir)) }
      assert_raises(Errno::ENOENT) { form(file: Pathname(dir).join("missing.pdf")) }
    end
  end

  def test_refuses_an_upload_of_something_it_cannot_read
    assert_raises(ArgumentError) { form(file: PennylaneClient::Upload.new("receipt.pdf")) }
  end

  def test_refuses_an_io_whose_size_it_cannot_know
    reader, writer = IO.pipe
    assert_raises(ArgumentError) { form(file: reader) }
  ensure
    [reader, writer].each(&:close)
  end
end

# frozen_string_literal: true

require "json"
require "pathname"
require "securerandom"
require "stringio"

module PennylaneClient
  # A file to upload, when the caller wants to set its filename or content
  # type. `source` is a File, a Pathname, or an IO that responds to `size`.
  #
  #   PennylaneClient::Upload.new(io, filename: "invoice.xml", content_type: "application/xml")
  #
  # A File, IO or Pathname passed on its own is read as an Upload that takes
  # the filename from the path and the content type from the extension.
  class Upload
    attr_reader :source, :filename, :content_type

    def initialize(source, filename: nil, content_type: nil)
      @source = source
      @filename = filename
      @content_type = content_type
      freeze
    end

    def inspect = "#<#{self.class.name} filename=#{filename.inspect} content_type=#{content_type.inspect}>"
  end

  # A multipart/form-data request body that streams its files instead of
  # reading them into memory, so a 100 MB upload costs a few kilobytes.
  #
  # It reads like an IO (`read(length, outbuf)`, `rewind`, `size`), which is
  # what Net::HTTP wants for `body_stream`. Each field becomes one part:
  #
  # - a File, IO, Pathname or Upload is a file part;
  # - a Hash or Array is an application/json part (the e-invoice imports
  #   declare `invoice_options` and friends that way);
  # - nil is left out; anything else is a text part.
  #
  # The size is known up front, so the request carries a Content-Length and
  # no chunked encoding. `rewind` puts every file back where it started, so
  # Retry can send the body again after a 429.
  class Multipart
    CONTENT_TYPES = {
      ".pdf" => "application/pdf", ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
      ".tif" => "image/tiff", ".tiff" => "image/tiff", ".bmp" => "image/bmp", ".gif" => "image/gif",
      ".xml" => "application/xml"
    }.freeze
    DEFAULT_CONTENT_TYPE = "application/octet-stream"
    CRLF = "\r\n"

    attr_reader :content_type, :size

    def initialize(fields)
      fields = fields.compact
      @boundary = "pennylane-client-#{SecureRandom.hex(16)}"
      @content_type = "multipart/form-data; boundary=#{@boundary}"
      @fields = fields.keys
      @parts = fields.flat_map { |name, value| part(name.to_s, value) } << text("--#{@boundary}--#{CRLF}")
      @size = @parts.sum(&:size)
      @index = 0
    end

    # IO#read semantics: up to `length` bytes, or nil at the end; with no
    # length, the rest (and "" at the end). Fills `outbuf` when given.
    def read(length = nil, outbuf = nil)
      out = outbuf ? outbuf.clear.force_encoding(Encoding::BINARY) : String.new(encoding: Encoding::BINARY)
      fill(out, length)
      out.empty? && length&.positive? ? nil : out
    end

    def rewind
      @parts.each(&:rewind)
      @index = 0
      0
    end

    # Closes the files it opened from a Pathname. Files the caller passed
    # stay open: they belong to the caller.
    def close = @parts.each(&:close)

    def inspect = "#<#{self.class.name} fields=#{@fields.inspect} size=#{@size}>"

    private

    def fill(out, length)
      until @index == @parts.size || (length && out.bytesize >= length)
        chunk = @parts[@index].read(length && (length - out.bytesize))
        next @index += 1 if chunk.nil? || chunk.empty?

        out << chunk.force_encoding(Encoding::BINARY)
      end
    end

    def part(name, value)
      case value
      when Upload, Pathname then file_part(name, value)
      when Hash, Array then [text(head(name, "application/json") + JSON.generate(Encoder.encode(value)) + CRLF)]
      else value.respond_to?(:read) ? file_part(name, value) : [text(head(name) + Encoder.scalar(value).to_s + CRLF)]
      end
    end

    def file_part(name, value)
      upload = value.is_a?(Upload) ? value : Upload.new(value)
      source = upload.source.is_a?(Pathname) ? PathSource.new(upload.source) : IOSource.new(upload.source)
      filename = upload.filename || source.filename
      [text(head(name, upload.content_type || type_of(filename), filename:)), source, text(CRLF)]
    end

    def type_of(filename) = CONTENT_TYPES.fetch(File.extname(filename).downcase, DEFAULT_CONTENT_TYPE)

    def head(name, type = nil, filename: nil)
      disposition = %(Content-Disposition: form-data; name="#{escape(name)}")
      disposition += %(; filename="#{escape(filename)}") if filename
      lines = ["--#{@boundary}", disposition]
      lines << "Content-Type: #{type}" if type
      lines.join(CRLF) + CRLF + CRLF
    end

    # The HTML form encoding of a name or filename inside quotes.
    def escape(value) = value.to_s.gsub('"', "%22").gsub("\r", "%0D").gsub("\n", "%0A")

    def text(string) = TextSource.new(string)

    # A part held in memory: a part's headers, a text field, the boundaries.
    class TextSource
      def initialize(string)
        @io = StringIO.new(string.b)
      end

      def size = @io.size
      def read(length) = @io.read(length)
      def rewind = @io.rewind
      def close = nil
    end

    # A file the caller opened, read in the chunks the reader asks for from
    # the position the caller left it at. It is never closed here.
    class IOSource
      attr_reader :size

      def initialize(io)
        raise ArgumentError, "cannot upload #{io.class}: it must respond to #size" unless io.respond_to?(:size)

        @io = io
        @start = io.respond_to?(:pos) ? io.pos : 0
        @size = io.size - @start
        @buffer = String.new
      end

      def filename = @io.respond_to?(:path) && @io.path ? File.basename(@io.path.to_s) : "upload"

      # Into one reused buffer: a new String per chunk would leave the whole
      # file behind as garbage faster than GC returns it.
      def read(length) = @io.read(length, @buffer)
      def rewind = @start.zero? ? @io.rewind : @io.seek(@start)
      def close = nil
    end

    # A file named by a Pathname: opened on the first read, closed by close.
    class PathSource
      attr_reader :size

      def initialize(path)
        @path = path
        @size = File.size(path)
        @buffer = String.new
      end

      def filename = @path.basename.to_s

      def read(length)
        @io ||= File.new(@path, "rb")
        @io.read(length, @buffer)
      end

      def rewind = @io&.rewind

      def close
        @io&.close
        @io = nil
      end
    end
  end
end

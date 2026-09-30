# frozen_string_literal: true

require "test_helper"
require "date"

# Exports: `client.exports`. Each stub is the method and path from the
# operation's reference page. An export is created pending, then polled
# until it is ready or has failed.
class ExportsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"
  PERIOD = { period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 6, 30) }.freeze
  PERIOD_JSON = '{"period_start":"2026-01-01","period_end":"2026-06-30"}'

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  # A clock that moves only when the sleeper sleeps.
  def exports
    @now = 0.0
    @slept = []
    sleeper = lambda do |seconds|
      @slept << seconds
      @now += seconds
    end
    PennylaneClient::Resources::Exports.new(client, clock: -> { @now }, sleeper:)
  end

  def export(status, file_url: nil) = JSON.generate({ id: 9, status:, file_url: })

  def stub_created(path, body = PERIOD_JSON)
    stub_request(:post, "#{API}/exports/#{path}").with(body:)
                                                 .to_return(status: 201, body: '{"id":9,"status":"pending"}')
  end

  def test_is_one_resource_per_client
    assert_same client.exports, client.exports
    refute_includes client.exports.inspect, "tok"
  end

  # names: exportFec
  def test_create_fec_encodes_the_period
    stub_created("fecs")

    assert_equal({ id: 9, status: "pending" }, exports.create_fec(**PERIOD))
  end

  # names: getFecExport
  def test_find_fec
    stub_request(:get, "#{API}/exports/fecs/9").to_return(status: 200, body: export("ready", file_url: "https://x/f"))

    assert_equal "https://x/f", exports.find_fec(9)[:file_url]
  end

  # names: exportGeneralLedger
  def test_create_general_ledger
    stub_created("general_ledgers")

    assert_equal "pending", exports.create_general_ledger(**PERIOD)[:status]
  end

  # names: getGeneralLedgerExport
  def test_find_general_ledger
    stub_request(:get, "#{API}/exports/general_ledgers/9").to_return(status: 200, body: export("pending"))

    assert_equal "pending", exports.find_general_ledger(9)[:status]
  end

  # names: exportAnalyticalGeneralLedger
  def test_create_analytical_general_ledger_passes_the_mode
    stub_created("analytical_general_ledgers", PERIOD_JSON.sub("}", ',"mode":"in_column"}'))

    assert_equal "pending", exports.create_analytical_general_ledger(**PERIOD, mode: "in_column")[:status]
  end

  # names: getAnalyticalGeneralLedgerExport
  def test_find_analytical_general_ledger
    stub_request(:get, "#{API}/exports/analytical_general_ledgers/9").to_return(status: 200, body: export("error"))

    assert_equal "error", exports.find_analytical_general_ledger(9)[:status]
  end

  def test_generate_fec_polls_until_ready
    stub_created("fecs")
    ready = { status: 200, body: export("ready", file_url: "https://x/f") }
    stub_request(:get, "#{API}/exports/fecs/9").to_return({ status: 200, body: export("pending") }, ready)
    resource = exports

    assert_equal "https://x/f", resource.generate_fec(**PERIOD, interval: 2)[:file_url]
    assert_equal [2], @slept
  end

  def test_generate_general_ledger_reads_the_export_once_ready
    stub_created("general_ledgers")
    stub_request(:get, "#{API}/exports/general_ledgers/9").to_return(status: 200, body: export("ready", file_url: "u"))

    assert_equal "u", exports.generate_general_ledger(**PERIOD)[:file_url]
  end

  def test_generate_analytical_general_ledger
    stub_created("analytical_general_ledgers")
    stub_request(:get, "#{API}/exports/analytical_general_ledgers/9")
      .to_return(status: 200, body: export("ready", file_url: "u"))

    assert_equal "u", exports.generate_analytical_general_ledger(**PERIOD)[:file_url]
  end

  def test_generate_raises_when_the_export_fails
    stub_created("fecs")
    stub_request(:get, "#{API}/exports/fecs/9").to_return(status: 200, body: export("error"))

    error = assert_raises(PennylaneClient::ExportError) { exports.generate_fec(**PERIOD) }
    assert_equal "error", error.export[:status]
    assert_match(/9/, error.message)
  end

  def test_generate_raises_when_not_ready_in_time
    stub_created("fecs")
    stub_request(:get, "#{API}/exports/fecs/9").to_return(status: 200, body: export("pending"))
    resource = exports

    error = assert_raises(PennylaneClient::ExportError) { resource.generate_fec(**PERIOD, timeout: 10, interval: 3) }
    assert_equal "pending", error.export[:status]
    assert_equal [3, 3, 3], @slept
    assert_match(/10/, error.message)
  end

  # AGENTS.md rule 4: a POST is not retried after a 5xx.
  def test_generate_does_not_retry_a_failed_create
    stub_request(:post, "#{API}/exports/fecs").to_return(status: 500, body: "oops")

    assert_raises(PennylaneClient::ServerError) { exports.generate_fec(**PERIOD) }
    assert_requested(:post, "#{API}/exports/fecs", times: 1)
  end

  def test_generate_refuses_a_non_positive_interval
    assert_raises(ArgumentError) { exports.generate_fec(**PERIOD, interval: 0) }
  end
end

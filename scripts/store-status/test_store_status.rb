# frozen_string_literal: true

# ruby scripts/store-status/test_store_status.rb   (necesita la gema jwt solo para la prueba del token)

require "json"
require "minitest/autorun"
require "openssl"
require_relative "store_status"

class StoreStatusTest < Minitest::Test
  FIXTURES = File.join(__dir__, "fixtures")

  def fixture(name)
    File.read(File.join(FIXTURES, name))
  end

  def test_versions_come_newest_first_and_keep_either_name_of_the_state
    versions = StoreStatus.parse_versions(JSON.parse(fixture("versions.json")))
    assert_equal %w[1.5.3 1.5.2 1.5.0], versions.map { |v| v["version"] }
    assert_equal %w[WAITING_FOR_REVIEW READY_FOR_SALE REPLACED_WITH_NEW_VERSION], versions.map { |v| v["state"] }
    assert_equal ["IOS"], versions.map { |v| v["platform"] }.uniq
  end

  def test_the_newer_state_name_wins_when_apple_sends_both_and_null_is_kept_when_it_sends_neither
    versions = StoreStatus.parse_versions(JSON.parse(fixture("versions_both_states.json")))
    assert_equal %w[1.6.1 1.6.0], versions.map { |v| v["version"] }
    # `appVersionState` says READY_FOR_DISTRIBUTION where the older `appStoreState` said READY_FOR_SALE;
    # the app maps both to "published". With neither attribute the state is null, and the app reads it
    # as an unknown state instead of refusing the whole file.
    assert_nil versions[0]["state"]
    assert_equal "READY_FOR_DISTRIBUTION", versions[1]["state"]
  end

  def test_a_version_without_a_number_is_dropped_and_the_list_is_capped
    json = JSON.parse(fixture("versions.json"))
    assert_equal 3, StoreStatus.parse_versions(json).size # the MAC_OS draft has no versionString
    assert_equal 2, StoreStatus.parse_versions(json, limit: 2).size
  end

  def test_builds_carry_the_marketing_version_from_the_included_pre_release
    builds = StoreStatus.parse_builds(JSON.parse(fixture("builds.json")))
    assert_equal %w[202610270821 202610140900], builds.map { |b| b["build"] }
    assert_equal %w[1.5.3 1.5.2], builds.map { |b| b["version"] }
    assert_equal [false, true], builds.map { |b| b["expired"] }
    assert_equal "VALID", builds.first["state"]
  end

  def test_sales_rows_are_read_by_column_name
    rows = StoreStatus.parse_sales(fixture("sales.tsv"))
    assert_equal 6, rows.size
    assert_equal "6740000000", rows.first["Apple Identifier"]
    assert_equal "1F", rows.first["Product Type Identifier"]
    assert_empty StoreStatus.parse_sales("")
    assert_empty StoreStatus.parse_sales("only a header\n")
  end

  def test_a_day_sums_downloads_updates_and_purchases_per_app
    rows = StoreStatus.parse_sales(fixture("sales.tsv"))
    totals = StoreStatus.summarize_day(rows, { "repomind" => "6740000000", "insync" => "6742222222" })
    # Two first downloads (3 + 2); the 4 redownloads (type 3) do not count.
    assert_equal({ "downloads" => 5, "updates" => 12, "purchases" => 1 }, totals["6740000000"])
    assert_equal({ "downloads" => 5, "updates" => 0, "purchases" => 0 }, totals["6742222222"])
    # The purchase row belongs to the app by SKU, never to its own Apple ID.
    refute totals.key?("6741111111")
  end

  def test_a_purchase_of_an_unknown_sku_is_ignored
    rows = StoreStatus.parse_sales(fixture("sales.tsv"))
    totals = StoreStatus.summarize_day(rows, {})
    assert_equal 0, totals.fetch("6740000000", {}).fetch("purchases", 0)
  end

  def test_the_series_has_a_day_per_date_with_zeros_where_apple_said_nothing
    dates = %w[2026-10-24 2026-10-25]
    per_day = { "2026-10-25" => { "6740000000" => { "downloads" => 5, "updates" => 12, "purchases" => 1 } } }
    series = StoreStatus.daily_series(per_day, dates, "6740000000")
    assert_equal [0, 5], series.map { |d| d["downloads"] }
    assert_equal [0, 12], series.map { |d| d["updates"] }
    assert_equal %w[2026-10-24 2026-10-25], series.map { |d| d["date"] }
    assert_equal [0, 0], StoreStatus.daily_series(per_day, dates, "someone else").map { |d| d["downloads"] }
  end

  def test_the_last_closed_day_is_the_day_before_yesterday_in_pacific_time
    # 06:30 UTC on the 27th is still the evening of the 26th in Pacific time.
    assert_equal Date.new(2026, 10, 24), StoreStatus.through_date(Time.utc(2026, 10, 27, 6, 30))
    assert_equal Date.new(2026, 10, 25), StoreStatus.through_date(Time.utc(2026, 10, 27, 12, 0))
  end

  def test_the_dates_run_oldest_first_and_end_on_the_closed_day
    dates = StoreStatus.dates_ending(Date.new(2026, 10, 25), 3)
    assert_equal %w[2026-10-23 2026-10-24 2026-10-25], dates
  end

  def test_the_document_has_the_schema_and_the_time
    doc = StoreStatus.document([{ "id" => "1" }], now: Time.utc(2026, 10, 27, 6, 31))
    assert_equal 1, doc["schema"]
    assert_equal "2026-10-27T06:31:00Z", doc["generatedAt"]
    assert_equal [{ "id" => "1" }], doc["apps"]
  end

  # The whole flow against a fake client: no network, no key.
  class FakeClient
    def initialize(fixtures, sales_error: nil)
      @fixtures = fixtures
      @sales_error = sales_error
      @sales_dates = []
    end
    attr_reader :sales_dates

    def get_json(path, _params = {})
      case path
      when "/v1/apps"
        { "data" => [{ "id" => "6740000000", "attributes" => { "name" => "RepoMind", "bundleId" => "idanidev.RepoMind", "sku" => "repomind" } }] }
      when %r{/appStoreVersions} then JSON.parse(@fixtures.call("versions.json"))
      when "/v1/builds" then JSON.parse(@fixtures.call("builds.json"))
      else raise "unexpected #{path}"
      end
    end

    def get_sales(params)
      raise @sales_error if @sales_error

      @sales_dates << params["filter[reportDate]"]
      params["filter[reportDate]"] == StoreStatus.through_date.strftime("%Y-%m-%d") ? File.read(File.join(FIXTURES, "sales.tsv")) : nil
    end
  end

  def test_collect_without_a_vendor_number_has_versions_and_no_sales
    client = FakeClient.new(method(:fixture))
    apps = StoreStatus.collect(client, repo_map: { "idanidev.RepoMind" => "RepoMind" }, vendor: nil, days: 3, log: StringIO.new)
    assert_equal 1, apps.size
    assert_equal "RepoMind", apps.first["repo"]
    assert_equal "1.5.3", apps.first["versions"].first["version"]
    assert_equal "1.5.3", apps.first["builds"].first["version"]
    refute apps.first.key?("sales")
    assert_empty client.sales_dates
  end

  def test_collect_with_a_vendor_number_fills_the_series
    client = FakeClient.new(method(:fixture))
    apps = StoreStatus.collect(client, repo_map: {}, vendor: "88888888", days: 3, log: StringIO.new)
    sales = apps.first["sales"]
    assert_equal StoreStatus.through_date.strftime("%Y-%m-%d"), sales["through"]
    assert_equal 3, sales["daily"].size
    assert_equal [0, 0, 5], sales["daily"].map { |d| d["downloads"] }
    refute apps.first.key?("repo")
  end

  def test_a_key_that_cannot_see_sales_keeps_the_versions
    error = StoreStatus::Error.new("salesReports: HTTP 403", 403)
    client = FakeClient.new(method(:fixture), sales_error: error)
    apps = StoreStatus.collect(client, repo_map: {}, vendor: "88888888", days: 3, log: StringIO.new)
    assert_equal "1.5.3", apps.first["versions"].first["version"]
    refute apps.first.key?("sales")
  end

  FakeResponse = Struct.new(:code, :body, :headers) do
    def [](name)
      (headers || {})[name]
    end
  end

  # `perform` es privado: se prueba a través de `send`, con Net::HTTP.start y el sleep sustituidos.
  def with_responses(responses)
    require "jwt"
    require "minitest/mock"
    key = OpenSSL::PKey::EC.generate("prime256v1")
    client = StoreStatus::Client.new(key_id: "K", issuer_id: "I", key_pem: key.to_pem)
    pauses = []
    client.define_singleton_method(:sleep) { |seconds| pauses << seconds }
    calls = 0
    Net::HTTP.stub :start, lambda { |*_args, **_options, &_block|
      calls += 1
      response = responses.shift
      raise response if response.is_a?(Class) && response <= Exception

      response
    } do
      yield client, pauses
    end
    calls
  end

  def test_a_transient_failure_is_retried_with_a_pause_and_then_answers
    responses = [FakeResponse.new("503", "busy"), Errno::ECONNRESET, FakeResponse.new("200", "{}")]
    calls = with_responses(responses) do |client, pauses|
      assert_equal [200, "{}"], client.send(:perform, "/v1/apps", {})
      assert_equal [2, 4], pauses
    end
    assert_equal 3, calls
  end

  def test_retry_after_is_honoured_and_a_404_is_not_retried
    calls = with_responses([FakeResponse.new("429", "", { "Retry-After" => "7" }), FakeResponse.new("404", "none")]) do |client, pauses|
      assert_equal [404, "none"], client.send(:perform, "/v1/apps", {})
      assert_equal [7], pauses
    end
    assert_equal 2, calls
  end

  def test_a_failure_that_does_not_go_away_is_reported_after_the_last_attempt
    responses = Array.new(StoreStatus::Client::MAX_ATTEMPTS) { FakeResponse.new("503", "busy") }
    with_responses(responses) do |client, _pauses|
      assert_equal [503, "busy"], client.send(:perform, "/v1/apps", {})
    end
  end

  def test_the_token_is_a_signed_es256_jwt_for_the_app_store_api
    require "jwt"
    key = OpenSSL::PKey::EC.generate("prime256v1")
    client = StoreStatus::Client.new(key_id: "ABC123", issuer_id: "issuer-uuid", key_pem: key.to_pem)
    payload, header = JWT.decode(client.token, key, true, { algorithm: "ES256" })
    assert_equal "ABC123", header["kid"]
    assert_equal "ES256", header["alg"]
    assert_equal "issuer-uuid", payload["iss"]
    assert_equal "appstoreconnect-v1", payload["aud"]
    assert_operator payload["exp"] - payload["iat"], :<=, 900
    assert_equal client.token, client.token # cached
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

# Escribe el estado de la App Store de todas las apps de la cuenta: qué versión está publicada, cuál
# pendiente, la última build de TestFlight y las descargas por día. El contrato está en
# docs/store-contract.md; RepoMind lo lee, no lo genera.
#
# Variables de entorno:
#   ASC_KEY_ID, ASC_ISSUER_ID      La clave de la API de App Store Connect.
#   ASC_KEY_P8 o ASC_KEY_FILEPATH  El contenido o la ruta de la clave .p8.
#   ASC_VENDOR_NUMBER              Opcional: sin él no hay descargas, solo versiones.
#   STORE_STATUS_OUT               Dónde escribir el JSON (por defecto store.json).
#   STORE_STATUS_APPS              El mapa bundle id → repo (por defecto apps.json, junto al script).
#   STORE_STATUS_DAYS              Cuántos días de ventas (por defecto 30).

require "date"
require "json"
require "net/http"
require "openssl"
require "stringio"
require "time"
require "uri"
require "zlib"

module StoreStatus
  API = "https://api.appstoreconnect.apple.com"

  # Product Type Identifier de los informes de ventas de Apple.
  DOWNLOAD_TYPES = %w[1 1F 1T F1 1E 1EP 1EU].freeze
  UPDATE_TYPES = %w[7 7F 7T F7].freeze
  PURCHASE_TYPES = %w[IA1].freeze

  class Error < StandardError
    attr_reader :status

    def initialize(message, status = nil)
      super(message)
      @status = status
    end
  end

  # ── Parseo: funciones puras, las que prueba test_store_status.rb ─────────────────────────────

  # `GET /v1/apps/{id}/appStoreVersions`. Apple ha ido cambiando el nombre del estado.
  def self.parse_versions(json, limit: 6)
    versions = (json["data"] || []).map do |item|
      attributes = item["attributes"] || {}
      {
        "platform" => attributes["platform"],
        "version" => attributes["versionString"],
        "state" => attributes["appVersionState"] || attributes["appStoreState"],
        "createdAt" => attributes["createdDate"],
      }
    end
    versions.reject { |v| v["version"].nil? }
            .sort_by { |v| v["createdAt"].to_s }
            .reverse
            .first(limit)
  end

  # `GET /v1/builds?include=preReleaseVersion`: la versión de marketing viene en lo incluido.
  def self.parse_builds(json, limit: 5)
    marketing = {}
    (json["included"] || []).each do |item|
      marketing[item["id"]] = item.dig("attributes", "version") if item["type"] == "preReleaseVersions"
    end
    builds = (json["data"] || []).map do |item|
      attributes = item["attributes"] || {}
      pre = item.dig("relationships", "preReleaseVersion", "data", "id")
      {
        "version" => marketing[pre],
        "build" => attributes["version"],
        "uploadedAt" => attributes["uploadedDate"],
        "state" => attributes["processingState"],
        "expired" => attributes["expired"] == true,
      }
    end
    builds.sort_by { |b| b["uploadedAt"].to_s }.reverse.first(limit)
  end

  # Un informe diario de ventas (TSV). Devuelve las filas como hashes por nombre de columna.
  def self.parse_sales(tsv)
    lines = tsv.to_s.lines.map(&:chomp).reject(&:empty?)
    return [] if lines.size < 2

    header = lines.first.split("\t")
    lines.drop(1).map { |line| header.zip(line.split("\t", -1)).to_h }
  end

  # Las filas de un día, sumadas por app. Las compras dentro de la app traen el SKU de la app en
  # `Parent Identifier`, no su Apple ID.
  def self.summarize_day(rows, sku_to_id)
    totals = Hash.new { |hash, key| hash[key] = { "downloads" => 0, "updates" => 0, "purchases" => 0 } }
    rows.each do |row|
      type = row["Product Type Identifier"]
      units = row["Units"].to_i
      if DOWNLOAD_TYPES.include?(type)
        totals[row["Apple Identifier"].to_s]["downloads"] += units
      elsif UPDATE_TYPES.include?(type)
        totals[row["Apple Identifier"].to_s]["updates"] += units
      elsif PURCHASE_TYPES.include?(type)
        id = sku_to_id[row["Parent Identifier"].to_s]
        totals[id]["purchases"] += units if id
      end
    end
    totals
  end

  # Un día por fecha hasta `through`, con ceros donde Apple no informa nada.
  def self.daily_series(per_day, dates, app_id)
    dates.map do |date|
      day = per_day.fetch(date, {}).fetch(app_id, nil) || {}
      {
        "date" => date,
        "downloads" => day.fetch("downloads", 0),
        "updates" => day.fetch("updates", 0),
        "purchases" => day.fetch("purchases", 0),
      }
    end
  end

  # El día del Pacífico en el que Apple cuenta las ventas. Un día se cierra a la mañana siguiente,
  # así que el último cerrado es anteayer en hora del Pacífico, con margen.
  def self.through_date(now = Time.now.utc)
    (now - (8 * 3600)).to_date - 2
  end

  def self.dates_ending(through, days)
    ((through - (days - 1))..through).map { |date| date.strftime("%Y-%m-%d") }
  end

  def self.document(apps, now: Time.now.utc)
    { "schema" => 1, "generatedAt" => now.utc.iso8601, "apps" => apps }
  end

  # ── Cliente de la API ───────────────────────────────────────────────────────────────────────

  class Client
    def initialize(key_id:, issuer_id:, key_pem:)
      require "jwt"
      @key_id = key_id
      @issuer_id = issuer_id
      @key = OpenSSL::PKey::EC.new(key_pem)
      @token = nil
      @token_expires = Time.at(0)
    end

    def token
      return @token if @token && Time.now < @token_expires - 60

      now = Time.now.to_i
      @token_expires = Time.at(now + 1200)
      payload = { iss: @issuer_id, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
      @token = JWT.encode(payload, @key, "ES256", { kid: @key_id, typ: "JWT" })
    end

    # JSON, o un Error con el estado HTTP.
    def get_json(path, params = {})
      status, body = perform(path, params)
      raise Error.new("#{path}: HTTP #{status} #{body.to_s[0, 300]}", status) unless status == 200

      JSON.parse(body)
    end

    # El cuerpo de un informe de ventas, ya descomprimido, o nil cuando no hubo ventas ese día.
    def get_sales(params)
      status, body = perform("/v1/salesReports", params)
      return nil if status == 404
      raise Error.new("salesReports: HTTP #{status} #{body.to_s[0, 300]}", status) unless status == 200

      Zlib::GzipReader.new(StringIO.new(body)).read
    rescue Zlib::GzipFile::Error
      body
    end

    private

    # [estado HTTP, cuerpo]. Reintenta dos veces los cortes de red, no las respuestas de error.
    def perform(path, params)
      uri = URI("#{API}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      attempts = 0
      begin
        attempts += 1
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Accept"] = "application/json, application/a-gzip"
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
          http.request(req)
        end
        [response.code.to_i, response.body]
      rescue Errno::ECONNRESET, Net::ReadTimeout, Net::OpenTimeout, OpenSSL::SSL::SSLError
        retry if attempts < 3
        raise
      end
    end
  end

  # ── Todo junto ──────────────────────────────────────────────────────────────────────────────

  def self.collect(client, repo_map:, vendor:, days:, log: $stderr)
    apps = client.get_json("/v1/apps", { "limit" => 200 })["data"] || []
    log.puts "#{apps.size} apps en la cuenta"

    result = apps.map do |app|
      id = app["id"]
      attributes = app["attributes"] || {}
      versions = parse_versions(client.get_json("/v1/apps/#{id}/appStoreVersions", { "limit" => 50 }))
      builds = parse_builds(client.get_json("/v1/builds", {
        "filter[app]" => id, "sort" => "-uploadedDate", "limit" => 5, "include" => "preReleaseVersion",
      }))
      entry = {
        "id" => id,
        "name" => attributes["name"],
        "bundleId" => attributes["bundleId"],
        "versions" => versions,
        "builds" => builds,
      }
      repo = repo_map[attributes["bundleId"]]
      entry["repo"] = repo if repo
      { "entry" => entry, "sku" => attributes["sku"] }
    end

    sales_by_app = vendor ? collect_sales(client, vendor, days, result, log) : nil
    result.map do |item|
      entry = item["entry"]
      entry["sales"] = sales_by_app[entry["id"]] if sales_by_app
      entry
    end
  end

  def self.collect_sales(client, vendor, days, result, log)
    through = through_date
    dates = dates_ending(through, days)
    sku_to_id = result.to_h { |item| [item["sku"].to_s, item["entry"]["id"]] }
    per_day = {}
    dates.each do |date|
      tsv = client.get_sales(
        "filter[frequency]" => "DAILY", "filter[reportType]" => "SALES", "filter[reportSubType]" => "SUMMARY",
        "filter[vendorNumber]" => vendor, "filter[reportDate]" => date, "filter[version]" => "1_1")
      per_day[date] = tsv ? summarize_day(parse_sales(tsv), sku_to_id) : {}
    end
    result.to_h do |item|
      id = item["entry"]["id"]
      [id, { "through" => through.strftime("%Y-%m-%d"), "daily" => daily_series(per_day, dates, id) }]
    end
  rescue Error => e
    # Una clave sin acceso a ventas (403) no debe tirar las versiones, que es lo que más importa.
    log.puts "Sin ventas: #{e.message}"
    nil
  end

  def self.run(env: ENV, log: $stderr)
    key = env["ASC_KEY_P8"].to_s.strip
    key = File.read(env["ASC_KEY_FILEPATH"]) if key.empty? && env["ASC_KEY_FILEPATH"]
    abort "Faltan ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (o ASC_KEY_FILEPATH)" if
      env["ASC_KEY_ID"].to_s.empty? || env["ASC_ISSUER_ID"].to_s.empty? || key.to_s.empty?

    apps_file = env["STORE_STATUS_APPS"] || File.join(__dir__, "apps.json")
    repo_map = File.exist?(apps_file) ? JSON.parse(File.read(apps_file)) : {}
    vendor = env["ASC_VENDOR_NUMBER"].to_s.strip
    log.puts "Sin ASC_VENDOR_NUMBER: solo versiones, sin descargas" if vendor.empty?

    client = Client.new(key_id: env["ASC_KEY_ID"], issuer_id: env["ASC_ISSUER_ID"], key_pem: key)
    apps = collect(client, repo_map: repo_map, vendor: vendor.empty? ? nil : vendor,
                           days: Integer(env["STORE_STATUS_DAYS"] || 30), log: log)
    out = env["STORE_STATUS_OUT"] || "store.json"
    File.write(out, JSON.pretty_generate(document(apps)) + "\n")
    log.puts "Escrito #{out}"
  end
end

StoreStatus.run if $PROGRAM_NAME == __FILE__

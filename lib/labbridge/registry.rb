# frozen_string_literal: true

require "json"
require "net/http"

module LabBridge
  # Hartwell Labs product registry check.
  #
  # Lab rule: the translator works only and exclusively on Hartwell Labs
  # products. Before any translation the target must be verified against
  # the lab product catalog — either the live Products Registry API
  # (set PRODUCTS_API_URL, e.g. http://localhost:4576) or the built-in
  # catalog below when the API is unreachable.
  class Registry
    SLUG_TO_TARGET = {
      "talus-process-monitor" => "talus",
      "aurora-os" => "aurora",
      "externum" => "externum"
    }.freeze

    BUILTIN = {
      "talus" => {
        name: "talus-process-monitor",
        repo: "BartoszOsiej/talus-process-monitor",
        packages: ["pypi:talus-process-monitor", "ghcr:hartwell-labs/talus-process-monitor"]
      },
      "aurora" => {
        name: "Aurora OS",
        repo: "BartoszOsiej/Aurora",
        packages: ["npm:@hartwell-labs/aurora-os", "ghcr:hartwell-labs/aurora"]
      },
      "externum" => {
        name: "externum",
        repo: "BartoszOsiej/externum",
        packages: ["pypi:externum", "ghcr:hartwell-labs/externum"]
      }
    }.freeze

    class << self
      # Raises LabBridge::Error unless target is a verified lab product.
      # Returns the product info hash on success.
      def verify!(target)
        product = products[target]
        unless product
          raise Error,
                "target '#{target}' is not a verified Hartwell Labs product " \
                "(allowed: #{products.keys.join(', ')})"
        end

        product
      end

      def verified?(target)
        products.key?(target)
      end

      # Live catalog from the Products Registry API when PRODUCTS_API_URL
      # is set and reachable; built-in catalog otherwise.
      def products
        live_products || BUILTIN
      rescue StandardError
        BUILTIN
      end

      private

      def live_products
        base = ENV["PRODUCTS_API_URL"]
        return nil unless base

        uri = URI("#{base.sub(%r{/+\z}, '')}/products")
        response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 3) do |http|
          http.get(uri.request_uri)
        end
        return nil unless response.is_a?(Net::HTTPSuccess)

        prods = JSON.parse(response.body)["products"] || []
        map = {}
        prods.each do |p|
          target = SLUG_TO_TARGET[p["slug"]]
          next unless target

          map[target] = {
            name: p["name"],
            repo: p["repo"],
            packages: (p["packages"] || []).map { |pkg| "#{pkg["registry"]}:#{pkg["name"]}" }
          }
        end
        map.empty? ? nil : map
      end
    end
  end
end

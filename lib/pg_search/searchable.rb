# frozen_string_literal: true

require "active_support/core_ext/class/attribute"

module PgSearch
  module Searchable
    def self.included(mod)
      mod.class_eval do
        after_commit :update_tsv
      end
    end

    def searchable_text_with_weight
      against = pg_search_searchable_options[:against]
      against = against.to_a if against.is_a?(Hash)
      against = Array(against)
      against.map do |item|
        method = item.is_a?(Array) ? item.first : item
        weight = item.is_a?(Array) ? item.last : "A"
        content = send(method).to_s
        [content, weight]
      end
    end

    def tsv
      sql = searchable_text_with_weight.map do |content, weight|
        "SETWEIGHT(TO_TSVECTOR('pg_catalog.english', #{self.class.connection.quote(content)}), '#{weight}')"
      end.join(" || ")

      self.class.connection.execute("SELECT #{sql} AS tsv").first["tsv"]
    end

    def update_tsv
      column = pg_search_searchable_options.dig(:using, :tsearch, :tsvector_column) || :tsv
      self.update_columns(column => tsv)
    end
  end
end

# frozen_string_literal: true

require "active_support/core_ext/class/attribute"

module PgSearch
  module Multisearchable
    def self.included(mod)
      mod.class_eval do
        has_one :pg_search_document,
          as: :searchable,
          class_name: "PgSearch::Document",
          dependent: :delete

        after_save :update_pg_search_document,
          if: -> { PgSearch.multisearch_enabled? }
      end
    end

    def searchable_text_with_weight
      against = pg_search_multisearchable_options[:against]
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

    def searchable_text
      Array(pg_search_multisearchable_options[:against])
        .map { |symbol| send(symbol) }
        .join(" ")
    end

    def pg_search_document_attrs
      {
        tsv: tsv
      }.tap do |h|
        if (attrs = pg_search_multisearchable_options[:additional_attributes])
          h.merge! attrs.to_proc.call(self)
        end
      end
    end

    def should_update_pg_search_document?
      return false if pg_search_document.destroyed?

      conditions = Array(pg_search_multisearchable_options[:update_if])
      conditions.all? { |condition| condition.to_proc.call(self) }
    end

    def update_pg_search_document
      if_conditions = Array(pg_search_multisearchable_options[:if])
      unless_conditions = Array(pg_search_multisearchable_options[:unless])

      should_have_document =
        if_conditions.all? { |condition| condition.to_proc.call(self) } &&
        unless_conditions.all? { |condition| !condition.to_proc.call(self) }

      if should_have_document
        create_or_update_pg_search_document
      else
        pg_search_document&.destroy # standard:disable Rails/SaveBang
      end
    end

    def create_or_update_pg_search_document
      if !pg_search_document
        create_pg_search_document(pg_search_document_attrs)
      elsif should_update_pg_search_document?
        pg_search_document.update(pg_search_document_attrs) # standard:disable Rails/SaveBang
      end
    end
  end
end

module JitPreloadExtension
  attr_accessor :jit_preloader
  attr_accessor :jit_n_plus_one_tracking
  attr_accessor :jit_preload_aggregates
  attr_accessor :jit_preload_scoped_relations

  def reload(*args)
    clear_jit_preloader!
    super
  end

  def clear_jit_preloader!
    self.jit_preload_aggregates = {}
    self.jit_preload_scoped_relations = {}
    if jit_preloader
      jit_preloader.records.delete(self)
      self.jit_preloader = nil
    end
  end

  if Gem::Version.new(ActiveRecord::VERSION::STRING) >= Gem::Version.new("7.0.0")
    def preload_scoped_relation(name:, base_association:, preload_scope: nil)
      return jit_preload_scoped_relations[name] if jit_preload_scoped_relations&.key?(name)

      base_association = base_association.to_sym
      records = jit_preloader&.records || [self]
      previous_association_values = {}

      records.each do |record|
        association = record.association(base_association)
        if association.loaded?
          previous_association_values[record] = association.target
          association.reset
        end
      end

      preloader_association = ActiveRecord::Associations::Preloader.new(
        records: records,
        associations: base_association,
        scope: preload_scope
      ).call.first

      records.each do |record|
        record.jit_preload_scoped_relations ||= {}
        association = record.association(base_association)
        record.jit_preload_scoped_relations[name] = preloader_association.records_by_owner[record] || []
        association.reset
        if previous_association_values.key?(record)
          association.target = previous_association_values[record]
        end
      end

      jit_preload_scoped_relations[name]
    end
  else
    def preload_scoped_relation(name:, base_association:, preload_scope: nil)
      return jit_preload_scoped_relations[name] if jit_preload_scoped_relations&.key?(name)

      base_association = base_association.to_sym
      records = jit_preloader&.records || [self]
      previous_association_values = {}

      records.each do |record|
        association = record.association(base_association)
        if association.loaded?
          previous_association_values[record] = association.target
          association.reset
        end
      end

      ActiveRecord::Associations::Preloader.new.preload(
        records,
        base_association,
        preload_scope
      )

      records.each do |record|
        record.jit_preload_scoped_relations ||= {}
        association = record.association(base_association)
        record.jit_preload_scoped_relations[name] = association.target
        association.reset
        if previous_association_values.key?(record)
          association.target = previous_association_values[record]
        end
      end

      jit_preload_scoped_relations[name]
    end
  end

  def self.prepended(base)
    class << base
      delegate :jit_preload, to: :all

    end
  end
end

ActiveRecord::Base.send(:prepend, JitPreloadExtension)

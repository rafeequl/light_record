module LightRecord
  extend self

  def build_for_class(klass, fields)
    new_klass = Class.new(klass) do
      self.table_name = klass.table_name
      self.inheritance_column = nil

      extend LightRecord::RecordAttributes

      define_fields(fields)

      def initialize(data)
        @data = data
        @attributes = @data
        @readonly = true
      end

      def read_attribute_before_type_cast(attr_name)
        @data[attr_name.to_sym]
      end

      def self.subclass_from_attributes?(attrs)
        false
      end

      def has_attribute?(attr_name)
        @attributes.has_key?(attr_name.to_sym)
      end

      def read_attribute(attr_name)
        @attributes[attr_name.to_sym]
      end

      def [](attr_name)
        @attributes[attr_name.to_sym]
      end
    
      def attributes
        @attributes
      end

      # to avoid errors when try saving data
      def remember_transaction_record_state
        @_start_transaction_state ||= {}
        super
      end
    end

    if klass.const_defined?(:LightRecord, false)
      new_klass.send(:include, klass::LightRecord)
    elsif klass.superclass.const_defined?(:LightRecord, false)
      new_klass.send(:include, klass.superclass::LightRecord)
    end

    new_klass
  end

  module RecordAttributes
    def define_fields(fields)
      @fields ||= []

      fields.each do |field|
        field = field.to_sym unless field.is_a?(Symbol)
        @fields << field
        define_method(field) do
          @data[field]
        end

        # to avoid errors when try saving data
        define_method("#{field}=") do |value|
          @data[field] = value
        end
      end

      # ActiveRecord make method :id refers to primary key, even there is no column "id"
      if !fields.include?(:id) && !fields.include?("id") && primary_key.present?
        define_method(:id) do
          @data[self.class.primary_key.to_sym]
        end
      end
    end

    # used in Record#respond_to?
    def define_attribute_methods
    end

    def column_names
      @fields.map(&:to_s)
    end
  end

  def base_extended(klass)
    @base_extended ||= {}
    if @base_extended[klass]
      return @base_extended[klass]
    end

    @base_extended[klass] = LightRecord.build_for_class(klass, klass.column_names)
  end

  module RelationMethods

    # Return array of light object
    def light_records(options = {})
      client = connection.instance_variable_get(:@connection)
      sql = self.to_sql

      result = nil
      event_payload = {sql: sql, name: "LightRecord", connection_id: connection.object_id, statement_name: nil, binds: []}
      ActiveSupport::Notifications.instrument('sql.active_record', event_payload) do
        result = client.query(sql, stream: false, symbolize_keys: true, cache_rows: false, as: :hash)
      end

      klass = LightRecord.build_for_class(self.klass, result.fields)

      if options[:set_const]
        self.klass.const_set(:"LR_#{Time.now.to_i}", klass)
      end

      records = []
      result.each do |row|
        records << klass.new(row)
      end

      return records
    end

    # Iterate for each object
    # this uses less memroy because it creates objects one-by-one
    # it uses stream feature of mysql client
    def light_records_each(options = {})
      #ActiveRecord::Base.connection_pool.with_connection do
        conn = ActiveRecord::Base.connection_pool.checkout
        client = conn.instance_variable_get(:@connection)
        sql = self.to_sql

        result = nil

        event_payload = {sql: sql, name: "LightRecord", connection_id: conn.object_id, statement_name: nil, binds: []}
        ActiveSupport::Notifications.instrument('sql.active_record', event_payload) do
          result = client.query(sql, stream: true, symbolize_keys: true, cache_rows: false, as: :hash)
        end

        klass = LightRecord.build_for_class(self.klass, result.fields)

        if options[:set_const]
          self.klass.const_set(:"LR_#{Time.now.to_i}", klass)
        end

        result.each do |row|
          yield klass.new(row)
        end
      #end
    ensure
      ActiveRecord::Base.connection_pool.checkin(conn)
    end
  end

end

ActiveRecord::Relation.send(:include, LightRecord::RelationMethods)
# Copyright (c) 2017 by Fred George.
# May be used freely except for training; license required for training.

require 'json'

require_relative './rapids_connection'
require_relative './packet'
require_relative './packet_problems'

# Understands a filtered stream of JSON messages
class River
  attr_reader :rapids_connection, :listening_services
  protected :rapids_connection, :listening_services

  def initialize rapids_connection
    @rapids_connection = rapids_connection
    @listening_services = []
    @validations = []
    rapids_connection.register(self);
  end

  def message send_port, message
    packet_problems = PacketProblems.new message
    packet = packet_from message, packet_problems
    @listening_services.each do |ls|
      next ls.on_error(send_port, packet_problems) if packet_problems.errors?
      ls.packet send_port, packet.clone_with_name(ls.service_name), packet_problems
    end
  end

  def register service
    @listening_services << service
  end

  def require *keys
    keys.each do |key|
      @validations << lambda do |json_hash, packet, packet_problems|
        validate_required key, json_hash, packet_problems
        create_accessors key, json_hash, packet
      end
    end
    self
  end

  def forbid *keys
    keys.each do |key|
      @validations << lambda do |json_hash, packet, packet_problems|
        validate_missing key, json_hash, packet_problems
        create_accessors key, json_hash, packet
      end
    end
    self
  end

  def require_values(key_value_hashes)
    key_value_hashes.each do |key, value|
      @validations << lambda do |json_hash, packet, packet_problems|
        validate_value key.to_s, value, json_hash, packet_problems
        create_accessors key.to_s, json_hash, packet
      end
    end
    self
  end

  def interested_in *keys
    keys.each do |key|
      @validations << lambda do |json_hash, packet, packet_problems|
        create_accessors key, json_hash, packet
      end
    end
    self
  end

  private

    def packet_from message, packet_problems
      begin
        json_hash = JSON.parse(message)
        packet = Packet.new json_hash
        @validations.each { |v| v.call json_hash, packet, packet_problems }
        packet
      rescue JSON::ParserError
        packet_problems.severe_error("Invalid JSON format. Please check syntax carefully.")
      rescue Exception => e
        packet_problems.severe_error("Packet creation issue:\n\t#{e}")
      end
    end

    def validate_required key, json_hash, packet_problems
      return packet_problems.error "Missing required key #{key}" unless json_hash[key]
      return packet_problems.error "Empty required key #{key}" unless value?(json_hash[key])
    end

    def validate_missing key, json_hash, packet_problems
      return unless json_hash.key? key
      return unless value?(json_hash[key])
      packet_problems.error "Forbidden key #{key} detected"
    end

    def validate_value key, value, json_hash, packet_problems
      validate_required key, json_hash, packet_problems
      return if json_hash[key] == value
      packet_problems.error "Required value of key '#{key}' is '#{json_hash[key]}', not '#{value}'"
    end

    def create_accessors key, json_hash, packet
      packet.used_key key
      establish_variable key, json_hash[key], packet
      define_getter key, packet
      define_setter key, packet
    end

    def establish_variable key, value = nil, packet
      variable = variable(key)
      packet.instance_variable_set variable, value
    end

    def define_getter key, packet
      variable = variable(key)
      packet.define_singleton_method(key.to_sym) do
        instance_variable_get variable
      end
    end

    def define_setter key, packet
      variable = variable(key)
      packet.define_singleton_method((key + '=').to_sym) do |new_value|
        instance_variable_set variable, new_value
      end
    end

    def variable key
      ('@' + key.to_s).to_sym
    end

    def value? value_under_test
      return false if value_under_test.nil?
      return true if value_under_test.kind_of?(Numeric)
      return false if value_under_test == ''
      return false if value_under_test == []
      true
    end

end

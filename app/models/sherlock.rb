# == Schema Information
#
# Table name: sherlocks
#
#  id              :integer          not null, primary key
#  acting_user_id  :integer
#  obj_klass       :string
#  obj_id          :integer
#  new_attributes  :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  acting_ip       :inet
#  explanation     :text
#  discovery_klass :string
#  discovery_type  :integer
#  changed_attrs   :text
#

class Sherlock < ApplicationRecord
  belongs_to :acting_user, class_name: "User", optional: true

  class JSONWrapper
    # Allows directly setting pre-stringified JSON.
    def self.dump(hash); hash.is_a?(String) ? hash : JSON.dump(hash); end
    def self.load(str); JSON.parse(str) rescue {}; end
  end
  serialize :new_attributes, JSONWrapper
  serialize :changed_attrs, JSONWrapper

  validate :some_changes_made

  before_save :set_discovery_type
  after_commit :broadcast_creation

  scope :by_type, ->(*types) { where(discovery_type: Sherlock.types_for(types)) }
  scope :by_klass, ->(*klasses) { where(discovery_klass: klasses) }

  class << self
    attr_writer :acting_user, :acting_ip

    def types_for(*syms)
      discovery_types.slice(*syms.flatten.map(&:to_sym)).values
    end

    def discovery_types
      {
        new:    0,
        edit:   1,
        remove: 2,
        ban:    3,
        other:  4
      }
    end

    def discovery_klasses
      [
        :user,
        :post,
        :reply,
        :shout,
        :chat,
        :ip
      ]
    end

    def discover(obj, active_record_changes, discovery_klass)
      return if active_record_changes.none?

      new_changes = active_record_changes.each_with_object({}) { |(changed_key, changed_array), memo| memo[changed_key] = changed_array.first }
      acting_ip = @acting_ip.presence || @acting_user.try(:current_sign_in_ip).presence || @acting_user.try(:last_sign_in_ip).presence || @acting_user.try(:ip_address).presence

      create(
        obj: obj,
        changed_attrs: new_changes,
        acting_user: @acting_user,
        acting_ip: acting_ip,
        discovery_klass: discovery_klass,
        new_attributes: obj.attributes
      )
    end
  end

  def obj
    obj_klass.constantize.find(obj_id)
  end

  def obj=(new_obj)
    self.obj_klass = new_obj.class.to_s
    self.obj_id = new_obj.try(:id)
  end

  def discovery_type
    "#{self.class.discovery_types.key(super)}_#{discovery_klass}"
  end

  def discovery_type=(new_type)
    super(self.class.types_for(new_type).first)
  end

  def set_discovery
    return unless discovery_klass_to_enum.present?
    mod_type = discovery_type
    self.discovery = "#{mod_type}_#{discovery_klass_to_enum}".to_sym
  end

  def set_discovery_type
    changed_keys = changed_attrs.keys
    self.discovery_type = if changed_keys.find { |changed_key| changed_key == "id" }
      :new
    elsif changed_keys.find { |changed_key| changed_key =~ /banned/ }
      :ban
    elsif changed_keys.find { |changed_key| changed_key =~ /remove/ }
      :remove
    else
      :edit
    end
  end

  private

  def broadcast_creation
    return unless obj_klass == :post

    ActionCable.server.broadcast("replies_for_#{obj_id}", {})
  end

  def some_changes_made
    return if changed_attrs.any?

    errors.add(:base, "No changes made.")
  end
end

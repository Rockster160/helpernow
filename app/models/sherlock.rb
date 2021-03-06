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
  include MarkdownHelper

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

  scope :by_type,   ->(*types) { where(discovery_type: types_for(types)) }
  scope :by_klass,  ->(*klasses) { where(discovery_klass: klasses) }
  scope :search_ip, ->(*searched_ips) {
    q = searched_ips.flatten.map { |ip| "TEXT(acting_ip) LIKE ?" }.join(" OR ")
    ips = searched_ips.flatten.map { |ip| "#{ip.squish}/%" }
    where(q, *ips)
  }
  scope :users,     -> { by_klass(:user) }
  scope :posts,     -> { by_klass(:post) }
  scope :replies,   -> { by_klass(:reply) }
  scope :shouts,    -> { by_klass(:shout) }
  scope :chats,     -> { by_klass(:chat) }
  scope :ips,       -> { by_klass(:ip) }
  scope :by_changed_attrs, ->(change_type, *changed_attr_keys) {
    raise "Invalid change type" unless change_type.to_s.upcase.in?(["OR", "AND"])
    q = changed_attr_keys.flatten.map { |attr_key| "sherlocks.changed_attrs ILIKE ?" }.join(" #{change_type} ")
    vals = changed_attr_keys.flatten.map {|attr_key| "%#{attr_key}%"}
    where(q, *vals)
  }
  scope :all_changed_attrs, ->(*changed_attr_keys) { by_changed_attrs(:AND, changed_attr_keys) }
  scope :any_changed_attrs, ->(*changed_attr_keys) { by_changed_attrs(:OR, changed_attr_keys) }

  class << self
    attr_writer :acting_user, :acting_ip, :exception_data

    def types_for(*syms)
      discovery_types.slice(*syms.flatten.map(&:to_sym)).values
    end

    def discovery_types
      {
        new:    0,
        edit:   1,
        remove: 2,
        ban:    3,
        other:  4,
        delete: 5
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
      acting_user = @acting_user || @exception_data&.dig(:current_user)
      acting_user ||= obj if obj.is_a?(User)
      acting_user ||= obj.try(:author) || obj.try(:user) || obj.try(:sent_from)

      if acting_user.nil?
        slack_attachment = {
          fallback: "Something went wrong discovering #{discovery_klass}",
          color: :warning,
          title: "Failed to discover #{discovery_klass}",
          text: "*User*\n#{acting_user.try(:username) || 'No User Found'}\n\n*Ip*\n#{acting_ip}\n\n*Params*\n#{@exception_data&.dig(:params)}\n\n*Object*\n#{obj.try(:attributes) || obj}\n\n*Changes*\n#{active_record_changes}",
        }
        SlackNotifier.notify(attachments: [slack_attachment])
      end

      new(
        obj:             obj,
        changed_attrs:   new_changes,
        acting_user:     acting_user,
        acting_ip:       acting_ip,
        discovery_klass: discovery_klass,
        new_attributes:  obj.attributes
      )
    end

    def displayable_post_edits
      select do |audit|
        (audit.changed_attrs.keys & ["body", "closed_at"]).any?
      end
    end
  end

  def obj
    @_obj ||= obj_klass.constantize.find_by(id: obj_id)
  end

  def obj=(new_obj)
    self.obj_klass = new_obj.class.to_s
    self.obj_id = new_obj.try(:id)
  end

  def audit_type
    "#{discovery_type}_#{discovery_klass}"
  end

  def discovery_type
    self.class.discovery_types.key(super)
  end

  def discovery_type=(new_type)
    super(self.class.types_for(new_type).first)
  end

  def set_discovery_type
    changed_keys = changed_attrs.keys
    self.discovery_type ||= if discovery_klass =~ /ip/
      :ban # Forcefully set as ip if klass is an IP ban
    elsif changed_keys.find { |changed_key| changed_key == "id" }
      :new
    elsif changed_keys.find { |changed_key| changed_key =~ /banned/ }
      :ban
    elsif changed_keys.find { |changed_key| changed_key =~ /remove/ }
      :remove
    else
      :edit
    end
  end

  def changes
    new_attributes.each_with_object({previous: {}, current: {}}) do |(attr_key, attr_val), formatted_changes|

      old_val = changed_attrs[attr_key]
      if changed_attrs.keys.include?(attr_key)
        formatted_changes[:current][attr_key] = format_change_for_display(attr_key, old_val, attr_val)
        formatted_changes[:previous][attr_key] = format_change_for_display(attr_key, attr_val, old_val, body_flip: false)
      else
        formatted_changes[:current][attr_key] = format_change_for_display(attr_key, attr_val, attr_val)
      end
    end
  end

  def changed_body
    return unless changed_attrs.key?("body")
    previous_body = changed_attrs["body"].to_s.gsub(/(\r)?\n/, "¬\\1")
    current_body = new_attributes["body"].to_s.gsub(/(\r)?\n/, "¬\\1")
    Differ.diff_by_word(escape_html_tags(current_body), escape_html_tags(previous_body))
  end

  private

  def should_ignore_changes?(change_key)
    /password|super|created_at|updated_at|sign_in|confirmation|token/.match(change_key)
  end

  def format_change_for_display(change_key, start_val, end_val, body_flip: true)
    return if should_ignore_changes?(change_key)
    start_val = humanize_bool(start_val) || start_val.to_s
    end_val = humanize_bool(end_val) || end_val.to_s

    if /_at|date/.match(change_key)
      start_val = DateTime.parse(start_val).to_formatted_s(:basic) rescue start_val
      end_val = DateTime.parse(end_val).to_formatted_s(:basic) rescue end_val
    end

    start_val, end_val = end_val, start_val if body_flip
    Differ.diff_by_word(escape_html_tags(start_val.to_s), escape_html_tags(end_val.to_s))
  end

  def broadcast_creation
    return unless obj_klass == :post

    ActionCable.server.broadcast("replies_for_#{obj_id}", {})
  end

  def some_changes_made
    return if changed_attrs.any?

    errors.add(:base, "No changes made.")
  end
end

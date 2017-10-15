module Accountable
  extend ActiveSupport::Concern

  included do
    before_validation :set_default_username, :set_slug

    validates_uniqueness_of :username, :slug, message: "Sorry, that Username has already been taken."
    validate :username_meets_requirements
    validate :at_least_13_years_of_age

    after_create :set_gravatar_if_exists, :create_associated_objects
  end

  def online?
    return false unless last_seen_at
    last_seen_at > 5.minutes.ago
  end
  def offline?; !online?; end
  def verified?; verified_at?; end
  def long_term_user?; created_at < 1.year.ago; end
  def long_time_user?; long_term_user?; end
  def deactivated?; !verified? && created_at < 1.day.ago; end

  def see!
    update(last_seen_at: DateTime.current)
  end

  def account_completion
    {
      "Confirm account (Verify email and add password)" => verified? && encrypted_password.present?,
      "Update Username" => has_updated_username?,
      "Upload Avatar" => avatar_url.present?,
      "Add Bio" => bio?,
      "Make your first post" => posts.count.positive?,
      "Help somebody (Comment on a post)" => replies.joins(:post).where.not(posts: { author_id: id }).count.positive?
    }
  end

  def ip_address
    location.try(:ip) || current_sign_in_ip || last_sign_in_ip || username || email || id
  end

  def adult?; age.present? && age >= 18; end
  def child?; age.nil? || age < 18; end
  def age
    return unless date_of_birth.present?
    now = Time.now.utc.to_date
    dob = date_of_birth
    now.year - dob.year - ((now.month > dob.month || (now.month == dob.month && now.day >= dob.day)) ? 0 : 1)
  end

  def date_of_birth=(dob)
    begin
      if dob.is_a?(Date)
        super(dob)
      elsif dob.is_a?(String)
        super(Date.strptime(dob, "%m/%d/%Y"))
      else
        super(Date.parse(dob))
      end
    rescue ArgumentError
    end
  end

  def gravatar?(options={})
    hash = Digest::MD5.hexdigest(email.to_s.downcase)
    options = { rating: "pg", timeout: 2 }.merge(options)
    http = Net::HTTP.new("www.gravatar.com", 80)
    http.read_timeout = options[:timeout]
    response = http.request_head("/avatar/#{hash}?rating=#{options[:rating]}&default=http://gravatar.com/avatar")
    response.code != "302"
  rescue StandardError, Timeout::Error
    false  # Show "no gravatar" if the service is down or slow
  end

  def avatar
    avatar_url.presence || letter.presence || "status_offline.png"
  end

  def to_param
    [id, username.parameterize].join("-")
  end

  private

  def set_gravatar_if_exists
    return unless gravatar?
    hash = Digest::MD5.hexdigest(email.to_s.downcase)
    update(avatar_url: "https://www.gravatar.com/avatar/#{hash}?rating=pg")
  end

  def set_default_username
    self.has_updated_username = true if username_changed?
    return if email.blank? || username.present?
    base_username = email.split("@").first
    loop do
      break if base_username.length >= 4
      base_username = "#{base_username}#{base_username}"
    end
    t = 0
    self.username ||= loop do
      try_username = t == 0 ? base_username : "#{base_username}#{t + 1}"
      t += 1
      break try_username if User.where(username: try_username).none?
    end
    username.try(:squish!)
  end

  def set_slug
    self.slug = username.try(:parameterize)
  end

  def at_least_13_years_of_age
    return unless date_of_birth.present?
    return if age >= 13

    errors.add(:base, "We're sorry- you must be 13 years of age or older to use this site.")
  end

  def create_associated_objects
    build_location(ip: current_sign_in_ip.presence || last_sign_in_ip.presence).save
    build_settings.save
  end

  def username_meets_requirements
    return unless email.present?

    if ["anonymous"].include?(username.to_s.downcase)
      return errors.add(:base, "Sorry, that is a reserved word and cannot be used as a Username.")
    end
    if username.blank?
      return errors.add(:username, "must be at least 4 characters.")
    end
    if username.include?(" ")
      errors.add(:username, "cannot contain spaces")
    end
    if username.include?("@")
      errors.add(:username, "cannot contain @'s'")
    end
    unless username.length > 3
      errors.add(:username, "must be at least 4 characters")
    end
    unless username.length < 25
      errors.add(:username, "must be less than 25 characters")
    end
    unless username.gsub(/[^a-z]/i, "").length > 1
      errors.add(:username, "must have at least 2 normal alpha characters (A-Z)")
    end
  end

end

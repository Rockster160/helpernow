# == Schema Information
#
# Table name: posts
#
#  id                 :integer          not null, primary key
#  body               :text
#  author_id          :integer
#  posted_anonymously :boolean
#  closed_at          :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

class Post < ApplicationRecord
  include FormatContent

  belongs_to :author, class_name: "User"
  has_many :views, class_name: "PostView"
  has_many :edits, class_name: "PostEdit"
  has_many :replies, class_name: "Comment"
  has_many :report_flags
  has_many :subscriptions
  has_many :post_tags
  has_many :tags, through: :post_tags

  scope :claimed, -> { where.not(posted_anonymously: true) }
  scope :unclaimed, -> { where(posted_anonymously: true) }

  after_create :auto_add_tags

  validate :body_has_alpha_characters

  def title
    return "BROKEN" unless body.present?
    first_sentence = body.split(/[\!|\.|\n|;|\?|\r] /).reject(&:blank?).first
    body[0..first_sentence.try(:length) || -1]
  end

  def open?; !closed?; end
  def closed?; closed_at?; end

  def preview_content
    body[title.length..-1].split("\n").reject(&:blank?).first
  end

  def format_body(options={})
    format_content(body[title.length..-1], options)
  end

  def username
    if posted_anonymously?
      "Anonymous"
    else
      author.username
    end
  end

  def avatar
    if posted_anonymously?
      identicon_src(author.ip_address)
    else
      author.avatar_url.presence || letter.presence || 'status_offline.png'
    end
  end

  def letter
    author.try(:letter) || "?"
  end

  def location
    return unless author.try(:location)
    [author.location.city.presence, author.location.region_code.presence, author.location.country_code.presence].compact.join(", ")
  end

  def to_param
    [id, title.parameterize].join("-")
  end

  private

  def body_has_alpha_characters
    unless body&.gsub(/[^a-z]/, "").length > 10
      errors.add(:base, "This post isn't long enough!")
    end
  end

  def auto_add_tags
    new_tag_strs = Tag.auto_extract_tags_from_body(body).first(5)
    new_tag_strs.each do |new_tag_str|
      new_tag = Tag.find_or_create_by(tag_name: new_tag_str.to_s.downcase)
      post_tags.create(tag: new_tag)
    end
  end

  def short_title
    cut_title = cut_string_before_index_at_char(title, 100)
    return cut_title if cut_title.length <= 100
    "#{cut_title}..."
  end

  def cut_string_before_index_at_char(str, idx, letter=" ")
    return str if str.length <= idx
    indices_of_letter = str.split("").map.with_index { |l, i| i if l == letter }.compact
    indices_before_index = indices_of_letter.select { |i| i <= idx }
    str[0..indices_before_index.last.to_i - 1]
  end

  def identicon_src(ip)
    base64_identicon = RubyIdenticon.create_base64(ip, square_size: 5, border_size: 0, grid_size: 7, background_color: 0xffffffff)
    "data:image/png;base64,#{base64_identicon}"
  end

end

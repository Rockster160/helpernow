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
#  reply_count        :integer
#  marked_as_adult    :boolean
#  in_moderation      :boolean          default("false")
#  removed_at         :datetime
#

class Post < ApplicationRecord
  include Defaults
  include Sherlockable
  include SpamCheck
  extend SpamCheck
  attr_accessor :skip_debounce

  DEFAULT_POST_TEXT = "Start Here. \n\nAsk a question, post a rant, tell us your story.".freeze

  sherlockable klass: :post, ignore: [ :updated_at, :reply_count ]

  belongs_to :author, class_name: "User"
  has_many :views, class_name: "PostView"
  has_many :edits, class_name: "PostEdit"
  has_many :replies
  has_many :post_invites
  has_many :invites
  has_many :subscriptions, -> { subscribed }
  has_many :subscribers, through: :subscriptions, source: :user
  has_many :post_tags
  has_many :tags, through: :post_tags
  has_many :favorite_replies
  has_one :poll

  scope :search_for,           ->(text) { where("posts.body ILIKE ?", "%#{text.gsub(/['"’“”]/, "['\"’“”]")}%") }
  scope :regex_search,         ->(text) { where("posts.body ~* ?", text.gsub(/['"’“”]/, "['\"’“”]")) } # POSIX
  scope :claimed,              -> { where(posted_anonymously: [false, nil]) }
  scope :unclaimed,            -> { where(posted_anonymously: true) }
  scope :verified_user,        -> { joins(:author).where.not(users: { verified_at: nil }) }
  scope :unverified_user,      -> { joins(:author).where(users: { verified_at: nil }) }
  scope :not_banned,           -> { joins(:author).where("users.banned_until IS NULL OR users.banned_until < ?", DateTime.current) }
  scope :closed,               -> { where.not(closed_at: nil) }
  scope :not_closed,           -> { where(closed_at: nil) }
  scope :removed,              -> { where.not(removed_at: nil) }
  scope :not_removed,          -> { where(removed_at: nil) }
  scope :needs_moderation,     -> { where(in_moderation: true) }
  scope :no_moderation,        -> { where(in_moderation: [nil, false]) }
  scope :no_replies,           -> { where("posts.reply_count = 0 OR posts.reply_count IS NULL") }
  scope :more_replies_than,    ->(count_of_replies) { where("posts.reply_count > ?", count_of_replies) }
  scope :less_replies_than_or, ->(count_of_replies) { where("posts.reply_count <= ?", count_of_replies) }
  scope :by_username,          ->(username) { claimed.joins(:author).where("users.username ILIKE ?", "%#{username}%") }
  scope :regex_username,       ->(username) { claimed.joins(:author).where("users.username ~* ?", username.gsub(/['"’“”]/, "['\"’“”]")) }
  scope :by_tags,              ->(*tag_words) { where(id: Tag.by_words(tag_words).map(&:post_ids).inject(&:&)) }
  scope :only_adult,           -> { where(posts: { marked_as_adult: true }) }
  scope :without_adult,        -> { where(posts: { marked_as_adult: [nil, false] }) }
  scope :conditional_adult,    ->(user=nil) { without_adult.or(where(posts: { author_id: user.try(:id) })) unless user.try(:adult?) && !user.try(:settings).try(:hide_adult_posts?) }
  scope :displayable,          ->(user=nil) { not_banned.not_removed.no_moderation.conditional_adult(user) }

  after_create :auto_add_tags, :alert_helpbot, :invite_users
  after_commit :broadcast_creation, :subscribe_author, :generate_poll, :remove_notices
  defaults reply_count: 0
  defaults posted_anonymously: false

  before_validation :format_body
  before_validation :auto_adult, on: :create
  validate :body_is_not_default, :body_has_alpha_characters, :debounce_posts, :not_spam

  def self.text_matches_default_text?(text)
    stripped_default_text = DEFAULT_POST_TEXT.gsub("\n", " ").gsub(/[^a-z| ]/i, "")
    stripped_body_text = text.gsub("\n", " ").gsub(/[^a-z| ]/i, "")

    stripped_default_text.include?(stripped_body_text) || stripped_body_text.include?(stripped_default_text)
  end

  def self.currently_popular
    pluck_last_replies = 200
    replies_for_age_appropriate_posts = Reply.displayable.joins(:post).where(posts: { marked_as_adult: [nil, false], closed_at: nil, in_moderation: [nil, false], removed_at: nil })
    uniq_replies_by_author_for_posts = replies_for_age_appropriate_posts.order(created_at: :desc, id: :desc).limit(pluck_last_replies).pluck(:post_id, :author_id).uniq
    counted_post_ids = uniq_replies_by_author_for_posts.each_with_object(Hash.new(0)) { |(post_id, author_id), count_hash| count_hash[post_id] += 1 }
    post_ids_sorted_by_uniq_author_count = counted_post_ids.sort_by { |(post_id, unique_author_count)| unique_author_count }.map(&:first)
    most_popular_post_id = post_ids_sorted_by_uniq_author_count.reverse.first
    Post.find(most_popular_post_id) if most_popular_post_id
  end

  def set_tags
    tags.pluck(:tag_name).join(", ")
  end
  def set_tags=(new_tags_string)
    post_tags.each(&:destroy)
    new_tags_string.split(",").each do |new_tag|
      new_tag = new_tag.downcase.squish
      tag = Tag.find_or_create_by(tag_name: new_tag)
      post_tags.find_or_create_by(tag: tag)
    end
  end

  def body; self[:body] || ""; end
  def title
    return "No Content" unless body.present?
    first_sentence = body.split(/[\!\.\n\;\?\r][ \r\n]/).reject(&:blank?).first
    long_title = body[0..first_sentence.try(:length) || -1].gsub(/\[poll\]/, "")
    max_title_length = 200
    cut_string_before_index_at_char(long_title, max_title_length)
  end
  def non_title_body
    body[title.length..-1]
  end
  def word_count
    body.to_s.squish.split(" ").count
  end

  def open?; !closed?; end
  def closed?; closed_at?; end
  def removed?; removed_at?; end
  def safe?; !nsfw?; end
  def nsfw?; marked_as_adult?; end

  def user_subscribed?(user)
    subscriptions.find_by(user: user).try(:subscribed?)
  end

  def notify_subscribers(not_user: nil, reply_id: nil)
    subscribers.each do |subscriber|
      next if subscriber == not_user
      subscriber.notices.subscription.find_or_create_by(post_id: id, reply_id: reply_id)
    end
  end

  def post_edits
    Sherlock.posts.where(obj_id: id).by_type(:edit).all_changed_attrs(:body)
  end

  def editors
    User.where(id: post_edits.pluck(:acting_user_id).uniq - [author_id])
  end

  def preview_content
    full_preview = body[title.length..-1].to_s.split("\n").reject(&:blank?).first
    cut_preview = cut_string_before_index_at_char(full_preview, 500)
    full_preview.to_s.length == cut_preview.to_s.length ? "#{full_preview}" : "#{cut_preview}..."
  end

  def username
    if posted_anonymously?
      "Anonymous"
    else
      author.username
    end
  end

  def avatar(size: nil)
    if posted_anonymously?
      author.anonicon(id)
    else
      author.avatar(size: size)
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

  def to_csv
    csv_array = []
    csv_array << "Author,Body"
    csv_array << "#{username.gsub(',', '%,')},#{body.gsub(/(\r)?\n/, "\\n")}"
    replies.order(:created_at, :id).each do |reply|
      csv_array << "#{reply.username.gsub(',', '%,')},#{reply.body.gsub(/(\r)?\n/, "\\n")}"
    end
    csv_array.join("\n")
  end

  private

  def broadcast_creation
    return if Rails.env.archive?
    ActionCable.server.broadcast("posts_channel", {})
  end

  def not_spam
    return if author.replies.where.not(id: id).any?

    if sounds_fake?
      errors.add(:base, "This post has been marked as spam. We use markdown rather than HTML. If you'd like to post a link somewhere, go ahead and just drop the url by itself and if it's safe, we'll post it!")
    elsif blacklisted_text?
      errors.add(:base, "This reply has been marked as spam.")
    elsif sounds_like_cash_cow?
      errors.add(:base, "This post has been marked as spam. Please do not advertise cash loans or anything similar. Instead, try to post relevant, actual help.")
    elsif sounds_like_ad?
      errors.add(:base, "This post has been marked as spam. It looks like you're not actually asking for help but advertising external sites.")
    elsif word_count < 2
      errors.add(:base, "This post has been marked as spam. Please try to explain your problem with detail so that others can help you.")
    end
  end

  def format_body
    self.body[0] = "" while self.body[0] =~ /[ \n\r]/ # Remove New Lines before post.
    self.body[-1] = "" while self.body[-1] =~ /[ \n\r]/ # Remove New Lines after post.
  end

  def generate_poll
    return if poll.present?
    poll_regex = /\[poll:?(.*?)\]/
    poll_markdown = body[poll_regex]
    return unless poll_markdown.present?

    options_text = poll_markdown[6..-2].to_s
    options = options_text.split(",").map(&:presence).compact
    return unless options.length >= 2

    poll = build_poll
    poll.save
    options.each do |option|
      poll.options.create(body: option)
    end

    update(body: body.sub(poll_regex, "[poll]"), ignore_sherlock: true)
  end

  def alert_helpbot
    HelpBot.react_to_post(self)
  end

  def body_is_not_default
    if Post.text_matches_default_text?(body)
      errors.add(:base, "Try asking a question!")
    end
  end

  def debounce_posts
    return if Rails.env.archive?
    return if skip_debounce
    return if !new_record? || author.posts.where("created_at > ?", 5.minutes.ago).none?

    errors.add(:base, "Slow down there! You're posting too fast. You can only make 1 new post every 5 minutes.")
  end

  def body_has_alpha_characters
    return if body.present? && body.gsub(/[^a-z]/, "").length > 10
    return if title.present? && preview_content.include?("[poll]")

    errors.add(:base, "This post isn't long enough! Try adding some more detail.")
  end

  def auto_adult
    self.marked_as_adult = Tag.sounds_nsfw?(body)
  end

  def auto_add_tags
    new_tag_strs = Tag.auto_extract_tags_from_body(body)
    auto_tags = Rails.env.archive? ? new_tag_strs : new_tag_strs.first(5)
    auto_tags&.each do |new_tag_str|
      new_tag = Tag.find_or_create_by(tag_name: new_tag_str.to_s.downcase)
      post_tags.find_or_create_by(tag: new_tag)
    end
  end

  def subscribe_author
    return unless author
    if created_at == updated_at && !author.helpbot?
      subscriptions.find_or_create_by(user_id: author_id)
    end
  end

  def remove_notices
    return unless closed? || removed?

    Notice.unread.where(post_id: id).each(&:read)
  end

  def invite_users
    return if Rails.env.archive?
    invited_users = []
    body.scan(/@([^ \`\@]+)/) do |username_tag|
      user = User.by_username($1)
      if user.present? && (user.friends?(author) || !user.settings.friends_only?)
        if user.invites.create(post_id: id, from_user: author, invited_anonymously: posted_anonymously?).persisted?
          invited_users << user
        end
      end
    end
    if invited_users.any?
      post_invites.create(user_id: author_id, invited_users: invited_users.count, invited_anonymously: posted_anonymously?)
    end
  end

  def cut_string_before_index_at_char(str, idx, letter=" ")
    # Cuts the string at the given index,
    #   then finds the LAST occurrence of the letter in that string,
    #   and cuts there.
    return str if str.to_s.length <= idx
    indices_of_letter = str.split("").map.with_index { |l, i| i if l == letter }.compact
    indices_before_index = indices_of_letter.select { |i| i <= idx }
    str[0..indices_before_index.last.to_i - 1]
  end

end

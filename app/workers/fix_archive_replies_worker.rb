class FixArchiveRepliesWorker
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform
    user = User.find_by(username: "Unclaimed")
    250.times do
      @post = user.posts.order(:updated_at).first
      @step = 0
      next if @post.blank?
      next save_post! if @post.replies.none?
      puts "Attempting Post #{@post.id}".colorize(:red)
      handle_post
    end
  end

  def handle_post
    first_reply = @post.replies.order(created_at: :asc, id: :asc).first
    @step += 1
    return set_reply!(first_reply) if correct_reply?(first_reply)

    last_reply = @post.replies.order(created_at: :asc, id: :asc).last
    @step += 1
    return set_reply!(last_reply) if correct_reply?(last_reply)

    found_reply = @post.replies.joins(:post).find_by("REGEXP_REPLACE(replies.body, '[^\\w]', '', 'g') LIKE REGEXP_REPLACE(posts.body, '[^\\w]', '', 'g')||'%'")
    @step += 1
    return set_reply!(found_reply) if found_reply.present?

    @step += 1
    save_post!
    SlackNotifier.notify("Failed to update: #{@post.id}")
  end

  def correct_reply?(reply)
    reply.body.gsub(/[^\w]/, "").include?(@post.body.gsub(/[^\w]/, ""))
  end

  def set_reply!(reply)
    @post.body = reply.body
    @post.author_id = reply.author_id
    save_post!
    reply.destroy
  end

  def save_post!
    puts "Saving post: #{@post.id} - Step: #{@step}".colorize(:red)
    @post.updated_at = DateTime.current
    @post.save(validate: false)
  end
end

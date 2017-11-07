require 'slack-notifier'
class SlackWorker
  include Sidekiq::Worker
  WEBHOOK_URL = "https://hooks.slack.com/services/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"

  # https://api.slack.com/docs/attachments

  def perform(message, channel='#helpqa', username='Help-Bot', icon_emoji=':helpbot:', attachments=[])
    ::Slack::Notifier.new(WEBHOOK_URL, channel: channel, username: username, attachments: attachments, icon_emoji: icon_emoji).ping(message)
  end

end

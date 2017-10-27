class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_mod, only: :remove_message

  def chat
    limit = 1000
    @messages = ChatMessage.includes(:author).order(created_at: :desc).limit(limit) # Intentionally ordering backwards so that limit gets the last N records
    @messages = @messages.not_banned.not_removed
    if params[:message].to_i > 0
      start_id = params[:message].to_i - (limit / 2)
      end_id = params[:message].to_i + (limit / 2)
      @messages = @messages.where(id: start_id..end_id)
    end
    if params[:id].to_i > 0
      @messages = @messages.where(id: params[:id])
    end
    if params[:since].to_i > 0
      @messages = @messages.where("chat_messages.created_at > ?", Time.at(params[:since].to_i))
    end
    @messages = @messages.reverse # Array reversal so that we get the LAST N records instead of the first.
    render partial: "messages" if request.xhr?
  end

  def remove_message
    message = ChatMessage.find(params[:id])
    message.update(removed: params[:restore] != "true")
    redirect_to chat_path
  end

end

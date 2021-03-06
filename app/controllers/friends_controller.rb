class FriendsController < ApplicationController
  before_action :authenticate_user
  after_action :mark_all_read, only: :index

  def index
    @friends = current_user.friends.order(last_seen_at: :desc)
    @fans = current_user.fans.order(last_seen_at: :desc)
    @favorites = current_user.favorites.order(last_seen_at: :desc)
  end

  def update
    friend = User.find(params[:id])
    if true_param?(:add)
      current_user.add_friend(friend)
    else
      friendship = current_user.friendship_with(friend)
      friendship&.update(params.permit(:reveal_email))
    end

    redirect_to account_friends_path
  end

  def destroy
    friend = User.find(params[:id])
    current_user.remove_friend(friend)
    redirect_to account_friends_path
  end

  private

  def mark_all_read
    current_user.notices.friend_request.unread.each(&:read)
  end

end

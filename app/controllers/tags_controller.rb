class TagsController < ApplicationController
  include ApplicationHelper
  include PostsHelper

  def index
    @tags = Tag.count_order.limit(100)
  end

  def show
    @tags = Tag.by_words(params[:tags].split(","))
    return render :no_tag if @tags.none?
    @posts = Post.displayable.by_tags(@tags.pluck(:tag_name)).order(created_at: :desc)
    @users = User.displayable.by_tags(@tags.pluck(:tag_name)).order(last_seen_at: :desc)
  end

  def redirect
    redirect_to tag_url(params[:tag_name])
  end

end

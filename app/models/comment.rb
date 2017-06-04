# == Schema Information
#
# Table name: comments
#
#  id                    :integer          not null, primary key
#  body                  :text
#  author_id             :integer
#  posted_anonymously    :boolean
#  has_questionable_text :boolean
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  post_id               :integer
#

class Comment < ApplicationRecord

  belongs_to :post
  belongs_to :author, class_name: "User"

end

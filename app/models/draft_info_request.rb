# == Schema Information
# Schema version: 20210114161442
#
# Table name: draft_info_requests
#
#  id               :integer          not null, primary key
#  title            :string
#  user_id          :integer
#  public_body_id   :integer
#  body             :text
#  embargo_duration :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#

class DraftInfoRequest < ApplicationRecord
  include AlaveteliPro::RequestSummaries
  include InfoRequest::DraftTitleValidation

  belongs_to :user,
             inverse_of: :draft_info_requests
  belongs_to :public_body, inverse_of: :draft_info_requests, optional: true

  strip_attributes

  # @see RequestSummaries#request_summary_body
  def request_summary_body
    body
  end

  # @see RequestSummaries#request_summary_public_body_names
  def request_summary_public_body_names
    public_body.name unless public_body.blank?
  end

  # @see RequestSummaries#request_summary_categories
  def request_summary_categories
    [AlaveteliPro::RequestSummaryCategory.draft]
  end
end

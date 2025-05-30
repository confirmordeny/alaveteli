# == Schema Information
# Schema version: 20210114161442
#
# Table name: widget_votes
#
#  id              :integer          not null, primary key
#  cookie          :string
#  info_request_id :integer          not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

require 'spec_helper'

RSpec.describe WidgetVote do
  describe '.new' do
    it 'requires an info request' do
      widget_vote = WidgetVote.new
      expect(widget_vote).not_to be_valid
      expect(widget_vote.errors[:info_request]).to include("must exist")
    end

    it 'validates the cookie length' do
      widget_vote = WidgetVote.new
      expect(widget_vote).not_to be_valid
      expect(widget_vote.errors[:cookie]).to eq(["is the wrong length (should be 20 characters)"])
    end

    it 'is valid with a cookie and info request' do
      widget_vote = FactoryBot.create(:widget_vote)
      expect(widget_vote).to be_valid
    end

    it 'enforces uniqueness of cookie per info request' do
      info_request = FactoryBot.create(:info_request)
      widget_vote = info_request.widget_votes.create(cookie: 'x' * 20)
      duplicate_vote = info_request.widget_votes.build(cookie: 'x' * 20)
      expect(duplicate_vote).not_to be_valid
      expect(duplicate_vote.errors[:cookie]).to eq(["has already been taken"])
    end

    it 'allows the same cookie to be used across info requests' do
      info_request = FactoryBot.create(:info_request)
      second_info_request = FactoryBot.create(:info_request)
      widget_vote = info_request.widget_votes.create(cookie: 'x' * 20)
      second_request_vote = second_info_request.widget_votes.build(cookie: 'x' * 20)
      expect(second_request_vote).to be_valid
    end
  end
end

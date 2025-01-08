require 'spec_helper'

RSpec.describe Statistics::Leaderboard do
  let(:statistics) { described_class.new }
  before { User.destroy_all }

  describe '#all_time_requesters' do
    it 'gets most frequent requesters' do
      user1 = FactoryBot.create(:user)
      user2 = FactoryBot.create(:user)
      user3 = FactoryBot.create(:user)
      banned_user = FactoryBot.create(:user, :banned)
      closed_account_user = FactoryBot.create(:user, :closed)

      travel_to(6.months.ago) do
        5.times { FactoryBot.create(:info_request, user: user1) }
        2.times { FactoryBot.create(:info_request, user: user2) }
        FactoryBot.create(:info_request, user: user3)
        10.times { FactoryBot.create(:info_request, user: banned_user) }
        10.times { FactoryBot.create(:info_request, user: closed_account_user) }
        3.times { FactoryBot.create(:info_request, :hidden, user: user1) }
        3.times { FactoryBot.create(:embargoed_request, user: user1) }
      end

      expect(statistics.all_time_requesters).
        to eq({ user1 => 5,
                user2 => 2,
                user3 => 1 })
    end
  end

  describe '#last_28_day_requesters' do
    it 'gets recent frequent requesters' do
      user_with_3_requests = FactoryBot.create(:user)
      3.times { FactoryBot.create(:info_request, user: user_with_3_requests) }
      user_with_2_requests = FactoryBot.create(:user)
      2.times { FactoryBot.create(:info_request, user: user_with_2_requests) }
      user_with_1_request = FactoryBot.create(:user)
      FactoryBot.create(:info_request, user: user_with_1_request)
      user_with_an_old_request = FactoryBot.create(:user)
      FactoryBot.create(:info_request,
                        user: user_with_an_old_request,
                        created_at: 2.months.ago)
      banned_user = FactoryBot.create(:user, :banned)
      10.times { FactoryBot.create(:info_request, user: banned_user) }
      closed_account_user = FactoryBot.create(:user, :closed)
      10.times { FactoryBot.create(:info_request, user: closed_account_user) }
      user_with_embargoed_request = FactoryBot.create(:user)
      FactoryBot.create(:embargoed_request, user: user_with_embargoed_request)
      user_with_hidden_request = FactoryBot.create(:user)
      FactoryBot.create(:info_request, :hidden, user: user_with_hidden_request)

      expect(statistics.last_28_day_requesters).
        to eql({ user_with_3_requests => 3,
                 user_with_2_requests => 2,
                 user_with_1_request => 1 })
    end
  end

  describe '#all_time_commenters' do
    let(:many_comments) { FactoryBot.create(:user) }
    let(:some_comments) { FactoryBot.create(:user) }
    let!(:none_comments) { FactoryBot.create(:user) }
    let(:banned_user) { FactoryBot.create(:user, :banned) }
    let(:closed_account_user) { FactoryBot.create(:user, :closed) }

    before do
      FactoryBot.create(:comment, user: many_comments)
      FactoryBot.create(:comment, user: many_comments)
      FactoryBot.create(:comment, user: some_comments)
      FactoryBot.create(:comment, user: many_comments)
      FactoryBot.create(:comment, user: some_comments)
      FactoryBot.create(:comment, user: many_comments)
      10.times { FactoryBot.create(:comment, user: banned_user) }
      10.times { FactoryBot.create(:comment, user: closed_account_user) }
    end

    it 'gets most frequent commenters' do
      expect(statistics.all_time_commenters).
        to eql({ many_comments => 4,
                 some_comments => 2 })
    end
  end

  describe '#last_28_day_commenters' do
    it 'gets recent frequent commenters' do
      user_with_3_comments = FactoryBot.create(:user)
      3.times { FactoryBot.create(:comment, user: user_with_3_comments) }
      user_with_2_comments = FactoryBot.create(:user)
      2.times { FactoryBot.create(:comment, user: user_with_2_comments) }
      user_with_1_comment = FactoryBot.create(:user)
      FactoryBot.create(:comment, user: user_with_1_comment)
      user_with_an_old_comment = FactoryBot.create(:user)
      FactoryBot.create(:comment,
                        user: user_with_an_old_comment,
                        created_at: 2.months.ago)
      banned_user = FactoryBot.create(:user, :banned)
      10.times { FactoryBot.create(:comment, user: banned_user) }
      closed_account_user = FactoryBot.create(:user, :closed)
      10.times { FactoryBot.create(:comment, user: closed_account_user) }

      expect(statistics.last_28_day_commenters).
        to eql({ user_with_3_comments => 3,
                 user_with_2_comments => 2,
                 user_with_1_comment => 1 })
    end
  end
end

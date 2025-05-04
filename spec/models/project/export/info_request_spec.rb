require 'spec_helper'
require_dependency 'project/export/info_request'

RSpec.describe Project::Export::InfoRequest do
  include Rails.application.routes.url_helpers
  include LinkToHelper

  let(:project) { FactoryBot.build(:project) }

  let(:key_set) { FactoryBot.build(:dataset_key_set, resource: project) }
  let!(:dataset_key) { FactoryBot.create(:dataset_key, key_set: key_set) }

  let(:contributor) { FactoryBot.build(:user) }

  let(:public_body) { FactoryBot.build(:public_body) }
  let(:info_request) do
    FactoryBot.build(:info_request, public_body: public_body)
  end

  let(:instance) { described_class.new(project, info_request) }

  describe '#data' do
    subject(:data) { instance.data }

    shared_context 'with non-project classification' do
      before do
        info_request.described_state = 'successful'
      end
    end

    shared_context 'with project classification' do
      let(:url) do
        request_url(info_request, host: AlaveteliConfiguration.domain)
      end

      let(:owner_url) do
        user_url(info_request.user, host: AlaveteliConfiguration.domain)
      end

      let(:authority_url) do
        public_body_url(public_body, host: AlaveteliConfiguration.domain)
      end

      let(:contributor_url) do
        user_url(contributor, host: AlaveteliConfiguration.domain)
      end

      before do
        FactoryBot.create(
          :project_submission,
          :for_classification,
          project: project,
          info_request: info_request,
          user: contributor
        )
      end
    end

    shared_context 'with project extraction' do
      before do
        FactoryBot.create(
          :project_submission,
          :for_extraction,
          project: project,
          info_request: info_request,
          user: contributor
        )
      end
    end

    context 'when info request has been classified outside of projects' do
      include_context 'with non-project classification'

      it 'uses project owner as latest status contributor' do
        expect(data[:classified_by]).to eq project.owner.name
      end
    end

    context 'when info request has been classified' do
      include_context 'with project classification'

      it 'shows classification and contributor' do
        is_expected.to eq(
          :request => info_request.title,
          :request_url => url,
          :requested_by => info_request.user.name,
          :requested_by_url => owner_url,
          :public_body => public_body.name,
          :public_body_url => authority_url,
          :classified_by => contributor.name,
          :classified_by_url => contributor_url,
          :classification => 'Awaiting response',
          :extracted_by => nil,
          :extracted_by_url => nil,
          'Were there any errors?' => nil
        )
      end
    end

    context 'when info request has been classified and extracted' do
      include_context 'with project classification'
      include_context 'with project extraction'

      it 'shows extracted values and contributor' do
        is_expected.to eq(
          :request => info_request.title,
          :request_url => url,
          :requested_by => info_request.user.name,
          :requested_by_url => owner_url,
          :public_body => public_body.name,
          :public_body_url => authority_url,
          :classified_by => contributor.name,
          :classified_by_url => contributor_url,
          :classification => 'Awaiting response',
          :extracted_by => contributor.name,
          :extracted_by_url => contributor_url,
          'Were there any errors?' => 'Yes'
        )
      end
    end
  end
end

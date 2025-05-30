require 'spec_helper'

RSpec.describe AlaveteliGeoIP do
  let(:ip_address) { '127.0.0.1' }
  let(:max_mind_config) { { mode: :MODE_MEMORY } }

  describe '.country_code_from_ip' do
    subject { described_class.country_code_from_ip }
    let(:delegate) { double(described_class) }

    before do
      allow(described_class).to receive(:instance).and_return(delegate)
    end

    it 'delegates to an instance of the class' do
      expect(delegate).to receive(:country_code_from_ip).with(ip_address)
      AlaveteliGeoIP.country_code_from_ip(ip_address)
    end
  end

  describe '.instance' do
    subject { described_class.instance }

    it { is_expected.to be_a(described_class) }

    it 'caches the instance' do
      expect(AlaveteliGeoIP.instance).to equal(AlaveteliGeoIP.instance)
    end
  end

  describe '.new' do
    subject { described_class.new }

    it 'configures the instance with the configured country code' do
      expect(subject.current_code).
        to eq(AlaveteliConfiguration.iso_country_code)
    end

    context 'if a database param is supplied' do
      before do
        allow(File).to receive(:file?).
          with('/my/geoip/database').and_return(true)
      end

      it 'configures the instance with the database specified' do
        expect(MaxMind::DB).to receive(:new).
          with('/my/geoip/database', max_mind_config)
        described_class.new('/my/geoip/database')
      end
    end

    context 'if there is a geoip database configured and present' do
      before do
        allow(File).to receive(:file?).
          with(AlaveteliConfiguration.geoip_database).and_return(true)
      end

      it 'configures the instance with an instance of MaxMind::DB' do
        expect(MaxMind::DB).to receive(:new).
          with(AlaveteliConfiguration.geoip_database, max_mind_config)
        subject
      end

      it 'assigns the MaxMind::DB instance to geoip' do
        mock_db = double(MaxMind::DB)
        allow(MaxMind::DB).to receive(:new).and_return(mock_db)
        expect(subject.geoip).to eq(mock_db)
      end
    end
  end

  describe '#country_code_from_ip' do
    let(:current_code) { 'GB' }

    subject { described_class.new.country_code_from_ip(ip_address) }

    before(:each) do
      allow(AlaveteliConfiguration).
        to receive(:iso_country_code).and_return current_code
    end

    context 'when the geoip database is configured' do
      let(:geoip) { double('FakeGeoIP') }

      before do
        allow(File).to receive(:file?).
          with(AlaveteliConfiguration.geoip_database).and_return(true)

        allow(geoip).to receive(:get).
          and_return("country" => { "iso_code" => 'XX' })

        allow(MaxMind::DB).to receive(:new).and_return(geoip)
      end

      it { is_expected.to eq('XX') }

      context 'the IP is mapped to a continent instead of a country' do
        before do
          allow(geoip).to receive(:get).
            and_return("continent" => { "iso_code" => 'XR' })
        end

        it { is_expected.to eq('XR') }
      end

      context 'the IP is an anonymous proxy' do
        before do
          allow(geoip).to receive(:get).and_return(
            'registered_country' => { 'iso_code' => 'US' },
            'traits' => { 'is_anonymous_proxy' => true }
          )
        end

        it 'ignores registered country, returning the default ISO code' do
          is_expected.to eq(current_code)
        end
      end
    end
  end
end

# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Channel::Driver::MicrosoftGraphInbound, :aggregate_failures do
  let(:credentials) { { client_id: 'client', client_secret: 'secret', client_tenant: 'tenant', cloud: 'us_gov' } }
  let(:options)     { { user: 'user@example.com', shared_mailbox: 'shared@example.com', password: 'token', cloud: 'us_gov', folder_id: 'source', post_import_action: 'move', move_to_folder_id: 'destination' } }
  let(:graph)       { instance_double(MicrosoftGraph, list_messages: { items: [], total_count: 0 }) }
  let(:channel)     { create(:channel, area: 'MicrosoftGraph::Account', options: { auth: credentials, inbound: { options: } }) }

  it 'uses the selected cloud while checking both move folders in the shared mailbox' do
    allow(MicrosoftGraph).to receive(:new).and_return(graph)
    allow(graph).to receive(:get_message_folder_details).with('source').and_return({ id: 'source' })
    allow(graph).to receive(:get_message_folder_details).with('destination').and_return({ id: 'destination' })

    expect(described_class.new.fetch(options, channel)).to include(result: 'ok')
    expect(MicrosoftGraph).to have_received(:new).with(access_token: 'token', mailbox: 'shared@example.com', cloud: 'us_gov')
    expect(graph).to have_received(:get_message_folder_details).with('source')
    expect(graph).to have_received(:get_message_folder_details).with('destination')
  end

  context 'when reauthorizing' do
    before do
      create(:external_credential, name: 'microsoft_graph', credentials:)
      response = {
        access_token: 'access', refresh_token: 'refresh', expires_in: 3600,
        scope: 'scope', token_type: 'Bearer',
        id_token: JWT.encode({ preferred_username: 'user@example.com' }, nil, 'none'),
      }
      stub_request(:post, 'https://login.microsoftonline.us/tenant/oauth2/v2.0/token').to_return(body: response.to_json)
    end

    it 'keeps move mode and folder IDs when the cloud and mailbox remain the same' do
      linked = ExternalCredential::MicrosoftGraph.link_account('state', { state: 'state', code: 'code', channel_id: channel.id })

      expect(linked.id).to eq(channel.id)
      expect(linked.options.dig(:inbound, :options)).to include(cloud: 'us_gov', post_import_action: 'move', folder_id: 'source', move_to_folder_id: 'destination')
    end

    it 'keeps move mode but requires new folders when changing clouds' do
      channel.update!(options: channel.options.deep_merge(auth: { cloud: 'global' }))
      linked = ExternalCredential::MicrosoftGraph.link_account('state', { state: 'state', code: 'code', channel_id: channel.id })
      inbound = linked.options.dig(:inbound, :options)

      expect(inbound).to include(cloud: 'us_gov', post_import_action: 'move')
      expect(inbound).not_to have_key(:folder_id)
      expect(inbound).not_to have_key(:move_to_folder_id)
      expect { described_class.new.fetch(inbound, linked) }.to raise_error(Exceptions::UnprocessableContent, 'Please select a destination folder.')
    end
  end
end

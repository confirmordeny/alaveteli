module AlaveteliPro
  module ActivityList
    class Overdue < Item
      def description
        N_('{{public_body_name}} are delayed in responding to your request "{{info_request_title}}".')
      end

      def call_to_action
        _("Send a follow up")
      end

      def call_to_action_url
        new_request_followup_path(
          event.info_request.url_title, anchor: 'followup'
        )
      end
    end
  end
end

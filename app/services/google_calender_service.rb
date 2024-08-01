require 'google/apis/calendar_v3'

class GoogleCalenderService
    def initialize(user)
        @client = Signet::OAuth2::Client.new(
            client_id: ENV["GOOGLE_OAUTH2_CLIENT_ID"],
            client_secret: ENV["GOOGLE_OAUTH2_CLIENT_SECRET"],
            token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
            scope: Google::Apis::CalendarV3::AUTH_CALENDAR
        )
        @client.access_token = user.goauth_token
        @client.refresh_token = user.goauth_refresh_token

        if user.goauth_expires_at < Time.now
            @client.refresh!
            user.update!(goauth_token: @client.access_token, goauth_expires_at: Time.at(@client.expires_at))
        end

        @client.access_token = user.goauth_token

        @service = Google::Apis::CalendarV3::CalendarService.new
        @service.authorization = @client
        @user = user
    end

    def create_event(event, attendees = [])
        event = Google::Apis::CalendarV3::Event.new(
            summary: event["title"],
            description: event["description"],
            start: Google::Apis::CalendarV3::EventDateTime.new(
                date_time: Time.parse(event["start_time"]).iso8601(),
                time_zone: "Asia/Kolkata"
            ),
            end: Google::Apis::CalendarV3::EventDateTime.new(
                date_time: Time.parse(event["end_time"]).iso8601(),
                time_zone: "Asia/Kolkata"
            ),
            conference_data: Google::Apis::CalendarV3::ConferenceData.new(
                create_request: Google::Apis::CalendarV3::CreateConferenceRequest.new(
                    request_id: SecureRandom.uuid,
                    conference_solution_key: Google::Apis::CalendarV3::ConferenceSolutionKey.new(
                        type: "hangoutsMeet"
                    )
                )
            ),
            attendees: attendees.map { |attendee| Google::Apis::CalendarV3::EventAttendee.new(email: attendee) }
        )

        # begin
            result = @service.insert_event("primary", event, conference_data_version: 1)
            return result.id

        # rescue Google::Apis::ClientError => error
            # Rails.logger.error "Error creating event: #{error.message}"
            # raise Exception.new("Google Calender Event Not Created")
        # end
    end

    def update_event(event_id, event)
        event = Google::Apis::CalendarV3::Event.new(
            summary: event["title"],
            description: event["description"],
            start: Google::Apis::CalendarV3::EventDateTime.new(
                date_time: Time.parse(event["start_time"]).iso8601(),
                time_zone: "Asia/Kolkata"
            ),
            end: Google::Apis::CalendarV3::EventDateTime.new(
                date_time: Time.parse(event["end_time"]).iso8601(),
                time_zone: "Asia/Kolkata"
            )
            # attendees: [
            #     Google::Apis::CalendarV3::EventAttendee.new(email: @user.email)
            # ],
        )

        @service.update_event("primary", event_id, event)
    end

    def delete_event(event_id)
        @service.delete_event("primary", event_id)
    end
end

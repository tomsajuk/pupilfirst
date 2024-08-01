class AddGoogleCalenderIntegration < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :goauth_token, :string
    add_column :users, :goauth_refresh_token, :string
    add_column :users, :goauth_expires_at, :datetime

    add_column :calendar_events, :google_event_id, :string
  end
end

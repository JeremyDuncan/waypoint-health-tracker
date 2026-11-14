ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
class ActiveSupport::TestCase
  parallelize(workers: 1)
  def create_user(email = "owner@example.test")
    User.create!(email_address: email, password: "test-password-123", time_zone: "America/New_York")
  end
end
class ActionDispatch::IntegrationTest
  def login(user)
    post session_path, params: { email_address: user.email_address, password: "test-password-123" }
    assert_response :see_other
  end
end

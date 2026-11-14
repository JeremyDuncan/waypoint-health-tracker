require "test_helper"

class PasswordChangeTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @other = create_user("other@example.test")
    login(@user)
    @digest = @user.reload.password_digest
    @user.sessions.create!
  end

  test "settings has a separate password form with empty password fields" do
    get settings_path
    assert_response :success
    assert_select 'form[action=?][method=post]', settings_password_path do
      assert_select 'input[name="_method"][value=patch]'
      assert_select 'input[type=password][required]', count: 3
      assert_select 'input[autocomplete=current-password]', count: 1
      assert_select 'input[autocomplete=new-password]', count: 2
      assert_select 'input[type=password][value]', count: 0
    end
  end

  test "unauthenticated requests cannot change a password" do
    delete session_path
    assert_no_difference("Session.count") do
      patch settings_password_path, params: password_params
    end
    assert_redirected_to new_session_path
    assert_equal @digest, @user.reload.password_digest
  end

  test "wrong or missing current password leaves password and sessions unchanged" do
    ["incorrect-password", "", nil].each do |current|
      assert_rejected(password_params(current_password: current))
    end
  end

  test "invalid new passwords and confirmations leave everything unchanged" do
    [
      { password: "", password_confirmation: "" },
      { password: nil, password_confirmation: nil },
      { password: "short", password_confirmation: "short" },
      { password: "a" * 73, password_confirmation: "a" * 73 },
      { password: "é" * 37, password_confirmation: "é" * 37 },
      { password_confirmation: "different-password" },
      { password_confirmation: "" },
      { password_confirmation: nil }
    ].each { |attrs| assert_rejected(password_params(**attrs)) }
  end

  test "success changes only current account and revokes its sessions on every device" do
    other_browser = open_session
    other_browser.post session_path, params: { email_address: @other.email_address, password: "test-password-123" }
    second_browser = open_session
    second_browser.post session_path, params: { email_address: @user.email_address, password: "test-password-123" }
    stale_cookie = second_browser.cookies[:session_token]
    other_digest = @other.reload.password_digest
    other_sessions = @other.sessions.pluck(:id)
    preferences = @user.preferences
    weight = @user.weights.create!(id: SecureRandom.uuid, value: 200, unit: "lb", occurred_at: "2026-11-01T12:00:00-05:00")

    patch settings_password_path, params: password_params.merge(user: password_params[:user].merge(
      id: @other.id, email_address: "changed@example.test", preferred_unit: "kg", time_zone: "UTC"
    ))
    assert_redirected_to new_session_path
    assert_equal 0, @user.sessions.count
    assert_empty cookies[:session_token]
    assert_not @user.reload.authenticate("test-password-123")
    assert @user.authenticate("replacement-password-456")
    assert_equal "owner@example.test", @user.email_address
    assert_equal preferences, @user.preferences
    assert_equal weight.id, @user.weights.sole.id
    assert_equal other_digest, @other.reload.password_digest
    assert_equal other_sessions, @other.sessions.pluck(:id)
    assert_equal "other@example.test", @other.email_address

    get settings_path
    assert_redirected_to new_session_path
    second_browser.cookies[:session_token] = stale_cookie
    second_browser.get settings_path
    second_browser.assert_redirected_to new_session_path
    other_browser.get settings_path
    other_browser.assert_response :success

    post session_path, params: { email_address: @user.email_address, password: "test-password-123" }
    assert_response :unprocessable_entity
    post session_path, params: { email_address: @user.email_address, password: "replacement-password-456" }
    assert_redirected_to root_path
  end

  test "passwords at the character and byte boundaries are accepted" do
    ["a" * 12, "a" * 72, "é" * 36].each_with_index do |password, index|
      user = create_user("boundary-#{index}@example.test")
      login(user)
      patch settings_password_path, params: password_params(password: password, password_confirmation: password)
      assert_redirected_to new_session_path
      assert user.reload.authenticate(password)
      assert_empty user.sessions
    end
  end

  test "password change requires standard Rails CSRF protection" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference("Session.count") { patch settings_password_path, params: password_params }
    assert_response :unprocessable_entity
    assert_equal @digest, @user.reload.password_digest
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "password parameters are filtered from logs" do
    values = { current_password: "old-secret", password: "new-secret", password_confirmation: "new-secret" }
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(user: values)
    values.values.each { |secret| assert_not_includes filtered.inspect, secret }
  end

  private

  def password_params(current_password: "test-password-123", password: "replacement-password-456", password_confirmation: "replacement-password-456")
    { user: { current_password: current_password, password: password, password_confirmation: password_confirmation } }
  end

  def assert_rejected(params)
    sessions = @user.sessions.pluck(:id)
    patch settings_password_path, params: params
    assert_response :unprocessable_entity
    assert_select ".errors"
    assert_select 'input[type=password][value]', count: 0
    assert_equal @digest, @user.reload.password_digest
    assert_equal sessions, @user.sessions.pluck(:id)
    get settings_path
    assert_response :success
  end
end

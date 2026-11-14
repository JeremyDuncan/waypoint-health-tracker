require "test_helper"
require "timeout"

class PasswordLoginRaceTest < ActionDispatch::IntegrationTest
  # The password change must really commit on a different connection while the
  # login holds a stale User instance, not share a test's rollback transaction.
  self.use_transactional_tests = false

  setup do
    @user = create_user("login-race@example.test")
    login(@user)
  end

  teardown do
    @user&.reload&.destroy!
    LoginAttempt.delete_all
  end

  test "a login holding old credentials cannot create a session after password change commits" do
    paused = Queue.new
    resume = Queue.new
    browser = open_session
    original_find_by = User.method(:find_by)
    authenticate_transactions = []
    pause_once = -> do
      unless Thread.current[:password_login_paused]
        Thread.current[:password_login_paused] = true
        paused << true
        Timeout.timeout(10) { resume.pop }
      end
    end
    lookup = ->(*args, **kwargs) do
      user = original_find_by.call(*args, **kwargs)
      if user && Thread.current[:password_login_race]
        # Pause after the initial credential check has accepted the old digest.
        # The final check must reload it after the password change commits.
        user.define_singleton_method(:authenticate_password) do |password|
          result = super(password)
          authenticate_transactions << self.class.connection_pool.with_connection(&:transaction_open?)
          pause_once.call
          result
        end
      end
      user
    end

    begin
      User.define_singleton_method(:find_by, lookup)
      login_thread = Thread.new do
        Thread.current[:password_login_race] = true
        browser.post session_path, params: { email_address: @user.email_address, password: "test-password-123" }
      end
      Timeout.timeout(10) { paused.pop }
      patch settings_password_path, params: { user: {
        current_password: "test-password-123",
        password: "replacement-password-456", password_confirmation: "replacement-password-456"
      } }
      assert_redirected_to new_session_path
      assert_empty @user.sessions.reload
      assert_not @user.reload.authenticate("test-password-123")
      resume << true
      Timeout.timeout(10) { login_thread.value }
    ensure
      resume << true
      login_thread&.join(10)
      User.define_singleton_method(:find_by, original_find_by)
    end

    browser.assert_response :unprocessable_entity
    assert_empty @user.sessions.reload
    assert_equal [false, true], authenticate_transactions, "the final credential check must share the session creation transaction"
    browser.get settings_path
    browser.assert_redirected_to new_session_path
    browser.post session_path, params: { email_address: @user.email_address, password: "replacement-password-456" }
    browser.assert_redirected_to root_path
  end
end

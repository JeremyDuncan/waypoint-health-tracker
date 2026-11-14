# Based on the Rails 8 authentication generator. Random encrypted session tokens
# prevent old cookies from matching reused numeric IDs after a database restore.
module Authentication
  extend ActiveSupport::Concern
  included do
    before_action :require_authentication
    helper_method :authenticated?
  end
  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end
  private
  def authenticated? = resume_session
  def require_authentication = resume_session || request_authentication
  def resume_session
    Current.session ||= Session.where("created_at > ?", 30.days.ago).find_by(token: cookies.encrypted[:session_token]) if cookies.encrypted[:session_token]
  end
  def request_authentication
    if request.format.json?
      render json: { errors: ["Your session expired. Sign in again in another tab, then retry this form."] }, status: :unauthorized
    else
      redirect_to new_session_path
    end
  end
  def start_new_session_for(user)
    reset_session
    Current.session = user.sessions.create!
    cookies.encrypted[:session_token] = { value: Current.session.token, httponly: true, same_site: :lax,
      secure: request.ssl?, expires: 30.days.from_now }
  end
  def terminate_session
    Current.session&.destroy!
    Current.reset
    reset_session
    cookies.delete(:session_token, secure: request.ssl?, same_site: :lax)
  end
end

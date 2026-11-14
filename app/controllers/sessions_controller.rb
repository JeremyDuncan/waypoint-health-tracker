class SessionsController < ApplicationController
  allow_unauthenticated_access only: [:new, :create]
  def new; end
  def create
    key = Digest::SHA256.hexdigest(request.remote_ip)
    unless LoginAttempt.allowed?(key)
      response.headers["Retry-After"] = "900"
      flash.now[:alert] = "Too many login attempts. Try again in 15 minutes."
      return render :new, status: :too_many_requests
    end
    user = User.authenticate_by(params.permit(:email_address, :password))
    signed_in = user&.with_lock do
      # with_lock reloads the digest inside the same database transaction used
      # by password changes. Never issue a session based on the earlier check.
      if user.authenticate_password(params[:password])
        start_new_session_for(user)
        true
      end
    end
    if signed_in
      LoginAttempt.where(key: key).delete_all
      redirect_to root_path, status: :see_other
    else
      flash.now[:alert] = "Email or password was not recognized."
      render :new, status: :unprocessable_entity
    end
  end
  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end

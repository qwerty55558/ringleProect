class ApplicationController < ActionController::API
  # Per the spec, real auth is out of scope. We identify the caller by an
  # X-User-Id header. Endpoints that require a user call `require_user!`,
  # admin-only endpoints additionally call `require_admin!`.
  rescue_from ActiveRecord::RecordNotFound,    with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid,     with: :render_unprocessable
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def current_user
    @current_user ||= begin
      id = request.headers["X-User-Id"].presence
      User.find_by(id: id) if id
    end
  end

  def require_user!
    return if current_user

    render json: { error: "unauthenticated" }, status: :unauthorized
  end

  def require_admin!
    return render json: { error: "unauthenticated" }, status: :unauthorized unless current_user
    return if current_user.admin?

    render json: { error: "forbidden" }, status: :forbidden
  end

  private

  def render_not_found(error)
    render json: { error: "not_found", message: error.message }, status: :not_found
  end

  def render_unprocessable(error)
    render json: { error: "unprocessable_entity", details: error.record.errors.full_messages },
           status: :unprocessable_entity
  end

  def render_bad_request(error)
    render json: { error: "bad_request", message: error.message }, status: :bad_request
  end
end

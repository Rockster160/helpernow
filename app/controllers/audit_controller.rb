class AuditController < ApplicationController
  include AuditHelper
  helper_method :current_filter

  def index
    set_audit_filters
  end

  def search
    redirect_to mod_audit_index_path(current_filter)
  end

  private

  def current_filter
    @current_filter ||= begin
      params.permit(:ip, :acting_uid, :meta_id, discovery_types: [], discovery_klasses: []).to_h
    end
  end

end

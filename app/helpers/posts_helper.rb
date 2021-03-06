module PostsHelper
  include ActionView::Helpers::NumberHelper
  using CoreExtensions

  def tags_container(tags, min:, max:, min_tag_count: nil, max_tag_count: nil, href: tag_path("{{tag}}"))
    return if tags.none?
    ordered_tags = tags.unscope(:order).count_order
    max_tag_count ||= ordered_tags.first.tags_count
    min_tag_count ||= ordered_tags.last.tags_count

    tags.map do |tag|
      size = range_map(tag.tags_count, min_tag_count, max_tag_count, min, max)
      tag_href = URI.unescape(href).gsub("{{tag}}", tag.tag_name.to_s)
      "<a href=\"#{tag_href}\" rel=\"nofollow\" class=\"underline\" style=\"font-size: #{size}px;\" title=\"#{pluralize(tag.tags_count, "post")}\">#{tag.tag_name}</a>"
    end.join(", ").html_safe
  end

  def range_map(input, input_start, input_end, output_start, output_end)
    return (output_start + output_end) / 2 if input_start == input_end
    input, input_start, input_end, output_start, output_end = [input, input_start, input_end, output_start, output_end].map(&:to_i)
    output_start + ((output_end - output_start) / (input_end - input_start).to_f) * (input - input_start)
  end

  def filter_feedback_link(link_text, resolution_status:)
    filtered_params = params.permit(:search, :by_user)
    if params[:resolution_status].to_s == resolution_status.to_s
      sorted_class = "current-filter"
    end

    link_to link_text, all_feedback_path(filtered_params.merge(resolution_status: resolution_status)), class: "#{sorted_class}", rel: "nofollow"
  end

  def filter_posts_link(link_text, options={})
    new_filter_options = options.slice(:claimed_status, :reply_count, :user_status, :rating, :status)

    current_filters = @filter_params || {}

    selected_filter_key = new_filter_options.keys.first
    selected_filter_value = new_filter_options.values.first
    current_filter_value = current_filters[selected_filter_key]

    current_filter_is_selected = current_filters.values.any? { |param_val| new_filter_options.values.include?(param_val) }
    if current_filter_is_selected || current_filter_value.nil? && selected_filter_value.nil?
      sorted_class = "current-filter"
    end

    current_filters = current_filters.merge(new_filter_options).reject { |param_key, param_val| param_val.blank? }
    current_filters[:tags] = current_filters[:tags].join(",") if current_filters[:tags].present?

    link_to link_text, "#{([page_root_path] + current_filters.values).join("/")}#{filter_query_string}", class: "#{sorted_class} #{options[:class]}", rel: "nofollow"
  end

  def current_tags(workable_params=params)
    workable_params.permit(:tags, :new_tag)
  end

  def page_root_path
    "/" + request.path.split("/")[1]
  end

  def build_filtered_path(workable_params=params)
    if workable_params.is_a?(ActionController::Parameters)
      workable_params[:tags] = workable_params.permit(:tags, :new_tag).values.join(",")
      workable_params.delete(:tags) unless workable_params[:tags].present?
      workable_params.delete(:new_tag)
      attached_params = workable_params.permit(:claimed_status, :reply_count, :user_status, :tags, :page).values.join("/")
    else
      workable_params[:tags] = workable_params.slice(:tags, :new_tag).values.join(",")
      workable_params.delete(:tags) unless workable_params[:tags].present?
      workable_params.delete(:new_tag)
      attached_params = workable_params.slice(:claimed_status, :reply_count, :user_status, :tags, :page).values.join("/")
    end
    "#{page_root_path}/#{attached_params}#{filter_query_string}"
  end

  def filter_query_string
    additional_queries = []
    additional_queries << "regex_body=#{params[:regex_body]}" if params[:regex_body].present?
    additional_queries << "regex_user=#{params[:regex_user]}" if params[:regex_user].present?
    additional_queries << "search=#{params[:search]}" if params[:search].present?
    additional_queries << "by_user=#{params[:by_user]}" if params[:by_user].present?
    additional_queries << "new_tag=#{params[:new_tag]}" if params[:new_tag].present?
    additional_queries.any? ? "?#{additional_queries.join('&')}" : ""
  end

  def feedback_pagination(association, options={})
    new_params = params.permit(:search, :by_user, :resolution_status)

    paginate(association, options).gsub(/href=".*?"/) do |found_href|
      page = found_href.scan(/page=\d+/).first&.gsub("page=", "") || "1"
      found_href.split("?").first + "?#{URI.encode_www_form(new_params.merge(page: page))}\""
    end.html_safe
  end

  def filter_users_link(link_text, options={})
    new_filter_options = options.slice(:status, :search)

    current_filters = params.permit(:status, :search)

    selected_filter_key = new_filter_options.keys.first
    selected_filter_value = new_filter_options.values.first
    current_filter_value = current_filters[selected_filter_key]

    current_filter_is_selected = current_filters.values.any? { |param_val| new_filter_options.values.include?(param_val) }
    if current_filter_is_selected || current_filter_value.nil? && selected_filter_value.nil?
      sorted_class = "current-filter"
    end

    current_filters = current_filters.merge(new_filter_options).reject { |param_key, param_val| param_val.blank? }

    link_to link_text, users_path(current_filters), class: "#{sorted_class} #{options[:class]}", rel: "nofollow"
  end

  def pagination(association, options={})
    current_filters = @filter_options.reject { |param_key, param_val| param_val.blank? }
    tags = current_filters.delete(:tags)&.map(&:squish)&.map(&:presence).try(:compact) || []
    current_filter_str = ([page_root_path] + current_filters.keys + [tags&.join(",")]).compact.join("/")

    paginate(association, options).gsub(/\/history.*?\d?"/) do |found_match|
      page = found_match.scan(/\/\d+/).first.presence || "/1"
      "#{current_filter_str}#{page}#{filter_query_string}\"" # escaped string at the end to catch the removed one from the gsub
    end.html_safe
  end

  def set_feedback_filters
    filter_values = params.permit(:resolution_status)

    @filter_options = {
      "resolved" => false,
      "unresolved" => false
    }

    @filter_params = {}
  end

  def set_post_filter_params
    filter_values = params.permit(:claimed_status, :reply_count, :user_status, :tags, :page, :new_tag).values

    @filter_options = {
      "claimed"      => false,
      "unclaimed"    => false,
      "no-replies"   => false,
      "some-replies" => false,
      "few-replies"  => false,
      "many-replies" => false,
      "verified"     => false,
      "unverified"   => false,
      "adult"        => false,
      "safe"         => false,
      "closed"       => false,
      "open"         => false
    }

    filter_values.each do |filter_val|
      if @filter_options.keys.include?(filter_val)
        @filter_options[filter_val] = true
      elsif filter_val =~ /[^0-9]+/
        @filter_options[:tags] ||= []
        @filter_options[:tags] += filter_val.split(",").map(&:squish)
      end
    end

    @filter_params = {}
    @filter_params[:claimed_status] = "claimed" if @filter_options["claimed"]
    @filter_params[:claimed_status] = "unclaimed" if @filter_options["unclaimed"]
    @filter_params[:reply_count] = "no-replies" if @filter_options["no-replies"]
    @filter_params[:reply_count] = "some-replies" if @filter_options["some-replies"]
    @filter_params[:reply_count] = "few-replies" if @filter_options["few-replies"]
    @filter_params[:reply_count] = "many-replies" if @filter_options["many-replies"]
    @filter_params[:user_status] = "verified" if @filter_options["verified"]
    @filter_params[:user_status] = "unverified" if @filter_options["unverified"]
    @filter_params[:rating] = "adult" if @filter_options["adult"]
    @filter_params[:rating] = "safe" if @filter_options["safe"]
    @filter_params[:status] = "closed" if @filter_options["closed"]
    @filter_params[:status] = "open" if @filter_options["open"]
    @filter_params[:tags] = @filter_options[:tags].uniq if @filter_options[:tags].present?
  end

end

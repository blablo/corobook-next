module NavHelper
  # DaisyUI menu active class when the current request is within the given path prefix.
  def nav_active_class(path)
    request.path == path || (path != "/" && request.path.start_with?(path)) ? "menu-active" : ""
  end
end

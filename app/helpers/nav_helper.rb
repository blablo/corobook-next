module NavHelper
  # DaisyUI menu active class when the current request is within the given path prefix.
  # Includes `flex w-full` so each nav item (and its active highlight) spans the full sidebar width.
  def nav_active_class(path)
    active = request.path == path || (path != "/" && request.path.start_with?(path))
    [ "flex w-full", ("menu-active" if active) ].compact.join(" ")
  end
end

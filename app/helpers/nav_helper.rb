module NavHelper
  # DaisyUI menu active class when the current request is within the given path prefix.
  # `w-full!` makes the menu anchor fill the full-width `menu w-full` list (DaisyUI usage rule 2/3:
  # a Tailwind utility with a trailing `!` for specificity, rather than custom CSS).
  def nav_active_class(path)
    active = request.path == path || (path != "/" && request.path.start_with?(path))
    [ "w-full!", ("menu-active" if active) ].compact.join(" ")
  end
end

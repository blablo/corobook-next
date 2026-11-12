module TeamHelper
  # "MG" for María García, "P" for a member who has only an email so far.
  def member_initials(user)
    words = user.name.to_s.split
    return user.email.first.upcase if words.empty?

    words.values_at(0, -1).uniq.map { |w| w.first.upcase }.join
  end
end

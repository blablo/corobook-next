# frozen_string_literal: true

module Corobook
  # Inline Turbo Stream broadcast of the current live frame (design §6.1). Called synchronously
  # from the operator action — never a Solid Queue job — so it never reads Current off-request;
  # the LiveSession (and its church) is passed explicitly.
  module LiveBroadcast
    module_function

    def position(session)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ session, :projector ],
        target: "live-frame",
        partial: "live/projector_frame",
        locals: { session: session }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        [ session, :musician ],
        target: "live-frame",
        partial: "live/musician_frame",
        locals: { session: session, target_key: nil, semitones: 0, capo: nil }
      )
    end

    def ended(session)
      [ :projector, :musician ].each do |role|
        Turbo::StreamsChannel.broadcast_replace_to(
          [ session, role ],
          target: "live-frame",
          partial: "live/ended_frame",
          locals: {}
        )
      end
    end
  end
end

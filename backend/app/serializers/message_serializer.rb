# Plain-old serializer for Message rows. Inlined here (instead of pulling
# in jsonapi-serializer / blueprinter) because we only need it from two
# controllers and a tiny PORO keeps the test surface obvious.
class MessageSerializer
  def self.call(message)
    {
      id: message.id,
      role: message.role,
      text: message.text,
      position: message.position,
      created_at: message.created_at.iso8601,
      audio_url: audio_url_for(message)
    }
  end

  def self.audio_url_for(message)
    return nil unless message.audio.attached?

    Rails.application.routes.url_helpers.audio_api_v1_conversation_message_path(
      conversation_id: message.conversation_id,
      id: message.id
    )
  end
end

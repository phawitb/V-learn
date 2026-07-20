enum ChatRole { user, assistant }

/// One turn in the CLEAR AI chat.
class ChatMessage {
  final int id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        role: json['role'] == 'assistant' ? ChatRole.assistant : ChatRole.user,
        content: json['content'] as String,
        createdAt: DateTime.parse('${json['created_at']}Z').toLocal(),
      );
}

/// A user-created folder grouping one or more Lokaler (and optionally sub-folders).
class Folder {
  final int? id;
  final int? parentFolderId; // null → root folder
  final String name;
  final DateTime createdAt;

  const Folder({
    this.id,
    this.parentFolderId,
    required this.name,
    required this.createdAt,
  });

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      parentFolderId: map['parent_folder_id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'parent_folder_id': parentFolderId,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Folder copyWith({int? id, int? parentFolderId, String? name, bool clearParent = false}) =>
      Folder(
        id: id ?? this.id,
        parentFolderId: clearParent ? null : (parentFolderId ?? this.parentFolderId),
        name: name ?? this.name,
        createdAt: createdAt,
      );
}

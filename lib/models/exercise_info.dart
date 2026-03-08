class ExerciseInfo {
  final int id;
  final String name;
  final String description;
  final List<String> images;

  ExerciseInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.images,
  });

  factory ExerciseInfo.fromJson(Map<String, dynamic> json) {
    // Extrai as imagens da lista de imagens associadas
    List<String> imageUrls = (json['images'] as List?)
        ?.map((image) => image['image'] as String)
        .toList() ?? [];

    return ExerciseInfo(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Exercício desconhecido',
      description: (json['description'] as String? ?? '').replaceAll(RegExp(r'<[^>]*>'), ''), // Remove tags HTML
      images: imageUrls,
    );
  }
}

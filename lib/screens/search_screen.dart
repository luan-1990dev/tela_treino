import 'package:flutter/material.dart';
import 'package:tela_treino/data/translation_map.dart';
import 'package:tela_treino/models/exercise_info.dart';
import 'package:tela_treino/services/exercise_api_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ExerciseApiService _apiService = ExerciseApiService();
  final TextEditingController _searchController = TextEditingController();
  ExerciseInfo? _exerciseInfo;
  bool _isLoading = false;

  void _searchExercise() async {
    final searchTerm = _searchController.text.trim().toLowerCase();
    if (searchTerm.isEmpty) return;

    setState(() {
      _isLoading = true;
      _exerciseInfo = null;
    });

    final englishName = exerciseTranslations[searchTerm] ?? searchTerm;

    try {
      final result = await _apiService.fetchExerciseInfo(englishName);
      setState(() {
        _exerciseInfo = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar exercício: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar Exercícios'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Digite o nome do exercício em português',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchExercise,
                ),
              ),
              onSubmitted: (_) => _searchExercise(),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_exerciseInfo != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _exerciseInfo!.name.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const Divider(),
                          if (_exerciseInfo!.images.isNotEmpty)
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              children: _exerciseInfo!.images
                                  .map((imageUrl) => Image.network(imageUrl, width: 150))
                                  .toList(),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            _exerciseInfo!.description,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else if (_searchController.text.isNotEmpty)
              const Center(child: Text('Nenhum exercício encontrado.')),
          ],
        ),
      ),
    );
  }
}

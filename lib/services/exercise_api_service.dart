import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tela_treino/models/exercise_info.dart';

class ExerciseApiService {
  final String _baseUrl = 'https://wger.de/api/v2';

  Future<ExerciseInfo?> fetchExerciseInfo(String exerciseName) async {
    // Etapa 1: Buscar o ID do exercício pelo nome (em inglês)
    final exerciseSearchUrl = Uri.parse('$_baseUrl/exercise/search/?term=$exerciseName&language=2');
    final searchResponse = await http.get(exerciseSearchUrl);

    if (searchResponse.statusCode != 200) {
      throw Exception('Falha na busca pelo nome do exercício.');
    }

    final searchResults = json.decode(utf8.decode(searchResponse.bodyBytes));
    if (searchResults['suggestions'] == null || searchResults['suggestions'].isEmpty) {
      return null; // Nenhum exercício encontrado
    }

    // Pega o ID do primeiro resultado da busca
    final exerciseId = searchResults['suggestions'][0]['data']['id'];

    // Etapa 2: Usar o ID para obter as informações detalhadas com imagens
    final infoUrl = Uri.parse('$_baseUrl/exerciseinfo/$exerciseId/');
    final infoResponse = await http.get(infoUrl);

    if (infoResponse.statusCode != 200) {
      throw Exception('Falha ao carregar detalhes do exercício.');
    }

    final infoData = json.decode(utf8.decode(infoResponse.bodyBytes));
    if (infoData == null) {
      return null; // Detalhes não encontrados
    }
    
    // A API /exerciseinfo/{id}/ retorna um único objeto, não uma lista
    return ExerciseInfo.fromJson(infoData);
  }
}

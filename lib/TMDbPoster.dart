import 'package:http/http.dart' as http;
import 'dart:convert';

Future<String?> fetchMoviePoster(String title) async {
  final apiKey = '77ad115f';
  final query = Uri.encodeComponent(title);
  final url = 'https://api.themoviedb.org/3/search/movie?api_key=$apiKey&query=$query';

  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['results'] != null && data['results'].isNotEmpty) {
      final posterPath = data['results'][0]['poster_path'];
      return 'https://image.tmdb.org/t/p/w500$posterPath';
    }
  }
  return null;
}

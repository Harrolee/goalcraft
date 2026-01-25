import 'package:dio/dio.dart';
import '../models/goal.dart';
import '../models/milestone.dart';

class ApiService {
  static const String _baseUrl = 'http://localhost:8000/api';

  final Dio _dio;

  ApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ));

  Future<Goal> createGoal({
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    try {
      final response = await _dio.post(
        '/goals',
        data: {
          'title': title,
          'description': description,
          'target_date': targetDate?.toIso8601String(),
        },
      );
      return Goal.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Goal>> getGoals() async {
    try {
      final response = await _dio.get('/goals');
      final List<dynamic> data = response.data;
      return data.map((json) => Goal.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Goal> getGoal(String id) async {
    try {
      final response = await _dio.get('/goals/$id');
      return Goal.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Goal> updateGoal(String id, {
    String? title,
    String? description,
    DateTime? targetDate,
  }) async {
    try {
      final response = await _dio.patch(
        '/goals/$id',
        data: {
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (targetDate != null) 'target_date': targetDate.toIso8601String(),
        },
      );
      return Goal.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteGoal(String id) async {
    try {
      await _dio.delete('/goals/$id');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Milestone> updateMilestone(
    String goalId,
    String milestoneId, {
    String? title,
    String? description,
    DateTime? dueDate,
    MilestoneStatus? status,
  }) async {
    try {
      final response = await _dio.patch(
        '/goals/$goalId/milestones/$milestoneId',
        data: {
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (dueDate != null) 'due_date': dueDate.toIso8601String(),
          if (status != null) 'status': status.name,
        },
      );
      return Milestone.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Google Calendar Integration

  /// Get Google Calendar connection status for a user
  Future<bool> getGoogleCalendarStatus(int userId) async {
    try {
      final response = await _dio.get('/auth/google/status/$userId');
      return response.data['connected'] ?? false;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get the Google OAuth authorization URL
  Future<String> getGoogleAuthUrl(int userId, String redirectUri) async {
    try {
      final response = await _dio.get('/auth/google/authorize', queryParameters: {
        'user_id': userId,
        'redirect_uri': redirectUri,
      });
      return response.data['authorization_url'];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Complete Google OAuth callback
  Future<bool> completeGoogleAuth({
    required String code,
    required String state,
    required int userId,
    required String redirectUri,
  }) async {
    try {
      final response = await _dio.get('/auth/google/callback', queryParameters: {
        'code': code,
        'state': state,
        'user_id': userId,
        'redirect_uri': redirectUri,
      });
      return response.data['success'] ?? false;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Disconnect Google Calendar from user account
  Future<bool> disconnectGoogleCalendar(int userId) async {
    try {
      final response = await _dio.delete('/auth/google/disconnect/$userId');
      return response.data['success'] ?? false;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Sync milestones to Google Calendar
  Future<void> syncMilestonesToCalendar(String goalId) async {
    try {
      await _dio.post('/goals/$goalId/sync-calendar');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timeout. Please check your network.');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['detail'] ?? 'Unknown error';
        return Exception('Error $statusCode: $message');
      case DioExceptionType.cancel:
        return Exception('Request cancelled');
      default:
        return Exception('Network error: ${e.message}');
    }
  }
}

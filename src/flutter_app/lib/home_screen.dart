import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

// --- Models ---
class Task {
  final String taskId;
  final String title;
  final String? description;
  final bool isCompleted;

  Task({
    required this.taskId,
    required this.title,
    this.description,
    required this.isCompleted,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      taskId: json['task_id'],
      title: json['title'],
      description: json['description'],
      isCompleted: json['is_completed'],
    );
  }
}

// --- API Service ---
class ApiService {
  // Use the injected API URL from api_config.dart
  final String _baseUrl = apiUrl; 

  Future<List<Task>> getTasks(String familyId) async {
    final response = await http.get(Uri.parse('$_baseUrl/family/$familyId/tasks'));

    if (response.statusCode == 200) {
      List<dynamic> tasksJson = json.decode(response.body);
      return tasksJson.map((json) => Task.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load tasks');
    }
  }
}

// --- Providers ---
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final tasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  // Hardcoded family ID for now. In a real app, this would come from auth.
  const familyId = "some-family-id"; 
  return ref.watch(apiServiceProvider).getTasks(familyId);
});

// --- UI ---
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsyncValue = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family To-Do'),
      ),
      body: tasksAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks yet!'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: ListTile(
                  title: Text(task.title),
                  subtitle: Text(task.description ?? ''),
                  trailing: Checkbox(
                    value: task.isCompleted,
                    onChanged: (bool? newValue) {
                      // TODO: Implement update task functionality
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Navigate to add new task screen
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider for tasks (real-time updates)
final tasksProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) {
    return Stream.value([]);
  }

  // TODO: Dynamically fetch family_group_id for the user
  return supabase
      .from('tasks')
      .stream(primaryKey: ['id'])
      .order('due_date', ascending: true)
      .limit(100)
      .eq('family_group_id', 'YOUR_FAMILY_GROUP_ID_FOR_MVP_OR_FETCH_DYNAMICALLY') // <-- Replace dynamically
      .map((data) => data);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsyncValue = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family To-Do'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: tasksAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks yet! Add one.'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: ListTile(
                  title: Text(task['title']),
                  subtitle: Text(
                    'Assigned to: {task['assigned_to'] ?? 'Unassigned'}'
                    '{task['due_date'] != null ? ' - Due: {DateTime.parse(task['due_date']).toLocal().toShortDateString()}' : ''}',
                  ),
                  trailing: Checkbox(
                    value: task['is_completed'] ?? false,
                    onChanged: (bool? newValue) async {
                      await Supabase.instance.client
                          .from('tasks')
                          .update({'is_completed': newValue})
                          .eq('id', task['id']);
                    },
                  ),
                  onTap: () {
                    // TODO: Navigate to task detail/edit screen
                  },
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

// Extension for simple date formatting
extension DateTimeExtension on DateTime {
  String toShortDateString() {
    return '{day.toString().padLeft(2, '0')}/{month.toString().padLeft(2, '0')}/{year.toString().substring(2)}';
  }
}

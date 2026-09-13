import 'package:go_router/go_router.dart';

import '../../presentation/shell/app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [GoRoute(path: '/', builder: (context, state) => const AppShell())],
);

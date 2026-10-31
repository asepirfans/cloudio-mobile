import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import '../widgets/mini_player.dart';
import '../theme/app_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return CloudioShell(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) => setState(() => _currentIndex = index),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          SearchScreen(isActive: _currentIndex == 1),
          const LibraryScreen(),
        ],
      ),
    );
  }
}

class CloudioShell extends StatelessWidget {
  const CloudioShell(
      {super.key,
      required this.body,
      required this.selectedIndex,
      required this.onDestinationSelected});
  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: body,
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppColors.borderSubtle)),
                    ),
                    child: NavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: 'Beranda',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.search_rounded),
                          selectedIcon: Icon(Icons.search_rounded),
                          label: 'Cari',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.my_library_music_rounded),
                          label: 'Koleksi',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      );
}
